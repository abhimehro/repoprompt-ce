@testable import RepoPromptApp
import RepoPromptDomainRuntime
import XCTest

#if DEBUG
    @MainActor
    final class ConcurrentSameWorkspaceAgentRunAdmissionTests: XCTestCase {
        func testSameWorkspaceAdmissionsAcquireInFIFOOrderAndTeardownEmpty() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let workspaceID = UUID()
            let holderID = UUID()
            let queuedIDs = (0 ..< 5).map { _ in UUID() }
            let recorder = AdmissionOrderRecorder()

            let holder = try await coordinator.acquire(
                workspaceID: workspaceID,
                admissionID: holderID
            )
            var queuedTasks: [Task<UUID, Error>] = []
            for (index, admissionID) in queuedIDs.enumerated() {
                queuedTasks.append(Task {
                    let lease = try await coordinator.acquire(
                        workspaceID: workspaceID,
                        admissionID: admissionID
                    )
                    await recorder.append(admissionID)
                    lease.release()
                    return admissionID
                })
                try await waitUntil("waiter \(index + 1) to enqueue") {
                    coordinator.waiterCount(for: workspaceID) == index + 1
                }
            }

            XCTAssertEqual(coordinator.activeCount(for: workspaceID), 1)
            XCTAssertTrue(holder.release())
            XCTAssertFalse(holder.release(), "Lease release must be idempotent.")
            for (task, expectedID) in zip(queuedTasks, queuedIDs) {
                let admittedID = try await task.value
                XCTAssertEqual(admittedID, expectedID)
            }

            let recordedOrder = await recorder.values()
            XCTAssertEqual(recordedOrder, queuedIDs)
            XCTAssertEqual(
                coordinator.snapshot(),
                WorkspaceAgentAdmissionCoordinator.Snapshot(
                    activeAdmissionCount: 0,
                    waiterCount: 0,
                    trackedWorkspaceCount: 0
                )
            )
        }

        func testQueuedCancellationNeverAcquiresAndLeavesNoCoordinatorState() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let workspaceID = UUID()
            let holder = try await coordinator.acquire(
                workspaceID: workspaceID,
                admissionID: UUID()
            )
            let cancelledID = UUID()
            let cancelledTask = Task {
                try await coordinator.acquire(
                    workspaceID: workspaceID,
                    admissionID: cancelledID
                )
            }
            try await waitUntil("cancelled waiter to enqueue") {
                coordinator.waiterCount(for: workspaceID) == 1
            }

            cancelledTask.cancel()
            do {
                _ = try await cancelledTask.value
                XCTFail("A cancelled queued admission must not acquire a lease.")
            } catch is CancellationError {}

            XCTAssertEqual(coordinator.waiterCount(for: workspaceID), 0)
            holder.release()
            XCTAssertEqual(coordinator.snapshot().trackedWorkspaceCount, 0)
        }

        func testCancellingFirstQueuedWaiterPreservesNextWaiterHandoff() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let workspaceID = UUID()
            let holder = try await coordinator.acquire(
                workspaceID: workspaceID,
                admissionID: UUID()
            )
            let waiterA = Task {
                try await coordinator.acquire(
                    workspaceID: workspaceID,
                    admissionID: UUID()
                )
            }
            try await waitUntil("first waiter to enqueue") {
                coordinator.waiterCount(for: workspaceID) == 1
            }
            let waiterB = Task {
                try await coordinator.acquire(
                    workspaceID: workspaceID,
                    admissionID: UUID()
                )
            }
            try await waitUntil("both waiters to enqueue") {
                coordinator.waiterCount(for: workspaceID) == 2
            }

            waiterA.cancel()
            do {
                _ = try await waiterA.value
                XCTFail("The cancelled first waiter must not acquire a lease.")
            } catch is CancellationError {}

            XCTAssertEqual(
                coordinator.snapshot(),
                WorkspaceAgentAdmissionCoordinator.Snapshot(
                    activeAdmissionCount: 1,
                    waiterCount: 1,
                    trackedWorkspaceCount: 1
                )
            )
            holder.release()
            let waiterBLease = try await waiterB.value
            waiterBLease.release()
            XCTAssertEqual(
                coordinator.snapshot(),
                WorkspaceAgentAdmissionCoordinator.Snapshot(
                    activeAdmissionCount: 0,
                    waiterCount: 0,
                    trackedWorkspaceCount: 0
                )
            )
        }

        func testCancellationAfterHandoffReleasesBeforeReturning() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let workspaceID = UUID()
            let holder = try await coordinator.acquire(
                workspaceID: workspaceID,
                admissionID: UUID()
            )
            let handoffGate = AdmissionHandoffGate()
            let handedOffID = UUID()
            coordinator.setDidResumeAfterHandoffHandlerForTesting { _, admissionID in
                guard admissionID == handedOffID else { return }
                await handoffGate.enterAndWait()
            }
            defer {
                coordinator.setDidResumeAfterHandoffHandlerForTesting(nil)
                Task { await handoffGate.open() }
            }

            let handedOffTask = Task {
                try await coordinator.acquire(
                    workspaceID: workspaceID,
                    admissionID: handedOffID
                )
            }
            try await waitUntil("handoff waiter to enqueue") {
                coordinator.waiterCount(for: workspaceID) == 1
            }
            holder.release()
            await handoffGate.waitUntilEntered()
            handedOffTask.cancel()
            await handoffGate.open()

            do {
                _ = try await handedOffTask.value
                XCTFail("Cancellation after handoff must reject the acquisition.")
            } catch is CancellationError {}

            XCTAssertEqual(
                coordinator.snapshot(),
                WorkspaceAgentAdmissionCoordinator.Snapshot(
                    activeAdmissionCount: 0,
                    waiterCount: 0,
                    trackedWorkspaceCount: 0
                )
            )
        }

        func testDistinctWorkspaceAdmissionsOverlap() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let workspaceA = UUID()
            let workspaceB = UUID()

            let leaseA = try await coordinator.acquire(
                workspaceID: workspaceA,
                admissionID: UUID()
            )
            let leaseB = try await coordinator.acquire(
                workspaceID: workspaceB,
                admissionID: UUID()
            )

            XCTAssertEqual(
                coordinator.snapshot(),
                WorkspaceAgentAdmissionCoordinator.Snapshot(
                    activeAdmissionCount: 2,
                    waiterCount: 0,
                    trackedWorkspaceCount: 2
                )
            )
            leaseA.release()
            leaseB.release()
            XCTAssertEqual(coordinator.snapshot().trackedWorkspaceCount, 0)
        }

        func testManagerAdmissionHelperReleasesLeaseWhenOperationThrows() async throws {
            let coordinator = WorkspaceAgentAdmissionCoordinator()
            let fixture = makeManagerFixture(coordinator: coordinator)
            defer { fixture.manager.prepareForWindowClose() }

            do {
                _ = try await fixture.manager.withAgentSessionAdmission(
                    workspaceID: UUID(),
                    admissionID: UUID()
                ) {
                    throw AdmissionTestError.expected
                }
                XCTFail("The controlled operation must throw.")
            } catch AdmissionTestError.expected {}

            XCTAssertEqual(coordinator.snapshot().trackedWorkspaceCount, 0)
        }

        func testAgentAdmissionSaveRetriesOnceThenPersistsNewestState() async throws {
            let root = try makeTemporaryDirectory(named: "RetrySuccess")
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = makePersistentWorkspaceFixture(root: root)
            defer {
                fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
                fixture.manager.prepareForWindowClose()
            }
            fixture.manager.resetWorkspaceSaveDiagnosticsForTesting()
            fixture.manager.markWorkspaceDirty()
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting {
                workspaceID,
                _,
                remainingRetryCount in
                guard remainingRetryCount == 1 else { return }
                await MainActor.run {
                    guard let index = fixture.manager.workspaces.firstIndex(where: {
                        $0.id == workspaceID
                    }) else { return }
                    fixture.manager.workspaces[index].currentPromptText = "newest state"
                    fixture.manager.markWorkspaceDirty()
                }
            }

            let outcome = await fixture.manager.pollAndSaveStateWithOutcomeAsync(
                workspaceID: fixture.workspace.id,
                source: WorkspaceSaveSource("agentSessionLifecycleAdmissionTest")
            )

            guard case .persisted = outcome else {
                return XCTFail("The one allowed recapture must persist: \(outcome)")
            }
            XCTAssertEqual(
                fixture.manager.workspaceSaveDiagnosticsForTesting(
                    workspaceID: fixture.workspace.id
                ).attemptCount,
                2
            )
            let saved = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
                at: fixture.manager.workspaceFileURL(for: fixture.workspace),
                scheduleNormalizationWriteback: false
            )
            XCTAssertEqual(saved.currentPromptText, "newest state")
        }

        func testAgentAdmissionSaveReportsLocalRetryExhaustionAfterTwoAttempts() async throws {
            let root = try makeTemporaryDirectory(named: "RetryExhaustion")
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = makePersistentWorkspaceFixture(root: root)
            defer {
                fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
                fixture.manager.prepareForWindowClose()
            }
            fixture.manager.resetWorkspaceSaveDiagnosticsForTesting()
            fixture.manager.markWorkspaceDirty()
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting {
                workspaceID,
                _,
                _ in
                await MainActor.run {
                    guard let index = fixture.manager.workspaces.firstIndex(where: {
                        $0.id == workspaceID
                    }) else { return }
                    var workspace = fixture.manager.workspaces[index]
                    workspace.currentPromptText = (workspace.currentPromptText ?? "") + "x"
                    fixture.manager.workspaces[index] = workspace
                    fixture.manager.markWorkspaceDirty()
                }
            }

            let outcome = await fixture.manager.pollAndSaveStateWithOutcomeAsync(
                workspaceID: fixture.workspace.id,
                source: WorkspaceSaveSource("agentSessionLifecycleAdmissionTest")
            )

            XCTAssertEqual(
                outcome,
                .rejected(
                    reason: "workspace_save_failed",
                    category: .localSavePreparationRetryExhausted
                )
            )
            XCTAssertEqual(
                outcome.normalizedFailureCategory,
                .localSavePreparationRetryExhausted
            )
            XCTAssertEqual(
                fixture.manager.workspaceSaveDiagnosticsForTesting(
                    workspaceID: fixture.workspace.id
                ).attemptCount,
                2
            )
            XCTAssertNil(
                fixture.manager.debugLastSavedVersionForWorkspace(fixture.workspace.id)
            )
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: fixture.manager.workspaceFileURL(for: fixture.workspace).path
            ))
        }

        func testNormalizedFailureLeavesRemainDistinct() {
            let reasonCases: [(String, WorkspacePersistenceFailureCategory)] = [
                ("local_save_retry_exhausted", .localSavePreparationRetryExhausted),
                ("authority_revision_conflict", .authorityRevisionConflict),
                ("authority_external_conflict", .authorityExternalConflict),
                ("workspace_not_writable", .authorityReadOnly),
                ("lock_timed_out", .lockTimedOut),
                ("cancelled", .cancelled),
                ("persistence_failure", .persistenceFailure),
                ("workspace_changed", .workspaceChanged),
                ("durability_uncertain", .durabilityUncertain)
            ]
            XCTAssertEqual(Set(reasonCases.map(\.1)).count, reasonCases.count)
            for (reason, expected) in reasonCases {
                XCTAssertEqual(
                    WorkspacePersistenceOutcome.rejected(reason: reason)
                        .normalizedFailureCategory,
                    expected
                )
            }

            let domainCases: [(DomainCommandErrorCode, WorkspacePersistenceFailureCategory)] = [
                (.stateConflict, .authorityRevisionConflict),
                (.workspaceExternalConflict, .authorityExternalConflict),
                (.runtimeReadOnlyDegraded, .authorityReadOnly),
                (.workspaceReadOnlyDegraded, .authorityReadOnly),
                (.lockTimedOut, .lockTimedOut),
                (.cancelled, .cancelled),
                (.workspaceUnavailable, .workspaceChanged),
                (.persistenceFailure, .persistenceFailure)
            ]
            for (domainCode, expected) in domainCases {
                XCTAssertEqual(
                    WorkspacePersistenceFailureCategory.classify(
                        domainErrorCode: domainCode
                    ),
                    expected
                )
            }
        }

        private func makePersistentWorkspaceFixture(
            root: URL
        ) -> (manager: WorkspaceManagerViewModel, workspace: WorkspaceModel) {
            let fixture = makeManagerFixture(
                coordinator: WorkspaceAgentAdmissionCoordinator()
            )
            let tab = ComposeTabState(name: "Admission")
            let workspace = WorkspaceModel(
                name: "Admission",
                repoPaths: [],
                customStoragePath: root,
                composeTabs: [tab],
                activeComposeTabID: tab.id
            )
            fixture.manager.workspaces = [workspace]
            fixture.manager.activeWorkspace = workspace
            fixture.prompt.loadComposeTabsFromWorkspace(workspace)
            return (fixture.manager, workspace)
        }

        private func makeManagerFixture(
            coordinator: WorkspaceAgentAdmissionCoordinator
        ) -> (
            manager: WorkspaceManagerViewModel,
            prompt: PromptViewModel
        ) {
            let fileManager = WorkspaceFilesViewModel()
            let keyManager = KeyManager(
                secureService: SecureKeysService(
                    secureStorage: TestSecureStorageBackend()
                )
            )
            let apiSettings = APISettingsViewModel(
                aiQueriesService: AIQueriesService(keyManager: keyManager),
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
                workspaceAgentAdmissionCoordinator: coordinator,
                performInitialWorkspaceActivation: false
            )
            return (manager, prompt)
        }

        private func makeTemporaryDirectory(named name: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ConcurrentSameWorkspaceAgentRunAdmissionTests-\(name)-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            return url
        }

        private func waitUntil(
            _ description: String,
            timeout: Duration = .seconds(5),
            condition: () -> Bool
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while !condition() {
                guard clock.now < deadline else {
                    throw AdmissionTestError.timedOut(description)
                }
                await Task.yield()
            }
        }
    }

    private enum AdmissionTestError: Error {
        case expected
        case timedOut(String)
    }

    private actor AdmissionOrderRecorder {
        private var recorded: [UUID] = []

        func append(_ id: UUID) {
            recorded.append(id)
        }

        func values() -> [UUID] {
            recorded
        }
    }

    private actor AdmissionHandoffGate {
        private var entered = false
        private var isOpen = false
        private var entryWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func enterAndWait() async {
            entered = true
            let pendingEntryWaiters = entryWaiters
            entryWaiters.removeAll()
            pendingEntryWaiters.forEach { $0.resume() }
            guard !isOpen else { return }
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { continuation in
                entryWaiters.append(continuation)
            }
        }

        func open() {
            isOpen = true
            let pendingReleaseWaiters = releaseWaiters
            releaseWaiters.removeAll()
            pendingReleaseWaiters.forEach { $0.resume() }
        }
    }
#endif
