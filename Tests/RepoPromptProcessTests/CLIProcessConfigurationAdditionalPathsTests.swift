import Foundation
@testable import RepoPromptProcess
import XCTest

final class CLIProcessConfigurationAdditionalPathsTests: XCTestCase {
    func testEnsureAdditionalPathsAppendsNewPathsAndDeduplicates() {
        var config = CLIProcessConfiguration(additionalPaths: ["/usr/bin", "/bin"])
        config.ensureAdditionalPaths(["/bin", "/usr/local/bin", "/bin", "/opt/bin"])
        XCTAssertEqual(config.additionalPaths, ["/usr/bin", "/bin", "/usr/local/bin", "/opt/bin"])
    }

    func testEnsureAdditionalPathsWithEmptyInputLeavesPathsUnchanged() {
        var config = CLIProcessConfiguration(additionalPaths: ["/usr/bin"])
        config.ensureAdditionalPaths([])
        XCTAssertEqual(config.additionalPaths, ["/usr/bin"])
    }

    func testEnsureAdditionalPathsPreservesOrderOfUniqueAdditions() {
        var config = CLIProcessConfiguration(additionalPaths: [])
        config.ensureAdditionalPaths(["/first", "/second", "/first", "/third"])
        XCTAssertEqual(config.additionalPaths, ["/first", "/second", "/third"])
    }
}
