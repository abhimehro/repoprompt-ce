import Foundation
@testable import RepoPromptApp
import RepoPromptShared
import XCTest

@MainActor
final class ContextBuilderRunStateContractTests: XCTestCase {
    func testFinalCommitAndTerminalClaimsAreExactlyOnce() {
        let tabID = UUID()
        let session = ContextBuilderAgentViewModel.TabSession(tabID: tabID)
        let record = makeRecord(
            tabID: tabID,
            session: session,
            ownership: session.beginRunAttempt(source: "claim-contract")
        )

        XCTAssertTrue(record.claimFinalContextCommit())
        XCTAssertTrue(record.finalContextCommitClaimed)
        XCTAssertFalse(record.claimFinalContextCommit())
        XCTAssertTrue(record.claimTerminal(.completed))
        XCTAssertFalse(record.claimTerminal(.cancelled))
    }

    func testRouteSettlementCoordinatorClaimsFirstSettlement() async {
        let routeFirst = ContextBuilderRouteSettlementCoordinator(
            maxBufferedTextCharacters: 5,
            maxBufferedEventCount: 5
        )
        XCTAssertTrue(routeFirst.settle(.routed))
        XCTAssertFalse(routeFirst.settle(.failedWithoutRoute("provider failed")))
        let routeFirstSettlement = await routeFirst.waitForSettlement()
        XCTAssertEqual(routeFirstSettlement, .routed)

        let terminalFirst = ContextBuilderRouteSettlementCoordinator(
            maxBufferedTextCharacters: 5,
            maxBufferedEventCount: 5
        )
        XCTAssertTrue(terminalFirst.settle(.failedWithoutRoute("provider failed")))
        XCTAssertFalse(terminalFirst.settle(.routed))
        let terminalFirstSettlement = await terminalFirst.waitForSettlement()
        XCTAssertEqual(
            terminalFirstSettlement,
            .failedWithoutRoute("provider failed")
        )
    }

    func testRouteSettlementCoordinatorBoundsBufferedPayloadsAndEvents() {
        let payloadBounded = ContextBuilderRouteSettlementCoordinator(
            maxBufferedTextCharacters: 28,
            maxBufferedEventCount: 10
        )
        payloadBounded.appendWhilePending(
            AIStreamResult(type: "content", text: "1234")
        )
        payloadBounded.appendWhilePending(
            AIStreamResult(type: "lifecycle", text: "retrying")
        )
        payloadBounded.appendWhilePending(
            AIStreamResult(type: "content", text: "6789")
        )

        let payloadResult = payloadBounded.drainBufferedEvents()
        XCTAssertEqual(payloadResult.events.map(\.type), ["lifecycle", "content"])
        XCTAssertEqual(payloadResult.events.map(\.text), ["retrying", "6789"])
        XCTAssertEqual(payloadResult.droppedTextCharacterCount, 11)
        XCTAssertEqual(payloadResult.droppedNonterminalEventCount, 1)

        let eventBounded = ContextBuilderRouteSettlementCoordinator(
            maxBufferedTextCharacters: 100,
            maxBufferedEventCount: 3
        )
        for index in 0 ..< 20 {
            eventBounded.appendWhilePending(
                AIStreamResult(type: "lifecycle", text: "retry-\(index)")
            )
            eventBounded.appendWhilePending(
                AIStreamResult(type: "content", text: "")
            )
        }
        eventBounded.appendWhilePending(
            AIStreamResult(type: "tool_call", text: "call")
        )
        eventBounded.appendWhilePending(
            AIStreamResult(type: "error", text: "provider warning")
        )
        eventBounded.appendWhilePending(
            AIStreamResult(type: "tool_result", text: "result")
        )

        let eventResult = eventBounded.drainBufferedEvents()
        XCTAssertEqual(
            eventResult.events.map(\.type),
            ["tool_call", "error", "tool_result"]
        )
        XCTAssertEqual(eventResult.droppedNonterminalEventCount, 40)
    }

    func testCancellationDuringFinalCommitDefersUntilSafeBoundary() {
        let tabID = UUID()
        let session = ContextBuilderAgentViewModel.TabSession(tabID: tabID)
        let record = makeRecord(
            tabID: tabID,
            session: session,
            ownership: session.beginRunAttempt(source: "deferred-cancel")
        )
        let settlementPolicy = ContextBuilderRunCancellationSettlementPolicy(
            waiterResolution: .snapshot,
            saveHistory: true
        )

        XCTAssertTrue(record.claimFinalContextCommit())
        XCTAssertEqual(
            record.requestCancellation(
                deferredSettlementPolicy: settlementPolicy
            ),
            .deferredUntilFinalContextCommitCompletes
        )
        XCTAssertEqual(
            record.cancellationState,
            .deferredUntilFinalContextCommitCompletes
        )
        XCTAssertEqual(
            record.deferredCancellationSettlementPolicy,
            settlementPolicy
        )
        XCTAssertTrue(record.hasDeferredCancellationPending)
        XCTAssertEqual(
            record.consumeDeferredCancellationAtSafeBoundary(),
            settlementPolicy
        )
        XCTAssertEqual(record.cancellationState, .applied)
        XCTAssertNil(record.consumeDeferredCancellationAtSafeBoundary())
        XCTAssertTrue(record.claimTerminal(.cancelled))
        XCTAssertFalse(record.claimTerminal(.completed))
    }

