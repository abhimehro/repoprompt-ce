## 2024-08-07 - Fix TOCTOU vulnerability in file permissions
**Vulnerability:** TOCTOU race condition when writing files and then setting their permissions via `setAttributes`.
**Learning:** Writing data and then setting permissions creates a window where the file is accessible with default (broad) permissions before they are restricted.
**Prevention:** Write to a temporary file with secure permissions via `createFile` first, then atomically replace the target file.
