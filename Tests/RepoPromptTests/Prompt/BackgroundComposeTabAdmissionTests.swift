@testable import RepoPromptApp
import XCTest

@MainActor
final class BackgroundComposeTabAdmissionTests: XCTestCase {
    func testBackgroundCreationCrossesLegacyLimitWithoutMutatingExistingTabs() async throws {
        let fixture = makeFixture(initialTabCount: 499)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabIDs = originalWorkspace.composeTabs.map(\.id)
        let originalSessionIDsByTabID = Dictionary(
            uniqueKeysWithValues: originalWorkspace.composeTabs.map { ($0.id, $0.activeAgentSessionID) }
        )
        let originalActiveTabID = try XCTUnwrap(originalWorkspace.activeComposeTabID)
        let originalStashedTabs = originalWorkspace.stashedTabs

        for expectedCount in 500 ... 502 {
            let created = await fixture.prompt.createBackgroundComposeTab(
                strategy: .blank,
                name: "Background \(expectedCount)"
            )

            XCTAssertNotNil(created, "Background creation should reach \(expectedCount) tabs")
            XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.count, expectedCount)
        }

        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let existingTabs = Array(finalWorkspace.composeTabs.prefix(originalTabIDs.count))
        XCTAssertEqual(existingTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: existingTabs.map { ($0.id, $0.activeAgentSessionID) }),
            originalSessionIDsByTabID
        )
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalActiveTabID)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalStashedTabs)
    }

    func testForegroundAgentCreationCrosses499Through502WithoutUnrelatedMutation() async throws {
        let fixture = makeFixture(initialTabCount: 499)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabs = originalWorkspace.composeTabs
        let originalTabIDs = originalTabs.map(\.id)
        let originalPins = Dictionary(uniqueKeysWithValues: originalTabs.map { ($0.id, $0.isPinned) })
        let originalBindings = Dictionary(uniqueKeysWithValues: originalTabs.map { ($0.id, $0.activeAgentSessionID) })
        let originalStashedTabs = originalWorkspace.stashedTabs
        let originalDirtyTabIDs = Set(originalTabIDs.prefix(7))
        fixture.prompt.testSetDirtyTabIDs(originalDirtyTabIDs)

        let sideEffects = ComposeRemovalSideEffectRecorder()
        fixture.prompt.composeTabCascadeResolver = { tabIDs, _ in
            await sideEffects.recordCascade(tabIDs)
            return .init()
        }
        let closeToken = fixture.prompt.addComposeTabsWillCloseListener { tabIDs, _ in
            await sideEffects.recordClose(tabIDs)
        }
        defer { fixture.prompt.removeComposeTabsWillCloseListener(closeToken) }

        var createdIDs: [UUID] = []
        for expectedCount in 500 ... 502 {
            let creationResult = await viewModel.createAndActivateSessionTab()
            let createdID = try XCTUnwrap(creationResult)
            createdIDs.append(createdID)
            XCTAssertEqual(fixture.prompt.activeComposeTabID, createdID)
            XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, createdID)
            XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.count, expectedCount)
            XCTAssertEqual(fixture.manager.composeTab(with: createdID)?.activeAgentSessionID, viewModel.sessions[createdID]?.activeAgentSessionID)
        }

        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let existingTabs = Array(finalWorkspace.composeTabs.prefix(originalTabs.count))
        XCTAssertEqual(existingTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: existingTabs.map { ($0.id, $0.isPinned) }), originalPins)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: existingTabs.map { ($0.id, $0.activeAgentSessionID) }), originalBindings)
        XCTAssertEqual(fixture.prompt.dirtyTabIDs.intersection(originalTabIDs), originalDirtyTabIDs)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalStashedTabs)
        XCTAssertEqual(Array(finalWorkspace.composeTabs.suffix(createdIDs.count)).map(\.id), createdIDs)
        let recordedSideEffects = await sideEffects.snapshot()
        XCTAssertEqual(recordedSideEffects, .init())
    }

    func testFailedForegroundCreationDoesNotReturnOrMarkOldActiveTab() async throws {
        let fixture = makeFixture(initialTabCount: 1)
        let oldActiveTabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        XCTAssertNil(viewModel.sessions[oldActiveTabID])

        fixture.manager.activeWorkspace = nil
        let createdID = await viewModel.createAndActivateSessionTab()

        XCTAssertNil(createdID)
        XCTAssertEqual(fixture.prompt.activeComposeTabID, oldActiveTabID)
        XCTAssertNil(viewModel.sessions[oldActiveTabID])
    }

    func testUnstashAboveFiftyRestoresRequestedTabWithoutUnrelatedMutation() async throws {
        let fixture = makeFixture(initialTabCount: 51)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabs = originalWorkspace.composeTabs
        let originalIDs = originalTabs.map(\.id)
        let originalPins = Dictionary(uniqueKeysWithValues: originalTabs.map { ($0.id, $0.isPinned) })
        let originalBindings = Dictionary(uniqueKeysWithValues: originalTabs.map { ($0.id, $0.activeAgentSessionID) })
        let stashed = try XCTUnwrap(originalWorkspace.stashedTabs.first)
        let dirtyIDs = Set(originalIDs.prefix(5))
        fixture.prompt.testSetDirtyTabIDs(dirtyIDs)

        await fixture.prompt.unstashTab(stashed.id)

        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.count, 52)
        XCTAssertEqual(Array(finalWorkspace.composeTabs.prefix(originalIDs.count)).map(\.id), originalIDs)
        XCTAssertEqual(finalWorkspace.composeTabs.last?.id, stashed.tab.id)
        XCTAssertEqual(finalWorkspace.activeComposeTabID, stashed.tab.id)
        XCTAssertTrue(finalWorkspace.stashedTabs.isEmpty)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: finalWorkspace.composeTabs.prefix(originalIDs.count).map { ($0.id, $0.isPinned) }),
            originalPins
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: finalWorkspace.composeTabs.prefix(originalIDs.count).map { ($0.id, $0.activeAgentSessionID) }),
            originalBindings
        )
        XCTAssertEqual(fixture.prompt.dirtyTabIDs.intersection(originalIDs), dirtyIDs)
    }

    func testFailedRequiredFlushKeepsTabRuntimeAndProjection() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let sessionID = try XCTUnwrap(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tabID)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: sessionID, on: session)
        session.setItemsSilently([.user("must persist", sequenceIndex: 0)], reason: .testOverride)
        session.isDirty = true
        session.runState = .running

        let saveAttempts = SaveAttemptRecorder()
        viewModel.test_setAgentSessionSaver { _, _, _ in
            await saveAttempts.record()
            throw RequiredFlushTestError.injectedFailure
        }
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { tabIDs, reason, workspaceID in
            await viewModel.preflightComposeTabsRemoval(tabIDs, reason: reason, workspaceID: workspaceID)
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let originalOpenIDs = fixture.manager.activeWorkspace?.composeTabs.map(\.id)
        let originalStashedTabs = fixture.manager.activeWorkspace?.stashedTabs
        await fixture.prompt.closeComposeTab(tabID)

        let saveAttemptCount = await saveAttempts.count()
        XCTAssertEqual(saveAttemptCount, 1)
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), originalOpenIDs)
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertEqual(fixture.prompt.activeComposeTabID, tabID)
        XCTAssertTrue(viewModel.sessions[tabID] === session)
        XCTAssertEqual(session.runState, .running)
        XCTAssertTrue(session.isDirty)
    }

    func testFailedDurableDeletionDoesNotResurrectRemovedComposeTab() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let sessionID = try XCTUnwrap(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tabID)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: sessionID, on: session)
        session.runState = .running
        viewModel.setAgentRunActive(tabID, isActive: true)

        var teardownTabIDs: [UUID] = []
        viewModel.test_setComposeTabRemovalTeardownObserver { removedTabID in
            XCTAssertFalse(fixture.manager.activeWorkspace?.composeTabs.contains(where: { $0.id == removedTabID }) == true)
            XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == removedTabID }))
            teardownTabIDs.append(removedTabID)
        }
        viewModel.test_setAgentSessionsDeleter { _, _ in
            throw RequiredFlushTestError.injectedFailure
        }
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        await fixture.prompt.closeComposeTab(tabID)

        XCTAssertFalse(fixture.manager.activeWorkspace?.composeTabs.contains(where: { $0.id == tabID }) == true)
        XCTAssertNil(viewModel.sessions[tabID])
        XCTAssertEqual(teardownTabIDs, [tabID])
    }

    func testRestoredTabDuringPostStashCleanupKeepsReplacementRuntime() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let removedSession = viewModel.session(for: tabID)
        var replacementSession = viewModel.sessions[UUID()]

        viewModel.test_setComposeTabRemovalTeardownObserver { removedTabID in
            guard let activeWorkspaceID = fixture.manager.activeWorkspaceID,
                  let workspaceIndex = fixture.manager.workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
            else {
                XCTFail("Expected active workspace")
                return
            }
            guard let stashedIndex = fixture.manager.workspaces[workspaceIndex].stashedTabs.firstIndex(
                where: { $0.tab.id == removedTabID }
            ) else {
                XCTFail("Expected stashed tab")
                return
            }
            let restoredTab = fixture.manager.workspaces[workspaceIndex].stashedTabs.remove(at: stashedIndex).tab
            fixture.manager.workspaces[workspaceIndex].composeTabs.append(restoredTab)
            replacementSession = viewModel.session(for: removedTabID)
        }
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }

        _ = await fixture.prompt.stashComposeTabs(withIDs: [tabID])

        XCTAssertFalse(viewModel.sessions[tabID] === removedSession)
        XCTAssertTrue(viewModel.sessions[tabID] === replacementSession)
    }

    func testFailedStashedDeletionDoesNotResurrectRemovedProjection() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let stashedTab = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        _ = viewModel.session(for: stashedTab.tab.id)
        viewModel.test_setAgentSessionsDeleter { _, _ in
            throw RequiredFlushTestError.injectedFailure
        }
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }

        await fixture.prompt.deleteStashedTab(stashedTab.id)

        XCTAssertFalse(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashedTab.id }))
        XCTAssertFalse(fixture.manager.activeWorkspace?.stashedTabs.contains(where: { $0.id == stashedTab.id }) == true)
        XCTAssertNil(viewModel.sessions[stashedTab.tab.id])
    }

    func testMultiTabDeletionFailureContinuesRemainingCleanup() async throws {
        let fixture = makeFixture(initialTabCount: 3)
        let tabs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        for tab in tabs {
            _ = viewModel.session(for: tab.id)
        }
        let orderedTabIDs = tabs.map(\.id).sorted(by: { $0.uuidString < $1.uuidString })
        let attempts = DeletionAttemptRecorder(failingTabID: orderedTabIDs[1])
        viewModel.test_setAgentSessionsDeleter { tabID, _ in
            try await attempts.delete(tabID)
        }
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }

        await fixture.prompt.closeAllComposeTabs()

        let attemptedTabIDs = await attempts.attempted()
        XCTAssertEqual(attemptedTabIDs, orderedTabIDs)
        for tab in tabs {
            XCTAssertNil(viewModel.sessions[tab.id])
        }
    }

    func testStashRunsPostProjectionTeardownWithoutDurableDeletion() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        _ = viewModel.session(for: tabID)
        let attempts = DeletionAttemptRecorder(failingTabID: nil)
        viewModel.test_setAgentSessionsDeleter { deletedTabID, _ in
            try await attempts.delete(deletedTabID)
        }
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        await fixture.prompt.stashTab(tabID)

        XCTAssertTrue(fixture.manager.activeWorkspace?.stashedTabs.contains(where: { $0.tab.id == tabID }) == true)
        XCTAssertNil(viewModel.sessions[tabID])
        let attemptedTabIDs = await attempts.attempted()
        XCTAssertTrue(attemptedTabIDs.isEmpty)
    }

    func testSingleStashOfLastTabCreatesReplacement() async throws {
        let fixture = makeFixture(initialTabCount: 1)
        let originalTab = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first)

        await fixture.prompt.stashTab(originalTab.id)

        let remainingTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs)
        XCTAssertEqual(remainingTabs.count, 1)
        XCTAssertNotEqual(remainingTabs.first?.id, originalTab.id)
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.tab.id == originalTab.id }))
    }

    func testBulkStashAllCreatesOneReplacementAndReportsRemovedTabs() async throws {
        let fixture = makeFixture(initialTabCount: 3)
        let originalIDs = try Set(XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.id)))

        let report = await fixture.prompt.stashComposeTabs(withIDs: originalIDs)

        XCTAssertEqual(report.removedComposeTabIDs, originalIDs)
        XCTAssertTrue(report.rejections.isEmpty)
        let remainingTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs)
        XCTAssertEqual(remainingTabs.count, 1)
        let replacement = try XCTUnwrap(remainingTabs.first)
        XCTAssertFalse(originalIDs.contains(replacement.id))
        XCTAssertEqual(fixture.prompt.activeComposeTabID, replacement.id)
        let finalStashedIDs = Set(fixture.manager.activeWorkspace?.stashedTabs.map(\.tab.id) ?? [])
        XCTAssertTrue(finalStashedIDs.isSuperset(of: originalIDs))
    }

    func testBatchPinUpdatesOnlyChangedTabs() throws {
        let fixture = makeFixture(initialTabCount: 3)
        let tabs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs)
        fixture.prompt.setComposeTabPinned(true, for: tabs[0].id)

        let report = fixture.prompt.setComposeTabsPinned(true, for: Set(tabs.map(\.id)))

        XCTAssertEqual(report.updatedTabIDs, Set(tabs.dropFirst().map(\.id)))
        XCTAssertTrue(fixture.prompt.currentComposeTabs.allSatisfy(\.isPinned))
        XCTAssertTrue(fixture.prompt.setComposeTabsPinned(true, for: Set(tabs.map(\.id))).updatedTabIDs.isEmpty)
    }

    func testBatchPinRejectsMissingTargetWithoutPartialMutation() throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.dropFirst().first?.id)

        let report = fixture.prompt.setComposeTabsPinned(true, for: [tabID, UUID()])

        XCTAssertTrue(report.contextRejected)
        XCTAssertFalse(fixture.prompt.currentComposeTabs.first(where: { $0.id == tabID })?.isPinned == true)
    }

    func testBulkDeletePreservesConcurrentSameWorkspacePinMutation() async throws {
        let fixture = makeFixture(initialTabCount: 3)
        let tabs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs)
        let targetID = tabs[0].id
        let retainedID = tabs[1].id
        let gate = ComposeRemovalPreflightGate()
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, _, _ in
            await gate.markStartedAndWaitForRelease()
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let deleteTask = Task { await fixture.prompt.closeComposeTabs(withIDs: [targetID]) }
        let preflightStarted = await gate.waitUntilStarted()
        XCTAssertTrue(preflightStarted)
        fixture.prompt.setComposeTabPinned(true, for: retainedID)
        await gate.release()
        _ = await deleteTask.value

        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == targetID }))
        XCTAssertEqual(fixture.prompt.currentComposeTabs.first(where: { $0.id == retainedID })?.isPinned, true)
    }

    func testCloseRejectsMissingRequestedRootBeforeCascadeResolution() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let stashed = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)

        let report = await fixture.prompt.closeComposeTabs(withIDs: [activeTabID, stashed.tab.id])

        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.prompt.currentComposeTabs.contains(where: { $0.id == activeTabID }))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashed.id }))
    }

    func testArchivedDeleteRejectsSelectedIdentityReplacedDuringCascade() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let selected = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let replacementTab = ComposeTabState(id: UUID(), name: "Replacement")
        let gate = ComposeRemovalPreflightGate()
        fixture.prompt.stashedTabCascadeResolver = { _ in
            await gate.markStartedAndWaitForRelease()
            return PromptViewModel.AgentSessionCascadePlan()
        }
        let target = PromptViewModel.ArchivedTabMutationTarget(
            stashedTabID: selected.id,
            tabID: selected.tab.id
        )

        let deleteTask = Task {
            await fixture.prompt.deleteComposeAndStashedTabs(
                composeTabIDs: [],
                archivedTargets: [target]
            )
        }
        let cascadeStarted = await gate.waitUntilStarted()
        XCTAssertTrue(cascadeStarted)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let workspaceIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID }))
        let selectedIndex = try XCTUnwrap(
            fixture.manager.workspaces[workspaceIndex].stashedTabs.firstIndex(where: { $0.id == selected.id })
        )
        fixture.manager.workspaces[workspaceIndex].stashedTabs[selectedIndex] = StashedTab(
            id: selected.id,
            tab: replacementTab
        )
        await gate.release()
        let report = await deleteTask.value

        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.manager.workspaces[workspaceIndex].stashedTabs.contains(where: {
            $0.id == selected.id && $0.tab.id == replacementTab.id
        }))
    }

    func testParentDeleteIncludesChildPausedAfterDurableAdmission() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let parentTab = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first)
        let parentSessionID = try XCTUnwrap(parentTab.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let admissionGate = ComposeRemovalPreflightGate()
        viewModel.test_setAfterDurableChildTabCreation {
            await admissionGate.markStartedAndWaitForRelease()
        }

        let admissionTask = Task {
            try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: nil,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: "Paused child",
                parentSessionID: parentSessionID
            )
        }
        let admissionPaused = await admissionGate.waitUntilStarted()
        XCTAssertTrue(admissionPaused)
        let childTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id != parentTab.id && $0.name == "Paused child" })?.id
        )

        let report = await fixture.prompt.deleteComposeAndStashedTabs(
            composeTabIDs: [parentTab.id],
            archivedTargets: []
        )
        await admissionGate.release()

        XCTAssertTrue(report.removedComposeTabIDs.contains(parentTab.id))
        XCTAssertTrue(report.removedComposeTabIDs.contains(childTabID))
        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == parentTab.id || $0.id == childTabID }))
        do {
            _ = try await admissionTask.value
            XCTFail("Expected paused child admission to reject after cascade deletion")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("removed before admission completed"))
        }
    }

    func testArchivedDeleteRejectsChildAdmittedDuringRequiredPersistence() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let archived = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let parentSessionID = try XCTUnwrap(archived.tab.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let preflightGate = ComposeRemovalPreflightGate()
        let admissionGate = ComposeRemovalPreflightGate()
        viewModel.test_setAfterDurableChildTabCreation {
            await admissionGate.markStartedAndWaitForRelease()
        }
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            if reason == .deleteStashed {
                await preflightGate.markStartedAndWaitForRelease()
            }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }
        let target = PromptViewModel.ArchivedTabMutationTarget(
            stashedTabID: archived.id,
            tabID: archived.tab.id
        )

        let deleteTask = Task {
            await fixture.prompt.deleteComposeAndStashedTabs(
                composeTabIDs: [],
                archivedTargets: [target]
            )
        }
        let preflightStarted = await preflightGate.waitUntilStarted()
        XCTAssertTrue(preflightStarted)
        let admissionTask = Task {
            try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: nil,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: "Late archived child",
                parentSessionID: parentSessionID
            )
        }
        let admissionPaused = await admissionGate.waitUntilStarted()
        XCTAssertTrue(admissionPaused)
        let childTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.name == "Late archived child" })?.id
        )
        await preflightGate.release()
        let report = await deleteTask.value
        await admissionGate.release()
        _ = try await admissionTask.value

        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == archived.id }))
        XCTAssertTrue(fixture.prompt.currentComposeTabs.contains(where: { $0.id == childTabID }))
    }

    func testDeleteRejectsCascadeAddedArchivedIdentityReplacement() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let archived = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let replacementTab = ComposeTabState(id: UUID(), name: "Replacement descendant")
        let gate = ComposeRemovalPreflightGate()
        fixture.prompt.composeTabCascadeResolver = { _, _ in
            await gate.markStartedAndWaitForRelease()
            return PromptViewModel.AgentSessionCascadePlan(archivedTargets: [
                .init(stashedTabID: archived.id, tabID: archived.tab.id)
            ])
        }

        let deleteTask = Task { await fixture.prompt.closeComposeTabs(withIDs: [activeTabID]) }
        let cascadeStarted = await gate.waitUntilStarted()
        XCTAssertTrue(cascadeStarted)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let workspaceIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID }))
        let archivedIndex = try XCTUnwrap(
            fixture.manager.workspaces[workspaceIndex].stashedTabs.firstIndex(where: { $0.id == archived.id })
        )
        fixture.manager.workspaces[workspaceIndex].stashedTabs[archivedIndex] = StashedTab(
            id: archived.id,
            tab: replacementTab
        )
        await gate.release()
        let report = await deleteTask.value

        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.prompt.currentComposeTabs.contains(where: { $0.id == activeTabID }))
        XCTAssertTrue(fixture.manager.workspaces[workspaceIndex].stashedTabs.contains(where: {
            $0.id == archived.id && $0.tab.id == replacementTab.id
        }))
    }

    func testBulkCoordinatorAppliesExactMixedDeleteTargets() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let stashed = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        viewModel.ui.sessionSidebar.selectAll(
            renderedOrder: [
                .active(tabID: activeTabID),
                .archived(stashedTabID: stashed.id, tabID: stashed.tab.id)
            ],
            workspaceID: workspaceID
        )
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [activeTabID],
            archivedDeleteTargets: [.init(stashedTabID: stashed.id, tabID: stashed.tab.id)],
            stashTabIDs: [],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        await viewModel.performSidebarBulkAction(
            .delete,
            origin: .selection,
            commandProgressPlacement: nil,
            targets: targets,
            promptManager: fixture.prompt
        )

        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == activeTabID }))
        XCTAssertFalse(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashed.id }))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
    }

    func testCommandCoordinatorPublishesCommandProgressAndRejectsReentryWhileDeleteIsSuspended() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        let fence = TestReleaseFence(name: "command sidebar delete preflight")
        defer { fence.release() }
        let preflightRecorder = RemovalPreflightRecorder()
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            await preflightRecorder.record(reason)
            if reason == .close { await fence.enterAndWait() }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [tabID],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        let deleteTask = Task {
            await viewModel.performSidebarBulkAction(
                .delete,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let preflightEntered = await fence.waitUntilEntered()
        XCTAssertTrue(preflightEntered)

        let operation = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertEqual(operation.workspaceID, workspaceID)
        XCTAssertEqual(operation.kind, .delete)
        XCTAssertEqual(operation.origin, .command)
        XCTAssertEqual(operation.targetCount, 1)
        XCTAssertEqual(operation.presentationTargets, [.active(tabID: tabID)])
        XCTAssertEqual(operation.commandProgressPlacement, .row)
        XCTAssertTrue(viewModel.ui.sessionSidebar.selectionState.isMutationInFlight)
        XCTAssertFalse(viewModel.ui.sessionSidebar.selectionState.showsSelectionPresentation)
        XCTAssertEqual(
            viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
                for: .active(tabID: tabID),
                workspaceID: workspaceID
            ),
            operation
        )
        XCTAssertNil(
            viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
                for: .active(tabID: UUID()),
                workspaceID: workspaceID
            )
        )

        await viewModel.performSidebarBulkAction(
            .delete,
            origin: .command,
            commandProgressPlacement: .row,
            targets: targets,
            promptManager: fixture.prompt
        )

        XCTAssertEqual(viewModel.ui.sessionSidebar.selectionState.inFlightAction, operation)
        let closePreflightCount = await preflightRecorder.count(for: .close)
        XCTAssertEqual(closePreflightCount, 1)

        fence.release()
        await deleteTask.value

        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == tabID }))
        XCTAssertFalse(viewModel.ui.sessionSidebar.selectionState.isMutationInFlight)
        XCTAssertFalse(viewModel.ui.sessionSidebar.selectionState.showsSelectionPresentation)
        XCTAssertNil(
            viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
                for: .active(tabID: tabID),
                workspaceID: workspaceID
            )
        )
    }

    func testCommandCoordinatorRetiresProgressAfterStashProjectionRemovalBeforeCleanup() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let activeIdentity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        let fence = TestReleaseFence(name: "command sidebar stash will-close")
        defer { fence.release() }
        let willCloseToken = fixture.prompt.addComposeTabsWillCloseListener { tabIDs, reason in
            guard reason == .stash, tabIDs.contains(tabID) else { return }
            await fence.enterAndWait()
        }
        defer { fixture.prompt.removeComposeTabsWillCloseListener(willCloseToken) }
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [tabID],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        let stashTask = Task {
            await viewModel.performSidebarBulkAction(
                .stash,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let willCloseEntered = await fence.waitUntilEntered()
        XCTAssertTrue(willCloseEntered)

        let workspaceSnapshot = try XCTUnwrap(fixture.prompt.sidebarWorkspaceSnapshot)
        XCTAssertEqual(workspaceSnapshot.workspaceID, workspaceID)
        XCTAssertFalse(workspaceSnapshot.composeTabs.contains(where: { $0.id == tabID }))
        let stashedTab = try XCTUnwrap(workspaceSnapshot.stashedTabs.first(where: { $0.tab.id == tabID }))
        let archivedIdentity = AgentSidebarSelectionIdentity.archived(
            stashedTabID: stashedTab.id,
            tabID: tabID
        )
        let operation = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertTrue(operation.commandRowProgressRetired)
        XCTAssertEqual(operation.presentationTargets, [activeIdentity])

        let projection = viewModel.sidebarListProjection(
            workspaceID: workspaceSnapshot.workspaceID,
            composeTabs: workspaceSnapshot.composeTabs,
            stashedTabs: workspaceSnapshot.stashedTabs,
            currentTabID: fixture.prompt.activeComposeTabID,
            sidebarSnapshot: viewModel.ui.sessionSidebar.snapshot,
            archivedSessionsExpanded: false,
            showComposeTabsWithoutAgentSessions: true
        )
        let renderedIdentities = Set(projection.pagedSessions.map {
            AgentSidebarSelectionIdentity.active(tabID: $0.tabID)
        })
        XCTAssertFalse(projection.existingSelectionIdentities.contains(activeIdentity))
        XCTAssertTrue(projection.existingSelectionIdentities.contains(archivedIdentity))
        XCTAssertFalse(projection.existingSelectionIdentities.contains(
            .archived(stashedTabID: UUID(), tabID: tabID)
        ))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandFallbackProgressOperation(
            existingIdentities: projection.existingSelectionIdentities,
            renderedIdentities: renderedIdentities,
            workspaceID: workspaceID
        ))

        fence.release()
        await stashTask.value

        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
    }

    func testCommandCoordinatorRetiresAllCommandProgressAfterProjectionRemoval() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let identity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        let fence = TestReleaseFence(name: "command sidebar delete post-projection cleanup")
        defer { fence.release() }
        viewModel.test_setComposeTabRemovalTeardownObserver { removedTabID in
            guard removedTabID == tabID else { return }
            await fence.enterAndWait()
        }
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [tabID],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        let deleteTask = Task {
            await viewModel.performSidebarBulkAction(
                .delete,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let cleanupEntered = await fence.waitUntilEntered()
        XCTAssertTrue(cleanupEntered)

        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == tabID }))
        let workspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let projection = viewModel.sidebarListProjection(
            workspaceID: workspace.id,
            composeTabs: workspace.composeTabs,
            stashedTabs: workspace.stashedTabs,
            currentTabID: fixture.prompt.activeComposeTabID,
            sidebarSnapshot: viewModel.ui.sessionSidebar.snapshot,
            archivedSessionsExpanded: true,
            showComposeTabsWithoutAgentSessions: true
        )
        XCTAssertFalse(projection.renderedSelectionOrder.contains(identity))
        let operation = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertTrue(operation.commandRowProgressRetired)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
            for: identity,
            workspaceID: workspaceID
        ))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandFallbackProgressOperation(
            existingIdentities: projection.existingSelectionIdentities,
            renderedIdentities: Set(projection.renderedSelectionOrder),
            workspaceID: workspaceID
        ))
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))

        fence.release()
        await deleteTask.value

        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandFallbackProgressOperation(
            existingIdentities: [],
            renderedIdentities: [],
            workspaceID: workspaceID
        ))
    }

    func testCommandCoordinatorDoesNotAttachOldProgressToSameIDReplacement() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let identity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let removedSession = viewModel.session(for: tabID)
        var replacementSession = viewModel.sessions[UUID()]
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        let fence = TestReleaseFence(name: "command sidebar stash same-ID replacement")
        defer { fence.release() }
        viewModel.test_setComposeTabRemovalTeardownObserver { removedTabID in
            guard removedTabID == tabID,
                  let workspaceIndex = fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID }),
                  let stashedIndex = fixture.manager.workspaces[workspaceIndex].stashedTabs.firstIndex(
                      where: { $0.tab.id == removedTabID }
                  )
            else {
                XCTFail("Expected stashed command target")
                return
            }
            let restoredTab = fixture.manager.workspaces[workspaceIndex].stashedTabs.remove(at: stashedIndex).tab
            fixture.manager.workspaces[workspaceIndex].composeTabs.append(restoredTab)
            replacementSession = viewModel.session(for: removedTabID)
            await fence.enterAndWait()
        }
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [tabID],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        let stashTask = Task {
            await viewModel.performSidebarBulkAction(
                .stash,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let cleanupEntered = await fence.waitUntilEntered()
        XCTAssertTrue(cleanupEntered)

        XCTAssertTrue(fixture.manager.activeWorkspace?.composeTabs.contains(where: { $0.id == tabID }) == true)
        XCTAssertFalse(viewModel.sessions[tabID] === removedSession)
        XCTAssertTrue(viewModel.sessions[tabID] === replacementSession)
        let workspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let projection = viewModel.sidebarListProjection(
            workspaceID: workspace.id,
            composeTabs: workspace.composeTabs,
            stashedTabs: workspace.stashedTabs,
            currentTabID: fixture.prompt.activeComposeTabID,
            sidebarSnapshot: viewModel.ui.sessionSidebar.snapshot,
            archivedSessionsExpanded: true,
            showComposeTabsWithoutAgentSessions: true
        )
        XCTAssertTrue(projection.renderedSelectionOrder.contains(identity))
        let operation = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertTrue(operation.commandRowProgressRetired)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
            for: identity,
            workspaceID: workspaceID
        ))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandFallbackProgressOperation(
            existingIdentities: projection.existingSelectionIdentities,
            renderedIdentities: Set(projection.renderedSelectionOrder),
            workspaceID: workspaceID
        ))
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))

        fence.release()
        await stashTask.value

        XCTAssertTrue(viewModel.sessions[tabID] === replacementSession)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
    }

    func testStaleCommandCleanupCannotRetireSameIDReplacementOperation() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let sourceWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let workspaceID = sourceWorkspace.id
        let tabID = try XCTUnwrap(sourceWorkspace.composeTabs.first?.id)
        let identity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }

        let cleanupFenceA = TestReleaseFence(name: "stale command A post-projection cleanup")
        defer { cleanupFenceA.release() }
        viewModel.test_setComposeTabRemovalTeardownObserver { removedTabID in
            guard removedTabID == tabID else { return }
            await cleanupFenceA.enterAndWait()
        }

        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [tabID],
            pinTabIDs: [],
            unpinTabIDs: []
        )
        let stashTaskA = Task {
            await viewModel.performSidebarBulkAction(
                .stash,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let cleanupAEntered = await cleanupFenceA.waitUntilEntered()
        XCTAssertTrue(cleanupAEntered)

        let snapshotAfterA = try XCTUnwrap(fixture.prompt.sidebarWorkspaceSnapshot)
        XCTAssertEqual(snapshotAfterA.workspaceID, workspaceID)
        XCTAssertFalse(snapshotAfterA.composeTabs.contains(where: { $0.id == tabID }))
        XCTAssertTrue(snapshotAfterA.stashedTabs.contains(where: { $0.tab.id == tabID }))
        let operationA = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertTrue(operationA.commandRowProgressRetired)

        let destinationWorkspace = WorkspaceModel(
            name: "Command retirement destination",
            repoPaths: sourceWorkspace.repoPaths,
            ephemeralFlag: true,
            composeTabs: [ComposeTabState(name: "Destination tab", activeAgentSessionID: UUID())]
        )
        fixture.manager.workspaces.append(destinationWorkspace)
        fixture.manager.activeWorkspace = destinationWorkspace
        fixture.prompt.loadComposeTabsFromWorkspace(destinationWorkspace)
        await viewModel.handleWorkspaceSwitch(destinationWorkspace)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)

        let latestSourceWorkspace = try XCTUnwrap(
            fixture.manager.workspaces.first(where: { $0.id == workspaceID })
        )
        fixture.manager.activeWorkspace = latestSourceWorkspace
        fixture.prompt.loadComposeTabsFromWorkspace(latestSourceWorkspace)
        await viewModel.handleWorkspaceSwitch(latestSourceWorkspace)

        let restoredTabResult = await fixture.prompt.restoreStashedComposeTab(containingTabID: tabID)
        let restoredTab = try XCTUnwrap(restoredTabResult)
        XCTAssertEqual(restoredTab.id, tabID)
        XCTAssertTrue(fixture.manager.activeWorkspace?.composeTabs.contains(where: { $0.id == tabID }) == true)

        let preflightFenceB = TestReleaseFence(name: "replacement command B preflight")
        defer { preflightFenceB.release() }
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { tabIDs, reason, _ in
            guard reason == .stash, tabIDs.contains(tabID) else { return .proceed }
            await preflightFenceB.enterAndWait()
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let stashTaskB = Task {
            await viewModel.performSidebarBulkAction(
                .stash,
                origin: .command,
                commandProgressPlacement: .row,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let preflightBEntered = await preflightFenceB.waitUntilEntered()
        XCTAssertTrue(preflightBEntered)

        let operationB = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertNotEqual(operationA.token, operationB.token)
        XCTAssertFalse(operationB.commandRowProgressRetired)
        XCTAssertEqual(
            viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
                for: identity,
                workspaceID: workspaceID
            ),
            operationB
        )
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))

        cleanupFenceA.release()
        await stashTaskA.value

        let operationBAfterA = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertEqual(operationBAfterA.token, operationB.token)
        XCTAssertFalse(operationBAfterA.commandRowProgressRetired)
        XCTAssertEqual(
            viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
                for: identity,
                workspaceID: workspaceID
            ),
            operationBAfterA
        )
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))

        preflightFenceB.release()
        await stashTaskB.value

        XCTAssertTrue(fixture.manager.activeWorkspace?.stashedTabs.contains(where: { $0.tab.id == tabID }) == true)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
            for: identity,
            workspaceID: workspaceID
        ))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandFallbackProgressOperation(
            existingIdentities: [],
            renderedIdentities: [],
            workspaceID: workspaceID
        ))
    }

    func testSelectionCoordinatorRetainsProgressAfterReconciliationWhileDeleteIsSuspended() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let identity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        viewModel.ui.sessionSidebar.selectAll(renderedOrder: [identity], workspaceID: workspaceID)
        let fence = TestReleaseFence(name: "selection sidebar delete preflight")
        defer { fence.release() }
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            if reason == .close { await fence.enterAndWait() }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [tabID],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [],
            unpinTabIDs: []
        )

        let deleteTask = Task {
            await viewModel.performSidebarBulkAction(
                .delete,
                origin: .selection,
                commandProgressPlacement: nil,
                targets: targets,
                promptManager: fixture.prompt
            )
        }
        let preflightEntered = await fence.waitUntilEntered()
        XCTAssertTrue(preflightEntered)

        let operation = try XCTUnwrap(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
        XCTAssertEqual(operation.workspaceID, workspaceID)
        XCTAssertEqual(operation.kind, .delete)
        XCTAssertEqual(operation.origin, .selection)
        XCTAssertEqual(operation.targetCount, 1)
        XCTAssertEqual(operation.presentationTargets, [identity])
        XCTAssertNil(operation.commandProgressPlacement)
        XCTAssertTrue(viewModel.ui.sessionSidebar.selectionState.isMutationInFlight)
        XCTAssertTrue(viewModel.ui.sessionSidebar.selectionState.showsSelectionPresentation)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
            for: identity,
            workspaceID: workspaceID
        ))
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.archivedHeaderCommandProgressOperation)

        viewModel.ui.sessionSidebar.reconcileSelection(renderedOrder: [], workspaceID: workspaceID)

        XCTAssertTrue(viewModel.ui.sessionSidebar.selectionState.selectedIdentities.isEmpty)
        XCTAssertTrue(viewModel.ui.sessionSidebar.selectionState.showsSelectionPresentation)
        XCTAssertEqual(viewModel.ui.sessionSidebar.selectionState.inFlightAction, operation)

        fence.release()
        await deleteTask.value

        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: { $0.id == tabID }))
        XCTAssertFalse(viewModel.ui.sessionSidebar.selectionState.isMutationInFlight)
        XCTAssertFalse(viewModel.ui.sessionSidebar.selectionState.showsSelectionPresentation)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.commandRowProgressOperation(
            for: identity,
            workspaceID: workspaceID
        ))
    }

    func testMixedDeleteDoesNotRetryArchivedTargetRejectedDuringActiveCascade() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let stashed = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        fixture.prompt.composeTabCascadeResolver = { _, _ in
            PromptViewModel.AgentSessionCascadePlan(archivedTargets: [
                .init(stashedTabID: stashed.id, tabID: stashed.tab.id)
            ])
        }
        fixture.prompt.stashedTabCascadeResolver = { _ in PromptViewModel.AgentSessionCascadePlan() }
        fixture.prompt.agentSessionCascadeSnapshotResolver = { _, _, _ in
            PromptViewModel.AgentSessionCascadePlan(archivedTargets: [
                .init(stashedTabID: stashed.id, tabID: stashed.tab.id)
            ])
        }
        let preflightRecorder = RemovalPreflightRecorder()
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            await preflightRecorder.record(reason)
            if reason == .deleteStashed {
                return .abort(.init(
                    stage: .requiredSessionFlush,
                    tabID: stashed.tab.id,
                    message: "Injected archived rejection."
                ))
            }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let report = await fixture.prompt.deleteComposeAndStashedTabs(
            composeTabIDs: [activeTabID],
            archivedTargets: [.init(stashedTabID: stashed.id, tabID: stashed.tab.id)]
        )

        let archivedPreflightCount = await preflightRecorder.count(for: .deleteStashed)
        XCTAssertEqual(archivedPreflightCount, 1)
        XCTAssertEqual(report.rejections.count(where: { $0.kind == .deleteStashed }), 1)
        XCTAssertTrue(report.removedComposeTabIDs.contains(activeTabID))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashed.id }))
    }

    func testMixedDeleteKeepsArchivedTargetWhenActiveCascadePreflightRejects() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let stashed = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        fixture.prompt.stashedTabCascadeResolver = { _ in
            PromptViewModel.AgentSessionCascadePlan(composeTabIDs: [activeTabID])
        }
        fixture.prompt.agentSessionCascadeSnapshotResolver = { _, _, _ in
            PromptViewModel.AgentSessionCascadePlan(composeTabIDs: [activeTabID])
        }
        let preflightRecorder = RemovalPreflightRecorder()
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            await preflightRecorder.record(reason)
            if reason == .close {
                return .abort(.init(
                    stage: .requiredSessionFlush,
                    tabID: activeTabID,
                    message: "Injected active rejection."
                ))
            }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let report = await fixture.prompt.deleteComposeAndStashedTabs(
            composeTabIDs: [],
            archivedTargets: [.init(stashedTabID: stashed.id, tabID: stashed.tab.id)]
        )

        let archivedPreflightCount = await preflightRecorder.count(for: .deleteStashed)
        XCTAssertEqual(archivedPreflightCount, 0)
        XCTAssertTrue(report.rejections.contains(where: { $0.kind == .close }))
        XCTAssertTrue(fixture.prompt.currentComposeTabs.contains(where: { $0.id == activeTabID }))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashed.id }))
    }

    func testArchivedDeleteReportPreservesActiveMutationWhenContextExpiresBeforeArchivedPreflight() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let activeTabID = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.first?.id)
        let stashed = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        fixture.prompt.stashedTabCascadeResolver = { _ in
            PromptViewModel.AgentSessionCascadePlan(composeTabIDs: [activeTabID])
        }
        fixture.prompt.agentSessionCascadeSnapshotResolver = { _, _, _ in
            PromptViewModel.AgentSessionCascadePlan(composeTabIDs: [activeTabID])
        }
        let context = MutationContextFlag()
        let didRemoveToken = fixture.prompt.addComposeTabsDidRemoveListener { _, _, _ in
            context.isCurrent = false
            return []
        }
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }

        let report = await fixture.prompt.deleteComposeAndStashedTabs(
            composeTabIDs: [],
            archivedTargets: [.init(stashedTabID: stashed.id, tabID: stashed.tab.id)],
            isMutationContextCurrent: { context.isCurrent }
        )

        XCTAssertEqual(report.removedComposeTabIDs, [activeTabID])
        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == stashed.id }))
    }

    func testArchivedDeleteRejectsMissingTargetWithoutPartialMutation() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let target = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)

        let report = await fixture.prompt.deleteStashedTabs(withIDs: [target.id, UUID()])

        XCTAssertTrue(report.rejections.contains(where: { $0.reason == .mutationContextChanged }))
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == target.id }))
    }

    func testArchivedDeletePreservesConcurrentUnrelatedStashedMutation() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let target = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs.first)
        let unrelated = StashedTab(tab: ComposeTabState(id: UUID(), name: "Concurrent archive"))
        let gate = ComposeRemovalPreflightGate()
        let preflightToken = fixture.prompt.setComposeTabsRemovalPreflight { _, reason, _ in
            if reason == .deleteStashed {
                await gate.markStartedAndWaitForRelease()
            }
            return .proceed
        }
        defer { fixture.prompt.removeComposeTabsRemovalPreflight(preflightToken) }

        let deleteTask = Task { await fixture.prompt.deleteStashedTabs(withIDs: [target.id]) }
        let preflightStarted = await gate.waitUntilStarted()
        XCTAssertTrue(preflightStarted)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let workspaceIndex = try XCTUnwrap(fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID }))
        fixture.manager.workspaces[workspaceIndex].stashedTabs.append(unrelated)
        await gate.release()
        let report = await deleteTask.value

        XCTAssertEqual(report.removedStashedTabIDs, [target.id])
        XCTAssertTrue(report.rejections.isEmpty)
        XCTAssertTrue(fixture.prompt.currentStashedTabs.contains(where: { $0.id == unrelated.id }))
    }

    func testArchivedOnlyWorkspaceUnavailableUsesArchivedRejection() async {
        let fixture = makeFixture(initialTabCount: 2)
        fixture.manager.activeWorkspace = nil

        let report = await fixture.prompt.deleteStashedTabs(withIDs: [UUID()])

        XCTAssertEqual(report.rejections.map(\.kind), [.deleteStashed])
    }

    func testBulkActionRejectsTargetsCapturedFromPreviousWorkspace() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let sourceWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tabID = try XCTUnwrap(sourceWorkspace.composeTabs.dropFirst().first?.id)
        let destinationWorkspace = WorkspaceModel(
            name: "Destination",
            repoPaths: sourceWorkspace.repoPaths,
            ephemeralFlag: true,
            composeTabs: sourceWorkspace.composeTabs,
            activeComposeTabID: sourceWorkspace.activeComposeTabID,
            stashedTabs: sourceWorkspace.stashedTabs
        )
        fixture.manager.workspaces.append(destinationWorkspace)
        fixture.manager.activeWorkspace = destinationWorkspace
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: sourceWorkspace.id,
            activeDeleteTabIDs: [tabID],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [tabID],
            unpinTabIDs: []
        )

        await viewModel.performSidebarBulkAction(
            .pin,
            origin: .command,
            commandProgressPlacement: .row,
            targets: targets,
            promptManager: fixture.prompt
        )

        XCTAssertFalse(fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id == tabID })?.isPinned == true)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)
    }

    func testBulkNoticeReportsCleanupFailureAndRejectedGroup() {
        let fixture = makeFixture(initialTabCount: 2)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let tabID = UUID()
        let report = PromptViewModel.ComposeTabMutationReport(
            removedComposeTabIDs: [tabID],
            rejections: [.init(
                kind: .deleteStashed,
                reason: .requiredSessionPreflight,
                tabID: UUID(),
                message: "Required persistence failed."
            )],
            cleanupIssues: [.init(tabID: tabID, reason: .close, message: "Cleanup failed.")]
        )

        let selectionNotice = viewModel.sidebarBulkActionNotice(
            for: report,
            action: .delete,
            origin: .selection
        )
        let commandNotice = viewModel.sidebarBulkActionNotice(
            for: report,
            action: .delete,
            origin: .command
        )

        XCTAssertEqual(selectionNotice, .init(
            severity: .error,
            title: "Bulk action partially completed",
            message: "Some chats changed, cleanup failed for 1 chat(s), and some selected or related chats were not changed. Cleanup failed."
        ))
        XCTAssertEqual(commandNotice, .init(
            severity: .error,
            title: "Action partially completed",
            message: "Some chats changed, cleanup failed for 1 chat(s), and some requested or related chats were not changed. Cleanup failed."
        ))
    }

    func testBulkNoticeUsesOriginAwarePartialAndNoOpWording() {
        let fixture = makeFixture(initialTabCount: 2)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let tabID = UUID()
        let partialReport = PromptViewModel.ComposeTabMutationReport(
            removedComposeTabIDs: [tabID],
            rejections: [.init(
                kind: .close,
                reason: .requiredSessionPreflight,
                tabID: UUID(),
                message: "Required persistence failed."
            )]
        )
        let noOpReport = PromptViewModel.ComposeTabMutationReport(noOpReasons: [.close])

        let selectionPartial = viewModel.sidebarBulkActionNotice(
            for: partialReport,
            action: .delete,
            origin: .selection
        )
        let commandPartial = viewModel.sidebarBulkActionNotice(
            for: partialReport,
            action: .delete,
            origin: .command
        )
        let selectionNoOp = viewModel.sidebarBulkActionNotice(
            for: noOpReport,
            action: .delete,
            origin: .selection
        )
        let commandNoOp = viewModel.sidebarBulkActionNotice(
            for: noOpReport,
            action: .delete,
            origin: .command
        )

        XCTAssertEqual(selectionPartial, .init(
            severity: .warning,
            title: "Bulk action partially completed",
            message: "Some chats changed, but some selected or related chats were rejected before mutation."
        ))
        XCTAssertEqual(commandPartial, .init(
            severity: .warning,
            title: "Action partially completed",
            message: "Some chats changed, but some requested or related chats were rejected before mutation."
        ))
        XCTAssertEqual(selectionNoOp?.message, "The selected chats no longer matched the delete action.")
        XCTAssertEqual(commandNoOp?.message, "The requested chats no longer matched the delete action.")
        XCTAssertFalse(commandPartial?.title.contains("Bulk") == true)
        XCTAssertFalse(commandPartial?.message.contains("selected") == true)
        XCTAssertFalse(commandNoOp?.message.contains("selected") == true)
    }

    func testPinContextRejectionNoticeUsesOriginWording() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let missingTabID = UUID()
        let pinTargets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [missingTabID],
            unpinTabIDs: []
        )

        await viewModel.performSidebarBulkAction(
            .pin,
            origin: .command,
            commandProgressPlacement: .row,
            targets: pinTargets,
            promptManager: fixture.prompt
        )

        XCTAssertEqual(viewModel.ui.sessionSidebar.selectionState.notice, .init(
            severity: .warning,
            title: "Chats were not pinned",
            message: "The workspace or requested chats changed before the action could be applied."
        ))

        viewModel.ui.sessionSidebar.dismissBulkActionNotice()
        viewModel.ui.sessionSidebar.selectAll(
            renderedOrder: [.active(tabID: missingTabID)],
            workspaceID: workspaceID
        )
        let unpinTargets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [],
            unpinTabIDs: [missingTabID]
        )

        await viewModel.performSidebarBulkAction(
            .unpin,
            origin: .selection,
            commandProgressPlacement: nil,
            targets: unpinTargets,
            promptManager: fixture.prompt
        )

        XCTAssertEqual(viewModel.ui.sessionSidebar.selectionState.notice, .init(
            severity: .warning,
            title: "Chats were not unpinned",
            message: "The workspace or selected chats changed before the action could be applied."
        ))
    }

    func testCommandCoordinatorGuardAndDirectCommandPredicateUseLiveSelectionState() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspace?.id)
        let tabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: { !$0.isPinned })?.id
        )
        let identity = AgentSidebarSelectionIdentity.active(tabID: tabID)
        let targets = AgentModeViewModel.SidebarBulkMutationTargets(
            workspaceID: workspaceID,
            activeDeleteTabIDs: [],
            archivedDeleteTargets: [],
            stashTabIDs: [],
            pinTabIDs: [tabID],
            unpinTabIDs: []
        )

        XCTAssertTrue(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: UUID()))

        viewModel.ui.sessionSidebar.selectAll(renderedOrder: [identity], workspaceID: workspaceID)
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))

        await viewModel.performSidebarBulkAction(
            .pin,
            origin: .command,
            commandProgressPlacement: .row,
            targets: targets,
            promptManager: fixture.prompt
        )

        XCTAssertFalse(fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id == tabID })?.isPinned == true)
        XCTAssertNil(viewModel.ui.sessionSidebar.selectionState.inFlightAction)

        viewModel.ui.sessionSidebar.clearSelection()
        let token = try XCTUnwrap(viewModel.ui.sessionSidebar.beginBulkAction(
            kind: .delete,
            origin: .command,
            presentationTargets: [identity],
            commandProgressPlacement: .row,
            workspaceID: workspaceID
        ))
        XCTAssertFalse(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))
        viewModel.ui.sessionSidebar.finishBulkAction(token: token, workspaceID: workspaceID, notice: nil)
        XCTAssertTrue(viewModel.canPerformDirectSidebarCommand(workspaceID: workspaceID))
    }

    func testPostRemovalClearsOnlyRemovedTabTranscriptRefreshSignature() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let removedTabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        let retainedTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id != removedTabID })?.id
        )
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        _ = viewModel.session(for: removedTabID)

        AgentTranscriptDebugInstrumentation.reset()
        defer { AgentTranscriptDebugInstrumentation.reset() }
        var attempts: [AgentTranscriptRefreshAttemptMetrics] = []
        AgentTranscriptDebugInstrumentation.configure(.init(
            refreshAttemptHandler: { attempts.append($0) }
        ))

        emitTranscriptRefreshAttempt(tabID: removedTabID, inputSignature: "removed-signature")
        emitTranscriptRefreshAttempt(tabID: retainedTabID, inputSignature: "retained-signature")

        let didRemoveToken = installDidRemoveListener(prompt: fixture.prompt, viewModel: viewModel)
        defer { fixture.prompt.removeComposeTabsDidRemoveListener(didRemoveToken) }
        await fixture.prompt.stashTab(removedTabID)

        attempts.removeAll()
        emitTranscriptRefreshAttempt(tabID: removedTabID, inputSignature: "removed-signature")
        emitTranscriptRefreshAttempt(tabID: retainedTabID, inputSignature: "retained-signature")

        XCTAssertEqual(attempts.count, 2)
        XCTAssertNil(attempts[0].previousInputSignature)
        XCTAssertFalse(attempts[0].isConsecutiveDuplicateInput)
        XCTAssertEqual(attempts[1].previousInputSignature, "retained-signature")
        XCTAssertTrue(attempts[1].isConsecutiveDuplicateInput)
    }

    func testRejectedConcurrentAgentAdmissionsPreserveActiveLivePinnedSession() async throws {
        let fixture = makeFixture(initialTabCount: 2)
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        fixture.manager.setWorkspaceEphemeral(workspaceID, false)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        fixture.prompt.setComposeTabPinned(true, for: tabID)
        let sessionID = try XCTUnwrap(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tabID)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: sessionID, on: session)
        session.runState = .running
        viewModel.setAgentRunActive(tabID, isActive: true)
        fixture.manager.setWorkspacePersistenceOutcomeOverrideForTesting(
            .rejected(reason: "workspace_not_writable")
        )
        defer { fixture.manager.setWorkspacePersistenceOutcomeOverrideForTesting(nil) }

        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabs = originalWorkspace.composeTabs
        let originalStashedTabs = originalWorkspace.stashedTabs

        let first = Task { @MainActor in
            await self.admissionWasRejected(viewModel)
        }
        let second = Task { @MainActor in
            await self.admissionWasRejected(viewModel)
        }
        let rejections = await [first.value, second.value]

        XCTAssertEqual(rejections, [true, true])
        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.id), originalTabs.map(\.id))
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.name), originalTabs.map(\.name))
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.isPinned), originalTabs.map(\.isPinned))
        XCTAssertEqual(
            finalWorkspace.composeTabs.map(\.activeAgentSessionID),
            originalTabs.map(\.activeAgentSessionID)
        )
        XCTAssertEqual(finalWorkspace.stashedTabs, originalStashedTabs)
        XCTAssertEqual(finalWorkspace.activeComposeTabID, tabID)
        XCTAssertEqual(fixture.prompt.activeComposeTabID, tabID)
        XCTAssertTrue(fixture.prompt.currentComposeTabs.contains(where: {
            $0.id == tabID && $0.isPinned && $0.activeAgentSessionID == sessionID
        }))
        XCTAssertTrue(viewModel.sessions[tabID] === session)
        XCTAssertEqual(session.activeAgentSessionID, sessionID)
        XCTAssertEqual(session.runState, .running)
        XCTAssertEqual(Set(viewModel.sessions.keys), Set([tabID]))
    }

    func testDurableBackgroundAdmissionCommitsExactlyOneTabWithoutForegroundMutation() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-Commit-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 3,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer { fixture.manager.prepareForWindowClose() }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let sessionID = UUID()

        let result = try await fixture.prompt.createDurableBackgroundAgentSessionTab(
            name: "Atomic background",
            sessionID: sessionID,
            expectedWorkspaceID: workspaceID,
            lifecycleAuthority: AgentSessionLifecycleAuthority()
        )

        guard case let .created(createdTab, receipt, recoveryClaim) = result else {
            return XCTFail("Expected the background admission to commit: \(result)")
        }
        guard case let .persisted(persistedWorkspaceID, _) = receipt.outcome else {
            return XCTFail("Expected durable persistence: \(receipt.outcome)")
        }
        XCTAssertEqual(persistedWorkspaceID, workspaceID)
        guard case .saved = receipt.commitEvidence else {
            return XCTFail("Expected saved commit evidence: \(receipt.commitEvidence)")
        }
        XCTAssertEqual(recoveryClaim.state, .provisional)
        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.count, originalWorkspace.composeTabs.count + 1)
        let retainedTabs = Array(finalWorkspace.composeTabs.dropLast())
        XCTAssertEqual(retainedTabs.map(\.id), originalWorkspace.composeTabs.map(\.id))
        XCTAssertEqual(retainedTabs.map(\.isPinned), originalWorkspace.composeTabs.map(\.isPinned))
        XCTAssertEqual(
            retainedTabs.map(\.activeAgentSessionID),
            originalWorkspace.composeTabs.map(\.activeAgentSessionID)
        )
        XCTAssertEqual(finalWorkspace.composeTabs.last?.id, createdTab.id)
        XCTAssertEqual(finalWorkspace.composeTabs.last?.activeAgentSessionID, sessionID)
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalWorkspace.activeComposeTabID)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalWorkspace.stashedTabs)
        XCTAssertEqual(fixture.prompt.activeComposeTabID, originalWorkspace.activeComposeTabID)
        let savedWorkspace = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
            at: fixture.manager.workspaceFileURL(for: finalWorkspace),
            scheduleNormalizationWriteback: false
        )
        XCTAssertTrue(savedWorkspace.composeTabs.contains(where: {
            $0.id == createdTab.id && $0.activeAgentSessionID == sessionID
        }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testQueuedDurableBackgroundAdmissionRejectsWorkspaceDriftBeforeMutation() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let fixture = makeFixture(initialTabCount: 2, coordinator: coordinator)
        let expectedWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalExpectedTabs = expectedWorkspace.composeTabs
        let sessionID = UUID()
        let holder = try await coordinator.acquire(
            workspaceID: expectedWorkspace.id,
            admissionID: UUID()
        )
        defer { holder.release() }
        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }

        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Must not appear",
                sessionID: sessionID,
                expectedWorkspaceID: expectedWorkspace.id,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await queuedSignal.wait()

        let destinationTab = ComposeTabState(name: "Destination")
        let destination = WorkspaceModel(
            name: "Destination",
            repoPaths: [],
            ephemeralFlag: true,
            composeTabs: [destinationTab],
            activeComposeTabID: destinationTab.id
        )
        fixture.manager.workspaces.append(destination)
        fixture.manager.activeWorkspace = destination
        fixture.prompt.loadComposeTabsFromWorkspace(destination)
        holder.release()

        let result = try await admissionTask.value
        XCTAssertEqual(result, .rejected(
            AgentAdmissionPersistenceReceipt(
                outcome: .rejected(reason: "workspace_changed"),
                commitEvidence: .none
            ),
            .workspaceChanged
        ))
        XCTAssertEqual(
            fixture.manager.workspaces.first(where: { $0.id == expectedWorkspace.id })?.composeTabs,
            originalExpectedTabs
        )
        XCTAssertFalse(fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == sessionID
        }))
        XCTAssertEqual(fixture.manager.activeWorkspaceID, destination.id)
        XCTAssertEqual(fixture.prompt.currentComposeTabs, [destinationTab])
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancelledDurableBackgroundAdmissionRollsBackBeforeNextLeaseHolder() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-Cancelled-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabIDs = originalWorkspace.composeTabs.map(\.id)
        let originalPins = originalWorkspace.composeTabs.map(\.isPinned)
        let originalBindings = originalWorkspace.composeTabs.map(\.activeAgentSessionID)
        let originalActiveTabID = originalWorkspace.activeComposeTabID
        let originalStashedTabs = originalWorkspace.stashedTabs
        let sessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }

        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Cancelled provisional",
                sessionID: sessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                guard let workspace = fixture.manager.activeWorkspace else { return false }
                return workspace.composeTabs.map(\.id) == originalTabIDs
                    && workspace.composeTabs.map(\.isPinned) == originalPins
                    && workspace.composeTabs.map(\.activeAgentSessionID) == originalBindings
                    && workspace.activeComposeTabID == originalActiveTabID
                    && workspace.stashedTabs == originalStashedTabs
                    && !fixture.prompt.currentComposeTabs.contains(where: {
                        $0.activeAgentSessionID == sessionID
                    })
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must propagate without a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedRollback = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedRollback)
        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.isPinned), originalPins)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.activeAgentSessionID), originalBindings)
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalActiveTabID)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalStashedTabs)
        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains(where: {
            $0.activeAgentSessionID == sessionID
        }))
        XCTAssertFalse(try FileManager.default.fileExists(
            atPath: fixture.manager.workspaceFileURL(
                for: XCTUnwrap(fixture.manager.activeWorkspace)
            ).path
        ))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationAfterSavedAdmissionRecoversBeforeReturningWithoutStaleRepublish() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-PostSaveCancellation-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.prompt.setAgentAdmissionPersistenceReceiptHandlerForTesting(nil)
            fixture.prompt.setAgentAdmissionRecoveryCompletedHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalTabIDs = originalWorkspace.composeTabs.map(\.id)
        let originalBindings = originalWorkspace.composeTabs.map(\.activeAgentSessionID)
        let sessionID = UUID()
        let receiptGate = AdmissionAsyncGate()
        var recoveryOutcome: AgentAdmissionRecoveryOutcome?
        fixture.prompt.setAgentAdmissionPersistenceReceiptHandlerForTesting { identity, receipt in
            XCTAssertEqual(identity.workspaceID, workspaceID)
            XCTAssertEqual(identity.sessionID, sessionID)
            guard case .saved = receipt.commitEvidence else {
                XCTFail("Cancellation gate requires saved evidence: \(receipt.commitEvidence)")
                return
            }
            await receiptGate.enterAndWait()
        }
        fixture.prompt.setAgentAdmissionRecoveryCompletedHandlerForTesting { identity, outcome in
            XCTAssertEqual(identity.workspaceID, workspaceID)
            recoveryOutcome = outcome
        }

        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Saved then cancelled",
                sessionID: sessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await receiptGate.waitUntilEntered()
        let workspaceAtCommit = try XCTUnwrap(fixture.manager.activeWorkspace)
        let versionAtCommit = fixture.manager.debugStateVersionForWorkspace(workspaceID)
        let savedAtCommit = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
            at: fixture.manager.workspaceFileURL(for: workspaceAtCommit),
            scheduleNormalizationWriteback: false
        )
        XCTAssertTrue(savedAtCommit.composeTabs.contains {
            $0.activeAgentSessionID == sessionID
        })

        admissionTask.cancel()
        await receiptGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        switch recoveryOutcome {
        case .recovered, .alreadyRecovered:
            break
        default:
            XCTFail("Saved cancellation must settle exact recovery: \(String(describing: recoveryOutcome))")
        }
        let recoveredWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(recoveredWorkspace.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(recoveredWorkspace.composeTabs.map(\.activeAgentSessionID), originalBindings)
        XCTAssertEqual(
            fixture.manager.debugStateVersionForWorkspace(workspaceID),
            versionAtCommit,
            "The idempotent local rollback must not dirty recovered state."
        )
        XCTAssertFalse(fixture.prompt.currentComposeTabs.contains {
            $0.activeAgentSessionID == sessionID
        })
        let savedAfterRecovery = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
            at: fixture.manager.workspaceFileURL(for: recoveredWorkspace),
            scheduleNormalizationWriteback: false
        )
        XCTAssertEqual(savedAfterRecovery.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(savedAfterRecovery.composeTabs.map(\.activeAgentSessionID), originalBindings)
        let postRecoveryPersistence = await fixture.manager.pollAndSaveStateWithOutcomeAsync(
            workspaceID: workspaceID
        )
        XCTAssertEqual(
            postRecoveryPersistence,
            .notRequired(workspaceID: workspaceID),
            "Recovery must leave no dirty stale projection for a later save to republish."
        )
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testExplicitTabAdmissionCommitsRuntimeAndDurableBindingAtomically() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-ExplicitCommit-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer { fixture.manager.prepareForWindowClose() }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tab = try XCTUnwrap(originalWorkspace.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        try fixture.prompt.loadComposeTabsFromWorkspace(
            XCTUnwrap(fixture.manager.activeWorkspace)
        )
        let viewModel = makeAgentModeViewModel(
            prompt: fixture.prompt,
            manager: fixture.manager
        )

        let target = try await viewModel.mcpResolveOrCreateSessionTarget(
            tabID: tab.id,
            sessionID: nil,
            createIfNeeded: true,
            sessionName: nil
        )

        let sessionID = try XCTUnwrap(target.sessionID)
        XCTAssertEqual(target.tabID, tab.id)
        XCTAssertEqual(fixture.manager.activeAgentSessionID(
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ), sessionID)
        XCTAssertEqual(viewModel.session(for: tab.id, createIfNeeded: false)?.activeAgentSessionID, sessionID)
        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.id), originalWorkspace.composeTabs.map(\.id))
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.isPinned), originalWorkspace.composeTabs.map(\.isPinned))
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalWorkspace.activeComposeTabID)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalWorkspace.stashedTabs)
        let savedWorkspace = try WorkspaceManagerViewModel.loadWorkspaceFromFile(
            at: fixture.manager.workspaceFileURL(for: finalWorkspace),
            scheduleNormalizationWriteback: false
        )
        XCTAssertEqual(
            savedWorkspace.composeTabs.first(where: { $0.id == tab.id })?.activeAgentSessionID,
            sessionID
        )
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testExplicitTabAdmissionRollsBackWrongWorkspaceDecisionBeforeLeaseRelease() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tab = try XCTUnwrap(originalWorkspace.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        try fixture.prompt.loadComposeTabsFromWorkspace(
            XCTUnwrap(fixture.manager.activeWorkspace)
        )
        let viewModel = makeAgentModeViewModel(
            prompt: fixture.prompt,
            manager: fixture.manager
        )
        fixture.manager.setWorkspacePersistenceOutcomeOverrideForTesting(
            .notRequired(workspaceID: UUID())
        )
        defer { fixture.manager.setWorkspacePersistenceOutcomeOverrideForTesting(nil) }

        do {
            _ = try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: tab.id,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: nil
            )
            XCTFail("A persistence outcome for another workspace must reject admission.")
        } catch {}

        XCTAssertNil(fixture.manager.activeAgentSessionID(
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        XCTAssertNil(viewModel.session(for: tab.id, createIfNeeded: false)?.activeAgentSessionID)
        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.id), originalWorkspace.composeTabs.map(\.id))
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.isPinned), originalWorkspace.composeTabs.map(\.isPinned))
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalWorkspace.activeComposeTabID)
        XCTAssertEqual(finalWorkspace.stashedTabs, originalWorkspace.stashedTabs)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testQueuedExplicitTabAdmissionRejectsWorkspaceDriftBeforeBinding() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let fixture = makeFixture(initialTabCount: 2, coordinator: coordinator)
        let expectedWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tab = try XCTUnwrap(expectedWorkspace.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: expectedWorkspace.id
        ))
        try fixture.prompt.loadComposeTabsFromWorkspace(
            XCTUnwrap(fixture.manager.activeWorkspace)
        )
        let viewModel = makeAgentModeViewModel(
            prompt: fixture.prompt,
            manager: fixture.manager
        )
        let holder = try await coordinator.acquire(
            workspaceID: expectedWorkspace.id,
            admissionID: UUID()
        )
        defer { holder.release() }
        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }

        let admissionTask = Task { @MainActor in
            do {
                _ = try await viewModel.mcpResolveOrCreateSessionTarget(
                    tabID: tab.id,
                    sessionID: nil,
                    createIfNeeded: true,
                    sessionName: nil
                )
                return false
            } catch {
                return true
            }
        }
        await queuedSignal.wait()

        let destinationTab = ComposeTabState(name: "Destination")
        let destination = WorkspaceModel(
            name: "Destination",
            repoPaths: [],
            ephemeralFlag: true,
            composeTabs: [destinationTab],
            activeComposeTabID: destinationTab.id
        )
        fixture.manager.workspaces.append(destination)
        fixture.manager.activeWorkspace = destination
        fixture.prompt.loadComposeTabsFromWorkspace(destination)
        holder.release()

        let admissionWasRejected = await admissionTask.value
        XCTAssertTrue(admissionWasRejected)
        XCTAssertNil(fixture.manager.activeAgentSessionID(
            forTabID: tab.id,
            inWorkspaceID: expectedWorkspace.id
        ))
        XCTAssertNil(viewModel.session(for: tab.id, createIfNeeded: false)?.activeAgentSessionID)
        XCTAssertEqual(fixture.manager.activeWorkspaceID, destination.id)
        XCTAssertEqual(fixture.prompt.currentComposeTabs, [destinationTab])
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancelledExplicitTabAdmissionRollsBackBeforeNextLeaseHolder() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-ExplicitCancelled-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let tab = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        try fixture.prompt.loadComposeTabsFromWorkspace(
            XCTUnwrap(fixture.manager.activeWorkspace)
        )
        let viewModel = makeAgentModeViewModel(
            prompt: fixture.prompt,
            manager: fixture.manager
        )
        let session = viewModel.session(for: tab.id)
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }

        let admissionTask = Task { @MainActor in
            try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: tab.id,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: nil
            )
        }
        await saveGate.waitUntilEntered()
        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                fixture.manager.activeAgentSessionID(
                    forTabID: tab.id,
                    inWorkspaceID: workspaceID
                ) == nil && session.activeAgentSessionID == nil
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return an explicit provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        let nextHolderObservedRollback = try await stateObservedByNextHolder.value

        XCTAssertTrue(nextHolderObservedRollback)
        XCTAssertNil(fixture.manager.activeAgentSessionID(
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        XCTAssertNil(session.activeAgentSessionID)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testAlreadyBoundExplicitTabRevalidatesWorkspaceAfterSessionPreparation() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let fixture = makeFixture(initialTabCount: 2, coordinator: coordinator)
        let expectedWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tab = try XCTUnwrap(expectedWorkspace.composeTabs.last)
        let sessionID = try XCTUnwrap(tab.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tab.id)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: sessionID, on: session)
        let preparationFence = TestReleaseFence(name: "explicit tab session preparation")
        viewModel.test_setAfterExplicitTabSessionReady {
            await preparationFence.enterAndWaitIgnoringCancellationUntilRelease()
        }
        defer {
            viewModel.test_setAfterExplicitTabSessionReady(nil)
            preparationFence.release()
        }

        let admissionTask = Task { @MainActor in
            try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: tab.id,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: nil
            )
        }
        let preparationDidSuspend = await preparationFence.waitUntilEntered()
        XCTAssertTrue(preparationDidSuspend)

        let sourceIndex = try XCTUnwrap(
            fixture.manager.workspaces.firstIndex(where: { $0.id == expectedWorkspace.id })
        )
        fixture.manager.workspaces[sourceIndex].composeTabs.removeAll { $0.id == tab.id }
        let destination = WorkspaceModel(
            name: "Destination",
            repoPaths: [],
            ephemeralFlag: true,
            composeTabs: [tab],
            activeComposeTabID: tab.id
        )
        fixture.manager.workspaces.append(destination)
        preparationFence.release()

        do {
            _ = try await admissionTask.value
            XCTFail("Workspace drift must not publish an already-bound target.")
        } catch is CancellationError {
            XCTFail("Workspace drift is not cancellation.")
        } catch {}
        XCTAssertEqual(session.activeAgentSessionID, sessionID)
        XCTAssertEqual(
            fixture.manager.activeAgentSessionID(forTabID: tab.id, inWorkspaceID: destination.id),
            sessionID
        )
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testExplicitBindingRejectionPreservesNewerRuntimeAndWorkspaceIdentity() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-ExplicitIdentityFence-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let tab = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: workspaceID
        ))
        try fixture.prompt.loadComposeTabsFromWorkspace(XCTUnwrap(fixture.manager.activeWorkspace))
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tab.id)
        let replacementSessionID = UUID()
        let replacementClaim = OneShotAdmissionClaim()
        let events = AdmissionLifecycleEventRecorder()
        AgentSessionLifecycleAuthority.setEventObserverForTesting { events.record($0) }
        defer { AgentSessionLifecycleAuthority.setEventObserverForTesting(nil) }
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            guard await replacementClaim.claim() else { return }
            await MainActor.run {
                _ = viewModel.test_installPersistentSessionBinding(
                    sessionID: replacementSessionID,
                    on: session,
                    compareAndSetInWorkspaceID: workspaceID
                )
            }
        }

        do {
            _ = try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: tab.id,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: nil
            )
            XCTFail("A replaced provisional identity must reject without returning a target.")
        } catch is CancellationError {
            XCTFail("Identity replacement is not cancellation.")
        } catch {}

        XCTAssertEqual(session.activeAgentSessionID, replacementSessionID)
        XCTAssertEqual(session.persistentSessionBindingIdentity?.sessionID, replacementSessionID)
        XCTAssertEqual(
            fixture.manager.activeAgentSessionID(forTabID: tab.id, inWorkspaceID: workspaceID),
            replacementSessionID
        )
        XCTAssertTrue(events.snapshot().contains(where: {
            $0.decision == .rejected
                && $0.reason == AgentSessionLifecycleAuthority.RejectionReason.sessionIdentityChanged.rawValue
        }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testBackgroundPersistedStaleBindingPreservesTypedRollbackReason() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-TypedRollback-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let sessionID = UUID()
        let replacementSessionID = UUID()
        let replacementClaim = OneShotAdmissionClaim()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            guard await replacementClaim.claim() else { return }
            await MainActor.run {
                guard let tabID = fixture.manager.workspaces
                    .first(where: { $0.id == workspaceID })?
                    .composeTabs.first(where: { $0.activeAgentSessionID == sessionID })?.id
                else {
                    XCTFail("Expected the provisional background binding.")
                    return
                }
                XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
                    expected: sessionID,
                    replacement: replacementSessionID,
                    forTabID: tabID,
                    inWorkspaceID: workspaceID
                ))
            }
        }

        let result = try await fixture.prompt.createDurableBackgroundAgentSessionTab(
            name: "Typed stale binding",
            sessionID: sessionID,
            expectedWorkspaceID: workspaceID,
            lifecycleAuthority: AgentSessionLifecycleAuthority()
        )

        guard case let .rejected(receipt, reason) = result else {
            return XCTFail("A stale persisted binding must reject: \(result)")
        }
        guard case let .persisted(persistedWorkspaceID, _) = receipt.outcome else {
            return XCTFail("Expected the stale outcome to have persisted: \(receipt.outcome)")
        }
        XCTAssertEqual(persistedWorkspaceID, workspaceID)
        XCTAssertEqual(reason, .sessionIdentityChanged)
        XCTAssertFalse(fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == sessionID
        }))
        XCTAssertTrue(fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == replacementSessionID
        }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancelledBackgroundAdmissionRestoresForegroundSelectedDuringPersistence() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-ForegroundRollback-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 3,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let originalActiveTabID = try XCTUnwrap(originalWorkspace.activeComposeTabID)
        let sessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }

        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Selected while pending",
                sessionID: sessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == sessionID
            })?.id
        )
        await fixture.prompt.switchComposeTab(provisionalTabID)
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let finalWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.id), originalWorkspace.composeTabs.map(\.id))
        XCTAssertEqual(finalWorkspace.composeTabs.map(\.isPinned), originalWorkspace.composeTabs.map(\.isPinned))
        XCTAssertEqual(finalWorkspace.stashedTabs, originalWorkspace.stashedTabs)
        XCTAssertEqual(finalWorkspace.activeComposeTabID, originalActiveTabID)
        XCTAssertEqual(fixture.prompt.activeComposeTabID, originalActiveTabID)
        XCTAssertFalse(finalWorkspace.composeTabs.contains(where: { $0.id == provisionalTabID }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationAfterCompletedProvisionalActivationRestoresNonblankLiveContextBeforeLeaseRelease() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-CompletedActivation-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let foregroundTab = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalTabIDs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.id))
        let originalPins = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.isPinned))
        let originalStashedTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Completed provisional activation",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == provisionalSessionID
            })?.id
        )

        await fixture.prompt.switchComposeTab(provisionalTabID)
        XCTAssertEqual(fixture.prompt.promptText, "")
        XCTAssertTrue(fixture.manager.fileManager.snapshotSelection().selectedPaths.isEmpty)
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.nonblankForegroundContextMatches(
                    fixture: fixture,
                    expectedTab: foregroundTab,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedRestoredContext = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedRestoredContext)
        XCTAssertTrue(nonblankForegroundContextMatches(
            fixture: fixture,
            expectedTab: foregroundTab,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.isPinned), originalPins)
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationWhileProvisionalActivationSuspendedRestoresNonblankLiveContextBeforeLeaseRelease() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-SuspendedActivation-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setComposeTabFastStateDidApplyHandlerForTesting(nil)
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let foregroundTab = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalTabIDs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.id))
        let originalPins = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.isPinned))
        let originalStashedTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        let activationGate = TestReleaseFence(name: "provisional compose activation")
        let activationCancellationSignal = BoundedTestSignal(name: "provisional activation cancellation")
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        fixture.manager.setComposeTabFastStateDidApplyHandlerForTesting { tabID in
            guard fixture.manager.activeAgentSessionID(
                forTabID: tabID,
                inWorkspaceID: workspaceID
            ) == provisionalSessionID else { return }
            await withTaskCancellationHandler {
                await activationGate.enterAndWaitIgnoringCancellationUntilRelease()
            } onCancel: {
                activationCancellationSignal.signal()
            }
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Suspended provisional activation",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == provisionalSessionID
            })?.id
        )
        let activationTask = Task { @MainActor in
            await fixture.prompt.switchComposeTab(provisionalTabID)
        }
        let activationDidSuspend = await activationGate.waitUntilEntered()
        XCTAssertTrue(activationDidSuspend)
        XCTAssertEqual(fixture.prompt.promptText, "")
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.nonblankForegroundContextMatches(
                    fixture: fixture,
                    expectedTab: foregroundTab,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        await activationCancellationSignal.wait()
        activationGate.release()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        await activationTask.value

        let nextHolderObservedRestoredContext = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedRestoredContext)
        XCTAssertTrue(nonblankForegroundContextMatches(
            fixture: fixture,
            expectedTab: foregroundTab,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.isPinned), originalPins)
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationWithoutSelectingProvisionalPreservesLatestStoredForegroundEdits() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-LatestStoredNoSwitch-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let originalForeground = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalTabIDs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.id))
        let originalStashedTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Never selected provisional",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let latestForeground = try await updateForegroundContextDuringAdmission(
            fixture: fixture,
            root: root,
            tabID: originalForeground.id,
            label: "NoSwitch"
        )
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, originalForeground.id)

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.nonblankForegroundContextMatches(
                    fixture: fixture,
                    expectedTab: latestForeground,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedLatestState = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedLatestState)
        XCTAssertTrue(nonblankForegroundContextMatches(
            fixture: fixture,
            expectedTab: latestForeground,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationAfterSelectingProvisionalRestoresLatestFlushedForegroundEdits() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-LatestStoredAfterSwitch-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let originalForeground = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalTabIDs = try XCTUnwrap(fixture.manager.activeWorkspace?.composeTabs.map(\.id))
        let originalStashedTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Selected after latest edits",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == provisionalSessionID
            })?.id
        )
        let latestForeground = try await updateForegroundContextDuringAdmission(
            fixture: fixture,
            root: root,
            tabID: originalForeground.id,
            label: "AfterSwitch"
        )
        await fixture.prompt.switchComposeTab(provisionalTabID)
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)
        XCTAssertEqual(fixture.prompt.promptText, "")

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.nonblankForegroundContextMatches(
                    fixture: fixture,
                    expectedTab: latestForeground,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedLatestState = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedLatestState)
        XCTAssertTrue(nonblankForegroundContextMatches(
            fixture: fixture,
            expectedTab: latestForeground,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), originalTabIDs)
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationAfterClosingPriorForegroundAppliesRemainingOpenFallbackBeforeLeaseRelease() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-ClosedPriorFallback-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let priorForeground = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let remainingTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id != priorForeground.id })?.id
        )
        await fixture.prompt.switchComposeTab(remainingTabID)
        let expectedFallback = try await updateForegroundContextDuringAdmission(
            fixture: fixture,
            root: root,
            tabID: remainingTabID,
            label: "ClosedPriorFallback"
        )
        await fixture.prompt.switchComposeTab(priorForeground.id)

        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let originalStashedTabs = try XCTUnwrap(fixture.manager.activeWorkspace?.stashedTabs)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Closed prior fallback",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == provisionalSessionID
            })?.id
        )
        await fixture.prompt.switchComposeTab(provisionalTabID)
        let closeReport = await fixture.prompt.closeComposeTab(priorForeground.id)
        XCTAssertEqual(closeReport.removedComposeTabIDs, [priorForeground.id])
        XCTAssertTrue(closeReport.rejections.isEmpty)
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.nonblankForegroundContextMatches(
                    fixture: fixture,
                    expectedTab: expectedFallback,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedFallback = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedFallback)
        XCTAssertTrue(nonblankForegroundContextMatches(
            fixture: fixture,
            expectedTab: expectedFallback,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(fixture.manager.activeWorkspace?.composeTabs.map(\.id), [remainingTabID])
        XCTAssertEqual(fixture.manager.activeWorkspace?.stashedTabs, originalStashedTabs)
        XCTAssertFalse(fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.id == priorForeground.id
        }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancellationAfterStashingOnlyPriorForegroundAppliesSingleBlankReplacementBeforeLeaseRelease() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-StashedPriorReplacement-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 1,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let priorForeground = try await configureNonblankForegroundContext(
            fixture: fixture,
            root: root
        )
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let provisionalSessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Stashed prior replacement",
                sessionID: provisionalSessionID,
                expectedWorkspaceID: workspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let provisionalTabID = try XCTUnwrap(
            fixture.manager.activeWorkspace?.composeTabs.first(where: {
                $0.activeAgentSessionID == provisionalSessionID
            })?.id
        )
        await fixture.prompt.switchComposeTab(provisionalTabID)
        let stashReport = await fixture.prompt.stashTab(priorForeground.id)
        XCTAssertEqual(stashReport.removedComposeTabIDs, [priorForeground.id])
        XCTAssertTrue(stashReport.rejections.isEmpty)
        XCTAssertTrue(fixture.manager.activeWorkspace?.stashedTabs.contains(where: {
            $0.tab.id == priorForeground.id
        }) == true)
        XCTAssertEqual(fixture.manager.activeWorkspace?.activeComposeTabID, provisionalTabID)

        let queuedSignal = AdmissionEventSignal(kind: .queued)
        coordinator.setEventObserverForTesting { queuedSignal.observe($0) }
        defer { coordinator.setEventObserverForTesting(nil) }
        let stateObservedByNextHolder = Task { @MainActor in
            try await fixture.manager.withAgentSessionAdmission(
                workspaceID: workspaceID,
                admissionID: UUID()
            ) {
                self.blankReplacementContextMatches(
                    fixture: fixture,
                    stashedPriorTabID: priorForeground.id,
                    rejectedSessionID: provisionalSessionID
                )
            }
        }
        await queuedSignal.wait()

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a provider-facing target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let nextHolderObservedReplacement = try await stateObservedByNextHolder.value
        XCTAssertTrue(nextHolderObservedReplacement)
        XCTAssertTrue(blankReplacementContextMatches(
            fixture: fixture,
            stashedPriorTabID: priorForeground.id,
            rejectedSessionID: provisionalSessionID
        ))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testCancelledBackgroundRollbackBumpsOnlyCapturedWorkspaceVersion() async throws {
        let coordinator = WorkspaceAgentAdmissionCoordinator()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BackgroundComposeTabAdmissionTests-TargetVersion-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = makeFixture(
            initialTabCount: 2,
            coordinator: coordinator,
            ephemeralFlag: false,
            customStoragePath: root
        )
        defer {
            fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting(nil)
            fixture.manager.prepareForWindowClose()
        }
        let expectedWorkspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let sessionID = UUID()
        let saveGate = AdmissionAsyncGate()
        fixture.manager.setWorkspaceSavePreparationDidFinishHandlerForTesting { _, _, _ in
            await saveGate.enterAndWait()
        }
        let admissionTask = Task { @MainActor in
            try await fixture.prompt.createDurableBackgroundAgentSessionTab(
                name: "Inactive rollback target",
                sessionID: sessionID,
                expectedWorkspaceID: expectedWorkspaceID,
                lifecycleAuthority: AgentSessionLifecycleAuthority()
            )
        }
        await saveGate.waitUntilEntered()
        let expectedVersionAfterAppend = fixture.manager.debugStateVersionForWorkspace(expectedWorkspaceID)

        let destinationTab = ComposeTabState(name: "Destination")
        let destination = WorkspaceModel(
            name: "Destination",
            repoPaths: [],
            ephemeralFlag: true,
            composeTabs: [destinationTab],
            activeComposeTabID: destinationTab.id
        )
        fixture.manager.workspaces.append(destination)
        fixture.manager.activeWorkspace = destination
        fixture.prompt.loadComposeTabsFromWorkspace(destination)
        let destinationVersion = fixture.manager.debugStateVersionForWorkspace(destination.id)

        admissionTask.cancel()
        await saveGate.open()
        do {
            _ = try await admissionTask.value
            XCTFail("Cancellation must not return a background target.")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(
            fixture.manager.debugStateVersionForWorkspace(expectedWorkspaceID),
            expectedVersionAfterAppend + 1
        )
        XCTAssertEqual(
            fixture.manager.debugStateVersionForWorkspace(destination.id),
            destinationVersion
        )
        XCTAssertEqual(fixture.manager.activeWorkspaceID, destination.id)
        XCTAssertEqual(fixture.prompt.currentComposeTabs, [destinationTab])
        XCTAssertFalse(fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == sessionID
        }))
        XCTAssertEqual(coordinator.snapshot(), .init(
            activeAdmissionCount: 0,
            waiterCount: 0,
            trackedWorkspaceCount: 0
        ))
    }

    func testWorkspaceScopedBindingCASBumpsOnlyTargetWorkspaceVersion() throws {
        let fixture = makeFixture(initialTabCount: 2)
        let sourceWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        let tab = try XCTUnwrap(sourceWorkspace.composeTabs.last)
        let originalSessionID = try XCTUnwrap(tab.activeAgentSessionID)
        let destinationTab = ComposeTabState(name: "Destination")
        let destination = WorkspaceModel(
            name: "Destination",
            repoPaths: [],
            ephemeralFlag: true,
            composeTabs: [destinationTab],
            activeComposeTabID: destinationTab.id
        )
        fixture.manager.workspaces.append(destination)
        fixture.manager.activeWorkspace = destination
        let sourceVersion = fixture.manager.debugStateVersionForWorkspace(sourceWorkspace.id)
        let destinationVersion = fixture.manager.debugStateVersionForWorkspace(destination.id)

        XCTAssertTrue(fixture.manager.compareAndSetActiveAgentSessionID(
            expected: originalSessionID,
            replacement: nil,
            forTabID: tab.id,
            inWorkspaceID: sourceWorkspace.id
        ))

        XCTAssertEqual(
            fixture.manager.debugStateVersionForWorkspace(sourceWorkspace.id),
            sourceVersion + 1
        )
        XCTAssertEqual(
            fixture.manager.debugStateVersionForWorkspace(destination.id),
            destinationVersion
        )
    }

    func testStaleProjectionCannotReplaceActiveLivePinnedSession() throws {
        let fixture = makeFixture(initialTabCount: 2)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        fixture.prompt.setComposeTabPinned(true, for: tabID)
        let sessionID = try XCTUnwrap(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tabID)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: sessionID, on: session)
        session.runState = .running
        viewModel.setAgentRunActive(tabID, isActive: true)

        let currentWorkspace = try XCTUnwrap(fixture.manager.activeWorkspace)
        var staleWorkspace = currentWorkspace
        var staleTab = try XCTUnwrap(currentWorkspace.composeTabs.first(where: { $0.id == tabID }))
        staleTab.name = "Stale replacement"
        staleTab.isPinned = false
        staleTab.activeAgentSessionID = UUID()
        staleWorkspace.composeTabs.removeAll { $0.id == tabID }
        staleWorkspace.activeComposeTabID = staleWorkspace.composeTabs.first?.id
        staleWorkspace.stashedTabs.append(StashedTab(
            tab: staleTab,
            stashedAt: Date()
        ))

        fixture.manager.applyDomainWorkspaceProjection(
            [staleWorkspace],
            fileURLsByWorkspaceID: [:],
            revisionsByWorkspaceID: [:],
            digestsByWorkspaceID: [:],
            healthByWorkspaceID: [:],
            catalogRevision: 1,
            preferredActiveWorkspaceID: currentWorkspace.id,
            publicationSequence: 1
        )

        let reconciled = try XCTUnwrap(fixture.manager.activeWorkspace)
        let protectedTab = try XCTUnwrap(reconciled.composeTabs.first(where: { $0.id == tabID }))
        XCTAssertTrue(protectedTab.isPinned)
        XCTAssertEqual(protectedTab.activeAgentSessionID, sessionID)
        XCTAssertEqual(protectedTab.name, currentWorkspace.composeTabs.first(where: { $0.id == tabID })?.name)
        XCTAssertEqual(reconciled.activeComposeTabID, tabID)
        XCTAssertFalse(reconciled.stashedTabs.contains(where: { $0.tab.id == tabID }))
        XCTAssertTrue(viewModel.sessions[tabID] === session)
        XCTAssertEqual(session.runState, .running)
    }

    func testLateTitleProviderAndInteractionAttemptsCannotCrossChangedSessionIdentity() async throws {
        let fixture = makeFixture(initialTabCount: 1)
        let tabID = try XCTUnwrap(fixture.prompt.activeComposeTabID)
        fixture.prompt.setComposeTabPinned(true, for: tabID)
        let originalSessionID = try XCTUnwrap(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID)
        let viewModel = makeAgentModeViewModel(prompt: fixture.prompt, manager: fixture.manager)
        let session = viewModel.session(for: tabID)
        _ = viewModel.test_installPersistentSessionBinding(sessionID: originalSessionID, on: session)
        let target = try viewModel.resolveAgentSessionLifecycleMutationTarget(
            tabID: tabID,
            expectedSessionID: originalSessionID,
            intent: .setStatus
        )
        let runTarget = AgentModeViewModel.MCPSessionTarget(
            tabID: tabID,
            sessionID: originalSessionID,
            origin: .existingSession,
            lifecycleIdentity: target.identity
        )
        let originalName = fixture.manager.composeTab(with: tabID)?.name

        let replacementSessionID = UUID()
        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        _ = viewModel.test_installPersistentSessionBinding(
            sessionID: replacementSessionID,
            on: session,
            compareAndSetInWorkspaceID: workspaceID
        )

        XCTAssertThrowsError(try viewModel.renameSession(target: target, to: "Late stale title"))
        XCTAssertThrowsError(try viewModel.requireCurrentAgentSessionLifecycleAdmission(runTarget))
        let interaction = AgentAskUserInteraction(
            title: "Late question",
            questions: [
                AgentAskUserQuestion(
                    id: "answer",
                    question: "Should not be shown",
                    allowsMultiple: false,
                    allowsCustom: true
                )
            ]
        )
        await assertThrowsErrorAsync {
            try await viewModel.askUserInteraction(target: target, interaction: interaction)
        }
        await assertThrowsErrorAsync {
            try await viewModel.waitForNextUserInstruction(target: target)
        }
        XCTAssertEqual(fixture.manager.composeTab(with: tabID)?.name, originalName)
        XCTAssertEqual(fixture.manager.composeTab(with: tabID)?.activeAgentSessionID, replacementSessionID)
        XCTAssertEqual(session.activeAgentSessionID, replacementSessionID)
        XCTAssertNil(session.pendingAskUser)
        XCTAssertNil(session.instructionContinuation)
    }

    func testLifecycleAdmissionAcceptsCorrectAlreadySavedWorkspaceAndRejectsWrongWorkspace() {
        let authority = AgentSessionLifecycleAuthority()
        let workspaceID = UUID()

        XCTAssertEqual(
            authority.decideAdmission(
                persistence: .notRequired(workspaceID: workspaceID),
                targetWorkspaceID: workspaceID,
                bindingStillCurrent: true
            ),
            .commit
        )
        XCTAssertEqual(
            authority.decideAdmission(
                persistence: .persisted(workspaceID: UUID(), stateVersion: 7),
                targetWorkspaceID: workspaceID,
                bindingStillCurrent: true
            ),
            .rollback(.workspaceChanged)
        )
    }

    private func admissionWasRejected(_ viewModel: AgentModeViewModel) async -> Bool {
        do {
            _ = try await viewModel.mcpResolveOrCreateSessionTarget(
                tabID: nil,
                sessionID: nil,
                createIfNeeded: true,
                sessionName: "Rejected concurrent workflow"
            )
            return false
        } catch {
            return true
        }
    }

    private func assertThrowsErrorAsync(
        _ expression: () async throws -> some Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {}
    }

    private func configureNonblankForegroundContext(
        fixture: (manager: WorkspaceManagerViewModel, prompt: PromptViewModel),
        root: URL
    ) async throws -> ComposeTabState {
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let selectedFile = sources.appendingPathComponent("Selected.swift")
        try "struct SelectedForegroundContext {}\n".write(
            to: selectedFile,
            atomically: true,
            encoding: .utf8
        )

        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let workspaceIndex = try XCTUnwrap(
            fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID })
        )
        fixture.manager.workspaces[workspaceIndex].repoPaths = [root.path]
        try await fixture.manager.fileManager.loadFolder(
            at: root,
            for: fixture.manager.workspaces[workspaceIndex],
            freshStart: true
        )

        let tabID = try XCTUnwrap(fixture.manager.workspaces[workspaceIndex].activeComposeTabID)
        let tabIndex = try XCTUnwrap(
            fixture.manager.workspaces[workspaceIndex].composeTabs.firstIndex(where: { $0.id == tabID })
        )
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].promptText = "Restore this foreground prompt"
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].selection = StoredSelection(
            selectedPaths: [selectedFile.path],
            codemapAutoEnabled: false
        )
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].expandedFolders = ["", "Sources"]
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].activeSubView = .context
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].contextOverrides = .init(
            useOverridePrompt: true,
            overridePromptText: "Restore this context override"
        )
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex].contextBuilder = .init(
            instructions: "Restore these compose instructions",
            followUpTypeRaw: "plan"
        )
        fixture.prompt.loadComposeTabsFromWorkspace(fixture.manager.workspaces[workspaceIndex])
        let foregroundTab = fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex]
        await fixture.manager.applyComposeTabState(foregroundTab)
        await fixture.manager.fileManager.restoreExpansionState(from: foregroundTab.expandedFolders)
        let liveForegroundTab = fixture.manager.collectComposeTabSnapshot(
            name: foregroundTab.name,
            base: foregroundTab
        )
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex] = liveForegroundTab
        fixture.prompt.loadComposeTabsFromWorkspace(fixture.manager.workspaces[workspaceIndex])
        return liveForegroundTab
    }

    private func updateForegroundContextDuringAdmission(
        fixture: (manager: WorkspaceManagerViewModel, prompt: PromptViewModel),
        root: URL,
        tabID: UUID,
        label: String
    ) async throws -> ComposeTabState {
        let latestFolder = root
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Latest-\(label)", isDirectory: true)
        try FileManager.default.createDirectory(at: latestFolder, withIntermediateDirectories: true)
        let latestFile = latestFolder.appendingPathComponent("Latest.swift")
        try "struct Latest\(label)ForegroundContext {}\n".write(
            to: latestFile,
            atomically: true,
            encoding: .utf8
        )

        let workspaceID = try XCTUnwrap(fixture.manager.activeWorkspaceID)
        let workspaceIndex = try XCTUnwrap(
            fixture.manager.workspaces.firstIndex(where: { $0.id == workspaceID })
        )
        let tabIndex = try XCTUnwrap(
            fixture.manager.workspaces[workspaceIndex].composeTabs.firstIndex(where: { $0.id == tabID })
        )
        var storedTab = fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex]
        storedTab.isPinned.toggle()
        storedTab.contextBuilder = .init(
            instructions: "Latest \(label) compose instructions",
            followUpTypeRaw: "question"
        )
        fixture.manager.workspaces[workspaceIndex].composeTabs[tabIndex] = storedTab

        fixture.prompt.promptText = "Latest \(label) foreground prompt"
        fixture.prompt.setActiveFilesTab(.context, source: .user)
        await fixture.prompt.applyContextBuilderOverrides(.init(
            useOverridePrompt: true,
            overridePromptText: "Latest \(label) context override"
        ))
        await fixture.manager.fileManager.applyStoredSelection(.init(
            selectedPaths: [latestFile.path],
            codemapAutoEnabled: false
        ))
        await fixture.manager.fileManager.restoreExpansionState(from: [
            root.path,
            root.appendingPathComponent("Sources", isDirectory: true).path,
            latestFolder.path
        ])
        fixture.manager.publishActiveComposeTabSnapshot(
            commitToMemory: true,
            touchModified: true
        )
        let latestStoredTab = try XCTUnwrap(
            fixture.manager.workspaces[workspaceIndex].composeTabs.first(where: { $0.id == tabID })
        )
        fixture.prompt.loadComposeTabsFromWorkspace(fixture.manager.workspaces[workspaceIndex])
        return latestStoredTab
    }

    private func blankReplacementContextMatches(
        fixture: (manager: WorkspaceManagerViewModel, prompt: PromptViewModel),
        stashedPriorTabID: UUID,
        rejectedSessionID: UUID
    ) -> Bool {
        let workspace = fixture.manager.activeWorkspace
        let replacementTab = workspace?.composeTabs.count == 1 ? workspace?.composeTabs.first : nil
        let presentationTab = fixture.prompt.currentComposeTabs.count == 1
            ? fixture.prompt.currentComposeTabs.first
            : nil
        let liveSelection = fixture.manager.fileManager.snapshotSelection()
        let liveExpandedFolders = Set(fixture.manager.fileManager.snapshotExpandedFolderFullPaths())
        let rejectedIdentityPresent = fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == rejectedSessionID
        }) || fixture.prompt.currentComposeTabs.contains(where: {
            $0.activeAgentSessionID == rejectedSessionID
        })
        let matches = replacementTab != nil
            && workspace?.activeComposeTabID == replacementTab?.id
            && fixture.prompt.activeComposeTabID == replacementTab?.id
            && fixture.prompt.promptText == replacementTab?.promptText
            && fixture.prompt.activeFilesTab == .context
            && fixture.prompt.currentContextBuilderOverridesSnapshot() == replacementTab?.contextOverrides
            && liveSelection == replacementTab?.selection
            && liveExpandedFolders == Set(replacementTab?.expandedFolders ?? [])
            && replacementTab?.activeAgentSessionID == nil
            && replacementTab?.activeChatSessionID == nil
            && presentationTab == replacementTab
            && workspace?.stashedTabs.contains(where: { $0.tab.id == stashedPriorTabID }) == true
            && fixture.prompt.isSwitchingComposeTab == false
            && !rejectedIdentityPresent
        if !matches {
            XCTFail(
                "Blank replacement context mismatch: tabs=\(String(describing: workspace?.composeTabs)) "
                    + "managerActive=\(String(describing: workspace?.activeComposeTabID)) "
                    + "promptActive=\(String(describing: fixture.prompt.activeComposeTabID)) "
                    + "prompt=\(fixture.prompt.promptText) selection=\(liveSelection) "
                    + "expanded=\(liveExpandedFolders) presentation=\(String(describing: presentationTab)) "
                    + "priorStashed=\(workspace?.stashedTabs.contains(where: { $0.tab.id == stashedPriorTabID }) == true) "
                    + "rejectedPresent=\(rejectedIdentityPresent)"
            )
        }
        return matches
    }

    private func nonblankForegroundContextMatches(
        fixture: (manager: WorkspaceManagerViewModel, prompt: PromptViewModel),
        expectedTab: ComposeTabState,
        rejectedSessionID: UUID
    ) -> Bool {
        let liveTab = fixture.manager.activeWorkspace?.composeTabs.first(where: { $0.id == expectedTab.id })
        let presentationTab = fixture.prompt.currentComposeTabs.first(where: { $0.id == expectedTab.id })
        let liveSelection = fixture.manager.fileManager.snapshotSelection()
        let liveExpandedFolders = Set(fixture.manager.fileManager.snapshotExpandedFolderFullPaths())
        let rejectedIdentityPresent = fixture.manager.workspaces.flatMap(\.composeTabs).contains(where: {
            $0.activeAgentSessionID == rejectedSessionID
        }) || fixture.prompt.currentComposeTabs.contains(where: {
            $0.activeAgentSessionID == rejectedSessionID
        })
        let matches = fixture.manager.activeWorkspace?.activeComposeTabID == expectedTab.id
            && fixture.prompt.activeComposeTabID == expectedTab.id
            && fixture.prompt.promptText == expectedTab.promptText
            && fixture.prompt.activeFilesTab == .context
            && fixture.prompt.currentContextBuilderOverridesSnapshot() == expectedTab.contextOverrides
            && liveSelection == expectedTab.selection
            && liveExpandedFolders == Set(expectedTab.expandedFolders)
            && fixture.prompt.isSwitchingComposeTab == false
            && liveTab?.isPinned == expectedTab.isPinned
            && liveTab?.selection == expectedTab.selection
            && liveTab?.expandedFolders == expectedTab.expandedFolders
            && liveTab?.contextOverrides == expectedTab.contextOverrides
            && liveTab?.contextBuilder == expectedTab.contextBuilder
            && presentationTab?.isPinned == expectedTab.isPinned
            && presentationTab?.promptText == expectedTab.promptText
            && presentationTab?.selection == expectedTab.selection
            && presentationTab?.expandedFolders == expectedTab.expandedFolders
            && presentationTab?.contextOverrides == expectedTab.contextOverrides
            && presentationTab?.contextBuilder == expectedTab.contextBuilder
            && !rejectedIdentityPresent
        if !matches {
            XCTFail(
                "Foreground context mismatch: managerActive=\(String(describing: fixture.manager.activeWorkspace?.activeComposeTabID)) "
                    + "promptActive=\(String(describing: fixture.prompt.activeComposeTabID)) "
                    + "prompt=\(fixture.prompt.promptText) filesTab=\(fixture.prompt.activeFilesTab) "
                    + "selection=\(liveSelection) expectedSelection=\(expectedTab.selection) "
                    + "expanded=\(liveExpandedFolders) expectedExpanded=\(Set(expectedTab.expandedFolders)) "
                    + "liveTabPinned=\(String(describing: liveTab?.isPinned)) expectedPinned=\(expectedTab.isPinned) "
                    + "presentationTab=\(String(describing: presentationTab)) "
                    + "liveTabSelection=\(String(describing: liveTab?.selection)) "
                    + "liveTabExpanded=\(String(describing: liveTab?.expandedFolders)) "
                    + "liveTabOverrides=\(String(describing: liveTab?.contextOverrides)) "
                    + "expectedOverrides=\(expectedTab.contextOverrides) "
                    + "liveTabBuilder=\(String(describing: liveTab?.contextBuilder)) "
                    + "expectedBuilder=\(expectedTab.contextBuilder) "
                    + "switching=\(fixture.prompt.isSwitchingComposeTab) rejectedPresent=\(rejectedIdentityPresent)"
            )
        }
        return matches
    }

    private func makeFixture(
        initialTabCount: Int,
        coordinator: WorkspaceAgentAdmissionCoordinator = .shared,
        ephemeralFlag: Bool = true,
        customStoragePath: URL? = nil
    ) -> (manager: WorkspaceManagerViewModel, prompt: PromptViewModel) {
        let fileManager = WorkspaceFilesViewModel()
        let keyManager = KeyManager(
            secureService: SecureKeysService(secureStorage: TestSecureStorageBackend())
        )
        let apiSettings = APISettingsViewModel(
            aiQueriesService: AIQueriesService(keyManager: keyManager),
            keyManager: keyManager,
            loadStoredDataOnInit: false
        )
        let prompt = PromptViewModel(
            fileManager: fileManager,
            apiSettingsViewModel: apiSettings,
            windowID: -1,
            settingsManager: WindowSettingsManager(windowID: -1)
        )
        let manager = WorkspaceManagerViewModel(
            fileManager: fileManager,
            promptViewModel: prompt,
            workspaceAgentAdmissionCoordinator: coordinator,
            performInitialWorkspaceActivation: false
        )
        let tabs = (0 ..< initialTabCount).map { index in
            ComposeTabState(
                name: "Existing \(index)",
                lastModified: Date(timeIntervalSince1970: TimeInterval(index)),
                isPinned: index.isMultiple(of: 11),
                activeAgentSessionID: UUID()
            )
        }
        let stashed = StashedTab(
            tab: ComposeTabState(name: "Already stashed", activeAgentSessionID: UUID()),
            stashedAt: Date(timeIntervalSince1970: 1)
        )
        let workspace = WorkspaceModel(
            name: "Background compose admission",
            repoPaths: [],
            customStoragePath: customStoragePath,
            ephemeralFlag: ephemeralFlag,
            composeTabs: tabs,
            activeComposeTabID: tabs.last?.id,
            stashedTabs: [stashed]
        )
        manager.workspaces = [workspace]
        manager.activeWorkspace = workspace
        prompt.loadComposeTabsFromWorkspace(workspace)
        return (manager, prompt)
    }

    private func makeAgentModeViewModel(
        prompt: PromptViewModel,
        manager: WorkspaceManagerViewModel
    ) -> AgentModeViewModel {
        let viewModel = AgentModeViewModel(
            codexControllerFactory: { _, _, _, _, _, _ in ComposeAdmissionFakeCodexController() }
        )
        viewModel.test_setSidebarAutoArchiveDependencies(promptManager: prompt, workspaceManager: manager)
        return viewModel
    }

    private func installDidRemoveListener(
        prompt: PromptViewModel,
        viewModel: AgentModeViewModel
    ) -> UUID {
        prompt.addComposeTabsDidRemoveListener { tabIDs, reason, workspaceID in
            await viewModel.handleComposeTabsDidRemove(tabIDs, reason: reason, workspaceID: workspaceID)
        }
    }

    private func emitTranscriptRefreshAttempt(tabID: UUID, inputSignature: String) {
        AgentTranscriptDebugInstrumentation.emitRefreshAttempt(
            tabID: tabID,
            reason: "test",
            sourceItemsRevision: 0,
            itemCount: 0,
            nextSequenceIndex: 0,
            runState: "idle",
            selectedAgent: "test",
            projectionProtection: "none",
            pendingMutationSummary: "none",
            incrementalPath: "test",
            inputSignature: inputSignature
        )
    }
}

