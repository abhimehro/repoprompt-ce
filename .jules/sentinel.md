## 2025-02-21 - Fix TOCTOU vulnerability in file writing
**Vulnerability:** Time-of-Check-to-Time-of-Use (TOCTOU) race condition when writing files using `Data.write(to:)` or `String.write(to:)` followed by `FileManager.setAttributes`.
**Learning:** Writing data to a file and then setting attributes in a separate step creates a window where the file exists with default permissions, which may be insecure (e.g., 0o644 instead of 0o600).
**Prevention:** Use `FileManager.default.createFile(atPath:contents:attributes:)` to write to a temporary file with the correct secure permissions atomically, then use `FileManager.replaceItem` or `FileManager.moveItem` to move it to the final destination.
