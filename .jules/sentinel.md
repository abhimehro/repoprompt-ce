## 2026-08-18 - TOCTOU file writing vulnerability
**Vulnerability:** File permission TOCTOU race condition when writing sensitive config JSON files.
**Learning:**  immediately followed by  creates a brief window where the file exists with default permissions before being locked down.
**Prevention:** Use  to create a temporary file with the target strict permissions atomically upon creation, then atomically  or  the temporary file to the destination.
## 2024-05-24 - TOCTOU file writing vulnerability
**Vulnerability:** File permission TOCTOU race condition when writing sensitive config JSON files.
**Learning:** `data.write` immediately followed by `setAttributes` creates a brief window where the file exists with default permissions before being locked down.
**Prevention:** Use `createFile` to create a temporary file with the target strict permissions atomically upon creation, then atomically `moveItem` or `replaceItem` the temporary file to the destination.
