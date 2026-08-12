//
//  REPLInputParserTests.swift
//  RepoPrompt
//

@testable import RepoPromptMCP
import XCTest

final class REPLInputParserTests: XCTestCase {
    func testSimpleCommand() {
        let result = REPLInputParser.parse("ls -la")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "ls -la")
        XCTAssertNil(result.segments[0].separatorAfter)
        XCTAssertNil(result.outputRedirectPath)
        XCTAssertFalse(result.appendMode)
    }

    func testCommandWithSemicolonSeparator() {
        let result = REPLInputParser.parse("ls -la ; echo 'done'")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "ls -la")
        XCTAssertEqual(result.segments[0].separatorAfter, .always)
        XCTAssertEqual(result.segments[1].command, "echo 'done'")
        XCTAssertNil(result.segments[1].separatorAfter)
    }

    func testCommandWithAndSeparator() {
        let result = REPLInputParser.parse("build && test")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "build")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "test")
        XCTAssertNil(result.segments[1].separatorAfter)
    }

    func testRedirectOutputTruncate() {
        let result = REPLInputParser.parse("ls -la > out.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "ls -la")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testRedirectOutputAppend() {
        let result = REPLInputParser.parse("echo 'log' >> log.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo 'log'")
        XCTAssertEqual(result.outputRedirectPath, "log.txt")
        XCTAssertTrue(result.appendMode)
    }

    func testQuotedRedirectOutput() {
        let result = REPLInputParser.parse("cat > \"output file.txt\"")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "cat")
        XCTAssertEqual(result.outputRedirectPath, "output file.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testSingleQuotedRedirectOutput() {
        let result = REPLInputParser.parse("cat > 'output file.txt'")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "cat")
        XCTAssertEqual(result.outputRedirectPath, "output file.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testQuotesInCommandArePreservedAndIgnoredForSeparators() {
        let result = REPLInputParser.parse("echo \"hello ; world\" && echo 'done'")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "echo \"hello ; world\"")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "echo 'done'")
    }

    func testEscapedQuotes() {
        let result = REPLInputParser.parse("echo \"hello \\\"world\\\"\" > out.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo \"hello \\\"world\\\"\"")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
    }

    func testRedirectWithInvalidTrailingWhitespace() {
        let result = REPLInputParser.parse("ls > ")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "ls >")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testMultipleSeparators() {
        let result = REPLInputParser.parse("cmd1 ; cmd2 && cmd3 ; cmd4")
        XCTAssertEqual(result.segments.count, 4)
        XCTAssertEqual(result.segments[0].command, "cmd1")
        XCTAssertEqual(result.segments[0].separatorAfter, .always)
        XCTAssertEqual(result.segments[1].command, "cmd2")
        XCTAssertEqual(result.segments[1].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[2].command, "cmd3")
        XCTAssertEqual(result.segments[2].separatorAfter, .always)
        XCTAssertEqual(result.segments[3].command, "cmd4")
    }

    func testRedirectSymbolInQuotes() {
        let result = REPLInputParser.parse("echo 'a > b' > file.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo 'a > b'")
        XCTAssertEqual(result.outputRedirectPath, "file.txt")
        XCTAssertFalse(result.appendMode)
    }

    // MARK: - Edge cases (salvaged from #186; unique vs main coverage)

    func testEmptyString() {
        let result = REPLInputParser.parse("")
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertNil(result.outputRedirectPath)
    }

    func testOnlyWhitespace() {
        let result = REPLInputParser.parse("   \t  ")
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertNil(result.outputRedirectPath)
    }

    func testCommandWithTrailingWhitespace() {
        let result = REPLInputParser.parse("echo hello  \t ")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello")
    }

    func testRepeatedSeparators() {
        let result = REPLInputParser.parse("a ;; b && && c")
        XCTAssertEqual(result.segments.count, 3)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[1].command, "b")
        XCTAssertEqual(result.segments[2].command, "c")
    }

    func testSeparatorAtStart() {
        let result = REPLInputParser.parse("; a")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "a")
    }

    func testSeparatorAtEnd() {
        let result = REPLInputParser.parse("a ;")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[0].separatorAfter, .always)
    }

    func testDoubleAmpersandAtEnd() {
        let result = REPLInputParser.parse("a &&")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
    }

    func testTripleAmpersand() {
        let result = REPLInputParser.parse("a &&& b")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "& b")
    }

    func testUnclosedSingleQuote() {
        let result = REPLInputParser.parse("echo 'hello")
        XCTAssertEqual(result.segments[0].command, "echo 'hello")
    }

    func testUnclosedDoubleQuote() {
        let result = REPLInputParser.parse("echo \"hello")
        XCTAssertEqual(result.segments[0].command, "echo \"hello")
    }

    func testEscapeAtVeryEnd() {
        let result = REPLInputParser.parse("echo \"hello\\")
        XCTAssertEqual(result.segments[0].command, "echo \"hello\\")
    }

    func testSingleQuoteInsideDoubleQuote() {
        let result = REPLInputParser.parse("echo \"it's OK\"")
        XCTAssertEqual(result.segments[0].command, "echo \"it's OK\"")
    }

    func testDoubleQuoteInsideSingleQuote() {
        let result = REPLInputParser.parse("echo 'he said \"hello\"'")
        XCTAssertEqual(result.segments[0].command, "echo 'he said \"hello\"'")
    }

    func testRedirectWithoutSpace() {
        let result = REPLInputParser.parse("echo hello>out.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testEmptyQuotedRedirectTarget() {
        let result = REPLInputParser.parse("echo hello > \"\"")
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "")
    }

    func testRedirectWithTrailingGarbageInQuotes() {
        let result = REPLInputParser.parse("echo hello > \"out.txt\" foo")
        XCTAssertEqual(result.segments[0].command, "echo hello > \"out.txt\" foo")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testMultipleRedirectOperators() {
        let result = REPLInputParser.parse("echo hello > a.txt > b.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello > a.txt")
        XCTAssertEqual(result.outputRedirectPath, "b.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testMultipleAppendRedirectOperators() {
        let result = REPLInputParser.parse("echo hello >> a.txt > b.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello >> a.txt")
        XCTAssertEqual(result.outputRedirectPath, "b.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testRedirectUnclosedQuote() {
        let result = REPLInputParser.parse("echo hello > \"out.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "\"out.txt")
    }

    func testRedirectUnclosedQuoteWithSpace() {
        let result = REPLInputParser.parse("echo hello > \"out txt")
        XCTAssertEqual(result.segments[0].command, "echo hello > \"out txt")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testEscapedQuoteInRedirectDoubleQuotes() {
        let result = REPLInputParser.parse("echo hello > \"out\\\"file.txt\"")
        XCTAssertEqual(result.outputRedirectPath, "out\"file.txt")
    }
}
