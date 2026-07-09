## 2023-10-27 - [Avoid In-line DateFormatters]
**Learning:** [In Swift codebases, instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive and creating them in-line in large numbers (like in a Changelog or large arrays) causes noticeable performance degradation.]
**Action:** [Always extract formatter instances to a static shared property when formatting style is constant to avoid noticeable performance degradation.]
