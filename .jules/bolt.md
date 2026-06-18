## 2026-06-12 - DateFormatter Performance in Swift
**Learning:** `DateFormatter` is highly expensive to instantiate in Swift. Repeated instantiations (e.g. inside a loop or frequent method calls) can cause noticeable performance degradation.
**Action:** Extract `DateFormatter` instances to a static shared property when the formatting style remains constant. Note that it is thread-safe to use for formatting strings.

## 2026-06-12 - SwiftUI View Re-computations
**Learning:** Collection operations like `.filter { ... }` or `.map { ... }` that run directly in SwiftUI view body (like inside a `.disabled(...)` modifier and a `ForEach`) will execute twice per render pass.
**Action:** Always compute these values once into a local constant within the `ViewBuilder` closure and use that constant to avoid redundant O(N) operations.
## 2026-06-18 - Expensive String Operations in SwiftUI Views
**Learning:** Expensive operations like `content.components(separatedBy: "\n")` when used inside computed properties that are called multiple times during a SwiftUI view's render pass lead to severe performance degradation.
**Action:** Always extract these expensive computations into local variables at the beginning of the `body` property to ensure they are evaluated exactly once per render cycle.
