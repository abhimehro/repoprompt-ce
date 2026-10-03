## 2026-03-30 - Insecure Shared Temporary Directory Permissions in File Export Helper
**Vulnerability:** `MCPConfigExportService.writeTempFile` created `RepoPromptDiscover` directory in `/tmp` using standard `fileManager.createDirectory` without securing permissions to `0o700` or validating ownership via `prepareSecureDirectory`.
**Learning:** Temporary files created in shared `/tmp` locations can suffer from symlink/pre-creation hijacking or permission leakage if directory permissions are left at default (`0o755`).
**Prevention:** Always delegate temporary directory creation and directory security checks to `prepareSecureDirectory` or explicitly apply `0o700` descriptor-based permissions.
