import Foundation

enum CursorACPLaunchCandidate: CaseIterable, Equatable {
    case cursorAgentACP
    case agentACP

    var command: String {
        switch self {
        case .cursorAgentACP:
            CLILaunchProfiles.cursor.commandName
        case .agentACP:
            "agent"
        }
    }

    var launchArguments: [String] {
        ["--approve-mcps", "acp"]
    }

    var helpArguments: [String] {
        ["acp", "--help"]
    }
}

struct CursorACPResolvedLaunch: Equatable {
    let candidate: CursorACPLaunchCandidate
    let command: String
    let arguments: [String]
    let additionalPathHints: [String]
    let environment: [String: String]
    let executableIdentity: ExecutableFileIdentity
}

enum CursorACPLaunchResolutionError: Error, Equatable, LocalizedError {
    case missingConfiguredCommand
    case unsafeConfiguredCommand(String)
    case exactPathNotFound(String)
    case noValidLaunchCandidate(String, [String], ShellEnvironmentSource?)
    case environmentDiscoveryRequired(String)
    case unsafeApplicationPath(String)
    case unsafeCanonicalBasename(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguredCommand:
            "Cursor Agent CLI launch requires `cursor-agent`, a verified `agent`, or an absolute path to either executable."
        case let .unsafeConfiguredCommand(command):
            "Refusing unsafe Cursor ACP command `\(command)`. Configure `cursor-agent` or the Cursor `agent` executable."
        case let .exactPathNotFound(command):
            "Cursor Agent CLI was not found as a valid executable regular file for `\(command)`. Install Cursor Agent CLI or configure an absolute `cursor-agent` or `agent` path."
        case let .noValidLaunchCandidate(command, failures, source):
            AgentCLILaunchDiagnostics.appendFallbackEnvironmentHint(
                to: "Cursor Agent CLI was not found as a valid executable regular file for `\(command)`. Tried: \(failures.joined(separator: "; "))",
                source: source
            )
        case let .environmentDiscoveryRequired(command):
            "Cursor Agent CLI discovery or identity verification has not completed for `\(command)`. Run the Cursor ACP support preflight before launching a generic `agent` entrypoint."
        case let .unsafeApplicationPath(path):
            "Refusing Cursor ACP executable inside an application bundle: \(path)"
        case let .unsafeCanonicalBasename(path):
            "Refusing Cursor ACP executable whose canonical basename is `cursor`: \(path)"
        }
    }
}

final class CursorACPLaunchResolver: @unchecked Sendable {
    typealias EnvironmentProvider = @Sendable (_ enableDebugLogging: Bool) async -> ACPLaunchEnvironment
    typealias SupplementalPathProvider = @Sendable (_ configuredPaths: [String]) -> [String]

    private let environmentProvider: EnvironmentProvider
    private let supplementalPathProvider: SupplementalPathProvider
    private let probeMutex = AsyncMutex()
    private let lock = NSLock()
    private var cachedLaunchByKey: [String: CursorACPResolvedLaunch] = [:]

    convenience init(
        environmentProvider: @escaping @Sendable (_ enableDebugLogging: Bool) async -> [String: String],
        supplementalPathProvider: @escaping SupplementalPathProvider = {
            CLILaunchProfiles.providerSpecificPathsSupplementedWithNativeDefaults($0)
        }
    ) {
        self.init(launchEnvironmentProvider: { enableDebugLogging in
            await ACPLaunchEnvironment(environment: environmentProvider(enableDebugLogging))
        }, supplementalPathProvider: supplementalPathProvider)
    }

    init(
        launchEnvironmentProvider: @escaping EnvironmentProvider = { enableDebugLogging in
            let result = await ProcessEnvironmentBuilder.build(
                ProcessEnvironmentRequest(
                    purpose: .acpAgent(providerID: ACPProviderID.cursor.rawValue),
                    enableDebugLogging: enableDebugLogging
                )
            )
            return ACPLaunchEnvironment(
                environment: result.environment,
                shellEnvironmentSource: result.shellEnvironmentSource
            )
        },
        supplementalPathProvider: @escaping SupplementalPathProvider = {
            CLILaunchProfiles.providerSpecificPathsSupplementedWithNativeDefaults($0)
        }
    ) {
        environmentProvider = launchEnvironmentProvider
        self.supplementalPathProvider = supplementalPathProvider
    }

    func resolvedLaunch(for config: CursorAgentConfig) throws -> CursorACPResolvedLaunch {
        let key = cacheKey(for: config)
        if let cached = cachedLaunch(forKey: key) {
            do {
                try cached.executableIdentity.validateForTrustedPathLaunch(atPath: cached.command)
                return cached
            } catch {
                invalidate(key: key)
                throw error
            }
        }

        let configuredCommand = try validatedConfiguredCommand(config)
        if (configuredCommand as NSString).lastPathComponent.caseInsensitiveCompare(
            CursorACPLaunchCandidate.agentACP.command
        ) == .orderedSame {
            throw CursorACPLaunchResolutionError.environmentDiscoveryRequired(configuredCommand)
        }

        let launch = try resolveExplicitLaunch(for: config)
        cache(launch, key: key)
        return launch
    }

