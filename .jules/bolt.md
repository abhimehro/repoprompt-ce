## 2026-08-03 - DateFormatter initialization overhead in Swift
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive in Swift. Creating hundreds of instances (e.g., parsing a changelog array) causes noticeable performance degradation.
**Action:** Always extract formatter instances to a static shared property when the formatting style is constant. They are thread-safe for reading and parsing on macOS 10.9+, making static caching safe without locks.
