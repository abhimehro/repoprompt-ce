import Combine
import Foundation

@MainActor
final class BenchmarkSettingsViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case run
        case history
        case leaderboard

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .run: "Run"
            case .history: "Run History"
            case .leaderboard: "Local Rankings"
            }
        }
    }

    struct ProgressStep: Identifiable {
        let id = UUID()
        var description: String
        var detailText: String = ""
        var additionalInfo: String?
        var isComplete: Bool = false
        var isActive: Bool = false
    }

    struct ProgressSummary {
        var totalSeeds: Int = 0
        var completedSeeds: Int = 0
        var totalTasks: Int = 0
        var completedTasks: Int = 0
    }

    private struct SeedProgress {
        var totalTasks: Int
        var completedTasks: Int
        var taskTypes: [BenchmarkCaseType]
    }

    struct DebugTaskRef: Identifiable {
        let id: String // e.g., "\(seed)-\(taskIndex)-\(spec.id)"
        let seed: UInt32
        let seedIndex: Int // 0-based index within the 5 sub-seeds
        let taskIndex: Int // 0-based index within that seed
        let spec: BenchmarkTaskSpec
    }

    @Published var activeTab: Tab = .run
    @Published var selectedModelRaw: String
    @Published var coreSeedInput: String
    @Published var debugLoggingEnabled: Bool = false
    @Published var subSeedCount: Int = 5
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var progressSteps: [ProgressStep] = []
    @Published private(set) var latestReport: BenchmarkFinalReport?
    @Published private(set) var latestSummary: BenchmarkRunSummary?
    @Published private(set) var runError: String?
    @Published private(set) var history: [BenchmarkRunSummary] = []
    @Published private(set) var leaderboard: [BenchmarkLeaderboardEntry] = []
    @Published private(set) var availableModels: [AIModel] = []
    @Published private(set) var lastAudit: [BenchmarkAuditResult] = []
    @Published private(set) var progressSummary: ProgressSummary = .init()
    @Published private(set) var latestLogURL: URL?
    @Published private(set) var runningTestIDs: Set<String> = []

    private let promptViewModel: PromptViewModel
    private let apiSettingsViewModel: APISettingsViewModel
    private let runStore: BenchmarkRunStore
    private var cancellables: Set<AnyCancellable> = []
    private var runTask: Task<Void, Never>?
    private var seedStepIndices: [UInt32: Int] = [:]
    private var seedProgress: [UInt32: SeedProgress] = [:]

    private static let selectedModelDefaultsKey = "BenchmarkSettingsView.selectedModel"

    // BOLT: Shared static instance to prevent expensive repeated DateFormatter allocations
    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    // BOLT: Shared static instance to prevent expensive repeated DateFormatter allocations
    private static let logFileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let csvTimestampFormatter = ISO8601DateFormatter()

    init(
        promptViewModel: PromptViewModel,
        apiSettingsViewModel: APISettingsViewModel,
        runStore: BenchmarkRunStore = .shared
    ) {
        self.promptViewModel = promptViewModel
        self.apiSettingsViewModel = apiSettingsViewModel
        self.runStore = runStore
        selectedModelRaw = promptViewModel.preferredModel
        coreSeedInput = String(BenchmarkSeedUtilities.canonicalCoreSeed)
        availableModels = apiSettingsViewModel.availableModels
        if let persistedModel = UserDefaults.standard.string(forKey: Self.selectedModelDefaultsKey) {
            selectedModelRaw = persistedModel
        }
        ensureValidModelSelection()

        apiSettingsViewModel.$availableModels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] models in
                self?.availableModels = models
                self?.ensureValidModelSelection()
            }
            .store(in: &cancellables)

        $selectedModelRaw
            .removeDuplicates()
            .sink { newValue in
                UserDefaults.standard.set(newValue, forKey: Self.selectedModelDefaultsKey)
            }
            .store(in: &cancellables)

        Task {
            await loadHistory()
        }
    }

    deinit {
        runTask?.cancel()
    }

    func generateRandomSeed() {
        coreSeedInput = String(Self.makeRandomCoreSeed())
    }

    func validateCurrentSeedForDebug() async {
        let seed = UInt32(coreSeedInput) ?? 42
        let config = BenchConfig(tasksAreCumulative: true)
        let generator = BenchmarkTaskGenerator()
        let generated = generator.generateSeed(seed, config: config)
        let auditor = BenchmarkAuditor()
        lastAudit = await auditor.auditSeed(generated)
    }

    func runBenchmark() {
        guard !isRunning else { return }
        runError = nil
        let model = AIModel.fromModelName(selectedModelRaw) ?? promptViewModel.preferredAIModel
        guard let aiService = promptViewModel.aiQueriesService else {
            runError = "AI service unavailable. Configure an API key first."
            return
        }
        guard let coreSeed = UInt32(coreSeedInput) else {
            runError = "Core seed must be a positive integer."
            return
        }
        progressSummary = ProgressSummary(totalSeeds: max(1, subSeedCount), completedSeeds: 0, totalTasks: 0, completedTasks: 0)
        seedProgress.removeAll()
        latestLogURL = nil
        isRunning = true
        progressSteps = []
        latestReport = nil
        latestSummary = nil

        let benchConfig = BenchConfig(tasksAreCumulative: true)
        let generator = BenchmarkTaskGenerator()
        let executor = BenchmarkTaskExecutor(
            aiQueriesService: aiService,
            model: model,
            maxContextChars: benchConfig.contextCharBudget,
            maxDecoyPerFileChars: benchConfig.decoyCharCap
        )
        let engine = BenchmarkEngine(generator: generator, executor: executor, config: benchConfig)

        runTask = Task { [weak self] in
            await self?.performRun(
                engine: engine,
                model: model,
                coreSeed: coreSeed
            )
        }
    }

    func stopRun() {
        runTask?.cancel()
        promptViewModel.aiQueriesService?.cancelQuery()
        isRunning = false
        seedStepIndices.removeAll()
        seedProgress.removeAll()
        progressSteps.removeAll()
        progressSummary = ProgressSummary()
        latestReport = nil
        latestSummary = nil
        latestLogURL = nil
        runError = "Benchmark run cancelled."
        runTask = nil
    }

    func clearHistory() {
        runTask?.cancel()
        Task {
            await runStore.clear()
            history = []
            rebuildLeaderboard()
        }
    }

    func deleteRun(at offsets: IndexSet) {
        Task {
            var updatedHistory = history
            updatedHistory.remove(atOffsets: offsets)
            await runStore.saveRuns(updatedHistory)
            history = updatedHistory
            rebuildLeaderboard()
        }
    }

    private func ensureValidModelSelection() {
        let current = selectedModelRaw
        guard availableModels.contains(where: { $0.rawValue == current }) else {
            if let fallback = availableModels.first {
                selectedModelRaw = fallback.rawValue
            } else {
                selectedModelRaw = promptViewModel.preferredModel
            }
            return
        }
    }

    private func performRun(engine: BenchmarkEngine, model: AIModel, coreSeed: UInt32) async {
        let subSeeds = max(1, subSeedCount)
        progressSteps.append(ProgressStep(description: "Preparing benchmark config...", isComplete: true))
        seedStepIndices.removeAll()

        let executions = await engine.run(
            coreSeed: coreSeed,
            subSeedCount: subSeeds,
            progress: { [weak self] event in
                self?.handleProgressEvent(event)
            }
        )

        if Task.isCancelled {
            runTask = nil
            return
        }

        progressSteps.append(ProgressStep(description: "Compiling report...", isComplete: false))

        let reporter = BenchmarkReporter(
            verifier: BenchmarkVerifier(
                policy: GradingPolicy(
                    passThreshold: 0.92,
                    lenient: false
                )
            )
        )
        let report = reporter.buildReport(coreSeed: coreSeed, executions: executions)
        let summary = BenchmarkRunSummary.make(report: report, model: model, temperature: nil)
        let runs = await runStore.append(summary)

        progressSummary.totalSeeds = max(progressSummary.totalSeeds, executions.count)
        progressSummary.completedSeeds = progressSummary.totalSeeds
        let totalTasks = executions.reduce(0) { $0 + $1.executions.count }
        progressSummary.totalTasks = max(progressSummary.totalTasks, totalTasks)
        progressSummary.completedTasks = progressSummary.totalTasks

        latestReport = report
        latestSummary = summary
        runError = nil
        if let lastIndex = progressSteps.indices.last {
            progressSteps[lastIndex].isComplete = true
            progressSteps[lastIndex].detailText = "Pass rate: \(Int(summary.passRate * 100))%"
        }

        if debugLoggingEnabled {
            await writeDebugLog(
                coreSeed: coreSeed,
                model: model,
                report: report,
                executions: executions,
                steps: progressSteps,
                progress: progressSummary
            )
        }

        isRunning = false
        history = runs
        rebuildLeaderboard()
        runTask = nil
    }

    private func handleProgressEvent(_ event: BenchmarkProgressEvent) {
        switch event {
        case let .started(totalSeeds):
            seedStepIndices.removeAll()
            seedProgress.removeAll()
            progressSummary.totalSeeds = totalSeeds
            progressSummary.completedSeeds = 0
            progressSummary.totalTasks = 0
            progressSummary.completedTasks = 0
            // Pre-allocate progress steps array with placeholders
            progressSteps = (0 ..< totalSeeds).map { index in
                ProgressStep(
                    description: "Task Group \(index + 1) of \(totalSeeds)",
                    detailText: "Waiting...",
                    additionalInfo: nil,
                    isComplete: false,
                    isActive: false
                )
            }
        case let .seedStarted(index, seed, totalSeeds, taskCount, taskTypes):
            let description = "Task Group \(index + 1) of \(totalSeeds)"
            // Update the step at the correct index
            if index < progressSteps.count {
                progressSteps[index].description = description
                progressSteps[index].detailText = "0/\(max(1, taskCount)) tasks"
                progressSteps[index].isActive = true
                progressSteps[index].isComplete = false
            }
            seedStepIndices[seed] = index
            seedProgress[seed] = SeedProgress(totalTasks: max(0, taskCount), completedTasks: 0, taskTypes: taskTypes)
            updateCurrentTaskInfo(for: seed)
            recalculateTaskProgress()
            progressSummary.totalSeeds = totalSeeds
        case let .taskCompleted(seed, completed, total):
            if var progress = seedProgress[seed] {
                progress.totalTasks = max(progress.totalTasks, total)
                progress.completedTasks = min(completed, progress.totalTasks)
                seedProgress[seed] = progress
                recalculateTaskProgress()
                updateCurrentTaskInfo(for: seed)
            }
            guard let stepIndex = seedStepIndices[seed], stepIndex < progressSteps.count else { return }
            progressSteps[stepIndex].detailText = "\(completed)/\(max(1, total)) tasks"
            progressSteps[stepIndex].isActive = true
            if completed >= total {
                progressSteps[stepIndex].isComplete = true
                progressSteps[stepIndex].isActive = false
                progressSteps[stepIndex].additionalInfo = nil
            }
        case let .seedCompleted(_, seed):
            if var progress = seedProgress[seed] {
                progress.completedTasks = progress.totalTasks
                seedProgress[seed] = progress
                recalculateTaskProgress()
                updateCurrentTaskInfo(for: seed)
            }
            if let stepIndex = seedStepIndices[seed], stepIndex < progressSteps.count {
                progressSteps[stepIndex].isComplete = true
                progressSteps[stepIndex].isActive = false
                progressSteps[stepIndex].detailText = "Completed"
                progressSteps[stepIndex].additionalInfo = nil
            }
            progressSummary.completedSeeds = min(progressSummary.totalSeeds, progressSummary.completedSeeds + 1)
        case .finished:
            recalculateTaskProgress()
            progressSummary.completedSeeds = progressSummary.totalSeeds
            progressSummary.completedTasks = progressSummary.totalTasks
            progressSteps.append(ProgressStep(description: "All task groups complete", detailText: "", isComplete: true))
        case .cancelled:
            isRunning = false
            runTask = nil
            seedStepIndices.removeAll()
            seedProgress.removeAll()
            progressSteps.removeAll()
            progressSummary = ProgressSummary()
            latestReport = nil
            latestSummary = nil
            latestLogURL = nil
            runError = "Benchmark run cancelled."
        }
    }

    private func loadHistory() async {
        let stored = await runStore.loadRuns()
        history = stored
        rebuildLeaderboard()
    }

    private func rebuildLeaderboard() {
        var aggregates: [String: (runs: Int, totalTasks: Int, passed: Int, totalScore: Double, totalPointsEarned: Double, totalMaxPoints: Double, lastRun: Date, display: String)] = [:]
        // Only include eligible benchmarks (no API errors) in leaderboard
        for summary in eligibleBenchmarks {
            let key = summary.modelRawValue
            let entry = aggregates[key] ?? (0, 0, 0, 0, 0, 0, .distantPast, summary.modelDisplayShort)
            let newRuns = entry.runs + 1
            let newTotalTasks = entry.totalTasks + summary.totalTasks
            let newPassed = entry.passed + summary.passedTasks
            let weightedScore = entry.totalScore + (summary.averageScore * Double(summary.totalTasks))
            let newPointsEarned = entry.totalPointsEarned + summary.totalPointsEarned
            let newMaxPoints = entry.totalMaxPoints + summary.totalMaxPoints
            let lastRun = max(entry.lastRun, summary.timestamp)
            aggregates[key] = (newRuns, newTotalTasks, newPassed, weightedScore, newPointsEarned, newMaxPoints, lastRun, summary.modelDisplayShort)
        }
        let entries = aggregates.map { key, value -> BenchmarkLeaderboardEntry in
            let averageScore = value.totalTasks == 0 ? 0 : value.totalScore / Double(value.totalTasks)
            let passRate = value.totalTasks == 0 ? 0 : Double(value.passed) / Double(value.totalTasks)
            let pointsRate = value.totalMaxPoints > 0 ? value.totalPointsEarned / value.totalMaxPoints : 0.0
            return BenchmarkLeaderboardEntry(
                modelRawValue: key,
                modelDisplayName: value.display,
                runs: value.runs,
                totalTasks: value.totalTasks,
                passedTasks: value.passed,
                averageScore: averageScore,
                passRate: passRate,
                pointsRate: pointsRate,
                lastRun: value.lastRun
            )
        }
        .sorted { lhs, rhs in
            if lhs.pointsRate == rhs.pointsRate {
                if lhs.passRate == rhs.passRate {
                    return lhs.totalTasks > rhs.totalTasks
                }
                return lhs.passRate > rhs.passRate
            }
            return lhs.pointsRate > rhs.pointsRate
        }

        leaderboard = entries
    }

    var eligibleBenchmarks: [BenchmarkRunSummary] {
        // Filter out runs that had API errors (hadErrors == true)
        // nil is treated as eligible for backward compatibility with old runs
        history.filter { run in
            if let hadErrors = run.hadErrors, hadErrors {
                return false
            }
            return true
        }
    }

    private func recalculateTaskProgress() {
        var totalTasks = 0
        var completedTasks = 0
        for progress in seedProgress.values {
            let taskTotal = max(0, progress.totalTasks)
            totalTasks += taskTotal
            completedTasks += min(progress.completedTasks, taskTotal)
        }
        progressSummary.totalTasks = totalTasks
        progressSummary.completedTasks = min(completedTasks, totalTasks)
    }

    private func updateCurrentTaskInfo(for seed: UInt32) {
        guard let stepIndex = seedStepIndices[seed], stepIndex < progressSteps.count else { return }
        guard let progress = seedProgress[seed] else { return }
        if let name = currentTaskName(for: progress) {
            progressSteps[stepIndex].additionalInfo = name
        } else {
            progressSteps[stepIndex].additionalInfo = nil
        }
    }

    private func currentTaskName(for progress: SeedProgress) -> String? {
        guard progress.totalTasks > 0 else { return nil }
        guard progress.completedTasks < progress.totalTasks else { return nil }
        guard let type = progress.taskTypes[safe: progress.completedTasks] else { return nil }
        return friendlyName(for: type)
    }

    private func writeDebugLog(
        coreSeed: UInt32,
        model: AIModel,
        report: BenchmarkFinalReport,
        executions: [BenchmarkSeedExecution],
        steps: [ProgressStep],
        progress: ProgressSummary
    ) async {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            if runError == nil {
                runError = "Failed to locate Downloads folder for debug log."
            }
            return
        }
        let timestamp = Self.logFileNameFormatter.string(from: Date())
        let fileName = "RepoPrompt-Benchmark-\(timestamp)-seed-\(coreSeed).md"
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        let content = makeDebugLogContent(
            coreSeed: coreSeed,
            model: model,
            report: report,
            executions: executions,
            steps: steps,
            progress: progress
        )
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            latestLogURL = fileURL
        } catch {
            if runError == nil {
                runError = "Failed to write debug log: \(error.localizedDescription)"
            }
        }
    }

    private func makeDebugLogContent(
        coreSeed: UInt32,
        model: AIModel,
        report: BenchmarkFinalReport,
        executions: [BenchmarkSeedExecution],
        steps: [ProgressStep],
        progress: ProgressSummary
    ) -> String {
        let now = Date()
        var lines: [String] = []
        lines.append("# RepoPrompt Benchmark Run")
        lines.append("")
        lines.append("- Timestamp: \(Self.logTimestampFormatter.string(from: now))")
        lines.append("- Model: \(model.displayName) (\(model.rawValue))")
        let temperatureLine = "- Temperature: model default (app overrides ignored)"
        lines.append(temperatureLine)
        lines.append("- Core Seed: \(coreSeed)")
        if !report.subSeeds.isEmpty {
            let seedsList = report.subSeeds.map(String.init).joined(separator: ", ")
            lines.append("- Sub Seeds: \(seedsList)")
        }
        lines.append("- Total Tasks: \(report.totalTasks)")
        lines.append(String(format: "- Pass Rate: %.2f%%", report.passRate * 100))
        lines.append(String(format: "- Average Score: %.2f", report.averageScore))
        lines.append("- Seeds Progress: \(progress.completedSeeds)/\(max(progress.totalSeeds, 1))")
        lines.append("- Tasks Progress: \(progress.completedTasks)/\(max(progress.totalTasks, 1))")
        lines.append("- Debug Logging: Enabled")
        lines.append("")

        let sortedTypeStats = report.perType.sorted { $0.key.rawValue < $1.key.rawValue }
        if !sortedTypeStats.isEmpty {
            lines.append("## Case Type Summary")
            for (type, stats) in sortedTypeStats {
                lines.append(String(
                    format: "- %@ • count %d • pass %.2f%% • avg %.2f",
                    type.rawValue,
                    stats.count,
                    stats.passRate * 100,
                    stats.averageScore
                ))
            }
            lines.append("")
        }

        if !steps.isEmpty {
            lines.append("## Progress Timeline")
            for step in steps {
                let status = step.isComplete ? "✅" : "⏳"
                let detail = step.detailText.isEmpty ? "" : " — \(step.detailText)"
                lines.append("- \(status) \(step.description)\(detail)")
            }
            lines.append("")
        }

        let seedReports = Dictionary(uniqueKeysWithValues: report.perSeed.map { ($0.seed, $0) })
        lines.append("## Seeds")
        for seedExecution in executions {
            let seed = seedExecution.seed
            let seedReport = seedReports[seed]
            lines.append("### Seed \(seed)")
            if let seedReport {
                lines.append(String(format: "- Pass Rate: %.2f%%", seedReport.passRate * 100))
                lines.append(String(format: "- Average Score: %.2f", seedReport.averageScore))
                lines.append("- Tasks: \(seedReport.tasks.count)")
            } else {
                lines.append("- Tasks: \(seedExecution.executions.count)")
            }
            lines.append("")
            for (index, execution) in seedExecution.executions.enumerated() {
                let spec = execution.task
                let header = "#### Task \(index + 1): \(spec.id) [\(spec.type.rawValue)]"
                lines.append(header)
                if let taskReport = seedReport?.tasks[safe: index] {
                    lines.append(String(format: "- Result: %@", taskReport.pass ? "Pass" : "Fail"))
                    lines.append(String(format: "- Score: %.2f", taskReport.score))
                    if !taskReport.reason.isEmpty {
                        let friendlyReason = BenchmarkVerifier.humanReadableReason(taskReport.reason)
                        lines.append("- Reason: \(friendlyReason)")
                    }
                }
                if !spec.task.isEmpty {
                    lines.append("- User Task: \(spec.task)")
                }
                if !spec.instructions.isEmpty {
                    lines.append("- Instructions:")
                    for instruction in spec.instructions {
                        lines.append("  - \(instruction)")
                    }
                }
                if !spec.acceptance.isEmpty {
                    lines.append("- Acceptance Criteria:")
                    for item in spec.acceptance {
                        lines.append("  - \(item)")
                    }
                }
                lines.append("- Selected Files: \(spec.selectFiles.joined(separator: ", "))")
                lines.append("- Max Edits: \(spec.maxEdits)")
                if !spec.params.isEmpty {
                    lines.append("- Params:")
                    for key in spec.params.keys.sorted() {
                        if let value = spec.params[key] {
                            lines.append("  - \(key): \(describeJSONValue(value))")
                        }
                    }
                }
                if !execution.result.errors.isEmpty {
                    lines.append("- Errors:")
                    for error in execution.result.errors {
                        var parts: [String] = [error.code]
                        if let path = error.path {
                            parts.append("path=\(path)")
                        }
                        if let detail = error.detail, !detail.isEmpty {
                            parts.append(detail)
                        }
                        lines.append("  - \(parts.joined(separator: " • "))")
                    }
                }
                if !execution.result.edited.isEmpty {
                    lines.append("- Edited Files:")
                    for edit in execution.result.edited {
                        lines.append("  - \(edit.path)")
                    }
                }
                if let meta = execution.result.meta, !meta.isEmpty {
                    let sortedMeta = meta.keys.sorted()
                    let filteredKeys = sortedMeta.filter { !["rawOutput", "systemPrompt", "userPrompt", "virtualFiles"].contains($0) }
                    if !filteredKeys.isEmpty {
                        lines.append("- Meta:")
                        for key in filteredKeys {
                            if let value = meta[key] {
                                lines.append("  - \(key): \(describeJSONValue(value))")
                            }
                        }
                    }
                    if let rawOutput = meta["rawOutput"]?.stringValue, !rawOutput.isEmpty {
                        lines.append("- Raw Output:")
                        lines.append("```xml")
                        lines.append(rawOutput)
                        lines.append("```")
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func describeJSONValue(_ value: BenchmarkJSONValue) -> String {
        switch value {
        case let .string(string):
            return string
        case let .integer(integer):
            return String(integer)
        case let .double(double):
            return String(double)
        case let .boolean(bool):
            return bool ? "true" : "false"
        case let .array(array):
            let items = array.map { describeJSONValue($0) }
            return "[" + items.joined(separator: ", ") + "]"
        case let .object(object):
            let entries = object.sorted { $0.key < $1.key }
            let parts = entries.map { "\($0.key): \(describeJSONValue($0.value))" }
            return "{" + parts.joined(separator: ", ") + "}"
        case .null:
            return "null"
        }
    }

    private static func makeRandomCoreSeed() -> UInt32 {
        UInt32.random(in: 1 ... UInt32.max)
    }

    private func friendlyName(for type: BenchmarkCaseType) -> String {
        let tokens = type.rawValue.split(separator: "_")
        let words = tokens.map { token -> String in
            switch token.lowercased() {
            case "ts":
                return "TypeScript"
            case "go":
                return "Go"
            default:
                return token.capitalized
            }
        }
        return words.joined(separator: " ")
    }

    private func friendlyName(forRawType rawType: String) -> String {
        let tokens = rawType.split(separator: "_")
        let words = tokens.map { token -> String in
            switch token.lowercased() {
            case "ts":
                return "TypeScript"
            case "go":
                return "Go"
            default:
                return token.capitalized
            }
        }
        return words.joined(separator: " ")
    }

    func exportHistoryToCSV() -> URL? {
        guard !history.isEmpty else { return nil }
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }

        let timestamp = Self.logFileNameFormatter.string(from: Date())
        let fileName = "RepoPrompt-Benchmark-History-\(timestamp).csv"
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        var csvLines: [String] = []

        // CSV Header - One row per run
        csvLines.append("Run ID,Timestamp,Model Name,Model Raw Value,Provider,Temperature,Total Tasks,Passed Tasks,Failed Tasks,Pass Rate (%),Average Score,Points Earned,Max Points,Points Rate (%),Failed Task Types")

        // CSV Rows - One row per run
        for run in history {
            let runID = run.id.uuidString
            let timestamp = Self.csvTimestampFormatter.string(from: run.timestamp)
            let modelName = csvEscape(run.modelDisplayShort)
            let modelRaw = csvEscape(run.modelRawValue)
            let provider = csvEscape(run.providerName)
            let temperature = if let model = AIModel.fromModelName(run.modelRawValue),
                                 let resolvedTemp = model.resolveTemperature(explicitTemperature: run.temperature, includeOverrides: false)
            {
                String(format: "%.2f", resolvedTemp)
            } else {
                "API Default"
            }
            let totalTasks = String(run.totalTasks)
            let passedTasks = String(run.passedTasks)
            let failedTasks = String(run.totalTasks - run.passedTasks)
            let passRate = String(format: "%.2f", run.passRate * 100)
            let averageScore = String(format: "%.2f", run.averageScore)
            let pointsEarned = String(format: "%.1f", run.totalPointsEarned)
            let maxPoints = String(format: "%.0f", run.totalMaxPoints)
            let pointsRate = String(format: "%.2f", run.pointsRate * 100)

            // Build failed task types summary
            var failedByType: [String: Int] = [:]
            for seedSummary in run.seedSummaries {
                for task in seedSummary.tasks where !task.pass {
                    let taskType = friendlyName(forRawType: task.type)
                    failedByType[taskType, default: 0] += 1
                }
            }
            let failedSummary = failedByType.isEmpty ? "None" : failedByType.map { "\($0.key)(\($0.value))" }.sorted().joined(separator: "; ")

            csvLines.append([
                runID,
                timestamp,
                modelName,
                modelRaw,
                provider,
                temperature,
                totalTasks,
                passedTasks,
                failedTasks,
                passRate,
                averageScore,
                pointsEarned,
                maxPoints,
                pointsRate,
                csvEscape(failedSummary)
            ].joined(separator: ","))
        }

        let csvContent = csvLines.joined(separator: "\n")

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            runError = "Failed to export CSV: \(error.localizedDescription)"
            return nil
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Debug Single Test Run

    var debugAvailableTests: [(seed: UInt32, tasks: [DebugTaskRef])] {
        let coreSeed = UInt32(coreSeedInput) ?? BenchmarkSeedUtilities.canonicalCoreSeed
        let subSeeds = BenchmarkSeedUtilities.deriveSubSeeds(coreSeed: coreSeed, count: max(1, subSeedCount))
        let config = BenchConfig(tasksAreCumulative: true)
        let generator = BenchmarkTaskGenerator()

        return subSeeds.enumerated().map { seedIndex, seed in
            let generated = generator.generateSeed(seed, config: config)
            let tasks = generated.tasks.enumerated().map { taskIndex, spec in
                DebugTaskRef(
                    id: "\(seed)-\(taskIndex)-\(spec.id)",
                    seed: seed,
                    seedIndex: seedIndex,
                    taskIndex: taskIndex,
                    spec: spec
                )
            }
            return (seed: seed, tasks: tasks)
        }
    }

    func runSingleTestDebug(_ ref: DebugTaskRef) async {
        // Track running state immediately
        runningTestIDs.insert(ref.id)
        runError = nil

        defer {
            runningTestIDs.remove(ref.id)
        }

        guard !isRunning else {
            runError = "Cannot run single test while full benchmark is running."
            return
        }

        let model = AIModel.fromModelName(selectedModelRaw) ?? promptViewModel.preferredAIModel
        guard let aiService = promptViewModel.aiQueriesService else {
            runError = "AI service unavailable."
            return
        }

        // Generate the test fresh from the seed
        let config = BenchConfig(tasksAreCumulative: false)
        let generator = BenchmarkTaskGenerator()
        let generated = generator.generateSeed(ref.seed, config: config)

        guard let taskSpec = generated.tasks[safe: ref.taskIndex] else {
            runError = "Task not found in generated seed."
            return
        }

        // Use the initial baseline (no cumulative state for debug)
        let baseline = generated.baseline

        // Create a fresh file system from the baseline
        var fs = BenchmarkMockFileSystem(files: baseline.dictionary())

        // Build executor
        let executor = BenchmarkTaskExecutor(
            aiQueriesService: aiService,
            model: model,
            maxContextChars: config.contextCharBudget,
            maxDecoyPerFileChars: config.decoyCharCap
        )

        // Execute the task
        let result = await executor.runTask(taskSpec, fileSystem: &fs, baseline: baseline)

        // Run verification
        let verifier = BenchmarkVerifier(policy: GradingPolicy(passThreshold: 0.92, lenient: false))
        let execution = BenchmarkTaskExecution(task: taskSpec, baseline: baseline, result: result)
        let verifyOutput = verifier.verify(execution)

        // Write debug log with verification results
        let url = await writeSingleTestDebugLog(
            model: model,
            seed: ref.seed,
            spec: taskSpec,
            baseline: baseline,
            result: result,
            verification: verifyOutput
        )

        if let url {
            latestLogURL = url
            runError = nil
        } else {
            if runError == nil {
                runError = "Failed to write debug log."
            }
        }
    }

    private func writeSingleTestDebugLog(
        model: AIModel,
        seed: UInt32,
        spec: BenchmarkTaskSpec,
        baseline: BenchmarkMockFileSystemSnapshot,
        result: BenchmarkTaskExecResult,
        verification: BenchmarkVerifyOutput
    ) async -> URL? {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            if runError == nil {
                runError = "Failed to locate Downloads folder."
            }
            return nil
        }

        let timestamp = Self.logFileNameFormatter.string(from: Date())
        let fileName = "RepoPrompt-Benchmark-Test-\(timestamp)-seed-\(seed)-\(spec.id).md"
        let fileURL = downloadsURL.appendingPathComponent(fileName)

        let content = makeSingleTestDebugLogContent(
            model: model,
            seed: seed,
            spec: spec,
            baseline: baseline,
            result: result,
            verification: verification
        )

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            if runError == nil {
                runError = "Failed to write debug log: \(error.localizedDescription)"
            }
            return nil
        }
    }

    private func makeSingleTestDebugLogContent(
        model: AIModel,
        seed: UInt32,
        spec: BenchmarkTaskSpec,
        baseline: BenchmarkMockFileSystemSnapshot,
        result: BenchmarkTaskExecResult,
        verification: BenchmarkVerifyOutput
    ) -> String {
        var lines: [String] = []
        lines.append("# RepoPrompt Single-Test Debug")
        lines.append("")
        lines.append("- Timestamp: \(Self.logTimestampFormatter.string(from: Date()))")
        lines.append("- Model: \(model.displayName) (\(model.rawValue))")
        lines.append("- Temperature: API Default (app overrides ignored)")
        lines.append("- Seed: \(seed)")
        lines.append("- Test: \(spec.id) [\(spec.type.rawValue)]")
        lines.append("")

        lines.append("## Result")
        lines.append("- Status: \(verification.pass ? "✅ PASS" : "❌ FAIL")")
        lines.append(String(format: "- Score: %.2f", verification.score))
        if !verification.reason.isEmpty {
            let friendlyReason = BenchmarkVerifier.humanReadableReason(verification.reason)
            lines.append("- Reason: \(friendlyReason)")
        }
        if !verification.metrics.isEmpty {
            lines.append("- Metrics:")
            for key in verification.metrics.keys.sorted() {
                if let value = verification.metrics[key] {
                    lines.append("  - \(key): \(describeJSONValue(value))")
                }
            }
        }
        lines.append("")

        lines.append("## Task")
        lines.append("- Select Files: \(spec.selectFiles.joined(separator: ", "))")
        lines.append("- Max Edits: \(spec.maxEdits)")
        if !spec.task.isEmpty {
            lines.append("- User Task: \(spec.task)")
        }
        if !spec.instructions.isEmpty {
            lines.append("- Instructions:")
            for instruction in spec.instructions {
                lines.append("  - \(instruction)")
            }
        }
        if !spec.acceptance.isEmpty {
            lines.append("- Acceptance:")
            for item in spec.acceptance {
                lines.append("  - \(item)")
            }
        }
        if !spec.params.isEmpty {
            lines.append("- Params:")
            for key in spec.params.keys.sorted() {
                if let value = spec.params[key] {
                    lines.append("  - \(key): \(describeJSONValue(value))")
                }
            }
        }
        lines.append("")

        // Prompt meta
        if let meta = result.meta {
            if let systemPrompt = meta["systemPrompt"]?.stringValue, !systemPrompt.isEmpty {
                lines.append("## System Prompt")
                lines.append("```")
                lines.append(systemPrompt)
                lines.append("```")
                lines.append("")
            }

            if let userPrompt = meta["userPrompt"]?.stringValue, !userPrompt.isEmpty {
                lines.append("## User Prompt")
                lines.append("```")
                lines.append(userPrompt)
                lines.append("```")
                lines.append("")
            }

            if case let .array(virtualFilesArray)? = meta["virtualFiles"] {
                lines.append("## Virtual Files")
                for vf in virtualFilesArray {
                    if case let .object(obj) = vf,
                       let path = obj["path"]?.stringValue,
                       let role = obj["role"]?.stringValue,
                       let fence = obj["fence"]?.stringValue,
                       let block = obj["block"]?.stringValue
                    {
                        let truncated = obj["truncated"]?.boolValue ?? false
                        lines.append("### \(path)")
                        lines.append("- Role: \(role)")
                        if truncated {
                            lines.append("- Truncated: yes")
                        }
                        lines.append(block)
                        lines.append("")
                    }
                }
                lines.append("")
            }

            if let rawOutput = meta["rawOutput"]?.stringValue, !rawOutput.isEmpty {
                lines.append("## Raw Output")
                lines.append("```xml")
                lines.append(rawOutput)
                lines.append("```")
                lines.append("")
            }

            // Parse summary meta
            let metaKeys = meta.keys.filter { !["systemPrompt", "userPrompt", "virtualFiles", "rawOutput"].contains($0) }
            if !metaKeys.isEmpty {
                lines.append("## Parse Meta")
                for key in metaKeys.sorted() {
                    if let value = meta[key] {
                        lines.append("- \(key): \(describeJSONValue(value))")
                    }
                }
                lines.append("")
            }
        }

        // Edited files
        if !result.edited.isEmpty {
            lines.append("## Edited Files")
            for edit in result.edited {
                lines.append("### \(edit.path)")
                lines.append("```")
                lines.append(edit.content)
                lines.append("```")
                lines.append("")
            }
        }

        // Errors
        if !result.errors.isEmpty {
            lines.append("## Errors")
            for error in result.errors {
                var parts: [String] = [error.code]
                if let path = error.path {
                    parts.append("path=\(path)")
                }
                if let detail = error.detail, !detail.isEmpty {
                    parts.append(detail)
                }
                lines.append("- \(parts.joined(separator: " • "))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
