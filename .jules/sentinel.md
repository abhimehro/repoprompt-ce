## 2024-08-04 - TOCTOU Race Condition in File Writes
**Vulnerability:** Writing sensitive files using `String.write(to:)` or `Data.write(to:)` followed by `FileManager.setAttributes` creates a Time-of-Check-to-Time-of-Use (TOCTOU) race condition where a file exists briefly with insecure permissions.
**Learning:** `write(to:)` cannot atomically set POSIX permissions in Swift. Attackers can read sensitive data during this brief window.
**Prevention:** Use `FileManager.default.createFile(atPath:contents:attributes:)` to a temporary path to guarantee initial permissions securely, then atomically move it to the destination using `replaceItem` or `moveItem`.
