import Foundation

/// Shared process-environment sanitization for child process launches.
///
/// Phase 1 only centralizes the policy and constants. Existing launch callers are
/// migrated in later phases so security detection and spawn-time scrubbing cannot
/// drift on dynamic-loader environment keys. Sanitization treats all `DYLD_`, `LD_`, and
/// `__XPC_DYLD_` variables as dynamic-loader state.
enum ProcessEnvironmentSanitizer {
    static let dynamicLoaderInsertLibrariesKey = "DYLD_INSERT_LIBRARIES"

    static let dynamicLoaderKeys: Set<String> = [
        dynamicLoaderInsertLibrariesKey,
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "DYLD_ROOT_PATH",
        "DYLD_FALLBACK_LIBRARY_PATH",
        "DYLD_FALLBACK_FRAMEWORK_PATH",
        "LD_PRELOAD",
        "LD_LIBRARY_PATH",
        "LD_AUDIT"
    ]

    static let dynamicLoaderKeyPrefixes: [String] = [
        "DYLD_",
        "__XPC_DYLD_",
        "LD_"
    ]

    static func sanitizedForChildLaunch(
        _ environment: [String: String],
        additionalRemovedKeys: Set<String> = []
    ) -> [String: String] {
        let upperRemovedKeys = Set(additionalRemovedKeys.map { $0.uppercased() })
        return environment.filter { key, _ in
            !isDynamicLoaderKey(key) && !upperRemovedKeys.contains(key.uppercased())
        }
    }

    static func isDynamicLoaderInsertKey(_ key: String) -> Bool {
        let upperKey = key.uppercased()
        return upperKey == dynamicLoaderInsertLibrariesKey || upperKey == "LD_PRELOAD"
    }

    static func isDynamicLoaderKey(_ key: String) -> Bool {
        let upperKey = key.uppercased()
        if dynamicLoaderKeys.contains(upperKey) {
            return true
        }
        return dynamicLoaderKeyPrefixes.contains { upperKey.hasPrefix($0) }
    }
}
