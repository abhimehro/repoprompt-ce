import Foundation
@testable import RepoPromptFileSystem
import XCTest

final class WorkspaceRootNamespaceManifestStoreTests: XCTestCase {
    func testOrderingReturnsSameWhenPathsAreEqual() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let lhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Main.swift",
            kind: .file,
            isSymbolicLink: false,
            fileSystemMode: 0o644
        )
        let rhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Main.swift",
            kind: .directory,
            isSymbolicLink: true,
            fileSystemMode: 0o755
        )

        XCTAssertEqual(format.ordering(lhs, rhs), .same)
    }

    func testOrderingReturnsAscendingWhenLhsPrecedesRhs() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let lhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Alpha.swift",
            kind: .file,
            isSymbolicLink: false
        )
        let rhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Beta.swift",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(lhs, rhs), .ascending)
    }

    func testOrderingReturnsDescendingWhenLhsFollowsRhs() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let lhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Beta.swift",
            kind: .file,
            isSymbolicLink: false
        )
        let rhs = WorkspaceRootNamespaceRecord(
            relativePath: "Sources/App/Alpha.swift",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(lhs, rhs), .descending)
    }

    func testOrderingHandlesPrefixHierarchyAndEmptyPaths() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let empty = WorkspaceRootNamespaceRecord(
            relativePath: "",
            kind: .file,
            isSymbolicLink: false
        )
        let root = WorkspaceRootNamespaceRecord(
            relativePath: "a",
            kind: .directory,
            isSymbolicLink: false
        )
        let nested = WorkspaceRootNamespaceRecord(
            relativePath: "a/b",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(empty, empty), .same)
        XCTAssertEqual(format.ordering(empty, root), .ascending)
        XCTAssertEqual(format.ordering(root, empty), .descending)
        XCTAssertEqual(format.ordering(root, nested), .ascending)
        XCTAssertEqual(format.ordering(nested, root), .descending)
    }

    func testOrderingRespectsByteLexicographicalOrder() {
        let format = WorkspaceRootNamespaceSpillFormat()
        let uppercase = WorkspaceRootNamespaceRecord(
            relativePath: "A",
            kind: .file,
            isSymbolicLink: false
        )
        let lowercase = WorkspaceRootNamespaceRecord(
            relativePath: "a",
            kind: .file,
            isSymbolicLink: false
        )

        XCTAssertEqual(format.ordering(uppercase, lowercase), .ascending)
        XCTAssertEqual(format.ordering(lowercase, uppercase), .descending)
    }
}
