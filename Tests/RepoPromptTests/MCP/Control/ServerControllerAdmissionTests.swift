@testable import RepoPrompt
import XCTest

final class ServerControllerAdmissionTests: XCTestCase {
    func testRepoPromptCLIAdmissionIdentityIsRecognizedButSanitizedFromPersistence() throws {
        #if DEBUG
            do {
                let caseLabel = "testRepoPromptCLIClientNamesAreRecognizedForVerificationOnly"
                XCTAssertTrue(ServerController.test_isRepoPromptCLIClientName("RepoPrompt CLI"), caseLabel)
                XCTAssertTrue(ServerController.test_isRepoPromptCLIClientName(" RepoPrompt CLI (Exec) "), caseLabel)
                XCTAssertTrue(ServerController.test_isRepoPromptCLIClientName("RepoPrompt CLI 1.2.3"), caseLabel)
                XCTAssertFalse(ServerController.test_isRepoPromptCLIClientName("Spoofed RepoPrompt CLI"), caseLabel)
                XCTAssertFalse(ServerController.test_isRepoPromptCLIClientName("repoPrompt CLI"), caseLabel)
            }

            do {
                let caseLabel = "testSanitizerRemovesPersistedRepoPromptCLIAllowListEntries"
                let sanitized = ServerController.test_sanitizedAlwaysAllowedClients([
                    "RepoPrompt CLI",
                    "RepoPrompt CLI (Exec)",
                    "RepoPrompt CLI 1.2.3",
                    "claude-code",
                    "custom-client"
                ])

                XCTAssertEqual(sanitized, ["claude-code", "custom-client"], caseLabel)
            }
        #else
            throw XCTSkip("DEBUG-only ServerController admission seams are unavailable in release builds: testRepoPromptCLIClientNamesAreRecognizedForVerificationOnly, testSanitizerRemovesPersistedRepoPromptCLIAllowListEntries")
        #endif
    }

    func testDefaultAdmissionAllowListExcludesRepoPromptCLIAndIncludesSynchronousACPClients() throws {
        #if DEBUG
            do {
                let caseLabel = "testDefaultAllowListDoesNotIncludeRepoPromptCLI"
                XCTAssertFalse(
                    ServerController.test_defaultAlwaysAllowedClients.contains {
                        ServerController.test_isRepoPromptCLIClientName($0)
                    },
                    caseLabel
                )
            }

            do {
                let caseLabel = "testDefaultAllowListIncludesSynchronousACPClients"
                let allowed = ServerController.test_defaultAlwaysAllowedClients

                XCTAssertTrue(allowed.contains(AgentProviderKind.openCodeMCPClientID), caseLabel)
                XCTAssertTrue(allowed.contains(AgentProviderKind.cursorMCPClientID), caseLabel)
            }
        #else
            throw XCTSkip("DEBUG-only ServerController admission seams are unavailable in release builds: testDefaultAllowListDoesNotIncludeRepoPromptCLI, testDefaultAllowListIncludesSynchronousACPClients")
        #endif
    }
}
