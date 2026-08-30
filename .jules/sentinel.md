## 2024-08-30 - TOCTOU vulnerabilities in file writes

**Vulnerability:** Found Time-of-Check-to-Time-of-Use (TOCTOU) race conditions when writing sensitive configuration files (like MCP configs or Terminal records). The code used `data.write(to:options:)` followed by `FileManager.default.setAttributes([.posixPermissions: 0o600], ...)` which momentarily creates the file with default insecure permissions before tightening them.

**Learning:** In Swift, writing data to a file with Foundation's standard APIs and applying permissions in two separate steps leaves a small window where the file is readable by other processes on the system with default permissions.

**Prevention:** Always use `FileManager.default.createFile(atPath:contents:attributes:)` using a temporary file with the secure permissions applied at creation time, then atomically move (`replaceItem`/`moveItem`) it to the final destination to guarantee it's never observable in an insecure state.
