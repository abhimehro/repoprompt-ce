@testable import RepoPromptApp
import RepoPromptDomainRuntime
import XCTest

@MainActor
final class AgentSelfCompactNativeCompletionTests: XCTestCase {
    @MainActor private final class Fake {
        var state = AgentSelfCompactState()
        var dispatchCount = 0
        var providerBoundTexts: [String] = []
        var shouldStartNote = true
        var shouldAcceptNote = true
        var noteTransportFailureGate: TestReleaseFence?
        var ownerIsCurrent = true
        var pendingSleeps: [CheckedContinuation<Void, Never>] = []
        var slept: [Duration] = []
        let owner = AgentSelfCompactOwner(
            windowID: 1, workspaceID: UUID(), tabID: UUID(), sessionID: UUID(),
            persistentBindingGeneration: UUID(), bindingTransitionGeneration: 1,
            runID: UUID(), runAttemptID: UUID()
        )
        let compactRunID = UUID()
        let compactAttemptID = UUID()

        func arm(support: AgentSessionLinkCompactSupport = .claudeCode, note: String = "alpha\nβeta") -> UUID {
            _ = state.reserve(note: note, idempotencyKey: "key", owner: owner)
            state.active?.admittedSupport = support
            state.active?.phase = .dispatchingCompact
            state.active?.compactProviderConversation = "provider-conversation"
            return state.active!.id
        }

        func coordinator() -> AgentSelfCompactNativeCompletionCoordinator {
            AgentSelfCompactNativeCompletionCoordinator(
                load: { self.state },
                store: { self.state = $0 },
                isCurrentOwner: { _ in self.ownerIsCurrent },
                dispatchNote: { requestID, admissible in
                    guard admissible(), let note = self.state.active?.note else { return false }
                    self.dispatchCount += 1
                    self.providerBoundTexts.append(AgentSelfCompactNoteEnvelope.frame(note))
                    guard self.shouldStartNote else { return false }
                    self.state.active?.phase = .dispatchingNote
                    let dispatchID = AgentSelfCompactionDispatchID(requestID: requestID, stage: .note)
                    if let failureGate = self.noteTransportFailureGate {
                        XCTAssertTrue(self.state.noteWillAttempt(dispatchID))
                        await failureGate.enterAndWait()
                        XCTAssertTrue(self.state.noteTransportFailed(dispatchID))
                        return false
                    }
                    if self.shouldAcceptNote {
                        XCTAssertTrue(self.state.noteWillAttempt(dispatchID))
                        XCTAssertTrue(self.state.noteAccepted(dispatchID))
                    }
                    return true
                },
                sleep: { duration in
                    self.slept.append(duration)
                    await withCheckedContinuation { continuation in
                        self.pendingSleeps.append(continuation)
                    }
                }
            )
        }

        func completeRevision(
            status: AgentSessionRunState,
            runAttemptID: UUID? = nil,
            successor: AgentRunEpochTransitionKind? = nil
        ) -> AgentRunTerminalCommitRevision {
            AgentRunTerminalCommitRevision(
                commitID: UUID(),
                ownership: AgentRunOwnership(
                    attemptID: runAttemptID ?? compactAttemptID,
                    binding: AgentRunBindingIdentity(tabID: owner.tabID, persistentSessionID: owner.sessionID)
                ),
                terminalState: status,
                failureReason: nil,
                expectedRunID: compactRunID,
                sourceItemsRevision: 0,
                assistantDeltaFlushGeneration: 0,
                providerDrainGeneration: 0,
                mcpPublicationEnvelope: nil,
                successorKind: successor,
                providerSuccessorID: nil
            )
        }

        func advanceDeadline() {
            let sleepers = pendingSleeps
            pendingSleeps.removeAll()
            sleepers.forEach { $0.resume() }
        }
    }

    private func drain() async {
        for _ in 0 ..< 30 {
            await Task.yield()
        }
    }

