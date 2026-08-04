## 2024-08-04 - Redundant file read during decoding
**Learning:** Re-reading the same file during decoding wastes I/O and time.
**Action:** Reuse the already read `Data` variable to decode instead of reading the file again.
