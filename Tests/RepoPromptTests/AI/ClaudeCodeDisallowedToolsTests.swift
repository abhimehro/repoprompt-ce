@testable import RepoPromptApp
import XCTest

final class ClaudeCodeDisallowedToolsTests: XCTestCase {
    /// Claude Code's native orchestration tools would bypass RepoPrompt's `agent_run`.
    func testAgentModeContextsBlockNativeOrchestrationTools() {
        let orchestrationTools = ["Agent", "Task", "Workflow", "ListAgents", "SendMessage"]
        for context in [AgentCLIToolContext.agentRun, .discoverRun, .promptOnly] {
            let disallowed = Set(ClaudeCodeIntegrationConfiguration.disallowedTools(for: context))
            for tool in orchestrationTools {
                XCTAssertTrue(disallowed.contains(tool), "\(tool) must be disallowed for \(context)")
            }
        }
    }
}
