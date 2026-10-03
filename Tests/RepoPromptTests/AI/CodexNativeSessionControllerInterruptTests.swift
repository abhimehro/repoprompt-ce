import Foundation
@testable import RepoPromptApp
import RepoPromptInstrumentation
import XCTest

final class CodexNativeSessionControllerInterruptTests: XCTestCase {
    func testActiveTurnMismatchParserMatrix() {
        let rows: [(description: String, expectedTurnID: String?)] = [
            ("turn/interrupt failed: expected active turn id `turn-old` but found `turn-new`", "turn-new"),
            ("network failed", nil),
            ("expected active turn id `old` but found ``", nil),
            ("expected active turn id `old` but found turn-new", nil)
        ]

        for row in rows {
            XCTAssertEqual(
                CodexNativeSessionController.activeTurnMismatchActualTurnID(fromErrorDescription: row.description),
                row.expectedTurnID,
                row.description
            )
        }
    }

    func testResolvedInterruptTurnIDMatrix() {
        XCTAssertNil(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed(nil)
            )
        )
        XCTAssertNil(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed(" \t\n")
            )
        )
        XCTAssertEqual(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .failed
            ),
            "stale-turn"
        )
        XCTAssertEqual(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed("fresh-turn")
            ),
            "fresh-turn"
        )
    }
}

final class CodexCLIProviderPerfRecorderTests: XCTestCase {
    private final class RecorderSpy: AgentModePerfRecording, @unchecked Sendable {
        private let fallback = NoopAgentModePerfRecorder()
        private let lock = NSLock()
        private var phases: [AgentPerfCodexLifecyclePhase] = []

        var isEnabled: Bool {
            true
        }

        func timestampMSIfEnabled() -> Double? {
            1
        }

        func timestampMS() -> Double {
            fallback.timestampMS()
        }

        func elapsedMS(since startMS: Double) -> Double {
            fallback.elapsedMS(since: startMS)
        }

        func formatMS(_ value: Double) -> String {
            fallback.formatMS(value)
        }

        func formatElapsedMS(since startMS: Double) -> String {
            fallback.formatElapsedMS(since: startMS)
        }

        func shortID(_ id: UUID?) -> String {
            fallback.shortID(id)
        }

        func counterKey(_ base: String, source: String?) -> String {
            fallback.counterKey(base, source: source)
        }

        func increment(_: String, tabID _: UUID?, by _: Int) {}
        func event(_: String, tabID _: UUID?, fields _: [String: String]) {}
        func durationEvent(_: String, startMS _: Double?, tabID _: UUID?, fields _: [String: String]) {}
        func recordStoreUpdate(_: String, published _: Bool, details _: [String: String]) {}
        func recordConversationReplay(_: AgentPerfConversationReplayEvent, startMS _: Double?) {}
        func beginSidebarDelete(_: AgentPerfSidebarDeleteBeginContext) -> UUID {
            UUID()
        }

        func markSidebarDeleteVisibleRemoved(tabID _: UUID, source _: String, fields _: [String: String]) {}
        func markSidebarDeleteAgentCleanupComplete(tabID _: UUID, source _: String, fields _: [String: String]) {}
        func markSidebarDeleteFullCleanupComplete(tabID _: UUID, source _: String, fields _: [String: String]) {}
        func cancelSidebarDeleteTracking(tabID _: UUID, source _: String, fields _: [String: String]) {}
        func recordSessionSnapshot(tabID _: UUID, fields _: [String: AgentPerfSnapshotValue]) {}
        func recordCodexLifecyclePhase(
            _ phase: AgentPerfCodexLifecyclePhase,
            outcome _: AgentPerfCodexLifecycleOutcome,
            startMS _: Double?,
            tabID _: UUID,
            transportGeneration _: UInt64?
        ) {
            lock.lock()
            phases.append(phase)
            lock.unlock()
        }

        func recordedPhases() -> [AgentPerfCodexLifecyclePhase] {
            lock.lock()
            defer { lock.unlock() }
            return phases
        }
    }

    func testDefaultInteractiveControllerReceivesProviderRecorder() async throws {
        let recorder = RecorderSpy()
        let provider = CodexCLIProvider(perfRecorder: recorder)
        let client = CodexAppServerClient()
        let controller = try XCTUnwrap(provider.makeInteractiveSessionController(
            appServerClient: client,
            excludeServers: [],
            requestTimeout: 10
        ) as? CodexNativeSessionController)

        await controller.debugRecordLifecyclePhaseForTesting()

        XCTAssertEqual(recorder.recordedPhases(), [.runtimeResolution])
    }
}
