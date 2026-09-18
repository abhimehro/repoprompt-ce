import Foundation
@testable import RepoPromptApp
import XCTest

final class CommandPathResolverShellLookupModeTests: XCTestCase {
    func testFallbackOnlyPrefersPathBeforeShellLookup() throws {
        let fixture = try makeResolverFixture(prefix: "resolver-fallback-only")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolved = CommandPathResolver.resolve(
            "codex",
            environment: fixture.environment,
            additionalPaths: [],
            preferredBasenames: ["codex"],
            shellLookupMode: .fallbackOnly
        )

        XCTAssertEqual(resolved, fixture.pathExecutable.path)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.shellInvocationMarker.path),
            "fallbackOnly should not invoke the shell when PATH already contains the command"
        )
    }

    func testPreferShellPreservesShellFirstResolution() throws {
        let fixture = try makeResolverFixture(prefix: "resolver-prefer-shell")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolved = CommandPathResolver.resolve(
            "codex",
            environment: fixture.environment,
            additionalPaths: [],
            preferredBasenames: ["codex"],
            shellLookupMode: .preferShell
        )

        XCTAssertEqual(resolved, fixture.shellExecutable.path)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.shellInvocationMarker.path),
            "preferShell should query the shell before PATH search"
        )
        assertSanitizedShellEnvironment(fixture, expectsLookupMarker: true)
    }

    func testLoginShellCaptureSanitizesChildEnvironment() throws {
        let fixture = try makeResolverFixture(prefix: "resolver-login-shell")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = CLIEnvironmentCache.captureEnvironment(
            shell: fixture.environment["SHELL"]!,
            arguments: ["-c", "env"],
            environment: fixture.environment,
            enableLogging: false,
            timeout: 5
        )
        assertSanitizedShellEnvironment(fixture, expectsLookupMarker: false)
    }

    private func assertSanitizedShellEnvironment(_ fixture: ResolverFixture, expectsLookupMarker: Bool) {
        let childEnvironment = (try? String(contentsOf: fixture.shellEnvironmentCapture)) ?? ""
        XCTAssertFalse(childEnvironment.contains("DYLD_INSERT_LIBRARIES="))
        XCTAssertFalse(childEnvironment.contains("__XPC_DYLD_TEST="))
        XCTAssertTrue(childEnvironment.contains("HOME=\(fixture.root.path)"))
        let path = fixture.environment["PATH"]!
        XCTAssertTrue(childEnvironment.contains("PATH=\(path)"))
        if expectsLookupMarker {
            XCTAssertTrue(childEnvironment.contains("RP_SHELL_LOOKUP=1"))
        }
    }

    private struct ResolverFixture {
        let root: URL
        let pathExecutable: URL
        let shellExecutable: URL
        let shellInvocationMarker: URL
        let shellEnvironmentCapture: URL
        let environment: [String: String]
    }

    private func makeResolverFixture(prefix: String) throws -> ResolverFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoPromptTests-")
            .appendingPathComponent(prefix + "-" + UUID().uuidString, isDirectory: true)
        let pathBin = root.appendingPathComponent("path-bin", isDirectory: true)
        let shellBin = root.appendingPathComponent("shell-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shellBin, withIntermediateDirectories: true)

        let pathExecutable = pathBin.appendingPathComponent("codex")
        let shellExecutable = shellBin.appendingPathComponent("codex")
        let shellInvocationMarker = root.appendingPathComponent("shell-was-invoked")
        let shellEnvironmentCapture = root.appendingPathComponent("shell-environment")
        let fakeShell = root.appendingPathComponent("fake-shell")

        try writeExecutable(pathExecutable, contents: "#!/bin/sh\nexit 0\n")
        try writeExecutable(shellExecutable, contents: "#!/bin/sh\nexit 0\n")
        try writeExecutable(
            fakeShell,
            contents: """
            #!/bin/sh
            printf invoked > "\(shellInvocationMarker.path)"
            env > "\(shellEnvironmentCapture.path)"
            printf '__RP_BEGIN__\\n'
            printf '%s\\n' "\(shellExecutable.path)"
            printf '__RP_END__\\n'
            exit 0
            """
        )

        return ResolverFixture(
            root: root,
            pathExecutable: pathExecutable,
            shellExecutable: shellExecutable,
            shellInvocationMarker: shellInvocationMarker,
            shellEnvironmentCapture: shellEnvironmentCapture,
            environment: [
                "HOME": root.path,
                "PATH": pathBin.path,
                "SHELL": fakeShell.path,
                "DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib",
                "__XPC_DYLD_TEST": "injected"
            ]
        )
    }

    private func writeExecutable(_ url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
