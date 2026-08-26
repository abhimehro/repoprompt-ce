## 2025-02-12 - Prevent Repeated ISO8601DateFormatter Initialization
**Learning:** `ISO8601DateFormatter` initialization in Swift is extremely expensive. Instantiating it in high-frequency paths (such as parsing the entire `Changelog` history directly) can cause severe performance issues or timeouts. We found 216 inline initializations of `ISO8601DateFormatter()` in `Changelog.swift`.
**Action:** Extract `ISO8601DateFormatter()` calls into a shared `nonisolated(unsafe) static let` instance and reuse it across all formatting calls to avoid repeated instantiation overhead.
