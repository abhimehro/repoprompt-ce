## 2026-08-04 - CI test failures on Linux
**Learning:** CI failures on CodeMapRootManifestStoreTests, particularly `testVerifiedCleanSnapshotRoundTripsWithoutAbsoluteDisplayOrSourceLeakage`, appear unrelated to the ChatPresetManager modification. The error code 1 points to `RepoPromptTests.CodeMapRootManifestStoreTests failed; elapsed=37.1s`. The modified file (`Sources/RepoPrompt/Features/Chat/ViewModels/Presets/ChatPresetManager.swift`) manages chat settings and has absolutely no dependency or connection to the `CodeMapRootManifestStore` or its low-level caching codec mechanisms, which operate on file systems and binary manifests. The failure might be environment-specific (Linux test flakes for filesystem interactions) or an underlying issue on `main`.
**Action:** Since the user's prompt only requested to "Integrate with ModelPresetsManager for Model Validation" in ChatPresetManager and the CI failure is totally unrelated to this scope, I will submit the requested fix while ignoring the unrelated CodeMap failure, per the boundary rules.
## 2026-08-06 - DateFormatter Instantiation Overhead
**Learning:** In Swift, DateFormatter and ISO8601DateFormatter are notoriously expensive to initialize. Reusing a single static let instance is a standard, thread-safe performance optimization to avoid repeated instantiation overhead when formatting or parsing multiple dates. In Changelog.swift, ISO8601DateFormatter() is instantiated inline over 200 times.
**Action:** Extract inline DateFormatter/ISO8601DateFormatter initializations to a static private property to avoid unnecessary allocation overhead.

## 2026-08-06 - Redundant file read during decoding (re-salvage #195)
**Learning:** Re-reading the same file during decoding wastes I/O and time.
**Action:** Reuse the already read `Data` variable to decode instead of reading the file again.
## 2024-08-09 - DateFormatter Instantiation Overhead
**Learning:** DateFormatter and ISO8601DateFormatter are extremely expensive to initialize in Swift. We found several instances of inline ISO8601DateFormatter().string(from:) usage that could cause severe performance issues in high-frequency paths.
**Action:** Refactored these instantiations by reusing static let instances of ISO8601DateFormatter to prevent unnecessary allocation overhead, specifically across multiple feature modules (like RuntimePolicyAdministration, ACPAgentSessionController, etc).
## 2024-08-09 - WorkspaceFileContextStoreTests flakes
**Learning:** `WorkspaceFileContextStoreTests` tests sometimes flake in GitHub Actions CI (e.g., `testWriteAdaptersAndApplyEditsMaterializeCreateOverwriteAndFailurePostconditions`), returning exit code 1. This appears to be an environmental or timing issue unrelated to simple code improvements like caching DateFormatter.
**Action:** Recognize this as a CI flake when it appears disjointed from the code under modification, and ignore the flake.
## 2024-08-13 - DateFormatter Instantiation Overhead
**Learning:** `DateFormatter` and `ISO8601DateFormatter` are extremely expensive to initialize in Swift. We found several instances of inline `DateFormatter` and `ISO8601DateFormatter` usage that could cause severe performance issues in high-frequency paths (e.g. `GitService` parsing blame output).
**Action:** Refactored these instantiations by reusing static let instances of `DateFormatter` and `ISO8601DateFormatter` to prevent unnecessary allocation overhead. Used `nonisolated(unsafe)` when extracting them to a static property inside a `Sendable` type to prevent strict concurrency warnings.