private actor ComposeRemovalSideEffectRecorder {
    struct Snapshot: Equatable {
        var cascadeCount = 0
        var closeCount = 0
        var affectedTabIDs: Set<UUID> = []
    }

    private var value = Snapshot()

    func recordCascade(_ tabIDs: Set<UUID>) {
        value.cascadeCount += 1
        value.affectedTabIDs.formUnion(tabIDs)
    }

    func recordClose(_ tabIDs: Set<UUID>) {
        value.closeCount += 1
        value.affectedTabIDs.formUnion(tabIDs)
    }

    func snapshot() -> Snapshot {
        value
    }
}

private actor SaveAttemptRecorder {
    private var value = 0

    func record() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

private actor DeletionAttemptRecorder {
    private let failingTabID: UUID?
    private var tabIDs: [UUID] = []

    init(failingTabID: UUID?) {
        self.failingTabID = failingTabID
    }

    func delete(_ tabID: UUID) throws {
        tabIDs.append(tabID)
        if tabID == failingTabID {
            throw RequiredFlushTestError.injectedFailure
        }
    }

    func attempted() -> [UUID] {
        tabIDs
    }
}

private enum RequiredFlushTestError: Error {
    case injectedFailure
}

private final class ComposeAdmissionFakeCodexController: CodexSessionControllerTurnDispatchTestDefaults {
    var hasActiveThread: Bool {
        false
    }

    var events: AsyncStream<CodexNativeSessionController.Event> {
        AsyncStream { continuation in continuation.finish() }
    }

    func ensureEventsStreamReady() {}

    func startOrResume(
        existing _: CodexNativeSessionController.SessionRef?,
        baseInstructions _: String
    ) async throws -> CodexNativeSessionController.SessionRef {
        .init(conversationID: "fake", rolloutPath: nil, model: nil, reasoningEffort: nil)
    }

    func startOrResume(
        existing _: CodexNativeSessionController.SessionRef?,
        baseInstructions _: String,
        model: String?,
        reasoningEffort: String?
    ) async throws -> CodexNativeSessionController.SessionRef {
        .init(conversationID: "fake", rolloutPath: nil, model: model, reasoningEffort: reasoningEffort)
    }

    func startOrResume(
        existing _: CodexNativeSessionController.SessionRef?,
        baseInstructions _: String,
        model: String?,
        reasoningEffort: String?,
        serviceTier _: String?
    ) async throws -> CodexNativeSessionController.SessionRef {
        .init(conversationID: "fake", rolloutPath: nil, model: model, reasoningEffort: reasoningEffort)
    }

    func readThreadSnapshot(
        includeTurns _: Bool,
        timeout _: TimeInterval?
    ) async throws -> CodexNativeSessionController.ThreadSnapshot {
        .init(
            conversationID: "fake",
            rolloutPath: nil,
            model: nil,
            reasoningEffort: nil,
            runtimeStatus: .idle,
            currentTurnID: nil,
            activeTurnIDs: [],
            latestTurnStatus: nil
        )
    }

    func setThreadName(_: String, threadID _: String?) async throws {}
    func compactThread() async throws {}
    func getThreadGoal() async throws -> CodexNativeSessionController.ThreadGoal? {
        nil
    }

    func setThreadGoalObjective(_: String) async throws -> CodexNativeSessionController.ThreadGoal {
        throw CancellationError()
    }

    func setThreadGoalStatus(_: CodexNativeSessionController.ThreadGoalStatus) async throws -> CodexNativeSessionController.ThreadGoal {
        throw CancellationError()
    }

    func clearThreadGoal() async throws -> Bool {
        false
    }

    func cancelCurrentTurn() async {}
    func shutdown() async {}
    func respondToServerRequest(id _: CodexAppServerRequestID, result _: [String: Any]) async {}
}

@MainActor
private final class MutationContextFlag {
    var isCurrent = true
}

private actor RemovalPreflightRecorder {
    private var reasons: [PromptViewModel.ComposeTabRemovalReason] = []

    func record(_ reason: PromptViewModel.ComposeTabRemovalReason) {
        reasons.append(reason)
    }

    func count(for reason: PromptViewModel.ComposeTabRemovalReason) -> Int {
        reasons.count { $0 == reason }
    }
}

private actor OneShotAdmissionClaim {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private final class AdmissionLifecycleEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AgentSessionLifecycleAuthority.Event] = []

    func record(_ event: AgentSessionLifecycleAuthority.Event) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [AgentSessionLifecycleAuthority.Event] {
        lock.withLock { events }
    }
}

