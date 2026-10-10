## 2025-10-10 - Sensitive Data Exposure in AI Provider Error Logs
**Vulnerability:** API key testing methods in Gemini, OpenRouter, and OpenAI providers logged unredacted raw Error objects (\(error)), potentially leaking API keys, request URLs, and credentials in application logs or stack traces.
**Learning:** Default Swift Error string interpolation via \(error) includes full NSError user info and request descriptions which may contain authorization headers or URL query parameters.
**Prevention:** Always use error.asFriendlyString() or a sanitized error description helper when logging errors in AI providers and authentication-related code paths.
