## 2026-08-06 - DateFormatter Instantiation Overhead
**Learning:** In Swift, DateFormatter and ISO8601DateFormatter are notoriously expensive to initialize. Reusing a single static let instance is a standard, thread-safe performance optimization to avoid repeated instantiation overhead when formatting or parsing multiple dates. In Changelog.swift, ISO8601DateFormatter() is instantiated inline over 200 times.
**Action:** Extract inline DateFormatter/ISO8601DateFormatter initializations to a static private property to avoid unnecessary allocation overhead.
## 2024-08-09 - DateFormatter Instantiation Overhead
**Learning:** DateFormatter and ISO8601DateFormatter are extremely expensive to initialize in Swift. We found several instances of inline ISO8601DateFormatter().string(from:) usage that could cause severe performance issues in high-frequency paths.
**Action:** Refactored these instantiations by reusing static let instances of ISO8601DateFormatter to prevent unnecessary allocation overhead, specifically across multiple feature modules (like RuntimePolicyAdministration, ACPAgentSessionController, etc).
## 2026-08-06 - DateFormatter Instantiation Overhead
**Learning:** In Swift, DateFormatter and ISO8601DateFormatter are notoriously expensive to initialize. Reusing a single static let instance is a standard, thread-safe performance optimization to avoid repeated instantiation overhead when formatting or parsing multiple dates.
**Action:** Extract inline DateFormatter/ISO8601DateFormatter initializations to a static private property to avoid unnecessary allocation overhead.
