import Foundation
@testable import RepoPromptApp
import RepoPromptDomainRuntime
import XCTest

@MainActor
final class MCPToolCatalogReadinessTests: XCTestCase {
    func testReadinessCoalescesLightweightScopeQueriesForOneTenAndOneHundredWaiters() async throws {
        #if DEBUG
            for waiterCount in [1, 10, 100] {
                let queryProbe = MCPReadinessScopePresenceProbe()
                let joinedCounter = MCPReadinessTestCounter()
                let readiness = MCPToolCatalogReadiness(
                    scopePresenceOperation: { requiredNames, scope in
                        await queryProbe.query(requiredNames: requiredNames, scope: scope)
                    },
                    windowStateOperation: { _ in
                        MCPToolCatalogReadiness.WindowRegistrationState(
                            toolsEnabled: true,
                            toolsRequested: true
                        )
                    },
                    checkJoinedOperation: { _ in
                        await joinedCounter.increment()
                    }
                )
                let waiters = (0 ..< waiterCount).map { _ in
                    Task { await readiness.awaitReady(windowID: 901, timeout: 5) }
                }

                do {
                    guard await queryProbe.waitUntilQueryEntered(1, timeout: .seconds(2)) else {
                        throw MCPReadinessTestTimeout(label: "first readiness scope query")
                    }
                    guard await joinedCounter.waitUntilAtLeast(waiterCount, timeout: .seconds(2)) else {
                        throw MCPReadinessTestTimeout(
                            label: "\(waiterCount) readiness callers joining the shared check"
                        )
                    }

                    let queryCountWhileBlocked = await queryProbe.queryCountValue()
                    XCTAssertEqual(
                        queryCountWhileBlocked,
                        1,
                        "\(waiterCount) concurrent waiters must share the initial application-scope query."
                    )

                    await queryProbe.releaseFirstQuery()
                    for waiter in waiters {
                        let ready = try await valueWithin(
                            waiter,
                            timeout: .seconds(2),
                            label: "coalesced readiness waiter"
                        )
                        XCTAssertTrue(ready)
                    }
                    let finalQueryCount = await queryProbe.queryCountValue()
                    XCTAssertEqual(
                        finalQueryCount,
                        2,
                        "Readiness should perform one application and one window scope-presence query regardless of waiter count."
                    )
                } catch {
                    waiters.forEach { $0.cancel() }
                    await queryProbe.releaseFirstQuery()
                    for waiter in waiters {
                        _ = try? await valueWithin(
                            waiter,
                            timeout: .seconds(2),
                            label: "coalescing cleanup"
                        )
                    }
                    let observedJoins = await joinedCounter.countValue()
                    let observedQueries = await queryProbe.queryCountValue()
                    XCTFail(
                        "Readiness coalescing setup failed for \(waiterCount) waiters: \(error); "
                            + "joined=\(observedJoins), queries=\(observedQueries)"
                    )
                }
            }
        #else
            throw XCTSkip("Readiness operation-count probes require DEBUG test seams.")
        #endif
    }

    func testReadinessCallerDeadlineDoesNotCancelSharedCheck() async throws {
        #if DEBUG
            let queryProbe = MCPReadinessScopePresenceProbe()
            let joinedCounter = MCPReadinessTestCounter()
            let readiness = MCPToolCatalogReadiness(
                scopePresenceOperation: { requiredNames, scope in
                    await queryProbe.query(requiredNames: requiredNames, scope: scope)
                },
                windowStateOperation: { _ in
                    MCPToolCatalogReadiness.WindowRegistrationState(
                        toolsEnabled: true,
                        toolsRequested: true
                    )
                },
                checkJoinedOperation: { _ in
                    await joinedCounter.increment()
                }
            )
            let longWaiters = (0 ..< 2).map { _ in
                Task { await readiness.awaitReady(windowID: 902, timeout: 5) }
            }
            let shortWaiter = Task {
                await readiness.awaitReady(windowID: 902, timeout: 0.05)
            }
            var lateWaiter: Task<Bool, Never>?

            do {
                guard await queryProbe.waitUntilQueryEntered(1, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "blocked readiness scope query")
                }
                guard await joinedCounter.waitUntilAtLeast(3, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "initial readiness callers joining the shared check")
                }

