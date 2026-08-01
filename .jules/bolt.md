## 2024-05-19 - Expensive DateFormatter Instantiation in Swift
**Learning:** Instantiating `ISO8601DateFormatter` (or `DateFormatter`) in Swift is an expensive operation. In `Changelog.swift`, an `ISO8601DateFormatter` is being instantiated 216 times statically when the application loads, causing unnecessary overhead. On macOS 10.9+, `ISO8601DateFormatter` is thread-safe, making it safe to extract and share a single static instance.
**Action:** Extract repeated instantiations of `DateFormatter` and `ISO8601DateFormatter` into static shared properties, especially when the formatting style is constant.

## 2024-08-01 - GHAS CI Runner Model Failure
**Learning:** The GitHub Advanced Security (GHAS) Code Scanning CI workflow can fail with `CAPIError: 400 The requested model is not supported` if the backend Copilot Agent running the analysis uses an unsupported model (e.g., `sweagent-capi-[REDACTED]-opus-4.6`). This is an infrastructure/runner issue, entirely unrelated to codebase performance or Swift code changes.
**Action:** When encountering a 400 error for unsupported models in the `github-advanced-security` check logs during unrelated performance optimizations, ignore the CI failure as it is outside the scope of code optimization and proceed with submitting the optimization.

## 2024-08-01 - Suppressing Unrelated Compiler Warnings
**Learning:** During CI build failures (like the Sentry-enabled Build workflow), Swift compiler warnings such as "unused expressions", "immutable variable never used", or "no throwing calls in try" can cause the build to fail if `WarningsAsErrors` is strictly enforced.
**Action:** When working on performance tasks, also correct unrelated compiler warnings in the diff paths or standard logs (e.g. discarding unused results via `_ =`, removing unused variables, or correcting `try`/`await` usage) to ensure the optimization isn't blocked by the CI's strict warning policies.

## 2024-08-01 - Avoid Overwriting Working Tree in CI Fixes
**Learning:** Running `git restore` on files you did not directly modify (like `README.md` or `LICENSE`) can revert them to an earlier state but introduce "new" additions relative to the base branch, triggering secret scanners like Gitleaks if the base branch was already clean.
**Action:** Do not arbitrarily `git restore` files to clean up working trees unless you know exactly what is being restored. Instead, perform surgical git checkouts from the base branch to ensure you do not reintroduce deleted code or trigger secret scanners on old code patterns.
