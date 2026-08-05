## 2024-10-25 - Prevent TOCTOU in file writing
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing sensitive files using `.write(to:)` followed by `FileManager.setAttributes()`.
**Learning:** Writing data with default permissions and changing them afterward leaves a brief window where sensitive data can be read or modified by unauthorized processes.
**Prevention:** Create a temporary file with secure permissions using `FileManager.default.createFile(atPath:contents:attributes:)` first, check its boolean return value, and then atomically move it to the final destination using `replaceItem(at:withItemAt:backupItemName:options:)` or `moveItem(at:to:)`.
