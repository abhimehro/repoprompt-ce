## 2024-05-24 - File Creation TOCTOU Prevention
**Vulnerability:** Time-of-Check-to-Time-of-Use race condition during initial file creation, leaving a window where POSIX attributes are loose before `setAttributes`.
**Learning:** The standard Data.write(to:) followed by FileManager.setAttributes pattern creates a window where sensitive files have default permissions before being secured.
**Prevention:** Use FileManager.default.createFile(atPath:contents:attributes:) to atomically create the file with the correct secure permissions from the start.
