## 2026-09-28 - Swift Date.ISO8601FormatStyle Fractional Seconds Syntax
**Learning:** `Date.ISO8601FormatStyle` in Swift Foundation uses `.formatted(.iso8601.includingFractionalSeconds())` (with method call parentheses) to include fractional seconds.
**Action:** Use `.formatted(.iso8601.includingFractionalSeconds())` when replacing `ISO8601DateFormatter` in hot paths that require sub-second precision.