    func probeSupport(for config: CursorAgentConfig) async throws -> ACPSupportResult {
        try await probeMutex.withLock { [self] in
            try await probeSupportSerially(for: config)
        }
    }

    private func probeSupportSerially(for config: CursorAgentConfig) async throws -> ACPSupportResult {
        let key = cacheKey(for: config)
        invalidate(key: key)
        do {
            // Resolve from the current effective environment on every support check. The cache only
            // bridges this successful probe to the immediately following launch configuration.
            let launch = try await resolveLaunchForProbe(for: config)
            let processConfig = CLIProcessConfiguration(
                command: launch.command,
                additionalPaths: [],
                enableDebugLogging: config.enableDebugLogging,
                shellLookupMode: .fallbackOnly
            )
            let result = try await CLIProcessRunner(config: processConfig).run(
                args: launch.candidate.helpArguments,
                stdin: nil,
                outputMode: .none,
                timeout: 10,
                cancelChildOnTaskCancellation: true
            )
            guard result.status == 0 else {
                return .unsupported(
                    reason: "Cursor Agent CLI ACP preflight failed: `\(launch.candidate.command) acp --help` exited with status \(result.status)."
                )
            }

            let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            let combined = "\(stdout)\n\(stderr)"
            guard advertisesCursorACP(combined, candidate: launch.candidate) else {
                return .unsupported(
                    reason: "Cursor Agent CLI ACP preflight failed: `\(launch.candidate.command) acp --help` did not prove Cursor ACP support."
                )
            }

            try launch.executableIdentity.validateForTrustedPathLaunch(atPath: launch.command)
            cache(launch, key: key)
            return .supported
        } catch is CancellationError {
            invalidate(key: key)
            throw CancellationError()
        } catch {
            invalidate(key: key)
            return .unsupported(reason: error.localizedDescription)
        }
    }

    private func resolveLaunchForProbe(for config: CursorAgentConfig) async throws -> CursorACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        let launchEnvironment = await environmentProvider(config.enableDebugLogging)
        let environment = launchEnvironment.environment
        try Task.checkCancellation()
        if configuredCommand.contains("/") {
            return try resolveExplicitLaunch(
                for: config,
                environment: environment,
                shellEnvironmentSource: launchEnvironment.shellEnvironmentSource
            )
        }

