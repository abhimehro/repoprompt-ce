## 2025-02-18 - [Insecure Keychain Item Accessibility]
**Vulnerability:** KeychainService uses kSecAttrAccessibleAfterFirstUnlock
**Learning:** Keys can be extracted if the device is unlocked and then locked again, or migrated to other devices if not restricted to ThisDeviceOnly.
**Prevention:** Always use kSecAttrAccessibleWhenUnlockedThisDeviceOnly for sensitive tokens and API keys.

## 2025-02-18 - [Missing Required Tools in Cloud Environments]
**Learning:** The cloud environment does not contain the `swiftformat` or `plutil` commands which fail tests like `make lint` and Python test scripts `make conductor-selftest`.
**Action:** These tests can be safely ignored if Homebrew and basic macOS build tools aren't present.
