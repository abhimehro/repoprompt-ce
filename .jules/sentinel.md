## 2026-08-08 - Secure File Creation
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition during file write.
**Learning:** Writing files via `write(to:)` followed by `setAttributes` leaves a brief window where files have default, insecure permissions before they are restricted. An attacker could exploit this race condition to read or modify sensitive data.
**Prevention:** Create files securely with initial permissions using `FileManager.createFile(atPath:contents:attributes:)` to a temporary path, then atomically move to the destination.
