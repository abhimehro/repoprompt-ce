## 2026-09-21 - Swift Date Formatting Performance in High-Frequency Paths
**Learning:** `ISO8601DateFormatter` initialization is extremely expensive and non-thread-safe. In high-frequency notification paths like `RepoPromptProgressNotification`, allocating a new instance per progress event creates unnecessary object allocation overhead and CPU strain.
**Action:** Use Swift Foundation's native, thread-safe `date.formatted(.iso8601)` in date-to-string formatting paths instead of instantiating `ISO8601DateFormatter()`.

**Benchmark:** The end-to-end-ish notification path is covered by
`MCPControlMessagesTests/testProgressNotificationThroughputUnderContention`. It creates
and JSON-encodes 8,000 progress notifications from eight concurrent workers (the encoding
is the delivery boundary used by the MCP transport). Reproduce with:

```sh
swift test -c release --filter MCPControlMessagesTests/testProgressNotificationThroughputUnderContention
```

The XCTest `measure` output reports the elapsed time per 8,000 notifications; divide
8,000 by that value for throughput. Run the command once on the baseline commit and once
on the change, on the same machine and power mode. For CPU contention and allocations,
run the same test under Instruments' **Time Profiler** and **Allocations** templates and
record hardware, OS, Swift configuration, iteration count, median elapsed time,
notifications/second, CPU time, and total allocations with the review results. This
keeps the performance claim reproducible rather than inferring it from formatter setup
alone.
