@testable import RepoPrompt
import XCTest

final class AgentFileTagWorktreeResolutionTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    @MainActor
    func testExpandedBoundWorktreeSuggestionUsesLogicalPathAndSubtitle() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: true)
        let lookupContext = await makeLookupContext(fixture: fixture)
        let configuration = FileMentionPickerConfiguration.expanded
        let service = AgentFileTagSuggestionService(
            store: fixture.store,
            searchService: nil,
            selectionCoordinator: nil,
            lookupContextProvider: { lookupContext },
            maxResults: configuration.maxResults,
            showsFileSubtitles: configuration.showsFileSubtitles
        )

        let suggestions = await service.suggestions(for: "BranchOnly")
        let suggestion = try XCTUnwrap(suggestions.first { $0.relativePath == "Sources/BranchOnly.swift" })

        XCTAssertEqual(suggestion.subtitle, "Sources")
        XCTAssertFalse(suggestions.contains { $0.relativePath.contains(".worktrees") }, String(describing: suggestions))
        XCTAssertFalse(suggestions.contains { $0.relativePath.contains(fixture.worktreeRoot.path) }, String(describing: suggestions))
    }

    @MainActor
    func testUnboundSuggestionDoesNotReadHiddenSessionWorktreeRoots() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: true)
        _ = await makeLookupContext(fixture: fixture) // Materializes the hidden session worktree root in the store.
        let service = AgentFileTagSuggestionService(
            store: fixture.store,
            searchService: nil,
            selectionCoordinator: nil,
            lookupContextProvider: { .visibleWorkspace },
            maxResults: 5
        )

        let suggestions = await service.suggestions(for: "BranchOnly")

        XCTAssertTrue(suggestions.isEmpty, String(describing: suggestions))
    }

    func testProviderTaggedFileContentReadsWorktreeButDisplaysLogicalPathAndDedupes() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: false)
        let lookupContext = await makeLookupContext(fixture: fixture)
        let physicalWorktreePath = fixture.worktreeRoot.appendingPathComponent("Sources/App.swift").path

        let resolvedXML = await AgentModeViewModel.taggedFileContentsXMLForTaggedPaths(
            ["Sources/App.swift", physicalWorktreePath],
            tokenBudget: 10000,
            maxFiles: 10,
            store: fixture.store,
            lookupContext: lookupContext
        )
        let xml = try XCTUnwrap(resolvedXML)

        XCTAssertTrue(xml.contains("File: Sources/App.swift"), xml)
        XCTAssertTrue(xml.contains("let origin = \"worktree\""), xml)
        XCTAssertFalse(xml.contains("let origin = \"base\""), xml)
        XCTAssertFalse(xml.contains(fixture.worktreeRoot.path), xml)
        XCTAssertEqual(xml.components(separatedBy: "let origin = \"worktree\"").count - 1, 1, xml)
    }

    func testPromotionLogicalizesStalePhysicalSelectionAndDedupesByEffectivePhysicalPath() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: false)
        let lookupContext = await makeLookupContext(fixture: fixture)
        let physicalPath = fixture.worktreeRoot.appendingPathComponent("Sources/App.swift").path
        let logicalPath = fixture.logicalRoot.appendingPathComponent("Sources/App.swift").path
        let staleSelection = StoredSelection(
            selectedPaths: [physicalPath],
            autoCodemapPaths: [physicalPath],
            slices: [physicalPath: [LineRange(start: 1, end: 1)]],
            codemapAutoEnabled: false
        )

        let updated = AgentModeViewModel.selectionByPromotingPathsToFullSelection(
            staleSelection,
            paths: [logicalPath],
            lookupContext: lookupContext
        )

        XCTAssertEqual(updated.selectedPaths, [logicalPath])
        XCTAssertTrue(updated.autoCodemapPaths.isEmpty)
        XCTAssertTrue(updated.slices.isEmpty)
        XCTAssertFalse(updated.selectedPaths.contains { $0.contains(fixture.worktreeRoot.path) })
    }

    @MainActor
    func testExpandedAgentFileTagsReturnMoreThanCompactCapWithParentSubtitles() async throws {
        let root = try makeTemporaryRoot(name: "AgentFileTagExpanded")
        let matchingFileCount = 80
        for index in 0 ..< matchingFileCount {
            let name = String(format: "Match%02d.swift", index)
            try write("let match\(index) = true\n", to: root.appendingPathComponent("Sources/\(name)"))
        }
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: root.path)
        let config = FileMentionPickerConfiguration.expanded
        let service = AgentFileTagSuggestionService(
            store: store,
            searchService: nil,
            selectionCoordinator: nil,
            lookupContextProvider: { .visibleWorkspace },
            maxResults: config.maxResults,
            showsFileSubtitles: config.showsFileSubtitles
        )

        let suggestions = await service.suggestions(for: "Match")

        XCTAssertEqual(suggestions.count, matchingFileCount, String(describing: suggestions))
        XCTAssertTrue(suggestions.count > FileMentionPickerConfiguration.compact.maxResults)
        XCTAssertTrue(suggestions.count > 64)
        XCTAssertTrue(suggestions.allSatisfy { $0.kind == .file })
        XCTAssertEqual(Set(suggestions.compactMap(\.subtitle)), ["Sources"])
        XCTAssertTrue(suggestions.allSatisfy { $0.commitDisplayText?.hasPrefix("Match") == true })
        XCTAssertTrue(suggestions.allSatisfy { $0.commitDisplayText?.contains("Sources/") == false })
    }

    @MainActor
    func testCompactAgentFileTagsPreserveDuplicateDisambiguationSubtitles() async throws {
        let firstRoot = try makeTemporaryRoot(name: "AgentFileTagDuplicateA")
        let secondRoot = try makeTemporaryRoot(name: "AgentFileTagDuplicateB")
        try write("let duplicate = \"a\"\n", to: firstRoot.appendingPathComponent("Sources/Shared.swift"))
        try write("let duplicate = \"b\"\n", to: secondRoot.appendingPathComponent("Sources/Shared.swift"))
        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: firstRoot.path)
        _ = try await store.loadRoot(path: secondRoot.path)
        let service = AgentFileTagSuggestionService(
            store: store,
            searchService: nil,
            selectionCoordinator: nil,
            lookupContextProvider: { .visibleWorkspace },
            maxResults: FileMentionPickerConfiguration.compact.maxResults,
            showsFileSubtitles: FileMentionPickerConfiguration.compact.showsFileSubtitles
        )

        let suggestions = await service.suggestions(for: "Shared")

        XCTAssertEqual(suggestions.count, 2, String(describing: suggestions))
        XCTAssertEqual(
            Set(suggestions.compactMap(\.subtitle)),
            [firstRoot.lastPathComponent, secondRoot.lastPathComponent]
        )
        XCTAssertTrue(suggestions.allSatisfy { $0.commitDisplayText?.hasSuffix("Sources/Shared.swift") == true })
    }

    @MainActor
    func testPartiallyBoundWorkspaceKeepsUnboundRootSuggestionDisplayRelative() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: false)
        let unboundRoot = try makeTemporaryRoot(name: "AgentFileTagUnbound")
        try write("let unbound = true\n", to: unboundRoot.appendingPathComponent("Sources/Other.swift"))
        _ = try await fixture.store.loadRoot(path: unboundRoot.path)
        let lookupContext = await makeLookupContext(fixture: fixture)
        let service = AgentFileTagSuggestionService(
            store: fixture.store,
            searchService: nil,
            selectionCoordinator: nil,
            lookupContextProvider: { lookupContext },
            maxResults: 5
        )

        let suggestions = await service.suggestions(for: "Other")
        let suggestion = try XCTUnwrap(suggestions.first { $0.relativePath.contains("Other.swift") })
        let logicalRootQualifiedSuggestions = await service.suggestions(for: "\(fixture.logicalRoot.lastPathComponent)/Sources/App")

        XCTAssertFalse(suggestion.relativePath.hasPrefix("/"), String(describing: suggestions))
        XCTAssertFalse(suggestion.relativePath.contains(unboundRoot.path), String(describing: suggestions))
        XCTAssertTrue(
            logicalRootQualifiedSuggestions.contains { $0.relativePath.contains("Sources/App.swift") },
            String(describing: logicalRootQualifiedSuggestions)
        )
        XCTAssertFalse(
            logicalRootQualifiedSuggestions.contains { $0.relativePath.contains(fixture.worktreeRoot.path) },
            String(describing: logicalRootQualifiedSuggestions)
        )
    }

    func testPartiallyBoundWorkspaceKeepsUnboundRootProviderDisplayRelative() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: false)
        let unboundRoot = try makeTemporaryRoot(name: "AgentFileTagProviderUnbound")
        let unboundFile = unboundRoot.appendingPathComponent("Sources/Other.swift")
        try write("let unbound = true\n", to: unboundFile)
        _ = try await fixture.store.loadRoot(path: unboundRoot.path)
        let lookupContext = await makeLookupContext(fixture: fixture)

        let resolvedXML = await AgentModeViewModel.taggedFileContentsXMLForTaggedPaths(
            [unboundFile.path],
            tokenBudget: 10000,
            maxFiles: 10,
            store: fixture.store,
            lookupContext: lookupContext
        )
        let xml = try XCTUnwrap(resolvedXML)

        XCTAssertTrue(xml.contains("let unbound = true"), xml)
        XCTAssertFalse(xml.contains(unboundRoot.path), xml)
    }

    func testNonWorktreeProviderTaggedFileContentPreservesVisibleWorkspaceBehavior() async throws {
        let fixture = try await makeBoundFixture(includeBranchOnly: true)
        _ = await makeLookupContext(fixture: fixture) // Keep hidden worktree loaded; visible lookups must still ignore it.

        let resolvedVisibleXML = await AgentModeViewModel.taggedFileContentsXMLForTaggedPaths(
            ["Sources/App.swift"],
            tokenBudget: 10000,
            maxFiles: 10,
            store: fixture.store,
            lookupContext: .visibleWorkspace
        )
        let visibleXML = try XCTUnwrap(resolvedVisibleXML)
        let hiddenXML = await AgentModeViewModel.taggedFileContentsXMLForTaggedPaths(
            ["Sources/BranchOnly.swift"],
            tokenBudget: 10000,
            maxFiles: 10,
            store: fixture.store,
            lookupContext: .visibleWorkspace
        )

        XCTAssertTrue(visibleXML.contains("let origin = \"base\""), visibleXML)
        XCTAssertFalse(visibleXML.contains("let origin = \"worktree\""), visibleXML)
        XCTAssertNil(hiddenXML)
    }

    private func makeBoundFixture(includeBranchOnly: Bool) async throws -> (
        logicalRoot: URL,
        worktreeRoot: URL,
        store: WorkspaceFileContextStore,
        sessionID: UUID,
        binding: AgentSessionWorktreeBinding
    ) {
        let logicalRoot = try makeTemporaryRoot(name: "AgentFileTagLogical")
        let worktreeRoot = try makeTemporaryRoot(name: "AgentFileTagWorktree")
        try write("let origin = \"base\"\n", to: logicalRoot.appendingPathComponent("Sources/App.swift"))
        try write("let origin = \"worktree\"\n", to: worktreeRoot.appendingPathComponent("Sources/App.swift"))
        if includeBranchOnly {
            try write("let branchOnly = true\n", to: worktreeRoot.appendingPathComponent("Sources/BranchOnly.swift"))
        }

        let store = WorkspaceFileContextStore()
        _ = try await store.loadRoot(path: logicalRoot.path)
        let sessionID = UUID()
        let binding = makeBinding(logicalRoot: logicalRoot, worktreeRoot: worktreeRoot)
        return (logicalRoot, worktreeRoot, store, sessionID, binding)
    }

    private func makeLookupContext(
        fixture: (
            logicalRoot: URL,
            worktreeRoot: URL,
            store: WorkspaceFileContextStore,
            sessionID: UUID,
            binding: AgentSessionWorktreeBinding
        )
    ) async -> WorkspaceLookupContext {
        await AgentWorkspaceLookupContextResolver.lookupContext(
            source: AgentWorkspaceLookupContextSource(
                activeAgentSessionID: fixture.sessionID,
                worktreeBindings: [fixture.binding]
            ),
            store: fixture.store
        )
    }

    private func makeBinding(logicalRoot: URL, worktreeRoot: URL) -> AgentSessionWorktreeBinding {
        AgentSessionWorktreeBinding(
            id: "bind_test",
            repositoryID: "repo_test",
            repoKey: "repo",
            logicalRootPath: logicalRoot.path,
            logicalRootName: logicalRoot.lastPathComponent,
            worktreeID: "worktree_test",
            worktreeRootPath: worktreeRoot.path,
            worktreeName: worktreeRoot.lastPathComponent,
            branch: "feature/test",
            head: "abcdef",
            visualLabel: "test",
            visualColorHex: "#3366FF",
            boundAt: Date(timeIntervalSinceReferenceDate: 123),
            source: "test"
        )
    }

    private func makeTemporaryRoot(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoPromptTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryRoots.append(url)
        return url
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
