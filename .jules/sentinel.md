# Sentinel Security Journal

## 2025-10-02 - Case-Insensitive Dynamic Loader Variable Sanitization
**Vulnerability:** Case-sensitive environment variable checks permitted dynamic loader injection variables (e.g., `dyld_insert_libraries`, `LD_PRELOAD`, `ld_preload`) to bypass child process sanitization and security monitoring.
**Learning:** Operating system dynamic linkers and environment variable passes may accept lowercase or mixed-case injection keys or platform-specific prefixes (`LD_` on ELF/Linux alongside `DYLD_` on macOS).
**Prevention:** Normalize environment keys to uppercase when evaluating dynamic loader blocklists (`DYLD_`, `__XPC_DYLD_`, `LD_`) and sanitize all casing variants before launching child processes.
