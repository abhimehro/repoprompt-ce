## 2024-06-25 - Expensive DateFormatter Instantiation
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` in Swift is highly expensive and can lead to noticeable performance degradation if done repeatedly.
**Action:** Extract formatter instances to a static shared property when formatting style is constant to avoid this overhead.
