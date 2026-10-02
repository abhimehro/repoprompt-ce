import Foundation
@testable import RepoPromptApp
import XCTest

final class ProcessEnvironmentSanitizerTests: XCTestCase {
    func testSanitizesDynamicLoaderVariablesCaseInsensitively() {
        let input: [String: String] = [
            "DYLD_INSERT_LIBRARIES": "/lib/inject.dylib",
            "dyld_insert_libraries": "/lib/inject.dylib",
            "LD_PRELOAD": "/lib/inject.so",
            "ld_preload": "/lib/inject.so",
            "LD_LIBRARY_PATH": "/custom/lib",
            "dyld_framework_path": "/custom/frameworks",
            "__xpc_dyld_something": "1",
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/test",
            "USER": "test"
        ]

        let sanitized = ProcessEnvironmentSanitizer.sanitizedForChildLaunch(input)

        XCTAssertNil(sanitized["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(sanitized["dyld_insert_libraries"])
        XCTAssertNil(sanitized["LD_PRELOAD"])
        XCTAssertNil(sanitized["ld_preload"])
        XCTAssertNil(sanitized["LD_LIBRARY_PATH"])
        XCTAssertNil(sanitized["dyld_framework_path"])
        XCTAssertNil(sanitized["__xpc_dyld_something"])

        XCTAssertEqual(sanitized["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(sanitized["HOME"], "/Users/test")
        XCTAssertEqual(sanitized["USER"], "test")
    }

    func testDetectsDynamicLoaderInsertKeys() {
        XCTAssertTrue(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("DYLD_INSERT_LIBRARIES"))
        XCTAssertTrue(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("dyld_insert_libraries"))
        XCTAssertTrue(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("LD_PRELOAD"))
        XCTAssertTrue(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("ld_preload"))
        XCTAssertFalse(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("DYLD_LIBRARY_PATH"))
        XCTAssertFalse(ProcessEnvironmentSanitizer.isDynamicLoaderInsertKey("PATH"))
    }

    func testAdditionalRemovedKeysAreCaseInsensitive() {
        let input = ["NODE_OPTIONS": "--inspect", "node_options": "--inspect", "USER": "test"]
        let sanitized = ProcessEnvironmentSanitizer.sanitizedForChildLaunch(input, additionalRemovedKeys: ["node_options"])
        XCTAssertNil(sanitized["NODE_OPTIONS"])
        XCTAssertNil(sanitized["node_options"])
        XCTAssertEqual(sanitized["USER"], "test")
    }
}
