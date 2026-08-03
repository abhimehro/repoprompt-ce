## 2026-08-03 - Prevent Sensitive Data Leakage in HTTP Clients
**Vulnerability:** URLSessionConfiguration.default was used for AI and network providers, allowing session data (including API keys and AI prompts) to be written to disk.
**Learning:** Default URLSession configurations cache request and response data, which can leak sensitive credentials and user prompts to the local file system.
**Prevention:** Always use URLSessionConfiguration.ephemeral for HTTP clients handling API requests with sensitive payloads or authentication tokens.
