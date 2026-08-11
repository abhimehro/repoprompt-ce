import Foundation
import MCP
@testable import RepoPromptMCP
import XCTest

final class ToolGroupsTests: XCTestCase {
    func testGroupNames() {
        let expected = ToolGroup.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(ToolGroupCatalog.groupNames, expected)
    }

    func testParseGroups_ValidSingle() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: "explore")
        XCTAssertEqual(groups, [.explore])
    }

    func testParseGroups_ValidMultiple() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: "explore,git")
        XCTAssertEqual(groups, [.explore, .git])
    }

    func testParseGroups_WithSpaces() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: " explore , git ")
        XCTAssertEqual(groups, [.explore, .git])
    }

    func testParseGroups_WithCase() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: "eXplore,GIT")
        XCTAssertEqual(groups, [.explore, .git])
    }

    func testParseGroups_WithAliases() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: "routing,workspace,chat")
        XCTAssertEqual(groups, [.binding, .context, .conversation])
    }

    func testParseGroups_DuplicateGroups() throws {
        let groups = try ToolGroupCatalog.parseGroups(spec: "explore,explore,git")
        XCTAssertEqual(groups, [.explore, .git])
    }

    func testParseGroups_EmptySpecThrows() {
        XCTAssertThrowsError(try ToolGroupCatalog.parseGroups(spec: "")) { error in
            guard let parseError = error as? ToolGroupParseError else {
                XCTFail("Expected ToolGroupParseError")
                return
            }
            if case .emptySpec = parseError {
                // Expected
            } else {
                XCTFail("Expected .emptySpec error")
            }
        }

        XCTAssertThrowsError(try ToolGroupCatalog.parseGroups(spec: "   "))
        XCTAssertThrowsError(try ToolGroupCatalog.parseGroups(spec: ","))
    }

    func testParseGroups_UnknownGroupThrows() {
        XCTAssertThrowsError(try ToolGroupCatalog.parseGroups(spec: "explore,unknown")) { error in
            guard let parseError = error as? ToolGroupParseError else {
                XCTFail("Expected ToolGroupParseError")
                return
            }
            if case let .unknownGroup(name) = parseError {
                XCTAssertEqual(name, "unknown")
            } else {
                XCTFail("Expected .unknownGroup error")
            }
        }
    }

    func testFilterTools() {
        // Prefer SDK Tool(name:description:inputSchema:) shape used elsewhere in RepoPromptTests.
        let tool1 = Tool(name: "bind_context", description: nil, inputSchema: [:])
        let tool2 = Tool(name: "git", description: nil, inputSchema: [:])
        let tool3 = Tool(name: "unknown_tool", description: nil, inputSchema: [:])

        let tools = [tool1, tool2, tool3]

        let filtered1 = ToolGroupCatalog.filter(tools: tools, groups: [.binding])
        XCTAssertEqual(filtered1.count, 1)
        XCTAssertEqual(filtered1[0].name, "bind_context")

        let filtered2 = ToolGroupCatalog.filter(tools: tools, groups: [.binding, .git])
        XCTAssertEqual(filtered2.count, 2)
        XCTAssertEqual(filtered2[0].name, "bind_context")
        XCTAssertEqual(filtered2[1].name, "git")
    }

    func testGroupsForTool() {
        let bindingGroups = ToolGroupCatalog.groups(forTool: "bind_context")
        XCTAssertEqual(bindingGroups, [.binding])

        let gitGroups = ToolGroupCatalog.groups(forTool: "git")
        XCTAssertEqual(gitGroups, [.explore, .git])

        let unknownGroups = ToolGroupCatalog.groups(forTool: "unknown_tool")
        XCTAssertTrue(unknownGroups.isEmpty)
    }

    func testIsInGroups() {
        XCTAssertTrue(ToolGroupCatalog.isInGroups("bind_context", groups: [.binding, .explore]))
        XCTAssertTrue(ToolGroupCatalog.isInGroups("git", groups: [.git]))
        XCTAssertTrue(ToolGroupCatalog.isInGroups("git", groups: [.explore]))

        XCTAssertFalse(ToolGroupCatalog.isInGroups("bind_context", groups: [.explore, .git]))
        XCTAssertFalse(ToolGroupCatalog.isInGroups("unknown_tool", groups: [.binding, .explore]))
    }
}
