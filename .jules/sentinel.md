## 2024-08-09 - File Attribute TOCTOU Race Condition
**Vulnerability:** Setting POSIX permissions on a sensitive file after writing it (via `write(to:)` and `setAttributes`) creates a Time-of-Check-to-Time-of-Use (TOCTOU) vulnerability where the file is briefly readable by other processes.
**Learning:** The window between file creation and attribute setting leaves sensitive data (like MCP terminal records) exposed.
**Prevention:** Create a temporary file with `FileManager.default.createFile(atPath:contents:attributes:)` to set permissions atomically at creation time, then securely move it to the final destination using `replaceItem(at:withItemAt:backupItemName:options:)` or `moveItem(at:to:)`.
