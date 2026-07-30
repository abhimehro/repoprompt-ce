## 2024-05-15 - Dictionary Check Perf
**Learning:** Checking for dictionary key existence with `.keys.contains(_)` in Swift creates O(N) linear time complexity for each lookup.
**Action:** Always prefer direct subscripting (e.g. `dict[key] != nil`) which uses the O(1) hash map lookup.
