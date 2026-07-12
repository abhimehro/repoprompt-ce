## Sentinel Journal
## 2025-03-04 - Insecure URLSessionConfiguration handling AI prompts
**Vulnerability:** URLSessionConfiguration.default writes session data (like API keys and AI prompts) to disk.
**Learning:** Found multiple places in `Sources/RepoPrompt/Infrastructure/AI/Providers/` and `Sources/RepoPrompt/Infrastructure/Networking/` where `.default` is used instead of `.ephemeral`. This can expose sensitive AI model inputs and outputs on disk.
**Prevention:** For Swift HTTP clients handling sensitive data, prefer URLSessionConfiguration.ephemeral over .default to prevent writing session data like cookies and credentials to disk.
