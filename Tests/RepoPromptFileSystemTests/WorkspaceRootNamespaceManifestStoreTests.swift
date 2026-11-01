import Foundation
@testable import RepoPromptFileSystem
import XCTest

final class WorkspaceRootNamespaceManifestStoreTests: XCTestCase {
    func testSpillFormatMapsAllFailuresToExpectedManifestErrors() {
        let format = WorkspaceRootNamespaceSpillFormat()

        let invalidConfigurationError = format.error(.invalidConfiguration)
        XCTAssertEqual(
            invalidConfigurationError as? WorkspaceRootNamespaceManifestError,
            .invalidConfiguration
        )

        let duplicateRecordError = format.error(.duplicateRecord)
        XCTAssertEqual(
            duplicateRecordError as? WorkspaceRootNamespaceManifestError,
            .duplicatePath
        )

        let outOfOrderError = format.error(.outOfOrder)
        XCTAssertEqual(
            outOfOrderError as? WorkspaceRootNamespaceManifestError,
            .outOfOrder
        )

        let resourceAdmissionError = format.error(.resourceAdmission)
        XCTAssertEqual(
            resourceAdmissionError as? WorkspaceRootNamespaceManifestError,
            .resourceAdmission
        )

        let closedError = format.error(.closed)
        XCTAssertEqual(
            closedError as? WorkspaceRootNamespaceManifestError,
            .closed
        )

        let corruptError = format.error(.corrupt("corrupted header frame"))
        XCTAssertEqual(
            corruptError as? WorkspaceRootNamespaceManifestError,
            .corrupt("corrupted header frame")
        )

        let ioError = format.error(.io(operation: "write", code: EIO))
        XCTAssertEqual(
            ioError as? WorkspaceRootNamespaceManifestError,
            .io(operation: "write", code: EIO)
        )
    }
}
