## 2025-05-15 - Extract ISO8601DateFormatter
**Learning:** In Swift, `DateFormatter` and `ISO8601DateFormatter` are extremely expensive to initialize. Inline instantiation in high-frequency paths can cause severe performance issues and CI timeouts.
**Action:** Always reuse a single `static let` instance to avoid repeated instantiation overhead. When extracting these to a static property inside a `Sendable` type, mark the declaration with `nonisolated(unsafe)` to prevent Swift strict concurrency warnings.
