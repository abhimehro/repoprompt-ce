## 2025-08-25 - Extracted ISO8601DateFormatter to a static property
**Learning:** Instantiating `ISO8601DateFormatter` is highly expensive in Swift. In a file like `Changelog.swift` with over 200 occurrences inline, it creates significant performance overhead during initialization and can even cause CI timeouts.
**Action:** Always reuse a single `static let` instance for `DateFormatter` and `ISO8601DateFormatter`. When adding to a `Sendable` type, mark it `nonisolated(unsafe)` to prevent Swift strict concurrency warnings.
