## 2026-03-31 - Enforce Dynamic Loader Sanitization at Spawn Boundary
**Vulnerability:** Unsanitized environment passed to posix_spawnp allowed potential dynamic loader library injection (DYLD_INSERT_LIBRARIES, DYLD_*, __XPC_DYLD_*) in spawned child processes.
**Learning:** High-level environment builders sanitized environment variables, but low-level ProcessLauncher.spawn did not enforce sanitization at the POSIX spawn boundary, leaving direct callers unprotected against dynamic loader injection.
**Prevention:** Always enforce security sanitization policies at low-level execution boundaries rather than relying on caller discipline.
