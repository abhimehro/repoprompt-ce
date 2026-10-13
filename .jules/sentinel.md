## 2025-05-10 - Sensitive Credential Leak in AI Provider Error Logging
**Vulnerability:** Default Swift `Error` string interpolation `\(error)` in AI provider `testAPIKey` methods can leak sensitive credentials, tokens, or URL query parameters in console/logs.
**Learning:** Default `\(error)` string interpolation evaluates `NSError` `userInfo` dictionaries which may contain request headers, raw query parameters, or token payloads.
**Prevention:** Always sanitize error objects using `error.asFriendlyString()` when logging API key test failures across AI providers.
