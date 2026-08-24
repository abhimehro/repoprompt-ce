## 2025-01-24 - Swift TOCTOU Vulnerability on File Creation
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing files and then changing permissions (e.g. `write(to:)` followed by `setAttributes`).
**Learning:** `write(to:)` creates a file with default POSIX permissions before `setAttributes` applies secure permissions, creating a race window where another process can read or overwrite the file.
**Prevention:** Use `FileManager.default.createFile(atPath:contents:attributes:)` to securely set permissions atomically during file creation, followed by a secure atomic move to the destination file.
