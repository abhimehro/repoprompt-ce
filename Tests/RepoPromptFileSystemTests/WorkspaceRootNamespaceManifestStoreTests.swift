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

    func testSpillFormatOrderingAscendingAndDescendingPairs() {
        let format = WorkspaceRootNamespaceSpillFormat()
        func makeRecord(_ path: String) -> WorkspaceRootNamespaceRecord {
            WorkspaceRootNamespaceRecord(relativePath: path, kind: .file, isSymbolicLink: false)
        }

        let testCases: [(earlier: String, later: String)] = [
            ("a", "b"),
            ("a", "aa"),
            ("dir/file.txt", "dir/file2.txt"),
            ("alpha", "beta"),
            ("folder/sub/a", "folder/sub/z"),
        ]

        for (earlierPath, laterPath) in testCases {
            let earlier = makeRecord(earlierPath)
            let later = makeRecord(laterPath)

            XCTAssertEqual(
                format.ordering(earlier, later),
                .ascending,
                "Expected '\(earlierPath)' < '\(laterPath)' to be ascending"
            )
            XCTAssertEqual(
                format.ordering(later, earlier),
                .descending,
                "Expected '\(laterPath)' > '\(earlierPath)' to be descending"
            )
        }
    }
}
