import Foundation

/// Request-correlated native completion and one-shot continuation. The injectable clock makes
/// the 300-second native deadline and the 90-second ACP settle testable without wall-clock waits.
/// Either expiring parks the note as unverified; neither sends it.
///
/// ACP completion is best-effort. A completed command turn, however long it took, is not verified
/// compaction. Only a vouched context drop is, and a settle timeout parks the note instead of
/// sending one.
@MainActor
final class AgentSelfCompactNativeCompletionCoordinator {
    typealias State = AgentSelfCompactState
    typealias NoteDispatch = @MainActor (
        _ requestID: UUID,
        _ stillAdmissible: @escaping @MainActor () -> Bool
    ) async -> Bool

    private let load: @MainActor () -> State
    private let store: @MainActor (State) -> Void
    private let isCurrentOwner: @MainActor (AgentSelfCompactOwner) -> Bool
    private let dispatchNote: NoteDispatch
    private let sleep: @MainActor (Duration) async -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private var deadlineTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var compactBoundAt: [UUID: ContinuousClock.Instant] = [:]
    private var acpTeardownSettled: (@MainActor () -> Bool)?

    init(
        load: @escaping @MainActor () -> State,
        store: @escaping @MainActor (State) -> Void,
        isCurrentOwner: @escaping @MainActor (AgentSelfCompactOwner) -> Bool,
        dispatchNote: @escaping NoteDispatch,
        sleep: @escaping @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.load = load
        self.store = store
        self.isCurrentOwner = isCurrentOwner
        self.dispatchNote = dispatchNote
        self.sleep = sleep
        self.now = now
    }

    @discardableResult
    func bindCompact(
        _ dispatchID: AgentSelfCompactionDispatchID,
        runID: UUID?,
        runAttemptID: UUID?
    ) -> Bool {
        var state = load()
        guard state.bindCompactRun(dispatchID, runID: runID, attemptID: runAttemptID) else { return false }
        store(state)
        compactBoundAt[dispatchID.requestID] = now()
        deadlineTask?.cancel()
        holdTask?.cancel()
        holdTask = nil
        deadlineTask = Task { @MainActor [self] in
            await sleep(.seconds(300))
            guard !Task.isCancelled else { return }
            var current = load()
            guard current.active?.id == dispatchID.requestID,
                  current.active?.phase == .dispatchingCompact
                  || current.active?.phase == .awaitingCompactTurn
            else { return }
            if let owner = current.active?.owner, !isCurrentOwner(owner) {
                current.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
            } else {
                // A slow native compaction may still finish. Like an unverified ACP turn, keep the
                // continuation parked for the next ordinary send rather than dropping it into
                // recovery; a late command terminal no longer matches and never sends it.
                current.active?.acpCompletionUnverified = true
                current.active?.phase = .parked
            }
            store(current)
        }
        return true
    }

    /// The ACP row baseline is consumed only for this accepted command turn. An unrelated,
    /// duplicate, or rejected publication must leave it available for the real terminal.
    func acceptsCompactTerminal(
        _ revision: AgentRunTerminalCommitRevision,
        publication: AgentRunTerminalPublicationResult
    ) -> Bool {
        guard let attempt = load().active,
              attempt.admittedSupport == .acpAdvertisedCommand,
              attempt.phase == .dispatchingCompact || attempt.phase == .awaitingCompactTurn,
              attempt.compactRunID == revision.expectedRunID,
              attempt.compactRunAttemptID == revision.ownership.attemptID,
              case .accepted(successorEpoch: nil) = publication
        else { return false }
        return true
    }

