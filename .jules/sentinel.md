## 2024-05-24 - TOCTOU File Write Vulnerability
**Vulnerability:** Use of `String.write(to:)` or `Data.write(to:)` followed by `FileManager.setAttributes` creates a Time-of-Check-to-Time-of-Use (TOCTOU) race condition where a file is written with default POSIX permissions before its permissions are locked down.
**Learning:** `Data.write(to:)` doesn't provide a way to set POSIX attributes at creation time atomically, making the file momentarily vulnerable to reading/modification by unauthorized processes.
**Prevention:** Create a temporary file with secure permissions using `FileManager.default.createFile(atPath:contents:attributes:)` (with a unique UUID name), and then safely move it using `replaceItem` (if destination exists) or `moveItem` to the destination URL.
