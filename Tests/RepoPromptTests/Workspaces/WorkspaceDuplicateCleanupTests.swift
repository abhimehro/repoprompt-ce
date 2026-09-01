@testable import RepoPromptApp
@testable import RepoPromptDomainRuntime
import XCTest

#if DEBUG
    @MainActor
    final class WorkspaceDuplicateCleanupTests: XCTestCase {
        private var originalMCPAutoStart = false
        private var originalStoragePath: String?
        private var storageRoot: URL!
        private var managers: [WorkspaceManagerViewModel] = []

        override func setUp() async throws {
            try await super.setUp()
            originalMCPAutoStart = GlobalSettingsStore.shared.mcpAutoStart()
            GlobalSettingsStore.shared.setMCPAutoStart(false, commit: false)
            originalStoragePath = UserDefaults.standard.string(forKey: "GlobalCustomStorageURL")
            storageRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("WorkspaceDuplicateCleanupTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            UserDefaults.standard.set(storageRoot.path, forKey: "GlobalCustomStorageURL")
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()
        }

        override func tearDown() async throws {
            managers.forEach { $0.prepareForWindowClose() }
            managers.removeAll()
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()
            try? FileManager.default.removeItem(at: storageRoot)
            if let originalStoragePath {
                UserDefaults.standard.set(originalStoragePath, forKey: "GlobalCustomStorageURL")
            } else {
                UserDefaults.standard.removeObject(forKey: "GlobalCustomStorageURL")
            }
            GlobalSettingsStore.shared.setMCPAutoStart(originalMCPAutoStart, commit: false)
            try await super.tearDown()
        }

        func testAuthoritativeRetirementSurvivesReloadPreservesSidecarsAndUnhideRestoresDetection() async throws {
            let mergedPromptID = UUID()
            let duplicateTabID = UUID()
            let duplicateAgentSessionID = UUID()
            let duplicateChatSessionID = UUID()
            let canonical = WorkspaceModel(
                id: UUID(),
                dateModified: Date(timeIntervalSince1970: 200),
                name: "Canonical",
                repoPaths: ["/tmp/shared-workspace-root"],
                lastUsed: Date(timeIntervalSince1970: 200)
            )
            let duplicate = WorkspaceModel(
                id: UUID(),
                dateModified: Date(timeIntervalSince1970: 100),
                name: "User Hidden Duplicate",
                repoPaths: canonical.repoPaths,
                lastUsed: Date(timeIntervalSince1970: 100),
                selectedMetaPromptIDs: [mergedPromptID],
                isHiddenInMenus: true,
                composeTabs: [
                    ComposeTabState(
                        id: duplicateTabID,
                        name: "Recovered history",
                        activeChatSessionID: duplicateChatSessionID,
                        activeAgentSessionID: duplicateAgentSessionID
                    )
                ],
                activeComposeTabID: duplicateTabID
            )
            try writeWorkspace(canonical)
            try writeWorkspace(duplicate)
            try writeLegacyIndex([canonical, duplicate])

            let duplicateDirectory = workspaceFileURL(for: duplicate).deletingLastPathComponent()
            let chatsDirectory = duplicateDirectory.appendingPathComponent("Chats", isDirectory: true)
            let agentSessionsDirectory = duplicateDirectory.appendingPathComponent("AgentSessions", isDirectory: true)
            let chatSidecarURL = chatsDirectory.appendingPathComponent(
                "ChatSession-\(duplicateChatSessionID.uuidString).json"
            )
            let agentSidecarURL = agentSessionsDirectory.appendingPathComponent(
                "AgentSession-\(duplicateAgentSessionID.uuidString).json"
            )
            try FileManager.default.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: agentSessionsDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(ChatSession(
                id: duplicateChatSessionID,
                workspaceID: duplicate.id,
                composeTabID: duplicateTabID,
                name: "Recovered Oracle history",
                messages: [
                    StoredMessage(
                        isUser: false,
                        rawText: "Recovered transcript content",
                        sequenceIndex: 0
                    )
                ]
            )).write(to: chatSidecarURL, options: .atomic)
            try JSONEncoder().encode(AgentSession(
                id: duplicateAgentSessionID,
                workspaceID: duplicate.id,
                composeTabID: duplicateTabID,
                name: "Recovered Agent history",
                itemCount: 7
            )).write(to: agentSidecarURL, options: .atomic)

            let runtime = MCPDomainRuntime(configuration: .init(
                mode: .app,
                profileIdentifier: "workspace-duplicate-retirement-\(UUID().uuidString)",
                storageDirectory: storageRoot.appendingPathComponent("runtime-state", isDirectory: true),
                workspaceStorageDirectory: storageRoot,
                eventDirectory: storageRoot.appendingPathComponent("events", isDirectory: true),
                temporaryDirectory: storageRoot.appendingPathComponent("tmp", isDirectory: true),
                externalReloadInterval: nil
            ))
            try await runtime.start()
            defer { Task { _ = await runtime.shutdown() } }
            let bootstrappedSnapshot = await runtime.workspaceStore.snapshot()
            let bootstrappedWorkspaceIDs = Set(bootstrappedSnapshot.workspaces.map(\.document.workspaceID))
            XCTAssertEqual(bootstrappedWorkspaceIDs, Set([canonical.id, duplicate.id]))
            let authorityClient = DomainWorkspaceAuthorityClient(
                store: runtime.workspaceStore,
                windowID: -781
            )
            let canonicalSnapshot = try XCTUnwrap(bootstrappedSnapshot.workspaces.first {
                $0.document.workspaceID == canonical.id
            })
            let materializeOutcome = try await authorityClient.replaceWorking(
                canonical,
                fileURL: workspaceFileURL(for: canonical),
                expectedWorkspaceRevision: canonicalSnapshot.revisions.workingRevision
            )
            XCTAssertTrue(
                materializeOutcome.disposition == .applied
                    || materializeOutcome.disposition == .unchanged
                    || materializeOutcome.disposition == .deduplicated
            )

            let manager = makeManager(
                windowID: -781,
                domainWorkspaceAuthorityClient: authorityClient
            )
            let backupDirectory = storageRoot.appendingPathComponent("cleanup-backups", isDirectory: true)
            manager.setDuplicateCleanupBackupDirectoryForTesting(backupDirectory)
            await manager.awaitInitialized()
            let presentationBridge = DomainWorkspacePresentationBridge(
                workspaceManager: manager,
                client: authorityClient
            )
            presentationBridge.start()
            defer { presentationBridge.stop() }
            let initialProjectionSequence = await (runtime.workspaceStore.snapshot()).publicationSequence
            let projectedInitial = await presentationBridge.waitUntilProjected(through: initialProjectionSequence)
            XCTAssertTrue(projectedInitial)

            let canonicalIndex = try XCTUnwrap(manager.workspaces.firstIndex { $0.id == canonical.id })
            let projectedCanonical = manager.workspaces[canonicalIndex]
            var mismatchedCanonical = projectedCanonical
            mismatchedCanonical.currentPromptText = "Uncommitted cleanup attempt"
            manager.workspaces[canonicalIndex] = mismatchedCanonical
            let authoritySnapshot = await authorityClient.snapshot()
            let canonicalBeforeLocalSave = try XCTUnwrap(authoritySnapshot.workspaces.first {
                $0.document.workspaceID == canonical.id
            })
            let suppressedOlderEcho = await presentationBridge.suppressSelfEchoForTesting(DomainWorkspaceEvent(
                runtimeID: runtime.identity.runtimeID,
                sequence: authoritySnapshot.publicationSequence,
                catalogRevision: authoritySnapshot.catalogRevision,
                kind: .workingStateCommitted,
                workspaceID: canonical.id,
                contextID: nil,
                operationID: UUID(),
                origin: .appPresentation(windowID: -781),
                revisions: nil,
                timestamp: Date(),
                diagnostic: nil
            ))
            XCTAssertTrue(suppressedOlderEcho)
            XCTAssertEqual(
                manager.workspace(withID: canonical.id)?.currentPromptText,
                mismatchedCanonical.currentPromptText,
                "An older accepted self-echo must not overwrite a newer local edit."
            )
            let baselineAfterOlderEcho = manager.debugDomainAuthorityBaseline(for: canonical.id)
            XCTAssertEqual(baselineAfterOlderEcho.revisions, canonicalBeforeLocalSave.revisions)
            XCTAssertEqual(baselineAfterOlderEcho.digest, canonicalBeforeLocalSave.document.contentDigest)
            _ = try await manager.saveWorkspaceToFileAsync(
                mismatchedCanonical,
                preserveDiskRepoPathsIfUnchangedSinceBaseline: false
            )
            let canonicalAfterLocalSave = try await authoritativeWorkspace(canonical.id, in: runtime)
            XCTAssertEqual(
                canonicalAfterLocalSave.currentPromptText,
                mismatchedCanonical.currentPromptText,
                "The preserved local edit must save from the advanced authority baseline."
            )

            // Runtime and the manager bootstrapped both records; now make the retired legacy index
            // stale. Cleanup must re-plan from DomainRuntime rather than making it authoritative.
            try writeLegacyIndex([canonical])

            XCTAssertEqual(
                manager.duplicateWorkspaceGroups().count,
                1,
                "A user-hidden, unretired workspace must remain detectable as a duplicate."
            )

            let previousWindows = WindowStatesManager.shared.allWindows
            WindowStatesManager.shared.allWindows = []
            defer { WindowStatesManager.shared.allWindows = previousWindows }

            let cleanup = await manager.consolidateDuplicateWorkspaces()
            XCTAssertEqual(cleanup.groupsDetected, 1)
            XCTAssertEqual(cleanup.groupsConsolidated, 1)
            XCTAssertEqual(cleanup.retiredWorkspaceIDs, [duplicate.id])
            XCTAssertTrue(cleanup.skipped.isEmpty, "Unexpected skips: \(cleanup.skipped)")
            XCTAssertEqual(cleanup.backupURL?.deletingLastPathComponent(), backupDirectory)
            XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(cleanup.backupURL).path))

            let authoritativeCanonical = try await authoritativeWorkspace(
                canonical.id,
                in: runtime
            )
            XCTAssertTrue(authoritativeCanonical.selectedMetaPromptIDs.contains(mergedPromptID))
            let mergedTab = try XCTUnwrap(authoritativeCanonical.composeTabs.first {
                $0.id == duplicateTabID
            })
            XCTAssertEqual(mergedTab.activeAgentSessionID, duplicateAgentSessionID)
            XCTAssertEqual(mergedTab.activeChatSessionID, duplicateChatSessionID)

            let canonicalDirectory = workspaceFileURL(for: canonical).deletingLastPathComponent()
            let canonicalChatSidecarURL = canonicalDirectory
                .appendingPathComponent("Chats", isDirectory: true)
                .appendingPathComponent(chatSidecarURL.lastPathComponent)
            let canonicalAgentSidecarURL = canonicalDirectory
                .appendingPathComponent("AgentSessions", isDirectory: true)
                .appendingPathComponent(agentSidecarURL.lastPathComponent)
            let migratedChat = try JSONDecoder().decode(
                ChatSession.self,
                from: Data(contentsOf: canonicalChatSidecarURL)
            )
            let migratedAgent = try JSONDecoder().decode(
                AgentSession.self,
                from: Data(contentsOf: canonicalAgentSidecarURL)
            )
            XCTAssertEqual(migratedChat.workspaceID, canonical.id)
            XCTAssertEqual(migratedChat.composeTabID, duplicateTabID)
            XCTAssertEqual(migratedChat.messages.map(\.rawText), ["Recovered transcript content"])
            XCTAssertEqual(migratedAgent.workspaceID, canonical.id)
            XCTAssertEqual(migratedAgent.composeTabID, duplicateTabID)
            XCTAssertEqual(migratedAgent.name, "Recovered Agent history")
            XCTAssertEqual(migratedAgent.effectiveItemCount, 7)

            let authoritativeRetired = try await authoritativeWorkspace(
                duplicate.id,
                in: runtime
            )
            XCTAssertTrue(authoritativeRetired.isHiddenInMenus)
            XCTAssertEqual(authoritativeRetired.consolidatedIntoWorkspaceID, canonical.id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: chatSidecarURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: agentSidecarURL.path))

            let retiredProjectionSequence = await (runtime.workspaceStore.snapshot()).publicationSequence
            let projectedRetirement = await presentationBridge.waitUntilProjected(through: retiredProjectionSequence)
            XCTAssertTrue(projectedRetirement)
            let unrelated = WorkspaceModel(
                name: "Unrelated projection trigger",
                repoPaths: ["/tmp/unrelated-projection-trigger"]
            )
            let unrelatedOutcome = try await authorityClient.create(
                unrelated,
                fileURL: workspaceFileURL(for: unrelated)
            )
            XCTAssertEqual(unrelatedOutcome.disposition, .applied)
            let unrelatedProjectionSequence = await (runtime.workspaceStore.snapshot()).publicationSequence
            let projectedUnrelated = await presentationBridge.waitUntilProjected(through: unrelatedProjectionSequence)
            XCTAssertTrue(projectedUnrelated)
            XCTAssertEqual(
                manager.workspace(withID: duplicate.id)?.consolidatedIntoWorkspaceID,
                canonical.id,
                "A later projection must not resurrect the bridge's pre-retirement model."
            )

            // Make the reload assertion start false, so the wait proves the authority projection
            // completed instead of passing immediately on the already-projected retirement.
            manager.applyWorkspaceHiddenStateInMemory(
                workspaceID: duplicate.id,
                hidden: true,
                consolidatedIntoWorkspaceID: nil,
                dateModified: Date()
            )
            manager.reloadWorkspacesFromDisk()
            let reloadDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while manager.workspace(withID: duplicate.id)?.consolidatedIntoWorkspaceID != canonical.id,
                  ContinuousClock.now < reloadDeadline
            {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(manager.workspace(withID: duplicate.id)?.consolidatedIntoWorkspaceID, canonical.id)
            XCTAssertTrue(manager.duplicateWorkspaceGroups().isEmpty)

            let projectedRetired = try XCTUnwrap(manager.workspace(withID: duplicate.id))
            let restoreGate = WorkspaceDuplicateCleanupSuspensionGate()
            manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { workspaceID, _, _ in
                guard workspaceID == duplicate.id else { return }
                await restoreGate.wait()
            }
            let restoreTask = Task { @MainActor in
                try await manager.setWorkspaceHiddenFromSnapshot(
                    projectedRetired,
                    hidden: false
                )
            }
            let pendingDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !manager.pendingConsolidatedRestoreIDs.contains(duplicate.id),
                  ContinuousClock.now < pendingDeadline
            {
                await Task.yield()
            }
            XCTAssertTrue(manager.pendingConsolidatedRestoreIDs.contains(duplicate.id))
            let blockedSwitch = await manager.requestWorkspaceSwitch(to: projectedRetired)
            XCTAssertFalse(blockedSwitch.didSwitch)
            await restoreGate.open()
            let restored = try await restoreTask.value
            manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            XCTAssertFalse(restored.isHiddenInMenus)
            XCTAssertNil(restored.consolidatedIntoWorkspaceID)
            XCTAssertFalse(manager.pendingConsolidatedRestoreIDs.contains(duplicate.id))

            let authoritativeRestored = try await authoritativeWorkspace(
                duplicate.id,
                in: runtime
            )
            XCTAssertFalse(authoritativeRestored.isHiddenInMenus)
            XCTAssertNil(authoritativeRestored.consolidatedIntoWorkspaceID)
            XCTAssertEqual(manager.duplicateWorkspaceGroups().count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: chatSidecarURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: agentSidecarURL.path))
        }

        func testConcurrentAuthorityUpdateWinsInsteadOfBeingOverwrittenByCleanup() async throws {
            let mergedPromptID = UUID()
            let canonical = WorkspaceModel(
                id: UUID(),
                dateModified: Date(timeIntervalSince1970: 200),
                name: "Canonical",
                repoPaths: ["/tmp/concurrent-cleanup-root"],
                lastUsed: Date(timeIntervalSince1970: 200)
            )
            let duplicate = WorkspaceModel(
                id: UUID(),
                dateModified: Date(timeIntervalSince1970: 100),
                name: "Duplicate",
                repoPaths: canonical.repoPaths,
                lastUsed: Date(timeIntervalSince1970: 100),
                selectedMetaPromptIDs: [mergedPromptID]
            )
            try writeWorkspace(canonical)
            try writeWorkspace(duplicate)
            try writeLegacyIndex([canonical, duplicate])

            let configuration = DomainRuntimeConfiguration(
                mode: .app,
                profileIdentifier: "workspace-duplicate-concurrent-save-\(UUID().uuidString)",
                storageDirectory: storageRoot.appendingPathComponent("runtime-state", isDirectory: true),
                workspaceStorageDirectory: storageRoot,
                eventDirectory: storageRoot.appendingPathComponent("events", isDirectory: true),
                temporaryDirectory: storageRoot.appendingPathComponent("tmp", isDirectory: true),
                externalReloadInterval: nil
            )
            let runtime = MCPDomainRuntime(configuration: configuration, runtimeID: UUID())
            let competingRuntime = MCPDomainRuntime(configuration: configuration, runtimeID: UUID())
            try await runtime.start()
            try await competingRuntime.start()
            defer {
                Task {
                    _ = await runtime.shutdown()
                    _ = await competingRuntime.shutdown()
                }
            }

            let managerClient = DomainWorkspaceAuthorityClient(store: runtime.workspaceStore, windowID: -782)
            let externalClient = DomainWorkspaceAuthorityClient(store: competingRuntime.workspaceStore, windowID: -783)
            let manager = makeManager(windowID: -782, domainWorkspaceAuthorityClient: managerClient)
            manager.setDuplicateCleanupBackupDirectoryForTesting(
                storageRoot.appendingPathComponent("cleanup-backups", isDirectory: true)
            )
            await manager.awaitInitialized()
            let presentationBridge = DomainWorkspacePresentationBridge(
                workspaceManager: manager,
                client: managerClient
            )
            presentationBridge.start()
            defer {
                manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
                presentationBridge.stop()
            }
            let initialSnapshot = await runtime.workspaceStore.snapshot()
            let projectedInitial = await presentationBridge.waitUntilProjected(
                through: initialSnapshot.publicationSequence
            )
            XCTAssertTrue(projectedInitial)

            let externalPrompt = "Concurrent authority winner"
            manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { workspaceID, _, remainingRetryCount in
                guard workspaceID == canonical.id, remainingRetryCount == 1 else { return }
                do {
                    let before = await externalClient.snapshot()
                    let authoritative = try XCTUnwrap(before.workspaces.first {
                        $0.document.workspaceID == canonical.id
                    })
                    var externalWinner = try WorkspaceManagerViewModel.decodeDomainWorkspaceProjection(
                        documentBytes: authoritative.document.documentBytes,
                        fileURL: authoritative.document.fileURL
                    )
                    externalWinner.currentPromptText = externalPrompt
                    externalWinner.dateModified = Date(timeIntervalSince1970: 300)
                    let outcome = try await externalClient.save(
                        externalWinner,
                        fileURL: authoritative.document.fileURL,
                        expectedWorkspaceRevision: authoritative.revisions.workingRevision,
                        expectedContentDigest: authoritative.document.contentDigest
                    )
                    XCTAssertTrue(
                        outcome.disposition == .applied
                            || outcome.disposition == .unchanged
                            || outcome.disposition == .deduplicated
                    )
                } catch {
                    XCTFail("Failed to install concurrent authority winner: \(error)")
                }
            }

            let previousWindows = WindowStatesManager.shared.allWindows
            WindowStatesManager.shared.allWindows = []
            defer { WindowStatesManager.shared.allWindows = previousWindows }

            let cleanup = await manager.consolidateDuplicateWorkspaces()
            XCTAssertEqual(cleanup.groupsDetected, 1)
            XCTAssertEqual(cleanup.groupsConsolidated, 0)
            XCTAssertTrue(cleanup.retiredWorkspaceIDs.isEmpty)
            XCTAssertTrue(cleanup.skipped.contains {
                $0.workspaceID == duplicate.id && $0.reason.hasPrefix("persist_failed:")
            })

            let authoritativeCanonical = try await authoritativeWorkspace(canonical.id, in: runtime)
            XCTAssertEqual(authoritativeCanonical.currentPromptText, externalPrompt)
            XCTAssertFalse(authoritativeCanonical.selectedMetaPromptIDs.contains(mergedPromptID))
            XCTAssertEqual(manager.workspace(withID: canonical.id), authoritativeCanonical)

            let finalSnapshot = await runtime.workspaceStore.snapshot()
            let finalCanonical = try XCTUnwrap(finalSnapshot.workspaces.first {
                $0.document.workspaceID == canonical.id
            })
            let managerBaseline = manager.debugDomainAuthorityBaseline(for: canonical.id)
            XCTAssertEqual(managerBaseline.revisions, finalCanonical.revisions)
            XCTAssertEqual(managerBaseline.digest, finalCanonical.document.contentDigest)
            XCTAssertEqual(managerBaseline.health, finalCanonical.health)

            let authoritativeDuplicate = try await authoritativeWorkspace(duplicate.id, in: runtime)
            XCTAssertNil(authoritativeDuplicate.consolidatedIntoWorkspaceID)
            XCTAssertFalse(authoritativeDuplicate.isHiddenInMenus)
            XCTAssertEqual(manager.duplicateWorkspaceGroups().count, 1)
        }

        func testWorkspaceRetirementMarkerRoundTripsAndDefaultsToNil() throws {
            let canonicalID = UUID()
            let retired = WorkspaceModel(
                name: "Retired",
                repoPaths: ["/tmp/retired"],
                isHiddenInMenus: true,
                consolidatedIntoWorkspaceID: canonicalID
            )
            let roundTripped = try JSONDecoder().decode(
                WorkspaceModel.self,
                from: JSONEncoder().encode(retired)
            )
            XCTAssertEqual(roundTripped.consolidatedIntoWorkspaceID, canonicalID)
            XCTAssertEqual(roundTripped, retired)

            let ordinary = WorkspaceModel(name: "Ordinary", repoPaths: ["/tmp/ordinary"])
            let legacyCompatible = try JSONDecoder().decode(
                WorkspaceModel.self,
                from: JSONEncoder().encode(ordinary)
            )
            XCTAssertNil(legacyCompatible.consolidatedIntoWorkspaceID)
        }

        func testRenameSafeStorageResolutionUsesStableWorkspaceIdentity() async throws {
            let workspace = WorkspaceModel(
                id: UUID(),
                name: "Before rename",
                repoPaths: ["/tmp/rename-safe-storage"]
            )
            let workspaceID = workspace.id
            let legacyDirectory = workspaceFileURL(for: workspace).deletingLastPathComponent()
            try writeWorkspace(workspace)
            try writeLegacyIndex([workspace])

            let resolver = WorkspaceStorageDirectoryResolver()
            XCTAssertEqual(
                try resolver.resolveDirectory(
                    workspaceID: workspaceID,
                    workspaceName: "After rename",
                    customStoragePath: nil,
                    catalogFileURL: nil,
                    baseRoot: storageRoot
                ),
                legacyDirectory.standardizedFileURL
            )

            var renamed = workspace
            renamed.name = "After rename"
            let manager = makeManager(windowID: -785)
            let savedURL = try await manager.saveWorkspaceToFileAsync(
                renamed,
                baseRoot: storageRoot
            )
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.flush(url: savedURL)
            XCTAssertEqual(savedURL.deletingLastPathComponent(), legacyDirectory.standardizedFileURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceFileURL(for: renamed).path))

            let catalogDirectory = storageRoot.appendingPathComponent("Catalog-owned", isDirectory: true)
            XCTAssertEqual(
                try WorkspaceStorageDirectoryResolver().resolveDirectory(
                    workspaceID: workspaceID,
                    workspaceName: "After rename",
                    customStoragePath: nil,
                    catalogFileURL: catalogDirectory.appendingPathComponent("workspace.json"),
                    baseRoot: storageRoot
                ),
                catalogDirectory.standardizedFileURL
            )

            let secondDirectory = storageRoot.appendingPathComponent(
                DomainWorkspaceStoragePath.directoryName(name: "Other old name", id: workspaceID),
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: secondDirectory.appendingPathComponent("workspace.json"))
            XCTAssertThrowsError(try WorkspaceStorageDirectoryResolver().resolveDirectory(
                workspaceID: workspaceID,
                workspaceName: "After rename",
                customStoragePath: nil,
                catalogFileURL: nil,
                baseRoot: storageRoot
            )) { error in
                guard case WorkspaceStorageDirectoryResolutionError.ambiguousDirectories = error else {
                    return XCTFail("Expected an ambiguity error, got \(error)")
                }
            }
        }

        func testBothSidecarFamiliesPreflightBeforeEitherWrites() async throws {
            let sourceDirectory = storageRoot.appendingPathComponent("sidecar-source", isDirectory: true)
            let destinationDirectory = storageRoot.appendingPathComponent("sidecar-destination", isDirectory: true)
            let sourceAgentDirectory = sourceDirectory.appendingPathComponent("AgentSessions", isDirectory: true)
            let sourceChatDirectory = sourceDirectory.appendingPathComponent("Chats", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceAgentDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sourceChatDirectory, withIntermediateDirectories: true)

            let sessionID = UUID()
            let agentFilename = "AgentSession-\(sessionID.uuidString).json"
            try JSONEncoder().encode(AgentSession(
                id: sessionID,
                workspaceID: UUID(),
                name: "Prepared only"
            )).write(to: sourceAgentDirectory.appendingPathComponent(agentFilename), options: .atomic)
            try Data("not-json".utf8).write(
                to: sourceChatDirectory.appendingPathComponent("ChatSession-\(UUID().uuidString).json"),
                options: .atomic
            )

            let agentBatch = try await AgentSessionDataService.shared.prepareWorkspaceSessionRehome(
                from: sourceDirectory,
                to: destinationDirectory,
                canonicalWorkspaceID: UUID()
            )
            XCTAssertNotNil(agentBatch)
            do {
                _ = try await ChatDataService.prepareWorkspaceSessionRehome(
                    from: sourceDirectory,
                    to: destinationDirectory,
                    canonicalWorkspaceID: UUID()
                )
                XCTFail("Expected the malformed Chat sidecar to fail preflight")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: destinationDirectory
                    .appendingPathComponent("AgentSessions", isDirectory: true)
                    .appendingPathComponent(agentFilename).path
            ))
        }

        func testFailClosedSaveReportsAWorkingOnlyCommit() async throws {
            let workspace = WorkspaceModel(
                id: UUID(),
                name: "Phase-aware save",
                repoPaths: ["/tmp/phase-aware-save"]
            )
            try writeWorkspace(workspace)
            try writeLegacyIndex([workspace])

            let runtime = MCPDomainRuntime(configuration: .init(
                mode: .app,
                profileIdentifier: "workspace-phase-aware-save-\(UUID().uuidString)",
                storageDirectory: storageRoot.appendingPathComponent("phase-runtime", isDirectory: true),
                workspaceStorageDirectory: storageRoot,
                eventDirectory: storageRoot.appendingPathComponent("phase-events", isDirectory: true),
                temporaryDirectory: storageRoot.appendingPathComponent("phase-tmp", isDirectory: true),
                externalReloadInterval: nil
            ))
            try await runtime.start()
            defer { Task { _ = await runtime.shutdown() } }

            let client = DomainWorkspaceAuthorityClient(store: runtime.workspaceStore, windowID: -784)
            let initialSnapshot = await client.snapshot()
            let initial = try XCTUnwrap(initialSnapshot.workspaces.first {
                $0.document.workspaceID == workspace.id
            })
            let reservedSavedOperationID = UUID()
            let reservation = try await client.replaceWorking(
                workspace,
                fileURL: initial.document.fileURL,
                expectedWorkspaceRevision: initial.revisions.workingRevision,
                operationID: reservedSavedOperationID
            )
            XCTAssertTrue(
                reservation.disposition == .applied
                    || reservation.disposition == .unchanged
                    || reservation.disposition == .deduplicated
            )

            var updated = workspace
            updated.currentPromptText = "Durable working update"
            let outcome = try await client.saveFailClosed(
                updated,
                fileURL: initial.document.fileURL,
                expectedWorkspaceRevision: reservation.after?.workingRevision
                    ?? reservation.workspace?.revisions.workingRevision
                    ?? initial.revisions.workingRevision,
                expectedContentDigest: reservation.resultingDigest
                    ?? reservation.workspace?.document.contentDigest
                    ?? initial.document.contentDigest,
                operationIDs: DomainWorkspaceSaveOperationIDs(
                    working: UUID(),
                    saved: reservedSavedOperationID
                )
            )

            XCTAssertTrue(outcome.workingCommitted)
            XCTAssertEqual(outcome.saved?.errorCode, .operationIDCollision)
            let afterSnapshot = await client.snapshot()
            let after = try XCTUnwrap(afterSnapshot.workspaces.first {
                $0.document.workspaceID == workspace.id
            })
            XCTAssertNotNil(after.revisions.dirtyRevision)
            let authoritative = try JSONDecoder().decode(
                WorkspaceModel.self,
                from: after.document.documentBytes
            )
            XCTAssertEqual(authoritative.currentPromptText, updated.currentPromptText)
        }

        private func authoritativeWorkspace(
            _ workspaceID: UUID,
            in runtime: MCPDomainRuntime
        ) async throws -> WorkspaceModel {
            let snapshot = await runtime.workspaceStore.snapshot()
            let authoritative = try XCTUnwrap(snapshot.workspaces.first {
                $0.document.workspaceID == workspaceID
            })
            return try JSONDecoder().decode(
                WorkspaceModel.self,
                from: authoritative.document.documentBytes
            )
        }

        private func writeWorkspace(_ workspace: WorkspaceModel) throws {
            let fileURL = workspaceFileURL(for: workspace)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(workspace).write(to: fileURL, options: .atomic)
        }

        private func workspaceFileURL(for workspace: WorkspaceModel) -> URL {
            storageRoot
                .appendingPathComponent(
                    DomainWorkspaceStoragePath.directoryName(name: workspace.name, id: workspace.id),
                    isDirectory: true
                )
                .appendingPathComponent("workspace.json")
        }

        private func writeLegacyIndex(_ workspaces: [WorkspaceModel]) throws {
            let entries = workspaces.map {
                WorkspaceIndexEntry(
                    id: $0.id,
                    name: $0.name,
                    customStoragePath: $0.customStoragePath,
                    isSystemWorkspace: $0.isSystemWorkspace,
                    isHiddenInMenus: $0.isHiddenInMenus
                )
            }
            try JSONEncoder().encode(entries).write(
                to: storageRoot.appendingPathComponent("workspacesIndex.json"),
                options: .atomic
            )
        }

        private func makeManager(
            windowID: Int,
            domainWorkspaceAuthorityClient: DomainWorkspaceAuthorityClient? = nil
        ) -> WorkspaceManagerViewModel {
            let keyManager = KeyManager(
                secureService: SecureKeysService(secureStorage: TestSecureStorageBackend())
            )
            let aiQueriesService = AIQueriesService(keyManager: keyManager)
            let fileManager = WorkspaceFilesViewModel()
            let apiSettings = APISettingsViewModel(
                aiQueriesService: aiQueriesService,
                keyManager: keyManager,
                loadStoredDataOnInit: false
            )
            let prompt = PromptViewModel(
                fileManager: fileManager,
                apiSettingsViewModel: apiSettings,
                windowID: windowID,
                settingsManager: WindowSettingsManager(windowID: windowID)
            )
            let manager = WorkspaceManagerViewModel(
                fileManager: fileManager,
                promptViewModel: prompt,
                domainWorkspaceAuthorityClient: domainWorkspaceAuthorityClient,
                workspaceActivityCoordinator: WorkspaceActivityCoordinator(),
                performInitialWorkspaceActivation: false
            )
            managers.append(manager)
            return manager
        }
    }

    private actor WorkspaceDuplicateCleanupSuspensionGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }
#endif
