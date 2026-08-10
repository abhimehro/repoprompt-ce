## 2024-08-10 - Secure File Creation to Prevent TOCTOU
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing sensitive files using String.write(to:) followed by FileManager.setAttributes. An attacker could potentially replace the file before attributes are set, gaining unauthorized access.
**Learning:** Swift's String.write or Data.write doesn't allow setting POSIX permissions atomically upon creation. Applying permissions after creation leaves a tiny window where the file has default (often broader) permissions.
**Prevention:** Use FileManager.createFile(atPath:contents:attributes:) to create a temporary file with secure initial POSIX permissions, then atomically replace/move it to the destination.
