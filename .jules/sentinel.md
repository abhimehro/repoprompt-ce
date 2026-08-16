## 2024-05-14 - Initialize Sentinel
**Vulnerability:** Initial run
**Learning:** Set up Sentinel.
**Prevention:** Need to read it.
## 2024-05-14 - Fix TOCTOU vulnerability
**Vulnerability:** Time-of-Check-to-Time-of-Use race condition when writing files and setting POSIX permissions separately.
**Learning:** In Swift, writing a file then updating its POSIX attributes creates a TOCTOU race condition. Using `createFile` with attributes ensures secure initial permissions.
**Prevention:** Create temporary files with POSIX attributes directly using `createFile`, then atomically move or replace.