private final class AdmissionEventSignal: @unchecked Sendable {
    private let kind: WorkspaceAgentAdmissionCoordinator.Event.Kind
    private let lock = NSLock()
    private var observed = false

    init(kind: WorkspaceAgentAdmissionCoordinator.Event.Kind) {
        self.kind = kind
    }

    func observe(_ event: WorkspaceAgentAdmissionCoordinator.Event) {
        guard event.kind == kind else { return }
        lock.withLock { observed = true }
    }

    func wait() async {
        do {
            try await AsyncTestWait.waitUntil(
                "workspace admission event \(kind.rawValue)",
                timeout: TestFenceDefaults.enterWait
            ) {
                self.lock.withLock { self.observed }
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

private final class BoundedTestSignal: @unchecked Sendable {
    private let name: String
    private let lock = NSLock()
    private var signalled = false

    init(name: String) {
        self.name = name
    }

    func signal() {
        lock.withLock { signalled = true }
    }

    func wait() async {
        do {
            try await AsyncTestWait.waitUntil(name, timeout: TestFenceDefaults.enterWait) {
                self.lock.withLock { self.signalled }
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

private final class AdmissionAsyncGate: @unchecked Sendable {
    private let fence = TestReleaseFence(name: "workspace admission save gate")

    func enterAndWait() async {
        await fence.enterAndWaitIgnoringCancellationUntilRelease()
    }

    func waitUntilEntered() async {
        _ = await fence.waitUntilEntered()
    }

    func open() async {
        fence.release()
    }
}

private actor ComposeRemovalPreflightGate {
    private var started = false
    private var released = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStartedAndWaitForRelease() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !started, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return started
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
