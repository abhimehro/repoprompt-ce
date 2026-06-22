## 2025-05-18 - ISO8601DateFormatter Initialization Overhead
**Learning:** Instantiating `DateFormatter` or `ISO8601DateFormatter` repeatedly is highly expensive in Swift and can severely impact startup performance (especially if done hundreds of times as in `Changelog.swift`).
**Action:** Always extract formatter instances to a static shared property when formatting style is constant.
