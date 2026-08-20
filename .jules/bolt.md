## 2024-05-18 - Swift DateFormatter Pitfalls
**Learning:** In Swift, initializing `ISO8601DateFormatter` (or `DateFormatter`) is notoriously expensive. Creating inline instances for 100+ strings in arrays/views (like `Changelog.swift`) causes massive initialization hitch/overhead. Using `nonisolated(unsafe) static let` to reuse a shared formatter is a core performance pattern for modern Swift concurrency that prevents these issues.
**Action:** Always hunt for and extract inline `DateFormatter()`/`ISO8601DateFormatter()` instantiations to shared static singletons in high-frequency paths.
