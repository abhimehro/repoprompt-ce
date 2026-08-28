## 2024-05-24 - TOCTOU File Writes
**Vulnerability:** `String.write` and `Data.write` followed by `FileManager.setAttributes` creates a race condition.
**Learning:** Writing data before securing permissions leaves a window where data is exposed.
**Prevention:** Use `FileManager.createFile` to set permissions atomically at creation, then move the temporary file to its destination.
