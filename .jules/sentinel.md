## 2025-05-18 - Sanitize Provider Error Interpolation in API Key Validation Logs
**Vulnerability:** Default Swift `Error` string interpolation (`\(error)`) in `testAPIKey` fallback logs could leak raw `NSError` user info dictionaries, API request details, or tokens into console output.
**Learning:** Raw `Error` stringification on `NSError` or custom HTTP client errors includes unredacted request/response payloads.
**Prevention:** Always convert errors using `error.asFriendlyString()` in provider logging and user-facing messages.
