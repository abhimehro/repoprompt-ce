import Foundation
@testable import RepoPromptClaudeCompatibleProvider
import XCTest

final class ClaudeSDKProtocolCodecTests: XCTestCase {
    func testProtocolCodecSmokeDecodesControlRepairsControlCharactersAndEncodesUserMessage() throws {
        let controlLine = Data(#"{"type":"control_request","request_id":"req-1","request":{"subtype":"permission","tool_name":"read_file","input":{"path":"Sources/App.swift"}}}"#.utf8)

        let controlMessage = try ClaudeSDKProtocolCodec.decodeLine(controlLine)

        guard case let .controlRequest(request) = controlMessage else {
            XCTFail("Expected control request")
            return
        }
        XCTAssertEqual(request.requestID, "req-1")
        XCTAssertEqual(request.subtype, "permission")
        XCTAssertEqual(request.request["tool_name"], .string("read_file"))
        XCTAssertEqual(request.request["input"]?.objectValue?["path"], .string("Sources/App.swift"))

        let rawControlCharacterLine = Data("{\"type\":\"assistant\",\"message\":{\"content\":\"hello\nworld\"}}".utf8)
        let streamMessage = try ClaudeSDKProtocolCodec.decodeLine(rawControlCharacterLine)
        guard case let .streamPayload(payload) = streamMessage else {
            XCTFail("Expected stream payload")
            return
        }
        XCTAssertEqual(payload["type"], .string("assistant"))
        XCTAssertEqual(payload["message"]?.objectValue?["content"], .string("hello\nworld"))

        let userData = try ClaudeSDKProtocolCodec.encodeUserMessage(text: "Continue", sessionID: "session-1")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: userData) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "user")
        XCTAssertEqual(object["session_id"] as? String, "session-1")
        XCTAssertTrue(object["parent_tool_use_id"] is NSNull)
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
    }
}
