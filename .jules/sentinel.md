## 2026-08-11 - Prevent TOCTOU in file writes
**Vulnerability:** TOCTOU race conditions when creating files with `String.write` or `Data.write` followed by `FileManager.setAttributes` to enforce strict permissions.
**Learning:** Writing sensitive data first and then restricting permissions leaves a race window where the data can be read by other processes. It breaks atomicity.
**Prevention:** Use `FileManager.createFile(atPath:contents:attributes:)` with a temporary file name (e.g. UUID) to set permissions atomically on creation, then `replaceItem(at:withItemAt:...)` to move it to the target location atomically.
