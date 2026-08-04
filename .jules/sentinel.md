## 2026-08-04 - Secure Keychain Non-Interactive Access
**Vulnerability:** Using kSecUseAuthenticationUISkip allows keychain operations to potentially bypass user presence checks when non-interactive access is intended, instead of failing securely.
**Learning:** Background processes that do not support UI should explicitly fail if UI is required to prevent unintended access or hangs.
**Prevention:** Use kSecUseAuthenticationUIFail instead of kSecUseAuthenticationUISkip for non-interactive access modes to explicitly enforce a secure failure when authentication is required.
