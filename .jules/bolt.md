## 2026-06-12 - DateFormatter Performance in Swift
**Learning:** `DateFormatter` is highly expensive to instantiate in Swift. Repeated instantiations (e.g. inside a loop or frequent method calls) can cause noticeable performance degradation.
**Action:** Extract `DateFormatter` instances to a static shared property when the formatting style remains constant. Note that it is thread-safe to use for formatting strings.

## 2026-06-12 - SwiftUI View Re-computations
**Learning:** Collection operations like `.filter { ... }` or `.map { ... }` that run directly in SwiftUI view body (like inside a `.disabled(...)` modifier and a `ForEach`) will execute twice per render pass.
**Action:** Always compute these values once into a local constant within the `ViewBuilder` closure and use that constant to avoid redundant O(N) operations.
