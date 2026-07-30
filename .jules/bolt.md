## 2026-07-30 - Optimize Array Deduplication
**Learning:** Avoid custom extensions (`removeDuplicatesInPlace()`) not in the standard Swift library unless you are certain they exist and are accessible, as they result in compile errors. Also, for large arrays, appending and then deduplicating is less optimal than checking membership initially via a `Set`.
**Action:** Default to extracting standard Swift `Set` logic (`var seen = Set(array)`, then `seen.insert(item).inserted`) when fixing N^2 loop containment checks.
## 2026-07-30 - DateFormatter Bottleneck
**Learning:** Instantiating ISO8601DateFormatter repeatedly in large static arrays (like Changelog versions) is highly expensive and degrades startup performance.
**Action:** Always extract DateFormatter instances to a static shared property.
