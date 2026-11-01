import Foundation
@testable import RepoPromptFileSystem
import XCTest

final class WorkspaceRootNamespaceManifestStoreTests: XCTestCase {
    func testSpillFormatOrderingEqualPathsReturnSame() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let lhs = WorkspaceRootNamespaceRecord(
            relativePath: "a/b/c.txt",
            kind: .file,
            isSymbolicLink: false,
            fileSystemMode: 0o644
        )
        let rhs = WorkspaceRootNamespaceRecord(
            relativePath: "a/b/c.txt",
            kind: .directory,
            isSymbolicLink: true,
            fileSystemMode: 0o755
        )

        XCTAssertEqual(format.ordering(lhs, rhs), .same)
    }

    func testSpillFormatOrderingAscendingPairs() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let recordA = WorkspaceRootNamespaceRecord(
            relativePath: "a",
            kind: .file,
            isSymbolicLink: false
        )
        let recordB = WorkspaceRootNamespaceRecord(
            relativePath: "b",
            kind: .file,
            isSymbolicLink: false
        )
        let recordAA = WorkspaceRootNamespaceRecord(
            relativePath: "aa",
            kind: .file,
            isSymbolicLink: false
        )
        let recordPrefix = WorkspaceRootNamespaceRecord(
            relativePath: "dir/file.txt",
            kind: .file,
            isSymbolicLink: false
        )
        let recordNext = WorkspaceRootNamespaceRecord(
            relativePath: "dir/file2.txt",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(recordA, recordB), .ascending)
        XCTAssertEqual(format.ordering(recordA, recordAA), .ascending)
        XCTAssertEqual(format.ordering(recordPrefix, recordNext), .ascending)
    }

    func testSpillFormatOrderingDescendingPairs() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let recordA = WorkspaceRootNamespaceRecord(
            relativePath: "a",
            kind: .file,
            isSymbolicLink: false
        )
        let recordB = WorkspaceRootNamespaceRecord(
            relativePath: "b",
            kind: .file,
            isSymbolicLink: false
        )
        let recordAA = WorkspaceRootNamespaceRecord(
            relativePath: "aa",
            kind: .file,
            isSymbolicLink: false
        )
        let recordPrefix = WorkspaceRootNamespaceRecord(
            relativePath: "dir/file.txt",
            kind: .file,
            isSymbolicLink: false
        )
        let recordNext = WorkspaceRootNamespaceRecord(
            relativePath: "dir/file2.txt",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(recordB, recordA), .descending)
        XCTAssertEqual(format.ordering(recordAA, recordA), .descending)
        XCTAssertEqual(format.ordering(recordNext, recordPrefix), .descending)
    }
}