    func compactTurnSettled(
        revision: AgentRunTerminalCommitRevision,
        publication: AgentRunTerminalPublicationResult,
        teardownSettled: @escaping @MainActor () -> Bool,
        assistantOrToolRowCount: Int? = nil,
        vouchedTokenCount: Int? = nil
    ) {
        var state = load()
        guard let attempt = state.active,
              attempt.phase == .dispatchingCompact || attempt.phase == .awaitingCompactTurn,
              let owner = attempt.owner,
              attempt.compactRunID == revision.expectedRunID,
              attempt.compactRunAttemptID == revision.ownership.attemptID
        else { return }
        guard case .accepted(successorEpoch: nil) = publication else {
            if case .rejected = publication { return }
            deadlineTask?.cancel()
            state.settle(.completionUnverified, noteDelivery: .notSent, completionVerified: false)
            store(state)
            return
        }
        deadlineTask?.cancel()
        guard isCurrentOwner(owner) else {
            state.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
            store(state)
            return
        }
        guard revision.successorKind == nil else {
            state.active?.phase = .parked
            store(state)
            return
        }
        if attempt.admittedSupport == .acpAdvertisedCommand {
            classifyACPCommandTurn(
                requestID: attempt.id,
                owner: owner,
                terminalCompleted: revision.terminalState == .completed,
                assistantOrToolRowCount: assistantOrToolRowCount,
                vouchedTokenCount: vouchedTokenCount,
                teardownSettled: teardownSettled
            )
            return
        }
        let succeeded = revision.terminalState == .completed
            && (attempt.admittedSupport == .claudeCode || attempt.compactTurnSucceeded == true)
        guard succeeded else {
            state.settle(.failed, noteDelivery: .notSent, completionVerified: false)
            store(state)
            return
        }
        state.active?.compactTurnSucceeded = true
        state.active?.phase = .awaitingNoteBoundary
        store(state)
        noteTask = Task { @MainActor [self] in
            await beginNote(requestID: attempt.id, owner: owner, teardownSettled: teardownSettled)
        }
    }

    /// A writer can bind after the note pipeline starts but before its physical send. Release the
    /// hold only while the note is provably unattempted; an attempted send remains ambiguous.
    @discardableResult
    func cancelUnattemptedNoteIfOwnerLost(_ dispatchID: AgentSelfCompactionDispatchID) -> Bool {
        var state = load()
        guard dispatchID.stage == .note,
              let attempt = state.active,
              attempt.id == dispatchID.requestID,
              attempt.phase == .noteDispatchPending || attempt.phase == .dispatchingNote || attempt.phase == .parked,
              !attempt.noteDispatchStarted,
              let owner = attempt.owner,
              !isCurrentOwner(owner)
        else { return false }
        noteTask?.cancel()
        state.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
        store(state)
        return true
    }

    func cancelRuntimeWork() {
        deadlineTask?.cancel()
        deadlineTask = nil
        holdTask?.cancel()
        holdTask = nil
        noteTask?.cancel()
        noteTask = nil
        acpTeardownSettled = nil
    }

    /// A usage report during the ACP settle. Anything other than a strictly lower vouch is ignored,
    /// including a report that arrives after the deadline has already parked the note.
    func noteVouchedContextCount(_ tokens: Int?) {
        let state = load()
        guard state.active?.phase == .acpSettling,
              let requestID = state.active?.id,
              let owner = state.active?.owner,
              let teardown = acpTeardownSettled,
              AgentSelfCompactInstantReturn.isVouchedDrop(
                  before: state.active?.usedTokensBeforeCompact,
                  current: tokens
              )
        else { return }
        beginVerifiedACPNote(requestID: requestID, owner: owner, teardownSettled: teardown)
    }

    /// An ordinary accepted input may win after native dispatch. It carries the parked note on
    /// its own physical send; the maintenance worker never races it with an extra prompt.
    func supersedeForOrdinaryInput() {
        holdTask?.cancel()
        holdTask = nil
        acpTeardownSettled = nil
        var state = load()
        guard let attempt = state.active,
              attempt.phase != .scheduled,
              attempt.phase != .compactDispatchPending,
              attempt.phase != .parked,
              !attempt.noteDispatchStarted
        else { return }
        deadlineTask?.cancel()
        if let owner = attempt.owner, !isCurrentOwner(owner) {
            state.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
        } else {
            state.active?.phase = .parked
        }
        store(state)
    }

