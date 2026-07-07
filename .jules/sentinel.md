## 2025-02-09 - Hardcoded HTTPClient URLSessionConfiguration timeout properties missing
**Vulnerability:** HTTP requests using `URLSessionConfiguration.default` could potentially persist sensitive data or credentials across sessions using default cache and cookie storages.
**Learning:** `URLSessionConfiguration.default` persists session data like cookies and credentials which is risky for an agent fetching potentially untrusted or varied resources.
**Prevention:** Use `URLSessionConfiguration.ephemeral` which stores all session data in memory and clears it when the session is invalidated.