                let shortResult = try await valueWithin(
                    shortWaiter,
                    timeout: .seconds(2),
                    label: "short readiness caller deadline"
                )
                XCTAssertFalse(
                    shortResult,
                    "The caller-local deadline must expire while the shared query remains held."
                )
                let queryCountAfterShortDeadline = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    queryCountAfterShortDeadline,
                    1,
                    "A timed-out caller must not start a replacement query or cancel shared work."
                )

                let lateWaiterTask = Task {
                    await readiness.awaitReady(windowID: 902, timeout: 5)
                }
                lateWaiter = lateWaiterTask
                guard await joinedCounter.waitUntilAtLeast(4, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "late readiness caller joining after the short deadline")
                }
                let queryCountAfterLateJoin = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    queryCountAfterLateJoin,
                    1,
                    "The shared check must remain registered for callers arriving after another caller times out."
                )

                await queryProbe.releaseFirstQuery()
                for waiter in longWaiters {
                    let ready = try await valueWithin(
                        waiter,
                        timeout: .seconds(2),
                        label: "long readiness waiter"
                    )
                    XCTAssertTrue(ready)
                }
                let lateReady = try await valueWithin(
                    lateWaiterTask,
                    timeout: .seconds(2),
                    label: "late readiness waiter"
                )
                XCTAssertTrue(lateReady)
                let finalQueryCount = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    finalQueryCount,
                    2,
                    "The surviving shared check should issue exactly one application and one window query."
                )
            } catch {
                longWaiters.forEach { $0.cancel() }
                shortWaiter.cancel()
                lateWaiter?.cancel()
                await queryProbe.releaseFirstQuery()
                for waiter in longWaiters {
                    _ = try? await valueWithin(
                        waiter,
                        timeout: .seconds(2),
                        label: "caller-deadline cleanup"
                    )
                }
                _ = try? await valueWithin(
                    shortWaiter,
                    timeout: .seconds(2),
                    label: "short caller cleanup"
                )
                if let lateWaiter {
                    _ = try? await valueWithin(
                        lateWaiter,
                        timeout: .seconds(2),
                        label: "late caller cleanup"
                    )
                }
                let observedJoins = await joinedCounter.countValue()
                let observedQueries = await queryProbe.queryCountValue()
                XCTFail(
                    "Readiness caller-deadline setup failed: \(error); "
                        + "joined=\(observedJoins), queries=\(observedQueries)"
                )
            }
        #else
            throw XCTSkip("Readiness operation-count probes require DEBUG test seams.")
        #endif
    }

    func testReadinessRetiresHungGenerationBeforeAllowingLateGeneration() async throws {
        #if DEBUG
            let ownerRetirementProbe = MCPReadinessRetirementSleepProbe()
            let joinedCounter = MCPReadinessTestCounter()
            let retiredCounter = MCPReadinessTestCounter()
            let settledCounter = MCPReadinessTestCounter()
            let queryProbe = MCPReadinessScopePresenceProbe(holdSecondQuery: true)
            let readiness = MCPToolCatalogReadiness(
                scopePresenceOperation: { requiredNames, scope in
                    await queryProbe.query(requiredNames: requiredNames, scope: scope)
                },
                windowStateOperation: { _ in
                    MCPToolCatalogReadiness.WindowRegistrationState(
                        toolsEnabled: true,
                        toolsRequested: true
                    )
                },
                checkJoinedOperation: { _ in
                    await joinedCounter.increment()
                },
                sharedCheckRetirementSleep: { _ in
                    await ownerRetirementProbe.wait()
                },
                checkRetiredOperation: { _ in
                    await retiredCounter.increment()
                },
                checkSettledOperation: { _ in
                    await settledCounter.increment()
                }
            )

            let firstWaiter = Task {
                await readiness.awaitReady(windowID: 903, timeout: 0.05)
            }
            var lateWaiter: Task<Bool, Never>?
            var thirdWaiter: Task<Bool, Never>?

            do {
                guard await queryProbe.waitUntilQueryEntered(1, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "first held readiness query")
                }
                guard await ownerRetirementProbe.waitUntilFirstEntered(timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "first shared-check retirement owner")
                }
                guard await joinedCounter.waitUntilAtLeast(1, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "first readiness caller joining the shared check")
                }

                let firstResult = try await valueWithin(
                    firstWaiter,
                    timeout: .seconds(2),
                    label: "first caller deadline"
                )
                XCTAssertFalse(
                    firstResult,
                    "A caller timeout must return while the held shared attempt remains alive."
                )
                let queryCountAfterCallerTimeout = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    queryCountAfterCallerTimeout,
                    1,
                    "A caller timeout must not start a replacement query."
                )

                await ownerRetirementProbe.releaseFirst()
                guard await retiredCounter.waitUntilAtLeast(1, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "owner retirement of the first generation")
                }

                let lateWaiterTask = Task {
                    await readiness.awaitReady(windowID: 903, timeout: 5)
                }
                lateWaiter = lateWaiterTask
                guard await queryProbe.waitUntilQueryEntered(2, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "second-generation readiness query")
                }
                guard await joinedCounter.waitUntilAtLeast(2, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "late readiness caller joining the second generation")
                }

                await queryProbe.releaseFirstQuery()
                guard await settledCounter.waitUntilAtLeast(1, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "late settlement of the retired first generation")
                }
                let queryCountAfterStaleSettlement = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    queryCountAfterStaleSettlement,
                    3,
                    "The retired generation may finish late, but it must not start or remove another generation."
                )

                let thirdWaiterTask = Task {
                    await readiness.awaitReady(windowID: 903, timeout: 5)
                }
                thirdWaiter = thirdWaiterTask
                guard await joinedCounter.waitUntilAtLeast(3, timeout: .seconds(2)) else {
                    throw MCPReadinessTestTimeout(label: "third readiness caller joining the second generation")
                }
                let queryCountAfterThirdJoin = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    queryCountAfterThirdJoin,
                    3,
                    "A caller arriving while generation 2 is held must join it after generation 1 settles late."
                )

                await queryProbe.releaseSecondQuery()
                let lateResult = try await valueWithin(
                    lateWaiterTask,
                    timeout: .seconds(2),
                    label: "second-generation late waiter"
                )
                let thirdResult = try await valueWithin(
                    thirdWaiterTask,
                    timeout: .seconds(2),
                    label: "second-generation third waiter"
                )
                await ownerRetirementProbe.releaseLater()

                XCTAssertTrue(lateResult)
                XCTAssertTrue(thirdResult)
                let finalQueryCount = await queryProbe.queryCountValue()
                XCTAssertEqual(
                    finalQueryCount,
                    4,
                    "Generation 2 should perform exactly one global and one window scope query."
                )
            } catch {
                firstWaiter.cancel()
                lateWaiter?.cancel()
                thirdWaiter?.cancel()
                await queryProbe.releaseFirstQuery()
                await queryProbe.releaseSecondQuery()
                await ownerRetirementProbe.releaseFirst()
                await ownerRetirementProbe.releaseLater()
                _ = try? await valueWithin(
                    firstWaiter,
                    timeout: .seconds(2),
                    label: "retirement cleanup first waiter"
                )
                if let lateWaiter {
                    _ = try? await valueWithin(
                        lateWaiter,
                        timeout: .seconds(2),
                        label: "retirement cleanup late waiter"
                    )
                }
                if let thirdWaiter {
                    _ = try? await valueWithin(
                        thirdWaiter,
                        timeout: .seconds(2),
                        label: "retirement cleanup third waiter"
                    )
                }
                let observedJoins = await joinedCounter.countValue()
                let observedRetirements = await retiredCounter.countValue()
                let observedSettlements = await settledCounter.countValue()
                let observedQueries = await queryProbe.queryCountValue()
                XCTFail(
                    "Readiness retirement setup failed: \(error); "
                        + "joined=\(observedJoins), "
                        + "retired=\(observedRetirements), "
                        + "settled=\(observedSettlements), "
                        + "queries=\(observedQueries)"
                )
            }
        #else
            throw XCTSkip("Readiness retirement probes require DEBUG test seams.")
        #endif
    }
}