    private func classifyACPCommandTurn(
        requestID: UUID,
        owner: AgentSelfCompactOwner,
        terminalCompleted: Bool,
        assistantOrToolRowCount: Int?,
        vouchedTokenCount: Int?,
        teardownSettled: @escaping @MainActor () -> Bool
    ) {
        guard terminalCompleted else {
            var state = load()
            guard state.active?.id == requestID else { return }
            state.settle(.failed, noteDelivery: .notSent, completionVerified: false)
            store(state)
            return
        }
        let before = load().active?.usedTokensBeforeCompact
        if AgentSelfCompactInstantReturn.isVouchedDrop(before: before, current: vouchedTokenCount) {
            beginVerifiedACPNote(requestID: requestID, owner: owner, teardownSettled: teardownSettled)
            return
        }
        let instant = AgentSelfCompactInstantReturn.isInstantReturn(
            elapsed: elapsedSinceCompactBind(requestID),
            assistantOrToolRowCount: assistantOrToolRowCount
        )
        guard instant else {
            parkACPUnverified(requestID)
            return
        }
        var state = load()
        guard state.active?.id == requestID,
              state.active?.phase == .dispatchingCompact || state.active?.phase == .awaitingCompactTurn
        else { return }
        state.active?.phase = .acpSettling
        store(state)
        acpTeardownSettled = teardownSettled
        holdTask?.cancel()
        holdTask = Task { @MainActor [self] in
            await sleep(AgentSelfCompactInstantReturn.settleDuration)
            guard !Task.isCancelled else { return }
            parkACPUnverified(requestID)
        }
    }

    private func beginVerifiedACPNote(
        requestID: UUID,
        owner: AgentSelfCompactOwner,
        teardownSettled: @escaping @MainActor () -> Bool
    ) {
        holdTask?.cancel()
        holdTask = nil
        acpTeardownSettled = nil
        var state = load()
        guard state.active?.id == requestID else { return }
        switch state.active?.phase {
        case .dispatchingCompact, .awaitingCompactTurn, .acpSettling:
            break
        default:
            return
        }
        state.active?.acpCompletionUnverified = nil
        state.active?.compactTurnSucceeded = true
        state.active?.phase = .awaitingNoteBoundary
        store(state)
        noteTask?.cancel()
        noteTask = Task { @MainActor [self] in
            await beginNote(requestID: requestID, owner: owner, teardownSettled: teardownSettled)
        }
    }

    private func parkACPUnverified(_ requestID: UUID) {
        var state = load()
        guard state.active?.id == requestID, state.active?.noteDispatchStarted != true else { return }
        switch state.active?.phase {
        case .acpSettling, .awaitingCompactTurn, .dispatchingCompact:
            break
        default:
            return
        }
        state.active?.acpCompletionUnverified = true
        state.active?.phase = .parked
        acpTeardownSettled = nil
        store(state)
    }

    private func elapsedSinceCompactBind(_ requestID: UUID) -> Duration? {
        guard let start = compactBoundAt[requestID] else { return nil }
        return start.duration(to: now())
    }

    private func beginNote(
        requestID: UUID,
        owner: AgentSelfCompactOwner,
        teardownSettled: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 600 {
            guard load().active?.id == requestID,
                  load().active?.phase == .awaitingNoteBoundary
            else { return }
            guard isCurrentOwner(owner) else {
                var state = load()
                state.settle(.cancelled, noteDelivery: .notSent, completionVerified: true)
                store(state)
                return
            }
            if teardownSettled() { break }
            await sleep(.milliseconds(100))
            guard !Task.isCancelled else { return }
            await Task.yield()
        }
        var state = load()
        guard state.active?.id == requestID,
              state.active?.phase == .awaitingNoteBoundary
        else { return }
        guard isCurrentOwner(owner) else {
            state.settle(.cancelled, noteDelivery: .notSent, completionVerified: true)
            store(state)
            return
        }
        guard teardownSettled() else {
            state.active?.phase = .parked
            store(state)
            return
        }
        state.active?.phase = .noteDispatchPending
        store(state)
        let didStart = await dispatchNote(requestID) { [self] in
            let current = load().active
            return current?.id == requestID
                && (current?.phase == .noteDispatchPending || current?.phase == .dispatchingNote)
                && current?.noteDispatchStarted == false
                && isCurrentOwner(owner)
        }
        state = load()
        guard state.active?.id == requestID else { return }
        if !didStart, state.active?.noteDispatchStarted == false {
            if !isCurrentOwner(owner) {
                state.settle(.cancelled, noteDelivery: .notSent, completionVerified: false)
            } else {
                state.active?.phase = .parked
            }
            store(state)
        }
    }
}
