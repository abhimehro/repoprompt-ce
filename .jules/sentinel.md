## 2024-07-13 - HTTP Client Session Caching
**Vulnerability:** URLSessionConfiguration.default was used, writing session data like cookies and credentials to disk.
**Learning:** For Swift HTTP clients handling sensitive data (e.g., AI prompts, API keys), URLSessionConfiguration.ephemeral should be used over .default to prevent writing session data to disk.
**Prevention:** Prefer ephemeral configurations for HTTP clients handling sensitive information.
