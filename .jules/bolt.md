## 2026-07-30 - Optimize Array Deduplication
**Learning:** Avoid custom extensions (`removeDuplicatesInPlace()`) not in the standard Swift library unless you are certain they exist and are accessible, as they result in compile errors. Also, for large arrays, appending and then deduplicating is less optimal than checking membership initially via a `Set`.
**Action:** Default to extracting standard Swift `Set` logic (`var seen = Set(array)`, then `seen.insert(item).inserted`) when fixing N^2 loop containment checks.
## 2025-03-01 - DateFormatter Performance Bottleneck
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive in Swift. Doing it inline (e.g., `ISO8601DateFormatter().date(from:)`) multiple times—such as 200+ times in `Changelog.swift`—causes significant performance degradation during app initialization.
**Action:** Always extract formatter instances to a static shared property when the formatting style is constant. They are thread-safe for reading and parsing.
