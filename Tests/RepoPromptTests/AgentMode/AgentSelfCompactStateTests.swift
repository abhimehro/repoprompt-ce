import CryptoKit
@testable import RepoPromptApp
import XCTest

final class AgentSelfCompactStateTests: XCTestCase {
    private static let teardownNote = "Continue the current task."

    private static func holding(
        _ phase: AgentSelfCompactAttempt.Phase,
        verified: Bool = false,
        noteStarted: Bool = false
    ) -> AgentSelfCompactState {
        var attempt = AgentSelfCompactAttempt(idempotencyKey: "hold", note: teardownNote, phase: phase)
        attempt.compactTurnSucceeded = verified ? true : nil
        attempt.noteDispatchStarted = noteStarted
        return AgentSelfCompactState(active: attempt)
    }

    func testManagedStopHoldCoversOnlyRepoPromptOwnedUnsentDispatch() {
        let blocking: Set<AgentSelfCompactAttempt.Phase> = [
            .compactDispatchPending, .dispatchingCompact, .awaitingCompactTurn, .acpSettling,
            .awaitingNoteBoundary, .noteDispatchPending, .dispatchingNote
        ]
        for phase in AgentSelfCompactAttempt.Phase.allCases {
            XCTAssertEqual(Self.holding(phase).blocksManagedStop, blocking.contains(phase), phase.rawValue)
        }
        // The caller's originating turn and every already-started note send stay stoppable, even
        // though overseer delivery remains held until the note settles.
        XCTAssertTrue(Self.holding(.scheduled).blocksOverseerDelivery)
        let started = Self.holding(.dispatchingNote, verified: true, noteStarted: true)
        XCTAssertFalse(started.blocksManagedStop)
        XCTAssertTrue(started.blocksOverseerDelivery)
        XCTAssertFalse(AgentSelfCompactState().blocksManagedStop)
    }

    @MainActor
    func testRuntimeTeardownSettlesOrParksEveryWorkerOwnedHold() {
        for phase in [AgentSelfCompactAttempt.Phase.scheduled, .compactDispatchPending] {
            let session = AgentTabSession(tabID: UUID())
            session.selfCompactState = Self.holding(phase)
            session.cancelEphemeralRuntimeState()
            XCTAssertNil(session.selfCompactState.active, phase.rawValue)
            XCTAssertEqual(session.selfCompactState.latest?.outcome, .cancelled, phase.rawValue)
            XCTAssertEqual(session.selfCompactState.latest?.noteDelivery, .notSent, phase.rawValue)
            XCTAssertEqual(session.selfCompactState.latest?.recoveryNote, Self.teardownNote, phase.rawValue)
            XCTAssertFalse(session.selfCompactState.blocksAutomaticWake, phase.rawValue)
        }

        let unproven: [AgentSelfCompactAttempt.Phase] = [.dispatchingCompact, .awaitingCompactTurn, .acpSettling]
        let proven: [AgentSelfCompactAttempt.Phase] = [.awaitingNoteBoundary, .noteDispatchPending, .dispatchingNote]
        for (phase, verified) in unproven.map({ ($0, false) }) + proven.map({ ($0, true) }) {
            let session = AgentTabSession(tabID: UUID())
            session.selfCompactState = Self.holding(phase, verified: verified)
            session.selfCompactACPCommandItemIDs = [UUID()]
            session.isDirty = false
            session.cancelEphemeralRuntimeState()
            let state = session.selfCompactState
            XCTAssertNil(state.latest, phase.rawValue)
            XCTAssertEqual(state.active?.phase, .parked, phase.rawValue)
            XCTAssertEqual(state.active?.acpCompletionUnverified, verified ? nil : true, phase.rawValue)
            XCTAssertEqual(state.parkedNote?.frame, AgentSelfCompactNoteEnvelope.frame(Self.teardownNote), phase.rawValue)
            XCTAssertFalse(state.blocksOverseerDelivery, phase.rawValue)
            XCTAssertFalse(state.blocksManagedStop, phase.rawValue)
            XCTAssertNil(session.selfCompactNativeCompletion, phase.rawValue)
            XCTAssertNil(session.selfCompactACPCommandItemIDs, phase.rawValue)
            XCTAssertTrue(session.isDirty, phase.rawValue)
        }

        // A started send is owned by its provider seam, which always settles it; a parked note is
        // already free of every hold except Auto-wake, which the next ordinary send clears.
        for untouched in [Self.holding(.dispatchingNote, verified: true, noteStarted: true), Self.holding(.parked)] {
            let session = AgentTabSession(tabID: UUID())
            session.selfCompactState = untouched
            session.cancelEphemeralRuntimeState()
            XCTAssertEqual(session.selfCompactState, untouched)
        }
    }

