## 2025-05-18 - Process Isolation for Unzip Execution
**Vulnerability:** Child process execution using `Process()` without configuring standard descriptors risks process inheritance or hanging on input.
**Learning:** Default `Process` invocations inherit parent process `stdin`, `stdout`, and `stderr` handles unless explicitly bound to `FileHandle.nullDevice` or dedicated pipes.
**Prevention:** Always isolate spawned sub-processes by redirecting `standardInput` to `FileHandle.nullDevice` and capturing/discarding output via `Pipe()` instances.