private struct MCPReadinessTestTimeout: Error, CustomStringConvertible {
    let label: String

    var description: String {
        "Timed out waiting for \(label)"
    }
}

private func valueWithin<Value: Sendable>(
    _ task: Task<Value, Never>,
    timeout: Duration,
    label: String
) async throws -> Value {
    let resultBox = MCPReadinessTestResultBox<Value>()
    let valueTask = Task {
        let value = await task.value
        await resultBox.resolve(value)
    }
    let timeoutTask = Task {
        do {
            // This is only a finite watchdog; explicit gates establish all test ordering.
            try await ContinuousClock().sleep(for: timeout)
        } catch {
            return
        }
        await resultBox.timeout()
    }
    let result = await resultBox.wait()
    valueTask.cancel()
    timeoutTask.cancel()
    guard let result else {
        throw MCPReadinessTestTimeout(label: label)
    }
    return result
}

private actor MCPReadinessTestResultBox<Value: Sendable> {
    private var resolved = false
    private var result: Value?
    private var continuation: CheckedContinuation<Value?, Never>?

    func wait() async -> Value? {
        if resolved {
            return result
        }
        return await withCheckedContinuation { continuation in
            if resolved {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: Value) {
        guard !resolved else { return }
        resolved = true
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }

    func timeout() {
        guard !resolved else { return }
        resolved = true
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

private actor MCPReadinessTestGate {
    private var hasEntered = false
    private var isOpen = false
    private var entryWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        hasEntered = true
        let entryWaiters = self.entryWaiters.values
        self.entryWaiters.removeAll()
        entryWaiters.forEach { $0.resume(returning: true) }

        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                openWaiters.append(continuation)
            }
        }
    }

    func waitUntilEntered(timeout: Duration) async -> Bool {
        if hasEntered {
            return true
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if hasEntered || Task.isCancelled {
                    continuation.resume(returning: hasEntered)
                    return
                }
                entryWaiters[waiterID] = continuation
                Task { [weak self] in
                    do {
                        try await ContinuousClock().sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.expireEntryWaiter(waiterID)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.expireEntryWaiter(waiterID)
            }
        }
    }

    func release() {
        guard !isOpen else { return }
        isOpen = true
        let openWaiters = self.openWaiters
        self.openWaiters.removeAll()
        openWaiters.forEach { $0.resume() }
    }

    private func expireEntryWaiter(_ waiterID: UUID) {
        guard let continuation = entryWaiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(returning: false)
    }
}

private actor MCPReadinessTestCounter {
    private struct Waiter {
        let minimum: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var count = 0
    private var waiters: [UUID: Waiter] = [:]

    func increment() {
        count += 1
        let readyWaiters = waiters.filter { $0.value.minimum <= count }
        readyWaiters.values.forEach { $0.continuation.resume(returning: true) }
        readyWaiters.keys.forEach { waiters.removeValue(forKey: $0) }
    }

    func countValue() -> Int {
        count
    }

    func waitUntilAtLeast(_ minimum: Int, timeout: Duration) async -> Bool {
        guard count < minimum else { return true }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if count >= minimum || Task.isCancelled {
                    continuation.resume(returning: count >= minimum)
                    return
                }
                waiters[waiterID] = Waiter(minimum: minimum, continuation: continuation)
                Task { [weak self] in
                    do {
                        try await ContinuousClock().sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.expire(waiterID)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.expire(waiterID)
            }
        }
    }

    private func expire(_ waiterID: UUID) {
        guard let waiter = waiters.removeValue(forKey: waiterID) else { return }
        waiter.continuation.resume(returning: false)
    }
}

private actor MCPReadinessScopePresenceProbe {
    private let holdSecondQuery: Bool
    private let firstQueryGate = MCPReadinessTestGate()
    private let secondQueryGate = MCPReadinessTestGate()
    private var queryCount = 0

    init(holdSecondQuery: Bool = false) {
        self.holdSecondQuery = holdSecondQuery
    }

    func query(
        requiredNames _: [String],
        scope _: MCPDomainToolRegistrationScope
    ) async -> MCPDomainToolScopePresence {
        queryCount += 1
        let queryNumber = queryCount
        if queryNumber == 1 {
            await firstQueryGate.arriveAndWait()
        } else if queryNumber == 2, holdSecondQuery {
            await secondQueryGate.arriveAndWait()
        }
        return MCPDomainToolScopePresence(revision: 1, isComplete: true)
    }

    func queryCountValue() -> Int {
        queryCount
    }

    func waitUntilQueryEntered(_ queryNumber: Int, timeout: Duration) async -> Bool {
        switch queryNumber {
        case 1:
            return await firstQueryGate.waitUntilEntered(timeout: timeout)
        case 2:
            return await secondQueryGate.waitUntilEntered(timeout: timeout)
        default:
            return false
        }
    }

    func releaseFirstQuery() async {
        await firstQueryGate.release()
    }

    func releaseSecondQuery() async {
        await secondQueryGate.release()
    }
}

private actor MCPReadinessRetirementSleepProbe {
    private let firstGate = MCPReadinessTestGate()
    private let laterGate = MCPReadinessTestGate()
    private var invocationCount = 0

    func wait() async {
        invocationCount += 1
        if invocationCount == 1 {
            await firstGate.arriveAndWait()
        } else {
            await laterGate.arriveAndWait()
        }
    }

    func waitUntilFirstEntered(timeout: Duration) async -> Bool {
        await firstGate.waitUntilEntered(timeout: timeout)
    }

    func releaseFirst() async {
        await firstGate.release()
    }

    func releaseLater() async {
        await laterGate.release()
    }
}