    func testNotePolicyIsByteBoundedAndPreservesBody() {
        let exact = String(repeating: "x", count: 8192)
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: exact), .valid(byteCount: 8192))
        XCTAssertEqual(
            AgentSessionSelfCompactNotePolicy.validation(of: exact + "x"),
            .tooLong(byteCount: 8193, maximum: 8192)
        )
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: " \t\r\n "), .empty)
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: "a\u{0000}b"), .invalidScalar)
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: "a\u{0085}b"), .invalidScalar)
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: "a\t\r\nb"), .valid(byteCount: 5))
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.validation(of: String(repeating: "😀", count: 2048)), .valid(byteCount: 8192))

        let body = "  /compact\r\nKeep  two spaces\t😀  "
        let expected = SHA256.hash(data: Data(("agent_self.compact/v1\n" + body).utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(AgentSessionSelfCompactNotePolicy.digest(of: body), expected)
        XCTAssertNotEqual(AgentSessionSelfCompactNotePolicy.digest(of: body), AgentSessionSelfCompactNotePolicy.digest(of: body.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func testActiveAndLatestIdempotencyHorizon() throws {
        var state = AgentSelfCompactState()
        let first = try XCTUnwrap(state.reserve(note: "first", idempotencyKey: "same").scheduledAttempt)
        XCTAssertEqual(state.reserve(note: "first", idempotencyKey: "same"), .duplicate(first.id))
        XCTAssertEqual(state.reserve(note: "changed", idempotencyKey: "same"), .conflict)
        XCTAssertEqual(state.reserve(note: "second", idempotencyKey: "other"), .alreadyPending)
        state.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
        XCTAssertNil(state.active)
        XCTAssertEqual(state.reserve(note: "first", idempotencyKey: "same"), .duplicate(first.id))
        XCTAssertEqual(state.reserve(note: "changed", idempotencyKey: "same"), .conflict)
        let second = try XCTUnwrap(state.reserve(note: "second", idempotencyKey: "other").scheduledAttempt)
        XCTAssertNotEqual(second.id, first.id)
        state.settle(.failed, noteDelivery: .notSent, completionVerified: false)
        // The contract intentionally retains only the active and latest keys.
        XCTAssertNotNil(state.reserve(note: "first", idempotencyKey: "same").scheduledAttempt)
    }

    func testColdDecodeConvertsEveryRestoredPhaseIncludingParkedToNonExecutingRecovery() throws {
        for phase in AgentSelfCompactAttempt.Phase.allCases {
            var session = AgentSession(name: "Cold", autoEditEnabled: true)
            var state = AgentSelfCompactState()
            let attempt = try XCTUnwrap(state.reserve(note: "verbatim\n  note", idempotencyKey: "key").scheduledAttempt)
            state.active?.phase = phase
            if phase == .dispatchingNote { state.active?.noteDispatchStarted = true }
            session.selfCompactState = state
            let restored = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
            XCTAssertNil(restored.selfCompactState?.active, "\(phase)")
            XCTAssertEqual(restored.selfCompactState?.latest?.outcome, .recoveryRequired, "\(phase)")
            XCTAssertEqual(restored.selfCompactState?.latest?.requestID, attempt.id, "\(phase)")
            XCTAssertEqual(restored.selfCompactState?.status?.recoveryNote, "verbatim\n  note", "\(phase)")
            let expectedDelivery: AgentSelfCompactSettlement.NoteDelivery = switch phase {
            case .parked, .dispatchingNote: .deliveryUnknown
            default: .notSent
            }
            XCTAssertEqual(restored.selfCompactState?.status?.noteDelivery, expectedDelivery, "\(phase)")
            XCTAssertTrue(restored.selfCompactNeedsRecoveryRewrite, "\(phase)")
        }
    }

    func testColdRestoreTreatsUnsavedDispatchMarkerAsDeliveryUnknown() throws {
        var session = AgentSession(name: "Prepared", autoEditEnabled: true)
        var state = AgentSelfCompactState()
        _ = state.reserve(note: "recover", idempotencyKey: "prepared")
        state.active?.phase = .dispatchingNote
        state.active?.noteDispatchStarted = false
        session.selfCompactState = state
        let restored = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
        // Claude can accept the note while its debounced noteDispatchStarted save still lags.
        // A persisted dispatching phase cannot prove the transport was never attempted.
        XCTAssertEqual(restored.selfCompactState?.latest?.noteDelivery, .deliveryUnknown)
        XCTAssertEqual(restored.selfCompactState?.latest?.recoveryNote, "recover")
    }

    func testColdRestoreOfParkedSnapshotAfterOrdinaryAcceptanceIsDeliveryUnknown() throws {
        // Claude, Codex, and ACP ordinary sends all persist the parked state before their
        // attempt marker, then schedule (rather than require) the marker save at transport.
        for provider in [
            AgentSessionLinkCompactSupport.claudeCode,
            .codex,
            .acpAdvertisedCommand
        ] {
            var session = AgentSession(name: "Parked \(provider.rawValue)", autoEditEnabled: true)
            var state = AgentSelfCompactState()
            let attempt = try XCTUnwrap(state.reserve(
                note: "recover once", idempotencyKey: "parked-\(provider.rawValue)"
            ).scheduledAttempt)
            state.active?.admittedSupport = provider
            state.active?.phase = .parked
            session.selfCompactState = state
            let durableBeforeSend = try JSONEncoder().encode(session)

            // Hold the durable snapshot while the live ordinary turn enters transport and is
            // accepted. The debounced marker/settlement save has not committed at crash time.
            let dispatchID = AgentSelfCompactionDispatchID(requestID: attempt.id, stage: .note)
            XCTAssertTrue(state.noteWillAttempt(dispatchID))
            XCTAssertTrue(state.noteAccepted(dispatchID))
            XCTAssertEqual(state.latest?.noteDelivery, .prepended)

            let restored = try JSONDecoder().decode(AgentSession.self, from: durableBeforeSend)
            XCTAssertNil(restored.selfCompactState?.active)
            XCTAssertEqual(restored.selfCompactState?.latest?.noteDelivery, .deliveryUnknown, provider.rawValue)
            XCTAssertEqual(restored.selfCompactState?.latest?.recoveryNote, "recover once")
            var retry = try XCTUnwrap(restored.selfCompactState)
            XCTAssertEqual(retry.reserve(
                note: "recover once", idempotencyKey: "parked-\(provider.rawValue)"
            ), .duplicate(attempt.id))
        }
    }

    func testMalformedOptionalRecordsDoNotDiscardSession() throws {
        let base = try JSONEncoder().encode(AgentSession(name: "Still here", autoEditEnabled: true))
        for malformed in [
            "{\"unknown\":true}",
            "{\"version\":99,\"active\":{}}",
            "{\"version\":1,\"active\":{\"note\":42,\"phase\":\"scheduled\"}}",
            "{\"version\":1,\"active\":{\"note\":\"\(String(repeating: "x", count: 8193))\",\"phase\":\"parked\"}}"
        ] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
            object["selfCompactState"] = try JSONSerialization.jsonObject(with: Data(malformed.utf8))
            let restored = try JSONDecoder().decode(AgentSession.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored.name, "Still here")
            XCTAssertNil(restored.selfCompactState?.active)
            XCTAssertTrue(restored.selfCompactPersistenceWarning)
            XCTAssertEqual(restored.selfCompactState?.latest?.outcome, .recoveryRequired)
        }
    }

    func testColdRestorePreservesUnknownNoteDeliveryWithoutRetry() throws {
        var session = AgentSession(name: "Ambiguous", autoEditEnabled: true)
        var state = AgentSelfCompactState()
        let attempt = try XCTUnwrap(state.reserve(note: "exact body", idempotencyKey: "same").scheduledAttempt)
        state.active?.phase = .dispatchingNote
        state.active?.noteDispatchStarted = true
        session.selfCompactState = state

        let restored = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(restored.selfCompactState?.active)
        XCTAssertEqual(restored.selfCompactState?.latest?.outcome, .recoveryRequired)
        XCTAssertEqual(restored.selfCompactState?.latest?.noteDelivery, .deliveryUnknown)
        XCTAssertEqual(restored.selfCompactState?.latest?.recoveryNote, "exact body")
        var retry = try XCTUnwrap(restored.selfCompactState)
        XCTAssertEqual(retry.reserve(note: "exact body", idempotencyKey: "same"), .duplicate(attempt.id))
    }

    func testMalformedRecordIsBackedUpBeforeRepair() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("self-compact-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = AgentSession(name: "Preserve source", autoEditEnabled: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        object["selfCompactState"] = ["version": 99, "note": "original recovery bytes"]
        let original = try JSONSerialization.data(withJSONObject: object)
        let fileURL = directory.appendingPathComponent("AgentSession-\(session.id.uuidString).json")
        try original.write(to: fileURL)

        let loaded = try await AgentSessionDataService().loadAgentSession(from: fileURL)
        XCTAssertEqual(loaded.name, "Preserve source")
        XCTAssertTrue(loaded.selfCompactPersistenceWarning)
        XCTAssertEqual(loaded.selfCompactState?.latest?.outcome, .recoveryRequired)
        let backupDirectory = directory.appendingPathComponent(".self-compact-recovery")
        let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
        let repaired = try JSONDecoder().decode(AgentSession.self, from: Data(contentsOf: fileURL))
        XCTAssertFalse(repaired.selfCompactPersistenceWarning)
        XCTAssertEqual(repaired.selfCompactState?.latest?.outcome, .recoveryRequired)
    }

    func testRepeatedMaximumSizeRetryHasBoundedCost() throws {
        let note = String(repeating: "😀", count: 2048)
        var state = AgentSelfCompactState()
        let first = try XCTUnwrap(state.reserve(note: note, idempotencyKey: "retry").scheduledAttempt)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0 ..< 1000 {
            XCTAssertEqual(state.reserve(note: note, idempotencyKey: "retry"), .duplicate(first.id))
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 5)
        XCTAssertEqual(state.active?.note, note)
    }
}

private extension AgentSelfCompactState.Reservation {
    var scheduledAttempt: AgentSelfCompactAttempt? {
        if case let .scheduled(attempt) = self { return attempt }
        return nil
    }
}
