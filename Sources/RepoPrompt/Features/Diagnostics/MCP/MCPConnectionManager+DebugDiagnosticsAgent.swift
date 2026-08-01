// MARK: - DEBUG Agent Diagnostics

import Foundation
import MCP

#if DEBUG
    extension ServerNetworkManager {
        func debugAgentPerfMetricsPayload(op: String, arguments: [String: Value]) async -> CallTool.Result {
            #if DEBUG
                if let enable = debugBool(arguments, "enable") {
                    AgentModePerfDiagnostics.setDebugProcessOverrideEnabled(enable)
                }
                if debugBool(arguments, "clear") == true {
                    AgentModePerfDiagnostics.clearRecentMetrics()
                }
                if debugBool(arguments, "emit_probe") == true {
                    AgentModePerfDiagnostics.event("agent.metrics.probe", fields: ["source": "debugDiagnostics"])
                }
                let mark = debugString(arguments, "mark")?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let mark, !mark.isEmpty {
                    AgentModePerfDiagnostics.event("agent.metrics.mark", fields: ["mark": mark])
                }
                let wantsSummary = debugBool(arguments, "summary") == true
                let startMark = debugString(arguments, "start_mark")?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let endMark = debugString(arguments, "end_mark")?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let eventNames: Set<String>?
                if wantsSummary {
                    guard let parsedEventNames = debugStringArray(arguments, "event_names", op: op) else {
                        return debugDiagnosticsError(op: op, code: "invalid_params", message: "`event_names` must be a string or array of strings.")
                    }
                    eventNames = parsedEventNames.map { Set($0) }
                } else {
                    eventNames = nil
                }

                // Optional diagnostic-only session snapshot collection. Lets scripted
                // multi-window validation populate `latest_session_snapshots` without
                // forcing focus cycling through every Agent tab. No UI sync runs.
                var snapshotSummary: [String: Any]? = nil
                if debugBool(arguments, "snapshot_sessions") == true {
                    guard let parsedTabIDs = debugUUIDSet(arguments, "tab_ids", op: op) else {
                        return debugDiagnosticsError(op: op, code: "invalid_params", message: "`tab_ids` must be an array of UUID strings.")
                    }
                    let filter: Set<UUID>? = parsedTabIDs.isEmpty ? nil : parsedTabIDs
                    snapshotSummary = await captureAgentPerfSessionSnapshots(filter: filter)
                }

                let limit: Int
                switch debugBoundedInt(arguments, "limit", defaultValue: 100, range: 1 ... 2000) {
                case let .value(parsed), let .defaulted(parsed):
                    limit = parsed
                case .invalid:
                    return debugDiagnosticsError(op: op, code: "invalid_params", message: "`limit` must be an integer between 1 and 2000.")
                }

                var payload = AgentModePerfDiagnostics.debugStateSnapshot(lineLimit: limit)
                payload["ok"] = true
                payload["op"] = op
                if let mark, !mark.isEmpty {
                    payload["mark"] = mark
                }
                if let snapshotSummary {
                    payload["snapshot_sessions_result"] = snapshotSummary
                }
                if wantsSummary {
                    payload["summary"] = AgentModePerfDiagnostics.debugMetricSummarySnapshot(
                        lineLimit: limit,
                        startMark: startMark,
                        endMark: endMark,
                        eventNames: eventNames
                    )
                }
                return debugDiagnosticsResult(payload)
            #else
                return debugDiagnosticsError(op: op, code: "unavailable", message: "`agent_perf_metrics` is only available in DEBUG builds.")
            #endif
        }

        func debugSeedAgentTextDerivationFixturePayload(op: String, arguments: [String: Value]) async -> CallTool.Result {
            #if DEBUG
                let windowID: Int
                switch debugBoundedInt(arguments, "window_id", defaultValue: 0, range: 0 ... Int.max) {
                case let .value(parsed), let .defaulted(parsed):
                    windowID = parsed
                case .invalid:
                    return debugDiagnosticsError(op: op, code: "invalid_params", message: "`window_id` must be a non-negative integer.")
                }
                let reset = debugBool(arguments, "reset") ?? true
                let activateAgentMode = debugBool(arguments, "activate_agent_mode") ?? true
                let tabID: UUID?
                if let rawTabID = debugString(arguments, "tab_id")?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTabID.isEmpty {
                    guard let parsedTabID = UUID(uuidString: rawTabID) else {
                        return debugDiagnosticsError(op: op, code: "invalid_params", message: "`tab_id` must be a valid UUID when provided.")
                    }
                    tabID = parsedTabID
                } else {
                    tabID = nil
                }

                switch await Self.debugSeedAgentTextDerivationFixture(
                    op: op,
                    windowID: windowID,
                    tabID: tabID,
                    reset: reset,
                    activateAgentMode: activateAgentMode
                ) {
                case let .payload(payload):
                    return debugDiagnosticsResult(payload)
                case let .error(code, message):
                    return debugDiagnosticsError(op: op, code: code, message: message)
                }
            #else
                return debugDiagnosticsError(op: op, code: "unavailable", message: "`seed_agent_text_derivation_fixture` is only available in DEBUG builds.")
            #endif
        }

        @MainActor
        private static func debugSeedAgentTextDerivationFixture(
            op: String,
            windowID: Int,
            tabID: UUID?,
            reset: Bool,
            activateAgentMode: Bool
        ) async -> DebugDiagnosticsPayloadResult {
            let manager = WindowStatesManager.shared
            let selectedWindow: WindowState? = if windowID > 0 {
                manager.allWindows.first { $0.windowID == windowID }
            } else {
                manager.allWindows.first { $0.isCurrentlyFocused } ?? manager.latestWindowState
            }
            guard let window = selectedWindow else {
                return .error(code: "no_window", message: "No matching RepoPrompt window is available for text derivation fixture seeding.")
            }

            guard let tab = await window.promptManager.ensureActiveComposeTab(
                tabID,
                creationStrategy: .blank,
                name: "Text Derivation Fixture"
            ) else {
                return .error(code: "no_tab", message: "Unable to resolve or create a compose tab for text derivation fixture seeding.")
            }

            let counts = await window.agentModeViewModel.testSeedTextDerivationFixture(tabID: tab.id, reset: reset)
            return .payload([
                "ok": true,
                "op": op,
                "window_id": window.windowID,
                "tab_id": tab.id.uuidString,
                "workspace": window.workspaceManager.activeWorkspace?.name ?? NSNull(),
                "reset": reset,
                "activate_agent_mode": activateAgentMode,
                "appended_counts": counts,
                "fixture": "debug_text_derivation_fixture_v1",
                "notes": "DEBUG-only synthetic Agent transcript with three long assistant messages plus plain/diff/json tool payloads. The first assistant is intentionally older than the two most recent assistant rows so collapse derivation can run when rendered."
            ])
        }

        private func captureAgentPerfSessionSnapshots(filter: Set<UUID>?) async -> [String: Any] {
            await MainActor.run { () -> [String: Any] in
                var recordedByWindow: [[String: Any]] = []
                var totalRecorded = 0
                for window in WindowStatesManager.shared.allWindows {
                    let recorded = window.agentModeViewModel.test_recordPerfSessionSnapshotsForAllTabs(
                        source: "debugDiagnostics",
                        tabIDs: filter
                    )
                    totalRecorded += recorded.count
                    recordedByWindow.append([
                        "window_id": window.windowID,
                        "recorded_tab_ids": recorded.map(\.uuidString)
                    ])
                }
                return [
                    "windows": recordedByWindow,
                    "total_recorded": totalRecorded,
                    "diagnostics_enabled": AgentModePerfDiagnostics.isEnabled
                ]
            }
        }
    }
#endif
