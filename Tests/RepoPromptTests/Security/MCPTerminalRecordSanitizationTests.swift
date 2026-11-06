import Foundation
import RepoPromptShared
import XCTest

final class MCPTerminalRecordSanitizationTests: XCTestCase {
    func testSessionTokenRedactionInTerminalRecordReasonAndErrorDescription() {
        let sessionToken = "session-secret-token-12345"
        let record = MCPTerminalRecord(
            layer: .proxy,
            initiator: .peer,
            reason: "Failed session session-secret-token-12345 connection",
            sessionToken: sessionToken,
            localPID: 1234,
            peerPID: 5678,
            appConnectionID: UUID(),
            connectionGeneration: 1,
            errno: nil,
            errorDescription: "Error processing session-secret-token-12345: unauthorized"
        )

        XCTAssertEqual(record.reason, "Failed session <redacted> connection")
        XCTAssertEqual(record.errorDescription, "Error processing <redacted>: unauthorized")
    }

    func testCredentialURLRedactionInTerminalRecord() {
        let record = MCPTerminalRecord(
            layer: .proxy,
            initiator: .peer,
            reason: "Connecting to https://user:secretpass123@api.example.com/v1",
            sessionToken: nil,
            localPID: 1234,
            peerPID: nil,
            appConnectionID: nil,
            connectionGeneration: nil,
            errno: nil,
            errorDescription: "Auth failure at postgres://admin:dbpass456@db.internal:5432/main"
        )

        XCTAssertEqual(record.reason, "Connecting to https://<redacted>@api.example.com/v1")
        XCTAssertEqual(record.errorDescription, "Auth failure at postgres://<redacted>@db.internal:5432/main")
    }

    func testSensitiveKeyValueRedactionInTerminalRecord() {
        let record = MCPTerminalRecord(
            layer: .proxy,
            initiator: .peer,
            reason: "Failed call with api_key=supersecretkey123 and authorization: Bearer mytokenabc",
            sessionToken: nil,
            localPID: 1234,
            peerPID: nil,
            appConnectionID: nil,
            connectionGeneration: nil,
            errno: nil,
            errorDescription: "Header proxy-authorization: Basic dXNlcjpwYXNz"
        )

        XCTAssertEqual(record.reason, "Failed call with api_key=<redacted> and authorization:<redacted>")
        XCTAssertEqual(record.errorDescription, "Header proxy-authorization:<redacted>")
    }

    func testStandaloneSecretPatternsRedactionInTerminalRecord() {
        let openAIToken = ["sk-proj-", "12345678901234567890"].joined()
        let jwtHeader = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let jwtPayload = "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ"
        let jwtSig = "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let jwtToken = "\(jwtHeader).\(jwtPayload).\(jwtSig)"

        let record = MCPTerminalRecord(
            layer: .proxy,
            initiator: .peer,
            reason: "Invoked with key \(openAIToken) and token \(jwtToken)",
            sessionToken: nil,
            localPID: 1234,
            peerPID: nil,
            appConnectionID: nil,
            connectionGeneration: nil,
            errno: nil,
            errorDescription: nil
        )

        XCTAssertEqual(record.reason, "Invoked with key <redacted> and token <redacted>")
    }
}
