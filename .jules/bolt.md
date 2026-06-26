## 2024-05-14 - Expensive DateFormatter Instantiation in Swift
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` in Swift is a known, surprisingly expensive operation. Initializing hundreds of them inline (like in a static constants file such as a Changelog) causes measurable performance degradation and memory overhead.
**Action:** Always extract formatter instances to a `static shared property` (e.g., `static let isoFormatter: ISO8601DateFormatter = { ... }()`) when the formatting style is constant across usage sites.
## 2024-05-14 - Repeated DateFormatter Invocations in String Output Loops
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` continuously in formatting loops (such as parsing lines for blame or commit history in Git outputs) adds significant, unnecessary CPU overhead and memory allocations.
**Action:** Extract formatters with fixed string formats or date/time styles to a static property, even inside smaller helper functions or extensions, instead of declaring them inline.
