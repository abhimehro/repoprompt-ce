@testable import RepoPromptMCP
import XCTest

final class REPLInputParserTests: XCTestCase {
    // MARK: - Basic Command Parsing

    func testSingleCommand() {
        let result = REPLInputParser.parse("echo hello")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertNil(result.segments[0].separatorAfter)
        XCTAssertNil(result.outputRedirectPath)
        XCTAssertFalse(result.appendMode)
    }

    func testCommandWithTrailingWhitespace() {
        let result = REPLInputParser.parse("echo hello  \t ")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello")
    }

    // MARK: - Chaining commands

    func testCommandChainingAlways() {
        let result = REPLInputParser.parse("echo a; echo b")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "echo a")
        XCTAssertEqual(result.segments[0].separatorAfter, .always)
        XCTAssertEqual(result.segments[1].command, "echo b")
        XCTAssertNil(result.segments[1].separatorAfter)
    }

    func testCommandChainingOnSuccess() {
        let result = REPLInputParser.parse("echo a && echo b")
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "echo a")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "echo b")
        XCTAssertNil(result.segments[1].separatorAfter)
    }

    func testCommandChainingMixed() {
        let result = REPLInputParser.parse("a && b ; c")
        XCTAssertEqual(result.segments.count, 3)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "b")
        XCTAssertEqual(result.segments[1].separatorAfter, .always)
        XCTAssertEqual(result.segments[2].command, "c")
    }

    // MARK: - Edge Cases: Missing segments

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

    func testRepeatedSeparators() {
        let result = REPLInputParser.parse("a ;; b && && c")
        // Flushes ignore empty trimmed strings
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
        // The first && flushes 'a', the third & is appended to the next command 'b'
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].command, "a")
        XCTAssertEqual(result.segments[0].separatorAfter, .onSuccess)
        XCTAssertEqual(result.segments[1].command, "& b")
    }

    // MARK: - Quoting Edge Cases

    func testQuotesProtectSeparators() {
        let result = REPLInputParser.parse("echo 'a ; b && c'")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo 'a ; b && c'")
    }

    func testDoubleQuotesProtectSeparators() {
        let result = REPLInputParser.parse("echo \"a ; b && c\"")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo \"a ; b && c\"")
    }

    func testEscapedQuotes() {
        let result = REPLInputParser.parse("echo \\\"hello\\\"")
        XCTAssertEqual(result.segments.count, 1)
        // if ch == "\\", inDouble { escaped = true; ... }
        XCTAssertEqual(result.segments[0].command, "echo \\\"hello\\\"")
    }

    func testEscapeAtVeryEnd() {
        // "echo \"hello\\" -> the last backslash would set escaped=true, then loop ends.
        let result = REPLInputParser.parse("echo \"hello\\")
        XCTAssertEqual(result.segments[0].command, "echo \"hello\\")
    }

    func testUnclosedSingleQuote() {
        let result = REPLInputParser.parse("echo 'hello")
        XCTAssertEqual(result.segments[0].command, "echo 'hello")
    }

    func testUnclosedDoubleQuote() {
        let result = REPLInputParser.parse("echo \"hello")
        XCTAssertEqual(result.segments[0].command, "echo \"hello")
    }

    func testSingleQuoteInsideDoubleQuote() {
        let result = REPLInputParser.parse("echo \"it's OK\"")
        XCTAssertEqual(result.segments[0].command, "echo \"it's OK\"")
    }

    func testDoubleQuoteInsideSingleQuote() {
        let result = REPLInputParser.parse("echo 'he said \"hello\"'")
        XCTAssertEqual(result.segments[0].command, "echo 'he said \"hello\"'")
    }

    // MARK: - Redirection

    func testBasicRedirect() {
        let result = REPLInputParser.parse("echo hello > out.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testAppendRedirect() {
        let result = REPLInputParser.parse("echo hello >> out.txt")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
        XCTAssertTrue(result.appendMode)
    }

    func testQuotedRedirectPath() {
        let result = REPLInputParser.parse("echo hello > \"my out file.txt\"")
        XCTAssertEqual(result.outputRedirectPath, "my out file.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testSingleQuotedRedirectPath() {
        let result = REPLInputParser.parse("echo hello >> 'my out file.txt'")
        XCTAssertEqual(result.outputRedirectPath, "my out file.txt")
        XCTAssertTrue(result.appendMode)
    }

    func testRedirectWithoutSpace() {
        let result = REPLInputParser.parse("echo hello>out.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "out.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testRedirectWithinQuotesIgnored() {
        let result = REPLInputParser.parse("echo \"hello > world\"")
        XCTAssertNil(result.outputRedirectPath)
        XCTAssertEqual(result.segments[0].command, "echo \"hello > world\"")
    }

    func testEmptyRedirectTarget() {
        let result = REPLInputParser.parse("echo hello > ")
        // If there is no target after > the parser treats it as no redirect
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].command, "echo hello >")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testEmptyQuotedRedirectTarget() {
        // parseQuotedString on "\"\"" returns ""
        let result = REPLInputParser.parse("echo hello > \"\"")
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "")
    }

    func testRedirectWithTrailingGarbageInQuotes() {
        // "out.txt" foo -> trailing chars break quoted parse, then fallback has spaces, so redirect fails
        let result = REPLInputParser.parse("echo hello > \"out.txt\" foo")
        XCTAssertEqual(result.segments[0].command, "echo hello > \"out.txt\" foo")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testMultipleRedirectOperators() {
        // > last unquoted > is used
        let result = REPLInputParser.parse("echo hello > a.txt > b.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello > a.txt")
        XCTAssertEqual(result.outputRedirectPath, "b.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testMultipleAppendRedirectOperators() {
        // >> > -> the last one is >
        let result = REPLInputParser.parse("echo hello >> a.txt > b.txt")
        XCTAssertEqual(result.segments[0].command, "echo hello >> a.txt")
        XCTAssertEqual(result.outputRedirectPath, "b.txt")
        XCTAssertFalse(result.appendMode)
    }

    func testRedirectUnclosedQuote() {
        // > "out.txt -> Unclosed quote means parseQuotedString returns nil. Fallback fails if whitespace.
        let result = REPLInputParser.parse("echo hello > \"out.txt")
        // No whitespace in fileSpec (which is "\"out.txt"), so fallback succeeds
        XCTAssertEqual(result.segments[0].command, "echo hello")
        XCTAssertEqual(result.outputRedirectPath, "\"out.txt")
    }

    func testRedirectUnclosedQuoteWithSpace() {
        // > "out txt -> parseQuotedString returns nil. Fallback fails due to whitespace.
        let result = REPLInputParser.parse("echo hello > \"out txt")
        XCTAssertEqual(result.segments[0].command, "echo hello > \"out txt")
        XCTAssertNil(result.outputRedirectPath)
    }

    func testEscapedQuoteInRedirectDoubleQuotes() {
        // > "out\"file.txt"
        let result = REPLInputParser.parse("echo hello > \"out\\\"file.txt\"")
        XCTAssertEqual(result.outputRedirectPath, "out\"file.txt")
    }
}
