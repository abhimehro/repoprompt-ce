import MCP
import XCTest

@testable import RepoPromptMCP

final class MCPCommandParserTests: XCTestCase {

    func testSuggestCommand_ExactMatch() {
        XCTAssertEqual(MCPCommandParser.suggestCommand(for: "help"), "help")
    }

    func testSuggestCommand_Typo_OneDistance() {
        XCTAssertEqual(MCPCommandParser.suggestCommand(for: "hlp"), "help")
    }

    func testSuggestCommand_Typo_TwoDistance() {
        XCTAssertEqual(MCPCommandParser.suggestCommand(for: "hepl"), "help")
    }

    func testSuggestCommand_Typo_ThreeDistanceReturnsNil() {
        XCTAssertNil(MCPCommandParser.suggestCommand(for: "hxxxp"))
    }

    func testSuggestCommand_DashToUnderscore() {
        // "manage-worktree" should map to "manage_worktree" which has a distance of 0 after normalize
        XCTAssertEqual(MCPCommandParser.suggestCommand(for: "manage-worktree"), "manage_worktree")
    }

    func testSuggestCommand_DashToUnderscoreWithTypo() {
        XCTAssertEqual(MCPCommandParser.suggestCommand(for: "manage-wroktree"), "manage_worktree")
    }

    // MARK: - JSON Args parsing

    func testParseJSONArgs_ValidInlineJSON() throws {
        let json = "{\"path\":\"/test\"}"
        let parsed = try MCPCommandParser.parseJSONArgs(json)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["path"], .string("/test"))
    }

    func testParseJSONArgs_EmptyStringReturnsNil() throws {
        XCTAssertNil(try MCPCommandParser.parseJSONArgs(""))
        XCTAssertNil(try MCPCommandParser.parseJSONArgs("   \n "))
    }

    func testParseJSONArgs_InvalidJSONThrows() {
        let json = "{\"path\":\"/test"
        XCTAssertThrowsError(try MCPCommandParser.parseJSONArgs(json)) { error in
            XCTAssertTrue(error is CommandParseError)
        }
    }

    func testParseJSONArgs_RepairControlCharacters() throws {
        // Unescaped newlines are invalid in strict JSON.
        let json = "{\"path\":\"/test\nmultiline\"}"
        let parsed = try MCPCommandParser.parseJSONArgs(json)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["path"], .string("/test\nmultiline"))
    }

    func testParseJSONArgs_RepairTabs() throws {
        let json = "{\"path\":\"/test\tfile\"}"
        let parsed = try MCPCommandParser.parseJSONArgs(json)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["path"], .string("/test\tfile"))
    }

    func testParseJSONArgs_LiteralAtEscape() throws {
        let json = "@@{\"path\":\"/test\"}"
        let parsed = try MCPCommandParser.parseJSONArgs(json)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["path"], .string("/test"))
    }

    func testParseJSONArgs_AutoDetectFile() throws {
        // Create a temporary JSON file
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try "{\"file\":\"test.json\"}".write(to: url, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try MCPCommandParser.parseJSONArgs(url.path)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["file"], .string("test.json"))
    }

    func testParseJSONArgs_AtFilePath() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try "{\"atFile\":\"true\"}".write(to: url, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try MCPCommandParser.parseJSONArgs("@" + url.path)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["atFile"], .string("true"))
    }
}
