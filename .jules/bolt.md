## 2024-10-24 - Expensive Formatter Instantiation in Changelog
**Learning:** Found over 200 inline instantiations of `ISO8601DateFormatter()` in `Changelog.swift`. In Swift, `DateFormatter` and `ISO8601DateFormatter` are extremely expensive to initialize and can cause significant performance overhead or CI timeouts when initialized repeatedly in a loop or large array.
**Action:** Always reuse a single `static let` instance. When extracting to a static property inside a `Sendable` type, mark it with `nonisolated(unsafe)` to prevent Swift strict concurrency warnings.
