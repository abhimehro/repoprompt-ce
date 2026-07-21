## 2023-10-27 - [Avoid In-line DateFormatters]
**Learning:** [In Swift codebases, instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive and creating them in-line in large numbers (like in a Changelog or large arrays) causes noticeable performance degradation.]
**Action:** [Always extract formatter instances to a static shared property when formatting style is constant to avoid noticeable performance degradation.]
## $(date +%Y-%m-%d) - [Thread-Safe Static DateFormatters]
**Learning:** [In Swift codebases, instantiating `DateFormatter` or `ISO8601DateFormatter` is highly expensive. They are thread-safe for reading and parsing on macOS 10.9+, making static caching safe without locks, which prevents noticeable performance degradation during loops.]
**Action:** [Always extract formatter instances to a static shared property when the formatting style is constant to avoid noticeable performance degradation.]
## 2026-07-21 - DateFormatter Performance Bottleneck
**Learning:** Instantiating DateFormatter or ISO8601DateFormatter inline in Swift is highly expensive and can degrade performance when called frequently. They are thread-safe on macOS 10.9+, so they should always be statically cached.
**Action:** Always extract constant DateFormatters to static shared properties.
