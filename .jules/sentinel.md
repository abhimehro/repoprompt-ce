## 2025-02-14 - Fix TOCTOU Vulnerability in File Writes
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing files using `write(to:)` and subsequently setting POSIX permissions using `setAttributes`.
**Learning:** This approach leaves a brief window where the file exists with default (often overly permissive) permissions before the restrictive permissions are applied, leaving sensitive data exposed momentarily.
**Prevention:** Create a temporary file securely with `FileManager.createFile(atPath:contents:attributes:)` to set atomic initial permissions, and then safely swap/move the file to its destination. Ensure to clean up the temporary file using `defer` and propagate I/O errors properly.
