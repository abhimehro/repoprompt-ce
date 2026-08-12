## 2024-08-12 - TOCTOU File Write Vulnerability
**Vulnerability:** Writing files using `.write(to:)` followed by `FileManager.default.setAttributes` creates a Time-of-Check-to-Time-of-Use (TOCTOU) race condition.
**Learning:** This is an insecure pattern. Between the time the file is written and its attributes (like permissions) are set, an attacker could potentially access the file or replace it with a symlink.
**Prevention:** Use `FileManager.default.createFile(atPath:contents:attributes:)` to securely create the file with the desired permissions atomically, avoiding the race condition.
