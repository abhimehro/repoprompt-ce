## 2025-02-05 - Extracted Expensive Formatters to Static Properties
**Learning:** Found over 200 inline instantiations of `ISO8601DateFormatter` within a single file (`Sources/RepoPrompt/App/Changelog.swift`), which is a major performance anti-pattern in Swift.
**Action:** Extract formatters to shared static variables inside the class scope.