    func testCodexSteerRejectionsReparkOnlyOnDefinitiveNonAttempt() throws {
        let failure = CodexAppServerClient.RequestFailure(
            method: "turn/steer", code: nil, message: "rejected", data: nil
        )
        let definitive: [CodexTurnSteerError] = [
            .expectedTurnMismatch(expectedTurnID: "old", actualTurnID: "new", failure: failure),
            .noActiveTurn(failure),
            .activeTurnNotSteerable(turnKind: "compact", failure: failure)
        ]
        for error in definitive {
            XCTAssertTrue(error.definitivelyRejectsInput)
            var state = AgentSelfCompactState()
            _ = state.reserve(note: "recover", idempotencyKey: "key")
            state.active?.phase = .dispatchingNote
            let dispatchID = try AgentSelfCompactionDispatchID(requestID: XCTUnwrap(state.active?.id), stage: .note)
            XCTAssertTrue(state.noteWillAttempt(dispatchID))
            XCTAssertTrue(state.noteDefinitivelyNotAttempted(dispatchID))
            XCTAssertEqual(state.active?.phase, .parked)
            XCTAssertEqual(state.active?.noteDispatchStarted, false)
        }
    }

    func testClaudeCompletionSendsVerbatimFramedNoteOnce() async {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 1)
        XCTAssertEqual(fake.providerBoundTexts, [AgentSelfCompactNoteEnvelope.frame("alpha\nβeta")])
        XCTAssertTrue(fake.providerBoundTexts[0].hasSuffix("<note>\nalpha\nβeta\n</note>"))
        XCTAssertEqual(fake.state.latest?.outcome, .noteAccepted)
        XCTAssertEqual(fake.state.latest?.noteDelivery, .accepted)
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 1)
    }

    func testCodexRequiresCompactKindSuccessEvidence() async {
        let fake = Fake()
        let id = fake.arm(support: .codex)
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 0)
        XCTAssertEqual(fake.state.latest?.outcome, .failed)
    }

    func testCodexCorrelatedSuccessSendsOneNote() async {
        let fake = Fake()
        let id = fake.arm(support: .codex)
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID, runAttemptID: fake.compactAttemptID
        ))
        fake.state.active?.compactTurnSucceeded = true
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 1)
        XCTAssertEqual(fake.state.latest?.outcome, .noteAccepted)
    }

    func testWrongAttemptAndStalePublicationDoNotSendNote() async {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID, runAttemptID: fake.compactAttemptID
        ))
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed, runAttemptID: UUID()),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 0)
        XCTAssertNotNil(fake.state.active)
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .stale, teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 0)
        XCTAssertEqual(fake.state.latest?.outcome, .completionUnverified)
    }

    func testDefinitiveNoteStartFailureParksWithoutSpeculativeRetry() async {
        let fake = Fake()
        fake.shouldStartNote = false
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID, runAttemptID: fake.compactAttemptID
        ))
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 1)
        XCTAssertEqual(fake.state.active?.phase, .parked)
        XCTAssertEqual(fake.state.parkedNote?.frame, AgentSelfCompactNoteEnvelope.frame("alpha\nβeta"))
    }

    func testNoteTransportFailureAfterAttemptReleasesHoldsWithoutRetry() async throws {
        let fake = Fake()
        let gate = TestReleaseFence(name: "continuation transport attempted")
        fake.noteTransportFailureGate = gate
        let id = fake.arm()
        let coordinator = fake.coordinator()
        defer {
            gate.release()
            coordinator.cancelRuntimeWork()
            fake.advanceDeadline()
        }
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID, runAttemptID: fake.compactAttemptID
        ))
        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        guard await gate.waitUntilEntered(timeout: 3) else { return }
        XCTAssertEqual(fake.state.active?.phase, .dispatchingNote)
        XCTAssertEqual(fake.state.active?.noteDispatchStarted, true)
        XCTAssertTrue(fake.state.blocksOverseerDelivery)
        XCTAssertTrue(fake.state.blocksAutomaticWake)

        gate.release()
        try await AsyncTestWait.waitUntil("failed continuation settled") {
            fake.state.active == nil
        }
        XCTAssertEqual(fake.state.latest?.requestID, id)
        XCTAssertEqual(fake.state.latest?.outcome, .deliveryUnknown)
        XCTAssertEqual(fake.state.latest?.noteDelivery, .deliveryUnknown)
        XCTAssertEqual(fake.state.latest?.recoveryNote, "alpha\nβeta")
        XCTAssertNil(fake.state.parkedNote)
        XCTAssertFalse(fake.state.blocksOverseerDelivery)
        XCTAssertFalse(fake.state.blocksAutomaticWake)

        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        XCTAssertEqual(fake.dispatchCount, 1)
        XCTAssertEqual(fake.state.reserve(note: "alpha\nβeta", idempotencyKey: "key", owner: fake.owner), .duplicate(id))
        guard case .scheduled = fake.state.reserve(note: "next note", idempotencyKey: "next-key", owner: fake.owner) else {
            return XCTFail("A settled transport failure must not block a new compaction request")
        }
    }

    func testFailedAndCancelledCompactNeverSendNote() async {
        for status in [AgentSessionRunState.failed, .cancelled] {
            let fake = Fake()
            let id = fake.arm()
            let coordinator = fake.coordinator()
            XCTAssertTrue(coordinator.bindCompact(
                .init(requestID: id, stage: .compact),
                runID: fake.compactRunID,
                runAttemptID: fake.compactAttemptID
            ))
            coordinator.compactTurnSettled(
                revision: fake.completeRevision(status: status),
                publication: .accepted(successorEpoch: nil), teardownSettled: { true }
            )
            await drain()
            XCTAssertEqual(fake.dispatchCount, 0)
            XCTAssertEqual(fake.state.latest?.outcome, .failed)
        }
    }

    func testDeadlineParksTheNoteUnverifiedAndLateCompletionNeverSendsIt() async {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        await drain()
        XCTAssertEqual(fake.slept, [.seconds(300)])
        fake.advanceDeadline()
        await drain()
        // The continuation survives a slow native compaction, exactly like an unverified ACP turn.
        XCTAssertNil(fake.state.latest)
        XCTAssertEqual(fake.state.active?.phase, .parked)
        XCTAssertEqual(fake.state.active?.acpCompletionUnverified, true)
        XCTAssertEqual(fake.state.parkedNote?.frame, AgentSelfCompactNoteEnvelope.frame("alpha\nβeta"))
        XCTAssertEqual(fake.state.status?.outcome, .completionUnverified)
        XCTAssertEqual(fake.state.status?.noteDelivery, .parked)
        XCTAssertFalse(fake.state.blocksOverseerDelivery)
        XCTAssertFalse(fake.state.blocksManagedStop)

        coordinator.compactTurnSettled(
            revision: fake.completeRevision(status: .completed),
            publication: .accepted(successorEpoch: nil), teardownSettled: { true }
        )
        await drain()
        XCTAssertEqual(fake.dispatchCount, 0, "a late command terminal never manufactures a prompt")
        XCTAssertEqual(fake.state.active?.phase, .parked)

        // Only the next ordinary send consumes it, once, still reporting unverified completion.
        let noteID = AgentSelfCompactionDispatchID(requestID: id, stage: .note)
        XCTAssertTrue(fake.state.noteWillAttempt(noteID))
        XCTAssertTrue(fake.state.noteAccepted(noteID))
        XCTAssertEqual(fake.state.latest?.outcome, .completionUnverified)
        XCTAssertEqual(fake.state.latest?.noteDelivery, .prepended)
        XCTAssertEqual(fake.state.latest?.completionVerified, false)
        XCTAssertNil(fake.state.active)
    }

    func testDeadlineAfterOwnerLossStillCancelsInsteadOfParking() async {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        await drain()
        fake.ownerIsCurrent = false
        fake.advanceDeadline()
        await drain()
        XCTAssertNil(fake.state.active)
        XCTAssertEqual(fake.state.latest?.outcome, .cancelled)
        XCTAssertEqual(fake.state.latest?.noteDelivery, .notSent)
        XCTAssertEqual(fake.dispatchCount, 0)
    }

    func testTeardownCancelsTheDeadlineBeforeItCanSettle() async {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        await drain()
        XCTAssertEqual(fake.slept, [.seconds(300)])
        coordinator.cancelRuntimeWork()
        fake.advanceDeadline()
        await drain()
        XCTAssertEqual(fake.state.active?.phase, .dispatchingCompact)
        XCTAssertNil(fake.state.latest)
        XCTAssertEqual(fake.dispatchCount, 0)
    }

    func testSupersedingOrdinaryInputParksAndOnlyPhysicalAcceptanceConsumes() throws {
        let fake = Fake()
        let id = fake.arm()
        let coordinator = fake.coordinator()
        XCTAssertTrue(coordinator.bindCompact(
            .init(requestID: id, stage: .compact),
            runID: fake.compactRunID,
            runAttemptID: fake.compactAttemptID
        ))
        coordinator.supersedeForOrdinaryInput()
        XCTAssertEqual(fake.state.active?.phase, .parked)
        let parked = try XCTUnwrap(fake.state.parkedNote)
        XCTAssertEqual(parked.frame, AgentSelfCompactNoteEnvelope.frame("alpha\nβeta"))
        XCTAssertTrue(fake.state.noteWillAttempt(parked.dispatchID))
        XCTAssertTrue(fake.state.noteAccepted(parked.dispatchID))
        XCTAssertNil(fake.state.active)
        XCTAssertEqual(fake.state.latest?.noteDelivery, .prepended)
        XCTAssertFalse(fake.state.noteAccepted(parked.dispatchID), "no duplicate acceptance")
    }

    func testDefinitiveNonAttemptMayParkButAmbiguousTransportCannotRetry() {
        let fake = Fake()
        let id = fake.arm()
        fake.state.active?.phase = .dispatchingNote
        let dispatchID = AgentSelfCompactionDispatchID(requestID: id, stage: .note)
        XCTAssertTrue(fake.state.noteDefinitivelyNotAttempted(dispatchID))
        XCTAssertNotNil(fake.state.parkedNote)
        XCTAssertTrue(fake.state.noteWillAttempt(dispatchID))
        XCTAssertTrue(fake.state.noteTransportFailed(dispatchID))
        XCTAssertNil(fake.state.parkedNote)
        XCTAssertEqual(fake.state.latest?.outcome, .deliveryUnknown)
        XCTAssertEqual(fake.state.latest?.recoveryNote, "alpha\nβeta")
    }

    func testSystemProvenanceNeverContainsNote() {
        let note = "private unique note 123"
        let rows = [
            AgentChatItem.selfCompactionRequest(sequenceIndex: 0),
            AgentChatItem.selfCompactionCancelled(sequenceIndex: 0),
            AgentChatItem.selfCompactionCouldNotStart(sequenceIndex: 0),
            AgentChatItem.selfCompactionCompletionUnverified(sequenceIndex: 0),
            AgentChatItem.selfCompactionNoteRestored(sequenceIndex: 0)
        ]
        XCTAssertEqual(
            rows.map(\.text),
            [
                "Context compaction was requested by this session.",
                "Scheduled self-compaction was cancelled before it reached the provider.",
                "Self-compaction could not start. The continuation note was retained for recovery.",
                "The provider did not confirm that compaction finished. The continuation note will be attached to the next message in this session.",
                "A continuation note from before compaction was restored to this session."
            ]
        )
        XCTAssertEqual(rows.map(\.kind), Array(repeating: AgentChatItemKind.system, count: rows.count))
        for row in rows {
            XCTAssertFalse(row.text.contains(note))
            XCTAssertFalse(row.text.contains("<note>"))
        }
        XCTAssertTrue(AgentSelfCompactNoteEnvelope.frame(note).contains(note))
    }
}
