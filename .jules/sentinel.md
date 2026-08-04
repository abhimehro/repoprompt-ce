## 2024-05-24 - Do not log STDERR from user login shells
**Vulnerability:** Sensitive Information Exposure
**Learning:** Logging the raw STDERR output from user login shell execution (e.g., `bash -l -c env`) can inadvertently expose secrets, API keys, or tokens that are printed during profile evaluation (e.g., via debug statements or misconfigured plugins).
**Prevention:** Only log metadata (like byte counts) for user shell outputs unless explicitly in a high-security debug mode where the user is aware of the risks, or avoid logging the content entirely.
