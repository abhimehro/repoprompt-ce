## 2023-10-27 - DateFormatter Instantiation Overhead
**Learning:** In Swift codebases, `ISO8601DateFormatter` and `DateFormatter` instantiations are significantly expensive. Repeated inline instantiations, such as those inside large static arrays or data structures (like a changelog with 200+ entries), cause measurable initialization delays.
**Action:** Always extract constant-format DateFormatters to a single `private static let` shared property to avoid repeated initialization costs.
