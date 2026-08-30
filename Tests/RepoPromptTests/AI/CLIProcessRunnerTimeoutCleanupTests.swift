import Foundation
@testable import RepoPromptApp
import XCTest

final class CLIProcessRunnerTimeoutCleanupTests: XCTestCase {
    func testRunTimeoutUsesExplicitCleanupPolicy() async throws {
        let runner = CLIProcessRunner(
            config: CLIProcessConfiguration(command: "/bin/sh", enableDebugLogging: false)
        )
        let cleanupPolicy = ProcessTermination.TimeoutCleanupPolicy(
            sigtermGrace: 0.05,
            sigkillGrace: 0.1
        )
        let startedAt = ProcessInfo.processInfo.systemUptime

        let result = try await runner.run(
            args: ["-c", "trap '' TERM; while :; do sleep 1; done"],
            stdin: nil,
            outputMode: .none,
            timeout: 0.1,
            timeoutCleanupPolicy: cleanupPolicy
        )

        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(
            elapsed,
            2.0,
            "Explicit timeout cleanup grace should replace the default multi-second cleanup allowance"
        )
    }
}
