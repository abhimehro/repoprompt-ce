import Foundation
@testable import RepoPromptProcess
import XCTest

final class ProcessEnvironmentSanitizerTests: XCTestCase {
    func testIsDynamicLoaderKeyIdentifiesDynamicLoaderKeys() {
        let dynamicKeys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH",
            "DYLD_ROOT_PATH",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "DYLD_FALLBACK_FRAMEWORK_PATH",
            "DYLD_CUSTOM_VAR",
            "__XPC_DYLD_INSERT_LIBRARIES",
            "__XPC_DYLD_SOMETHING"
        ]

        for key in dynamicKeys {
            XCTAssertTrue(
                ProcessEnvironmentSanitizer.isDynamicLoaderKey(key),
                "Expected \(key) to be identified as dynamic loader key"
            )
        }

        let safeKeys = [
            "PATH",
            "HOME",
            "USER",
            "SHELL",
            "XPC_SERVICE_NAME",
            "DY_NOT_LOADER",
            "XPC_DYLD_NO_PREFIX"
        ]

        for key in safeKeys {
            XCTAssertFalse(
                ProcessEnvironmentSanitizer.isDynamicLoaderKey(key),
                "Expected \(key) NOT to be identified as dynamic loader key"
            )
        }
    }

    func testSanitizedForChildLaunchStripsDynamicLoaderAndAdditionalKeys() {
        let inputEnvironment: [String: String] = [
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/test",
            "DYLD_INSERT_LIBRARIES": "/path/to/malicious.dylib",
            "DYLD_LIBRARY_PATH": "/path/to/libs",
            "__XPC_DYLD_INSERT_LIBRARIES": "/path/to/xpc.dylib",
            "SECRET_TOKEN": "sensitive_val"
        ]

        let sanitized = ProcessEnvironmentSanitizer.sanitizedForChildLaunch(
            inputEnvironment,
            additionalRemovedKeys: ["SECRET_TOKEN"]
        )

        XCTAssertEqual(sanitized["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(sanitized["HOME"], "/Users/test")
        XCTAssertNil(sanitized["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(sanitized["DYLD_LIBRARY_PATH"])
        XCTAssertNil(sanitized["__XPC_DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(sanitized["SECRET_TOKEN"])
    }
}
