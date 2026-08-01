## 2025-03-01 - DateFormatter Performance Bottleneck
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive in Swift. Doing it inline (e.g., `ISO8601DateFormatter().date(from:)`) multiple times—such as 200+ times in `Changelog.swift`—causes significant performance degradation during app initialization.
**Action:** Always extract formatter instances to a static shared property when the formatting style is constant. They are thread-safe for reading and parsing.
