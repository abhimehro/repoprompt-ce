## 2026-09-28 - Swift Date.ISO8601FormatStyle Fractional Seconds Syntax
**Learning:** `Date.ISO8601FormatStyle` in Swift Foundation uses `.formatted(.iso8601.includingFractionalSeconds)` to include fractional seconds, rather than `.withFractionalSeconds` or `.time(includingFractionalSeconds: true)`.
**Action:** Use `.formatted(.iso8601.includingFractionalSeconds)` when replacing `ISO8601DateFormatter` in hot paths that require sub-second precision.