    func testCancelCommitRaceResolvesExactlyOnceForEitherOrdering() {
        let settlementPolicy = ContextBuilderRunCancellationSettlementPolicy(
            waiterResolution: .snapshot,
            saveHistory: true
        )
        let cancelFirstTabID = UUID()
        let cancelFirstSession = ContextBuilderAgentViewModel.TabSession(
            tabID: cancelFirstTabID
        )
        let cancelFirst = makeRecord(
            tabID: cancelFirstTabID,
            session: cancelFirstSession,
            ownership: cancelFirstSession.beginRunAttempt(source: "cancel-first")
        )

        XCTAssertEqual(
            cancelFirst.requestCancellation(
                deferredSettlementPolicy: settlementPolicy
            ),
            .settleImmediately
        )
        XCTAssertFalse(cancelFirst.claimFinalContextCommit())
        XCTAssertTrue(cancelFirst.claimTerminal(.cancelled))
        XCTAssertFalse(cancelFirst.claimTerminal(.completed))

        let commitFirstTabID = UUID()
        let commitFirstSession = ContextBuilderAgentViewModel.TabSession(
            tabID: commitFirstTabID
        )
        let commitFirst = makeRecord(
            tabID: commitFirstTabID,
            session: commitFirstSession,
            ownership: commitFirstSession.beginRunAttempt(source: "commit-first")
        )

        XCTAssertTrue(commitFirst.claimFinalContextCommit())
        XCTAssertEqual(
            commitFirst.requestCancellation(
                deferredSettlementPolicy: settlementPolicy
            ),
            .deferredUntilFinalContextCommitCompletes
        )
        XCTAssertEqual(
            commitFirst.consumeDeferredCancellationAtSafeBoundary(),
            settlementPolicy
        )
        XCTAssertTrue(commitFirst.claimTerminal(.cancelled))
        XCTAssertFalse(commitFirst.claimTerminal(.completed))
    }

    func testPreCommitCancellationRemainsImmediate() {
        let tabID = UUID()
        let session = ContextBuilderAgentViewModel.TabSession(tabID: tabID)
        let record = makeRecord(
            tabID: tabID,
            session: session,
            ownership: session.beginRunAttempt(source: "pre-commit-cancel")
        )
        let settlementPolicy = ContextBuilderRunCancellationSettlementPolicy(
            waiterResolution: .cancellationError,
            saveHistory: false
        )

        XCTAssertEqual(
            record.requestCancellation(
                deferredSettlementPolicy: settlementPolicy
            ),
            .settleImmediately
        )
        XCTAssertEqual(record.cancellationState, .requested)
        XCTAssertNil(record.deferredCancellationSettlementPolicy)
        XCTAssertFalse(record.hasDeferredCancellationPending)
        XCTAssertFalse(record.claimFinalContextCommit())
        XCTAssertTrue(record.claimTerminal(.cancelled))
    }

    func testLogicalReleaseAdmitsSuccessorAndRejectsOldEvents() {
        let registry = ContextBuilderRunRegistry()
        let tabID = UUID()
        let session = ContextBuilderAgentViewModel.TabSession(tabID: tabID)
        let firstOwnership = session.beginRunAttempt(source: "first")
        let first = makeRecord(
            tabID: tabID,
            session: session,
            ownership: firstOwnership
        )

        XCTAssertTrue(registry.register(first))
        XCTAssertTrue(registry.acceptsEvents(from: first, currentSession: session))
        let blocked = makeRecord(
            tabID: tabID,
            session: session,
            ownership: firstOwnership
        )
        XCTAssertFalse(registry.register(blocked))
        XCTAssertTrue(first.claimTerminal(.cancelled))
        XCTAssertTrue(registry.releaseActiveSlot(for: first))

        let secondOwnership = session.beginRunAttempt(source: "second")
        let second = makeRecord(
            tabID: tabID,
            session: session,
            ownership: secondOwnership
        )
        XCTAssertTrue(registry.register(second))
        XCTAssertFalse(registry.acceptsEvents(from: first, currentSession: session))
        XCTAssertTrue(registry.acceptsEvents(from: second, currentSession: session))
    }

    private func makeRecord(
        tabID: UUID,
        session: ContextBuilderAgentViewModel.TabSession,
        ownership: AgentRunOwnership
    ) -> ContextBuilderRunRecord {
        ContextBuilderRunRecord(
            runID: UUID(),
            tabID: tabID,
            session: session,
            ownership: ownership,
            origin: .ui,
            agentKind: .claudeCode,
            modelRaw: AgentModel.defaultModel.rawValue
        )
    }
}
