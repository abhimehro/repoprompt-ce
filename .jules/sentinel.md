
## 2026-08-22 - Fix TOCTOU vulnerability in file writes
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing sensitive files using String.write(to:) or Data.write(to:) followed by FileManager.setAttributes.
**Learning:** This approach leaves a brief window where the file is written with default POSIX permissions before they are restricted, potentially exposing sensitive data.
**Prevention:** Use FileManager.default.createFile(atPath:contents:attributes:) to create a temporary file with secure initial permissions, then atomically move/replace it to the destination.
