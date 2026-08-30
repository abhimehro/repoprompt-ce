@testable import RepoPromptApp
import RepoPromptDomainRuntime
import XCTest

#if DEBUG
    @MainActor
    final class AgentAdmissionRecoveryTests: XCTestCase {
        private actor RecoveryCoalescingGate {
            private var firstCallerSuspended = false
            private var firstCallerReleased = false
            private var coalescedCallerObserved = false
            private var firstCallerSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
            private var firstCallerReleaseWaiters: [CheckedContinuation<Void, Never>] = []
            private var coalescedCallerWaiters: [CheckedContinuation<Void, Never>] = []

            func suspendFirstCaller() async {
                firstCallerSuspended = true
                firstCallerSuspensionWaiters.forEach { $0.resume() }
                firstCallerSuspensionWaiters.removeAll()
                guard !firstCallerReleased else { return }
                await withCheckedContinuation { continuation in
                    firstCallerReleaseWaiters.append(continuation)
                }
            }

            func waitUntilFirstCallerIsSuspended() async {
                guard !firstCallerSuspended else { return }
                await withCheckedContinuation { continuation in
                    firstCallerSuspensionWaiters.append(continuation)
                }
            }

            func observeCoalescedCaller() {
                coalescedCallerObserved = true
                coalescedCallerWaiters.forEach { $0.resume() }
                coalescedCallerWaiters.removeAll()
            }

            func waitUntilCoalescedCallerIsObserved() async {
                guard !coalescedCallerObserved else { return }
                await withCheckedContinuation { continuation in
                    coalescedCallerWaiters.append(continuation)
                }
            }

            func releaseFirstCaller() {
                firstCallerReleased = true
                firstCallerReleaseWaiters.forEach { $0.resume() }
                firstCallerReleaseWaiters.removeAll()
            }
        }

        private var originalMCPAutoStart = false
        private var originalStoragePath: String?
        private var storageRoot: URL!
        private var managers: [WorkspaceManagerViewModel] = []
        private var runtimes: [MCPDomainRuntime] = []

        override func setUp() async throws {
            try await super.setUp()
            originalMCPAutoStart = GlobalSettingsStore.shared.mcpAutoStart()
            GlobalSettingsStore.shared.setMCPAutoStart(false, commit: false)
            originalStoragePath = UserDefaults.standard.string(forKey: "GlobalCustomStorageURL")
            storageRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("AgentAdmissionRecoveryTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            UserDefaults.standard.set(storageRoot.path, forKey: "GlobalCustomStorageURL")
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()
        }

        override func tearDown() async throws {
            managers.forEach { $0.prepareForWindowClose() }
            managers.removeAll()
            for runtime in runtimes {
                _ = await runtime.shutdown()
            }
            runtimes.removeAll()
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

        func testActiveRecoveryIsStructurallyNarrowAndPersistsExactRemoval() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let unrelatedDiskBefore = try Data(contentsOf: fixture.workspaceBURL)
            let unrelatedBefore = fixture.manager.workspace(withID: fixture.workspaceB.id)

            let receipt = await fixture.manager.persistAgentAdmission(fixture.identity)
            guard case .saved = receipt.commitEvidence else {
                return XCTFail("Expected saved admission evidence, got \(receipt.commitEvidence)")
            }
            let canonicalBeforeRecovery = try await canonicalModel(fixture)

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }

            let canonical = try await canonicalModel(fixture)
            let disk = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fixture.workspaceAURL,
                scheduleNormalizationWriteback: false
            )
            let managerWorkspace = try XCTUnwrap(fixture.manager.workspace(withID: fixture.workspaceA.id))
            for recovered in [canonical, disk, managerWorkspace] {
                XCTAssertFalse(recovered.composeTabs.contains { $0.id == fixture.identity.tabID })
                XCTAssertFalse(recovered.composeTabs.contains {
                    $0.activeAgentSessionID == fixture.identity.sessionID
                })
                XCTAssertEqual(recovered.composeTabs.map(\.id), [fixture.leftTab.id, fixture.rightTab.id])
                XCTAssertEqual(recovered.activeComposeTabID, fixture.rightTab.id)
                assertNonComposeFieldsEqual(recovered, canonicalBeforeRecovery)
            }
            XCTAssertEqual(
                fixture.prompt.currentComposeTabs.map(\.id),
                [fixture.leftTab.id, fixture.rightTab.id]
            )
            XCTAssertEqual(fixture.prompt.activeComposeTabID, fixture.rightTab.id)
            XCTAssertEqual(fixture.manager.workspace(withID: fixture.workspaceB.id), unrelatedBefore)
            XCTAssertEqual(try Data(contentsOf: fixture.workspaceBURL), unrelatedDiskBefore)
            let snapshotValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let snapshot = try XCTUnwrap(snapshotValue)
            XCTAssertNil(snapshot.revisions.dirtyRevision)
        }

        func testInactiveRecoveryLeavesActivePromptAndWorkspaceUnchanged() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceB
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceB)
            let promptTabsBefore = fixture.prompt.currentComposeTabs
            let promptActiveBefore = fixture.prompt.activeComposeTabID
            let activeWorkspaceBefore = fixture.manager.workspace(withID: fixture.workspaceB.id)
            let activeDiskBefore = try Data(contentsOf: fixture.workspaceBURL)

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }

            XCTAssertEqual(fixture.prompt.currentComposeTabs, promptTabsBefore)
            XCTAssertEqual(fixture.prompt.activeComposeTabID, promptActiveBefore)
            XCTAssertEqual(fixture.manager.activeWorkspaceID, fixture.workspaceB.id)
            XCTAssertEqual(fixture.manager.workspace(withID: fixture.workspaceB.id), activeWorkspaceBefore)
            XCTAssertEqual(try Data(contentsOf: fixture.workspaceBURL), activeDiskBefore)
            let recoveredCanonical = try await canonicalModel(fixture)
            XCTAssertFalse(recoveredCanonical.composeTabs.contains {
                $0.id == fixture.identity.tabID
            })
        }

        func testActiveRecoveryPreservesUnrelatedLivePromptProjectionEdits() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            var liveWorkspace = fixture.workspaceA
            let rightIndex = try XCTUnwrap(liveWorkspace.composeTabs.firstIndex {
                $0.id == fixture.rightTab.id
            })
            let liveSelection = StoredSelection(selectedPaths: ["/tmp/live-selection"])
            liveWorkspace.composeTabs[rightIndex].promptText = "live tab prompt"
            liveWorkspace.composeTabs[rightIndex].selection = liveSelection
            liveWorkspace.composeTabs[rightIndex].isPinned = true
            liveWorkspace.composeTabs[rightIndex].contextOverrides = ContextBuilderOverrides(
                useOverridePrompt: true,
                overridePromptText: "live override"
            )
            let unrelatedStash = StashedTab(tab: ComposeTabState(
                name: "Live stash",
                promptText: "preserve stashed edit"
            ))
            liveWorkspace.stashedTabs = [unrelatedStash]
            fixture.prompt.loadComposeTabsFromWorkspace(liveWorkspace)

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }
            XCTAssertEqual(fixture.prompt.currentStashedTabs, [unrelatedStash])
            let preserved = try XCTUnwrap(fixture.prompt.currentComposeTabs.first {
                $0.id == fixture.rightTab.id
            })
            XCTAssertEqual(preserved.promptText, "live tab prompt")
            XCTAssertEqual(preserved.selection, liveSelection)
            XCTAssertTrue(preserved.isPinned)
            XCTAssertEqual(
                preserved.contextOverrides,
                ContextBuilderOverrides(
                    useOverridePrompt: true,
                    overridePromptText: "live override"
                )
            )
            XCTAssertFalse(fixture.prompt.currentComposeTabs.contains {
                $0.id == fixture.identity.tabID
            })
        }

        func testManagerProjectionConflictLeavesPromptAndSidebarProjectionsUnchanged() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let successorID = UUID()
            let managerIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex {
                $0.id == fixture.workspaceA.id
            })
            let tabIndex = try XCTUnwrap(fixture.manager.workspaces[managerIndex].composeTabs.firstIndex {
                $0.id == fixture.identity.tabID
            })
            fixture.manager.workspaces[managerIndex].composeTabs[tabIndex].activeAgentSessionID = successorID
            let managerBefore = fixture.manager.workspaces[managerIndex]
            let promptTabsBefore = fixture.prompt.currentComposeTabs
            let promptActiveBefore = fixture.prompt.activeComposeTabID
            let sidebarBefore = fixture.prompt.sidebarWorkspaceSnapshot

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            XCTAssertEqual(outcome, .ownershipChanged)
            XCTAssertEqual(fixture.manager.workspaces[managerIndex], managerBefore)
            XCTAssertEqual(fixture.prompt.currentComposeTabs, promptTabsBefore)
            XCTAssertEqual(fixture.prompt.activeComposeTabID, promptActiveBefore)
            XCTAssertEqual(fixture.prompt.sidebarWorkspaceSnapshot, sidebarBefore)
        }

        func testCurrentProjectionAlreadyAbsentStillReconcilesMatchingSidebarSnapshot() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let currentTabs = [fixture.leftTab, fixture.rightTab]
            fixture.prompt.setCurrentComposeTabsForAgentAdmissionRecoveryTesting(
                currentTabs,
                activeComposeTabID: fixture.rightTab.id
            )
            XCTAssertTrue(fixture.prompt.sidebarWorkspaceSnapshot?.composeTabs.contains {
                $0.id == fixture.identity.tabID
            } == true)

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }
            XCTAssertEqual(fixture.prompt.currentComposeTabs, currentTabs)
            XCTAssertEqual(fixture.prompt.activeComposeTabID, fixture.rightTab.id)
            XCTAssertEqual(
                fixture.prompt.sidebarWorkspaceSnapshot?.composeTabs.map(\.id),
                currentTabs.map(\.id)
            )
        }

        func testRecoveryPreservesSuccessorIdentityWithoutMutation() async throws {
            let fixture = try await makeFixture()
            let initialValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let initial = try XCTUnwrap(initialValue)
            let successorID = UUID()
            var successor = fixture.workspaceA
            let tabIndex = try XCTUnwrap(successor.composeTabs.firstIndex {
                $0.id == fixture.identity.tabID
            })
            successor.composeTabs[tabIndex].activeAgentSessionID = successorID
            let replaced = try await fixture.client.replaceWorking(
                successor,
                fileURL: fixture.workspaceAURL,
                expectedWorkspaceRevision: initial.revisions.workingRevision
            )
            let saved = try await fixture.client.save(
                successor,
                fileURL: fixture.workspaceAURL,
                expectedWorkspaceRevision: replaced.after?.workingRevision,
                expectedContentDigest: replaced.resultingDigest
            )
            XCTAssertEqual(saved.disposition, .applied)
            let managerIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex {
                $0.id == successor.id
            })
            fixture.manager.workspaces[managerIndex] = successor
            let beforeValue = await fixture.client.canonicalWorkspaceSnapshot(successor.id)
            let before = try XCTUnwrap(beforeValue)
            let digestBefore = before.document.contentDigest

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            XCTAssertEqual(outcome, .ownershipChanged)
            let afterValue = await fixture.client.canonicalWorkspaceSnapshot(successor.id)
            let after = try XCTUnwrap(afterValue)
            XCTAssertEqual(after.document.contentDigest, digestBefore)
            let successorCanonical = try await canonicalModel(fixture)
            XCTAssertEqual(successorCanonical.composeTabs.first {
                $0.id == fixture.identity.tabID
            }?.activeAgentSessionID, successorID)
        }

        func testCanonicalWorkingRecoveryRetriesSaveOnlyAndReplayIsIdempotent() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            var hookCount = 0
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting { _, _ in
                hookCount += 1
                return false
            }

            let partialOutcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case let .retryablePartial(owned) = partialOutcome else {
                return XCTFail("Expected retryable working commit, got \(partialOutcome)")
            }
            XCTAssertEqual(hookCount, 1)
            let dirtyValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let dirty = try XCTUnwrap(dirtyValue)
            XCTAssertEqual(dirty.revisions.workingRevision, owned.revision)
            XCTAssertEqual(dirty.document.contentDigest, owned.digest)
            XCTAssertEqual(dirty.revisions.dirtyRevision, owned.revision)
            let diskBeforeRetry = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fixture.workspaceAURL,
                scheduleNormalizationWriteback: false
            )
            XCTAssertTrue(diskBeforeRetry.composeTabs.contains { $0.id == fixture.identity.tabID })

            let repeatedPartial = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            XCTAssertEqual(repeatedPartial, .retryablePartial(owned))
            XCTAssertEqual(hookCount, 2)

            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting(nil)
            let recovered = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            switch recovered {
            case .recovered, .alreadyRecovered:
                break
            default:
                return XCTFail("Expected save-only convergence, got \(recovered)")
            }
            let cleanValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let clean = try XCTUnwrap(cleanValue)
            XCTAssertEqual(clean.revisions.workingRevision, owned.revision)
            XCTAssertEqual(clean.revisions.savedRevision, owned.revision)
            XCTAssertNil(clean.revisions.dirtyRevision)
            XCTAssertEqual(clean.document.contentDigest, owned.digest)

            let replay = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .alreadyRecovered = replay else {
                return XCTFail("Expected idempotent replay, got \(replay)")
            }
            let replayedValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let replayed = try XCTUnwrap(replayedValue)
            XCTAssertEqual(replayed.revisions, clean.revisions)
            XCTAssertEqual(replayed.document.contentDigest, clean.document.contentDigest)
        }

        func testLostSaveResponseConvergesThroughCanonicalReread() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            var droppedResponseCount = 0
            fixture.manager.setAgentAdmissionRecoverySaveResponseHandlerForTesting { workspaceID, outcome in
                XCTAssertEqual(workspaceID, fixture.workspaceA.id)
                XCTAssertTrue(
                    outcome.disposition == .applied
                        || outcome.disposition == .unchanged
                        || outcome.disposition == .deduplicated
                )
                droppedResponseCount += 1
                return false
            }

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = outcome else {
                return XCTFail("Expected canonical re-read convergence, got \(outcome)")
            }
            XCTAssertEqual(droppedResponseCount, 1)
            let snapshotValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let snapshot = try XCTUnwrap(snapshotValue)
            XCTAssertNil(snapshot.revisions.dirtyRevision)
            let canonical = try WorkspaceManagerViewModel.decodeDomainWorkspaceProjection(
                documentBytes: snapshot.document.documentBytes,
                fileURL: snapshot.document.fileURL
            )
            XCTAssertFalse(canonical.composeTabs.contains { $0.id == fixture.identity.tabID })
            let baseline = fixture.manager.debugDomainAuthorityBaseline(for: fixture.workspaceA.id)
            XCTAssertEqual(baseline.revisions, snapshot.revisions)
            XCTAssertEqual(baseline.digest, snapshot.document.contentDigest)
            let disk = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fixture.workspaceAURL,
                scheduleNormalizationWriteback: false
            )
            XCTAssertFalse(disk.composeTabs.contains { $0.id == fixture.identity.tabID })
        }

        func testReplacementPreparationFailureLeavesEveryProjectionAndCanonicalStateUnchanged() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let managerBefore = fixture.manager.workspace(withID: fixture.workspaceA.id)
            let promptTabsBefore = fixture.prompt.currentComposeTabs
            let promptActiveBefore = fixture.prompt.activeComposeTabID
            let sidebarBefore = fixture.prompt.sidebarWorkspaceSnapshot
            let canonicalBeforeValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let canonicalBefore = try XCTUnwrap(canonicalBeforeValue)
            let diskBefore = try Data(contentsOf: fixture.workspaceAURL)
            fixture.manager.setAgentAdmissionRecoveryReplacementPreparationHandlerForTesting { workspaceID in
                XCTAssertEqual(workspaceID, fixture.workspaceA.id)
                return false
            }

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            XCTAssertEqual(outcome, .failed(.persistenceFailure))
            XCTAssertEqual(fixture.manager.workspace(withID: fixture.workspaceA.id), managerBefore)
            XCTAssertEqual(fixture.prompt.currentComposeTabs, promptTabsBefore)
            XCTAssertEqual(fixture.prompt.activeComposeTabID, promptActiveBefore)
            XCTAssertEqual(fixture.prompt.sidebarWorkspaceSnapshot, sidebarBefore)
            let canonicalAfterValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let canonicalAfter = try XCTUnwrap(canonicalAfterValue)
            XCTAssertEqual(canonicalAfter.revisions, canonicalBefore.revisions)
            XCTAssertEqual(canonicalAfter.document.contentDigest, canonicalBefore.document.contentDigest)
            XCTAssertEqual(try Data(contentsOf: fixture.workspaceAURL), diskBefore)
        }

        func testLostReplacementResponseConvergesThroughCanonicalReread() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            var droppedResponseCount = 0
            fixture.manager.setAgentAdmissionRecoveryReplacementResponseHandlerForTesting { workspaceID, outcome in
                XCTAssertEqual(workspaceID, fixture.workspaceA.id)
                XCTAssertTrue(
                    outcome.disposition == .applied
                        || outcome.disposition == .unchanged
                        || outcome.disposition == .deduplicated
                )
                droppedResponseCount += 1
                return false
            }

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = outcome else {
                return XCTFail("Expected canonical re-read convergence, got \(outcome)")
            }
            XCTAssertEqual(droppedResponseCount, 1)
            let snapshotValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let snapshot = try XCTUnwrap(snapshotValue)
            XCTAssertNil(snapshot.revisions.dirtyRevision)
            let canonical = try await canonicalModel(fixture)
            XCTAssertFalse(canonical.composeTabs.contains {
                $0.id == fixture.identity.tabID
            })
            let baseline = fixture.manager.debugDomainAuthorityBaseline(for: fixture.workspaceA.id)
            XCTAssertEqual(baseline.revisions, snapshot.revisions)
            XCTAssertEqual(baseline.digest, snapshot.document.contentDigest)
        }

        func testUnavailablePostReplacementRereadRetainsAnticipatedFenceThenConverges() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let initialValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let initial = try XCTUnwrap(initialValue)
            var canonicalReadCount = 0
            fixture.manager.setAgentAdmissionRecoveryPostReplacementCanonicalReadHandlerForTesting { workspaceID in
                XCTAssertEqual(workspaceID, fixture.workspaceA.id)
                canonicalReadCount += 1
                return false
            }

            let partial = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case let .retryablePartial(anticipated) = partial else {
                return XCTFail("Expected anticipated retry fence, got \(partial)")
            }
            XCTAssertEqual(anticipated.revision, initial.revisions.workingRevision &+ 1)
            XCTAssertEqual(canonicalReadCount, 1)
            let committedValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let committed = try XCTUnwrap(committedValue)
            XCTAssertEqual(committed.revisions.workingRevision, anticipated.revision)
            XCTAssertEqual(committed.document.contentDigest, anticipated.digest)
            XCTAssertEqual(committed.revisions.dirtyRevision, anticipated.revision)

            fixture.manager.setAgentAdmissionRecoveryPostReplacementCanonicalReadHandlerForTesting(nil)
            let retry = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = retry else {
                return XCTFail("Expected fenced save-only convergence, got \(retry)")
            }
            let finalValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let final = try XCTUnwrap(finalValue)
            XCTAssertEqual(final.revisions.workingRevision, anticipated.revision)
            XCTAssertEqual(final.revisions.savedRevision, anticipated.revision)
            XCTAssertNil(final.revisions.dirtyRevision)
            XCTAssertEqual(final.document.contentDigest, anticipated.digest)
        }

        func testReturnedReplacementNoncommitRetainsAnticipatedFenceThenRetriesOnce() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let initialValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let initial = try XCTUnwrap(initialValue)
            var dispatchCount = 0
            fixture.manager.setAgentAdmissionRecoveryReplacementDispatchHandlerForTesting { workspaceID, revision in
                XCTAssertEqual(workspaceID, fixture.workspaceA.id)
                XCTAssertEqual(revision, initial.revisions.workingRevision)
                dispatchCount += 1
                guard dispatchCount == 1 else { return nil }
                return DomainCommandOutcome(
                    operationID: UUID(),
                    disposition: .failed,
                    before: initial.revisions,
                    after: initial.revisions,
                    catalogRevision: 0,
                    resultingDigest: initial.document.contentDigest,
                    errorCode: .lockTimedOut,
                    diagnostic: "deterministic noncommit"
                )
            }

            let partial = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case let .retryablePartial(anticipated) = partial else {
                return XCTFail("Expected anticipated retry fence, got \(partial)")
            }
            XCTAssertEqual(anticipated.revision, initial.revisions.workingRevision &+ 1)
            XCTAssertEqual(dispatchCount, 1)
            let unchangedValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let unchanged = try XCTUnwrap(unchangedValue)
            XCTAssertEqual(unchanged.revisions, initial.revisions)
            XCTAssertEqual(unchanged.document.contentDigest, initial.document.contentDigest)
            let unchangedModel = try WorkspaceManagerViewModel.decodeDomainWorkspaceProjection(
                documentBytes: unchanged.document.documentBytes,
                fileURL: unchanged.document.fileURL
            )
            XCTAssertTrue(unchangedModel.composeTabs.contains {
                $0.id == fixture.identity.tabID
                    && $0.activeAgentSessionID == fixture.identity.sessionID
            })

            let retry = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            guard case .recovered = retry else {
                return XCTFail("Expected bounded replacement retry to converge, got \(retry)")
            }
            XCTAssertEqual(dispatchCount, 2)
            let finalValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let final = try XCTUnwrap(finalValue)
            XCTAssertEqual(final.revisions.workingRevision, anticipated.revision)
            XCTAssertEqual(final.revisions.savedRevision, anticipated.revision)
            XCTAssertNil(final.revisions.dirtyRevision)
            XCTAssertEqual(final.document.contentDigest, anticipated.digest)
        }

        func testRecoveryUsesDeterministicReplacementWhenProvisionalTabIsOnlyTab() async throws {
            let fixture = try await makeFixture()
            let initialValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let initial = try XCTUnwrap(initialValue)
            let provisional = try XCTUnwrap(fixture.workspaceA.composeTabs.first {
                $0.id == fixture.identity.tabID
            })
            var singleTabWorkspace = fixture.workspaceA
            singleTabWorkspace.composeTabs = [provisional]
            singleTabWorkspace.activeComposeTabID = provisional.id
            let working = try await fixture.client.replaceWorking(
                singleTabWorkspace,
                fileURL: fixture.workspaceAURL,
                expectedWorkspaceRevision: initial.revisions.workingRevision
            )
            _ = try await fixture.client.save(
                singleTabWorkspace,
                fileURL: fixture.workspaceAURL,
                expectedWorkspaceRevision: working.after?.workingRevision,
                expectedContentDigest: working.resultingDigest
            )
            let managerIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex {
                $0.id == fixture.workspaceA.id
            })
            fixture.manager.workspaces[managerIndex] = singleTabWorkspace
            fixture.manager.activeWorkspace = singleTabWorkspace
            fixture.prompt.loadComposeTabsFromWorkspace(singleTabWorkspace)

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }

            let canonical = try await canonicalModel(fixture)
            XCTAssertEqual(canonical.composeTabs.map(\.id), [fixture.identity.replacementTabID])
            XCTAssertEqual(canonical.activeComposeTabID, fixture.identity.replacementTabID)
            XCTAssertNil(canonical.composeTabs.first?.activeAgentSessionID)
        }

        func testFinalManagerReconciliationPreservesConcurrentLocalEdit() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting { workspaceID, _ in
                if let index = fixture.manager.workspaces.firstIndex(where: {
                    $0.id == workspaceID
                }) {
                    fixture.manager.workspaces[index].lastSearchQuery = "concurrent local edit"
                    fixture.manager.markWorkspaceDirty(workspaceID: workspaceID)
                }
                return true
            }

            let outcome = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .recovered = outcome else {
                return XCTFail("Expected recovery, got \(outcome)")
            }

            let managerWorkspace = try XCTUnwrap(
                fixture.manager.workspace(withID: fixture.workspaceA.id)
            )
            XCTAssertEqual(managerWorkspace.lastSearchQuery, "concurrent local edit")
            XCTAssertFalse(managerWorkspace.composeTabs.contains { $0.id == fixture.identity.tabID })
            XCTAssertNotEqual(
                fixture.manager.debugLastSavedVersionForWorkspace(fixture.workspaceA.id),
                fixture.manager.debugStateVersionForWorkspace(fixture.workspaceA.id)
            )
        }

        func testRetryablePartialDoesNotSuppressLaterWorkingPublicationAndSave() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting { _, _ in false }
            let partial = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .retryablePartial = partial else {
                return XCTFail("Expected retryable partial, got \(partial)")
            }
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting(nil)
            let workspaceIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex {
                $0.id == fixture.workspaceA.id
            })
            fixture.manager.workspaces[workspaceIndex].lastSearchQuery = "legitimate later edit"
            fixture.manager.markWorkspaceDirty(workspaceID: fixture.workspaceA.id)

            await fixture.manager.debugPublishWorkingDocumentToDomainAuthority(
                fixture.manager.workspaces[workspaceIndex]
            )

            let working = try await canonicalModel(fixture)
            XCTAssertEqual(working.lastSearchQuery, "legitimate later edit")
            let saved = await fixture.manager.pollAndSaveStateWithOutcomeAsync(
                workspaceID: fixture.workspaceA.id,
                source: WorkspaceSaveSource("recoveryPartialSuccessor")
            )
            XCTAssertTrue(saved.acceptedForLifecycleAdmission)
            let disk = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fixture.workspaceAURL,
                scheduleNormalizationWriteback: false
            )
            XCTAssertEqual(disk.lastSearchQuery, "legitimate later edit")
        }

        func testSupersededRetryFenceCannotSaveNewerWorkingRevision() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting { _, _ in false }
            let partial = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            guard case .retryablePartial = partial else {
                return XCTFail("Expected retryable partial, got \(partial)")
            }
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting(nil)
            let workspaceIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex {
                $0.id == fixture.workspaceA.id
            })
            fixture.manager.workspaces[workspaceIndex].lastSearchQuery = "newer working revision"
            fixture.manager.markWorkspaceDirty(workspaceID: fixture.workspaceA.id)
            await fixture.manager.debugPublishWorkingDocumentToDomainAuthority(
                fixture.manager.workspaces[workspaceIndex]
            )
            let newerValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let newer = try XCTUnwrap(newerValue)
            XCTAssertNotNil(newer.revisions.dirtyRevision)

            let retry = await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)

            XCTAssertEqual(retry, .ownershipChanged)
            let afterValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let after = try XCTUnwrap(afterValue)
            XCTAssertEqual(after.revisions, newer.revisions)
            XCTAssertEqual(after.document.contentDigest, newer.document.contentDigest)
            let canonical = try await canonicalModel(fixture)
            XCTAssertEqual(canonical.lastSearchQuery, "newer working revision")
        }

        func testLegacyRecoveryPersistsDurableProjectionAndFencesWorkspaceIdentity() async throws {
            let sessionID = UUID()
            let provisional = ComposeTabState(activeAgentSessionID: sessionID)
            let workspace = WorkspaceModel(
                name: "Legacy durable recovery",
                repoPaths: ["/tmp/legacy-durable"],
                lastSearchQuery: "memory value",
                composeTabs: [provisional],
                activeComposeTabID: provisional.id
            )
            let fileURL = try writeWorkspace(workspace)
            try writeIndex([workspace])
            let (manager, prompt) = makeManager(client: nil)
            await manager.awaitInitialized()
            manager.activeWorkspace = workspace
            prompt.loadComposeTabsFromWorkspace(workspace)
            var durableNewer = workspace
            durableNewer.lastSearchQuery = "durable newer value"
            let durableBytes = try JSONEncoder().encode(durableNewer)
            try durableBytes.write(to: fileURL, options: .atomic)
            let identity = AgentProvisionalAdmissionIdentity(
                recoveryID: UUID(),
                workspaceID: workspace.id,
                tabID: provisional.id,
                sessionID: sessionID,
                replacementTabID: UUID()
            )

            let recovered = await manager.recoverProvisionalAgentAdmission(identity)

            guard case .recovered = recovered else {
                return XCTFail("Expected legacy recovery, got \(recovered)")
            }
            let recoveredDisk = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fileURL,
                scheduleNormalizationWriteback: false
            )
            XCTAssertEqual(recoveredDisk.lastSearchQuery, "durable newer value")
            XCTAssertFalse(recoveredDisk.composeTabs.contains { $0.id == provisional.id })
            XCTAssertEqual(
                manager.workspace(withID: workspace.id)?.lastSearchQuery,
                "durable newer value"
            )

            let foreign = WorkspaceModel(
                id: UUID(),
                name: durableNewer.name,
                repoPaths: durableNewer.repoPaths,
                lastSearchQuery: durableNewer.lastSearchQuery,
                composeTabs: [provisional],
                activeComposeTabID: provisional.id
            )
            let foreignBytes = try JSONEncoder().encode(foreign)
            try foreignBytes.write(to: fileURL, options: .atomic)
            let foreignOutcome = await manager.recoverProvisionalAgentAdmission(
                AgentProvisionalAdmissionIdentity(
                    recoveryID: UUID(),
                    workspaceID: workspace.id,
                    tabID: provisional.id,
                    sessionID: sessionID,
                    replacementTabID: UUID()
                )
            )
            XCTAssertEqual(foreignOutcome, .ownershipChanged)
            XCTAssertEqual(try Data(contentsOf: fileURL), foreignBytes)
        }

        func testLegacyRecoveryFailsClosedWhenPersistedWorkspaceCannotBeDecoded() async throws {
            let sessionID = UUID()
            let provisional = ComposeTabState(activeAgentSessionID: sessionID)
            let workspace = WorkspaceModel(
                name: "Legacy corrupt recovery",
                repoPaths: ["/tmp/legacy-recovery"],
                composeTabs: [provisional],
                activeComposeTabID: provisional.id
            )
            let fileURL = try writeWorkspace(workspace)
            try writeIndex([workspace])
            let (manager, prompt) = makeManager(client: nil)
            await manager.awaitInitialized()
            manager.activeWorkspace = workspace
            prompt.loadComposeTabsFromWorkspace(workspace)
            let corrupt = Data("{not-json".utf8)
            try corrupt.write(to: fileURL, options: .atomic)
            let identity = AgentProvisionalAdmissionIdentity(
                recoveryID: UUID(),
                workspaceID: workspace.id,
                tabID: provisional.id,
                sessionID: sessionID,
                replacementTabID: UUID()
            )

            let outcome = await manager.recoverProvisionalAgentAdmission(identity)

            XCTAssertEqual(outcome, .failed(.durabilityUncertain))
            XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
            XCTAssertTrue(manager.workspace(withID: workspace.id)?.composeTabs.contains {
                $0.id == provisional.id && $0.activeAgentSessionID == sessionID
            } == true)
        }

        func testLegacyRecoveryWriteFailureLeavesInMemoryProjectionUnchanged() async throws {
            let sessionID = UUID()
            let provisional = ComposeTabState(activeAgentSessionID: sessionID)
            let workspace = WorkspaceModel(
                name: "Legacy failed durable recovery",
                repoPaths: ["/tmp/legacy-recovery-write-failure"],
                composeTabs: [provisional],
                activeComposeTabID: provisional.id
            )
            let fileURL = try writeWorkspace(workspace)
            try writeIndex([workspace])
            let (manager, prompt) = makeManager(client: nil)
            await manager.awaitInitialized()
            manager.activeWorkspace = workspace
            prompt.loadComposeTabsFromWorkspace(workspace)
            let managerBefore = manager.workspace(withID: workspace.id)
            let promptTabsBefore = prompt.currentComposeTabs
            let promptActiveBefore = prompt.activeComposeTabID
            let sidebarBefore = prompt.sidebarWorkspaceSnapshot
            let identity = AgentProvisionalAdmissionIdentity(
                recoveryID: UUID(),
                workspaceID: workspace.id,
                tabID: provisional.id,
                sessionID: sessionID,
                replacementTabID: UUID()
            )
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.setAtomicWriteGateForTesting {
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            }

            let outcome = await manager.recoverProvisionalAgentAdmission(identity)
            await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.setAtomicWriteGateForTesting(nil)

            XCTAssertEqual(outcome, .failed(.durabilityUncertain))
            XCTAssertEqual(manager.workspace(withID: workspace.id), managerBefore)
            XCTAssertEqual(prompt.currentComposeTabs, promptTabsBefore)
            XCTAssertEqual(prompt.activeComposeTabID, promptActiveBefore)
            XCTAssertEqual(prompt.sidebarWorkspaceSnapshot, sidebarBefore)
        }

        func testConcurrentRecoveryCallersCoalesceOneCanonicalMutation() async throws {
            let fixture = try await makeFixture()
            fixture.manager.activeWorkspace = fixture.workspaceA
            fixture.prompt.loadComposeTabsFromWorkspace(fixture.workspaceA)
            let gate = RecoveryCoalescingGate()
            var hookCount = 0
            fixture.manager.setAgentAdmissionRecoveryWorkingCommitHandlerForTesting { _, _ in
                hookCount += 1
                await gate.suspendFirstCaller()
                return true
            }
            fixture.manager.setAgentAdmissionRecoveryDidCoalesceHandlerForTesting { identity in
                XCTAssertEqual(identity, fixture.identity)
                await gate.observeCoalescedCaller()
            }

            let first = Task { @MainActor in
                await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            }
            await gate.waitUntilFirstCallerIsSuspended()
            let second = Task { @MainActor in
                await fixture.manager.recoverProvisionalAgentAdmission(fixture.identity)
            }
            await gate.waitUntilCoalescedCallerIsObserved()
            await gate.releaseFirstCaller()
            let outcomes = await [first.value, second.value]

            XCTAssertEqual(outcomes[0], outcomes[1])
            XCTAssertEqual(hookCount, 1)
            let finalSnapshot = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            XCTAssertNil(finalSnapshot?.revisions.dirtyRevision)
        }

        private struct Fixture {
            let runtime: MCPDomainRuntime
            let client: DomainWorkspaceAuthorityClient
            let manager: WorkspaceManagerViewModel
            let prompt: PromptViewModel
            let workspaceA: WorkspaceModel
            let workspaceB: WorkspaceModel
            let workspaceAURL: URL
            let workspaceBURL: URL
            let identity: AgentProvisionalAdmissionIdentity
            let leftTab: ComposeTabState
            let rightTab: ComposeTabState
        }

        private func makeFixture() async throws -> Fixture {
            let sessionID = UUID()
            let provisional = ComposeTabState(
                name: "Provisional",
                isPinned: true,
                activeAgentSessionID: sessionID,
                promptText: "remove only me"
            )
            let left = ComposeTabState(
                name: "Left",
                selection: StoredSelection(selectedPaths: ["/tmp/left"]),
                promptText: "left prompt"
            )
            let right = ComposeTabState(
                name: "Right",
                selection: StoredSelection(selectedPaths: ["/tmp/right"]),
                promptText: "right prompt"
            )
            let workspaceA = WorkspaceModel(
                name: "Recovery A",
                repoPaths: ["/tmp/recovery-a"],
                lastSearchQuery: "keep search",
                selectedMetaPromptIDs: [UUID()],
                isHiddenInMenus: true,
                composeTabs: [left, provisional, right],
                activeComposeTabID: provisional.id
            )
            let workspaceBTab = ComposeTabState(name: "Unrelated", promptText: "untouched")
            let workspaceB = WorkspaceModel(
                name: "Recovery B",
                repoPaths: ["/tmp/recovery-b"],
                currentPromptText: "unrelated workspace",
                composeTabs: [workspaceBTab],
                activeComposeTabID: workspaceBTab.id
            )
            let workspaceAURL = try writeWorkspace(workspaceA)
            let workspaceBURL = try writeWorkspace(workspaceB)
            try writeIndex([workspaceA, workspaceB])

            let runtime = MCPDomainRuntime(configuration: .init(
                mode: .app,
                profileIdentifier: "agent-admission-recovery-\(UUID().uuidString)",
                storageDirectory: storageRoot.appendingPathComponent("runtime-state-\(UUID().uuidString)", isDirectory: true),
                workspaceStorageDirectory: storageRoot,
                eventDirectory: storageRoot.appendingPathComponent("events-\(UUID().uuidString)", isDirectory: true),
                temporaryDirectory: storageRoot.appendingPathComponent("tmp-\(UUID().uuidString)", isDirectory: true),
                externalReloadInterval: nil
            ))
            try await runtime.start()
            runtimes.append(runtime)
            let client = DomainWorkspaceAuthorityClient(store: runtime.workspaceStore, windowID: -882)
            let (manager, prompt) = makeManager(client: client)
            await manager.awaitInitialized()
            return Fixture(
                runtime: runtime,
                client: client,
                manager: manager,
                prompt: prompt,
                workspaceA: workspaceA,
                workspaceB: workspaceB,
                workspaceAURL: workspaceAURL,
                workspaceBURL: workspaceBURL,
                identity: AgentProvisionalAdmissionIdentity(
                    recoveryID: UUID(),
                    workspaceID: workspaceA.id,
                    tabID: provisional.id,
                    sessionID: sessionID,
                    replacementTabID: UUID()
                ),
                leftTab: left,
                rightTab: right
            )
        }

        private func makeManager(
            client: DomainWorkspaceAuthorityClient?
        ) -> (WorkspaceManagerViewModel, PromptViewModel) {
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
                windowID: -882,
                settingsManager: WindowSettingsManager(windowID: -882)
            )
            let manager = WorkspaceManagerViewModel(
                fileManager: fileManager,
                promptViewModel: prompt,
                domainWorkspaceAuthorityClient: client,
                performInitialWorkspaceActivation: false
            )
            managers.append(manager)
            return (manager, prompt)
        }

        private func writeWorkspace(_ workspace: WorkspaceModel) throws -> URL {
            let url = storageRoot
                .appendingPathComponent(
                    DomainWorkspaceStoragePath.directoryName(name: workspace.name, id: workspace.id),
                    isDirectory: true
                )
                .appendingPathComponent("workspace.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(workspace).write(to: url, options: .atomic)
            return url
        }

        private func writeIndex(_ workspaces: [WorkspaceModel]) throws {
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

        private func canonicalModel(_ fixture: Fixture) async throws -> WorkspaceModel {
            let snapshotValue = await fixture.client.canonicalWorkspaceSnapshot(fixture.workspaceA.id)
            let snapshot = try XCTUnwrap(snapshotValue)
            return try WorkspaceManagerViewModel.decodeDomainWorkspaceProjection(
                documentBytes: snapshot.document.documentBytes,
                fileURL: snapshot.document.fileURL
            )
        }

        private func assertNonComposeFieldsEqual(
            _ recovered: WorkspaceModel,
            _ original: WorkspaceModel,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            var normalizedRecovered = recovered
            normalizedRecovered.composeTabs = original.composeTabs
            normalizedRecovered.activeComposeTabID = original.activeComposeTabID
            normalizedRecovered.dateModified = original.dateModified
            XCTAssertEqual(normalizedRecovered, original, file: file, line: line)
        }
    }
#endif