        let effectiveHints = supplementalPathProvider(config.additionalPathHints)
        return try firstValidLaunch(
            candidates: launchCandidates(
                configuredCommand: configuredCommand,
                additionalPathHints: effectiveHints,
                environment: environment
            ),
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints,
            environment: environment,
            shellEnvironmentSource: launchEnvironment.shellEnvironmentSource
        )
    }

    private func resolveExplicitLaunch(
        for config: CursorAgentConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shellEnvironmentSource: ShellEnvironmentSource? = nil
    ) throws -> CursorACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        guard configuredCommand.contains("/") else {
            throw CursorACPLaunchResolutionError.environmentDiscoveryRequired(configuredCommand)
        }
        let effectiveHints = supplementalPathProvider(config.additionalPathHints)
        do {
            return try validatedLaunch(
                entryPath: CommandPathResolver.expandPath(configuredCommand, environment: environment),
                configuredCommand: configuredCommand,
                additionalPathHints: effectiveHints,
                environment: environment
            )
        } catch {
            // Explicit-path failures intentionally keep their specific errors
            // (exactPathNotFound / unsafeApplicationPath / unsafeCanonicalBasename) and omit the
            // fallback-PATH hint: an exact configured path does not depend on PATH discovery.
            // Still record the same resolution-failure telemetry OpenCode emits for explicit paths.
            AgentCLILaunchDiagnostics.recordPathResolutionFailure(
                providerKind: .cursor,
                shellEnvironmentSource: shellEnvironmentSource,
                candidateCount: 1
            )
            throw error
        }
    }

    private func validatedConfiguredCommand(_ config: CursorAgentConfig) throws -> String {
        let configuredCommand = config.commandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configuredCommand.isEmpty else {
            throw CursorACPLaunchResolutionError.missingConfiguredCommand
        }
        let supportedCommands = Set(CursorACPLaunchCandidate.allCases.map { $0.command.lowercased() })
        let configuredBasename = (configuredCommand as NSString).lastPathComponent.lowercased()
        guard supportedCommands.contains(configuredBasename) else {
            throw CursorACPLaunchResolutionError.unsafeConfiguredCommand(configuredCommand)
        }
        if configuredCommand.contains("/") {
            return configuredCommand
        } else if configuredCommand.caseInsensitiveCompare(configuredBasename) != .orderedSame {
            throw CursorACPLaunchResolutionError.unsafeConfiguredCommand(configuredCommand)
        }
        return configuredCommand
    }

    private func validatedLaunch(
        entryPath: String,
        configuredCommand: String,
        additionalPathHints: [String],
        environment: [String: String],
        preserveValidationError: Bool = false
    ) throws -> CursorACPResolvedLaunch {
        let entryBasename = (entryPath as NSString).lastPathComponent.lowercased()
        let candidate = CursorACPLaunchCandidate.allCases.first { $0.command.lowercased() == entryBasename }
        guard entryPath.hasPrefix("/"),
              let candidate
        else {
            throw CursorACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        let identity: ExecutableFileIdentity
        do {
            identity = try ExecutableFileIdentity.captureForTrustedPathLaunch(atPath: entryPath)
        } catch {
            if preserveValidationError { throw error }
            throw CursorACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        if identity.canonicalPath.split(separator: "/").contains(where: { $0.lowercased().hasSuffix(".app") }) {
            throw CursorACPLaunchResolutionError.unsafeApplicationPath(identity.canonicalPath)
        }
        if (identity.canonicalPath as NSString).lastPathComponent.caseInsensitiveCompare("cursor") == .orderedSame {
            throw CursorACPLaunchResolutionError.unsafeCanonicalBasename(identity.canonicalPath)
        }

        return CursorACPResolvedLaunch(
            candidate: candidate,
            command: identity.canonicalPath,
            arguments: candidate.launchArguments,
            additionalPathHints: additionalPathHints,
            environment: environment,
            executableIdentity: identity
        )
    }

    private func advertisesCursorACP(_ output: String, candidate: CursorACPLaunchCandidate) -> Bool {
        switch candidate {
        case .cursorAgentACP:
            output.localizedCaseInsensitiveContains("acp")
                || output.localizedCaseInsensitiveContains("agent client protocol")
        case .agentACP:
            output.localizedCaseInsensitiveContains("usage: agent acp")
                && output.localizedCaseInsensitiveContains("cursor agent")
                && output.localizedCaseInsensitiveContains("agent client protocol")
        }
    }

    private func launchCandidates(
        configuredCommand: String,
        additionalPathHints: [String],
        environment: [String: String]
    ) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String) {
            let expanded = CommandPathResolver.expandPath(candidate, environment: environment)
            guard !expanded.isEmpty,
                  expanded.hasPrefix("/"),
                  seen.insert(expanded).inserted
            else { return }
            candidates.append(expanded)
        }

        let configuredBasename = (configuredCommand as NSString).lastPathComponent.lowercased()
        let launchCandidates: [CursorACPLaunchCandidate] = configuredBasename == CursorACPLaunchCandidate.agentACP.command
            ? [.agentACP]
            : [.cursorAgentACP, .agentACP]
        for launchCandidate in launchCandidates {
            append(
                CommandPathResolver.resolve(
                    launchCandidate.command,
                    environment: environment,
                    additionalPaths: additionalPathHints,
                    preferredBasenames: [launchCandidate.command],
                    shellLookupMode: .fallbackOnly
                )
            )
            for directory in CommandPathResolver.mergedPathComponents(
                environment: environment,
                additionalPaths: additionalPathHints
            ) {
                append((directory as NSString).appendingPathComponent(launchCandidate.command))
            }
        }
        return candidates
    }

    private func firstValidLaunch(
        candidates: [String],
        configuredCommand: String,
        additionalPathHints: [String],
        environment: [String: String],
        shellEnvironmentSource: ShellEnvironmentSource?
    ) throws -> CursorACPResolvedLaunch {
        var failures: [String] = []
        for candidate in candidates {
            do {
                return try validatedLaunch(
                    entryPath: candidate,
                    configuredCommand: configuredCommand,
                    additionalPathHints: additionalPathHints,
                    environment: environment,
                    preserveValidationError: true
                )
            } catch {
                failures.append("\(candidate): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            throw CursorACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }
        AgentCLILaunchDiagnostics.recordPathResolutionFailure(
            providerKind: .cursor,
            shellEnvironmentSource: shellEnvironmentSource,
            candidateCount: candidates.count
        )
        throw CursorACPLaunchResolutionError.noValidLaunchCandidate(configuredCommand, failures, shellEnvironmentSource)
    }

    private func cachedLaunch(forKey key: String) -> CursorACPResolvedLaunch? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLaunchByKey[key]
    }

    private func cache(_ launch: CursorACPResolvedLaunch, key: String) {
        lock.lock()
        cachedLaunchByKey[key] = launch
        lock.unlock()
    }

    private func invalidate(key: String) {
        lock.lock()
        cachedLaunchByKey.removeValue(forKey: key)
        lock.unlock()
    }

    private func cacheKey(for config: CursorAgentConfig) -> String {
        ([config.commandName] + config.additionalPathHints).joined(separator: "\u{1F}")
    }
}
