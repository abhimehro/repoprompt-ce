import Foundation
@_spi(TestSupport) @testable import RepoPromptApp
import XCTest

final class AntigravityRuntimeManagerTests: XCTestCase {
    func testValidateArchiveEntriesRejectsTraversalAndAbsolutePaths() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetDir = tempDir.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let safeZip = tempDir.appendingPathComponent("safe.zip")
        let traversalZip = tempDir.appendingPathComponent("traversal.zip")

        try createZip(at: safeZip, entries: ["safe/file.txt": "content"])
        try createZip(at: traversalZip, entries: ["../escaped.txt": "evil"])

        XCTAssertNoThrow(try AntigravityRuntimeManager.validateArchiveEntries(at: safeZip, targetDirectory: targetDir))
        XCTAssertThrowsError(try AntigravityRuntimeManager.validateArchiveEntries(at: traversalZip, targetDirectory: targetDir))
    }

    private func createZip(at url: URL, entries: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "-c",
            """
            import sys, zipfile
            zip_path = sys.argv[1]
            with zipfile.ZipFile(zip_path, 'w') as zf:
                for i in range(2, len(sys.argv), 2):
                    zf.writestr(sys.argv[i], sys.argv[i+1])
            """,
            url.path
        ]
        for (k, v) in entries {
            process.arguments?.append(k)
            process.arguments?.append(v)
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "TestZip", code: 1)
        }
    }
}
