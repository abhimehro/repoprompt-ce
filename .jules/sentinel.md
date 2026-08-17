## 2024-10-24 - Swift TOCTOU via File Attributes
**Vulnerability:** Writing data via String or Data .write() and then applying POSIX permissions using FileManager.setAttributes creates a Time-of-Check-to-Time-of-Use race condition.
**Learning:** Swift native APIs do not allow atomically setting permissions upon file creation via .write(), exposing the file to read/write by unauthorized processes in the gap.
**Prevention:** Create temporary files with FileManager.default.createFile which takes posix permissions initially, then atomically replace the target file.
