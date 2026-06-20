## 2024-05-18 - Caching Swift DateFormatter
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` in Swift is highly expensive. When dealing with static data containing hundreds of date strings (e.g., in a changelog), repeatedly instantiating `ISO8601DateFormatter()` causes significant performance degradation.
**Action:** Always extract `DateFormatter` or `ISO8601DateFormatter` instances to a static shared property when the formatting style is constant.
