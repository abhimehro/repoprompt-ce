## 2024-08-23 - ISO8601DateFormatter Expensive Instantiation
**Learning:** `ISO8601DateFormatter` (and `DateFormatter`) in Swift are extremely expensive to initialize. Instantiating them inline (e.g., inside loops, properties, or long arrays) can cause severe performance issues or CI timeouts.
**Action:** Always extract these to a single `static let` instance. When doing so in a `Sendable` type context, annotate it with `nonisolated(unsafe)` to prevent Swift strict concurrency warnings.
