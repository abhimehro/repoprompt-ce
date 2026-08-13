
## 2024-05-24 - TOCTOU File Write Race Condition
**Vulnerability:** TOCTOU race condition when writing configuration files. `String.write` followed by `FileManager.setAttributes` leaves a window where the file has default permissions before being secured.
**Learning:** Using `FileManager.default.createFile(atPath:contents:attributes:)` on a temporary file followed by an atomic move ensures permissions are correctly enforced from the moment of creation.
**Prevention:** Use a unique temporary file and `createFile` with `.posixPermissions` when writing sensitive data, then `moveItem` or `replaceItem` to the final destination.
