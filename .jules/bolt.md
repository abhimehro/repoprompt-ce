## 2026-09-21 - Swift Date Formatting Performance in High-Frequency Paths
**Learning:** `ISO8601DateFormatter` initialization is extremely expensive and non-thread-safe. In high-frequency notification paths like `RepoPromptProgressNotification`, allocating a new instance per progress event creates unnecessary object allocation overhead and CPU strain.
**Action:** Use Swift Foundation's native, thread-safe `date.formatted(.iso8601)` in date-to-string formatting paths instead of instantiating `ISO8601DateFormatter()`.
