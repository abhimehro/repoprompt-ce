## 2024-05-14 - Expensive DateFormatter Instantiation in Swift
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` in Swift is a known, surprisingly expensive operation. Initializing hundreds of them inline (like in a static constants file such as a Changelog) causes measurable performance degradation and memory overhead.
**Action:** Always extract formatter instances to a `static shared property` (e.g., `static let isoFormatter: ISO8601DateFormatter = { ... }()`) when the formatting style is constant across usage sites.
## 2024-05-14 - Repeated DateFormatter Invocations in String Output Loops
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` continuously in formatting loops (such as parsing lines for blame or commit history in Git outputs) adds significant, unnecessary CPU overhead and memory allocations.
**Action:** Extract formatters with fixed string formats or date/time styles to a static property, even inside smaller helper functions or extensions, instead of declaring them inline.

## 2026-07-04 - Avoid SwiftUI init for expensive operations
**Learning:** In SwiftUI, View structs are ephemeral data descriptions, and `init` is called every time the parent evaluates its body. Moving an expensive operation (like string splitting) from a computed property into the `init` method introduces severe performance regressions on the main thread, especially in scrollable lists.
**Action:** Never move expensive computations into a SwiftUI view's `init` method to optimize them. Instead, use view models to pre-compute the data before passing it to the view, or rely on lazy evaluation for items that may not need rendering.

## 2026-07-04 - String allocation efficiency
**Learning:** In Swift, using `components(separatedBy:)` allocates a new `Array` of `String` components, which can be computationally expensive if called frequently (e.g., during sorting of thousands of files).
**Action:** When extracting simple parts of strings (like a file extension), use native `String` index and slice methods (e.g., `lastIndex(of:)`, `suffix(from:)`) to avoid unnecessary array allocations.
