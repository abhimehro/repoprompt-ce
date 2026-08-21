## 2024-11-13 - [DateFormatter Overhead]
**Learning:** ISO8601DateFormatter instantiation is extremely expensive in Swift, especially when used inside high-frequency paths like an array of changelog versions. Over 200 formatters are instantiated statically during app launch in `Changelog.swift`.
**Action:** Extract a single `nonisolated(unsafe) private static let iso8601Formatter = ISO8601DateFormatter()` and reuse it to avoid repeated instantiation overhead and improve startup times.
