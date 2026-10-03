<!-- markdownlint-disable MD013 MD043 -->
# Initial security scan

Issue: abhimehro/repoprompt-ce#286
Generated: 2026-10-03 (UTC)

## Status

GitHub code scanning was already enabled for this repository through **CodeQL
default setup** (configured 2026-08-31, `remote` threat model, weekly schedule,
all detectable languages), so the first scan has already run — this document
summarizes its current results. Default setup was switched off on 2026-10-03 so
that the versioned advanced workflow added in this PR
(`.github/workflows/security.yml`) can take over; GitHub blocks CodeQL uploads
from an advanced workflow while default setup is enabled.

## Scan coverage

Latest completed analyses on `main` (2026-10-03, commit `8a5c905`):

- `actions`: 5 results
- `python`, `swift`, `c-cpp`: 0 results each
- `csharp`, `go`, `java-kotlin`, `javascript-typescript`, `rust`: 0 results each

Note on Swift coverage: default setup runs Swift on standard runners via
autobuild, which looks for a committed Xcode project/workspace. This repo
generates its Xcode workspace (`.build/xcode`) and builds via SwiftPM, so the
`0 results` for Swift should be read as *no findings reported*, not *complete
coverage confirmed*. The new `security.yml` scans Swift on `macos-26` with a
manual `swift build`, which compiles the package's products (test targets are not built) for extraction.

## Open findings (5, all HIGH)

All open alerts are the same CodeQL Actions rule —
[`actions/cache-poisoning/poisonable-step`](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning):
a step that runs code controlled by a fork/PR while reusing a cache scoped to
the base ref, allowing cache poisoning of trusted builds.

- #10 `main-tip.yml:742` — high — [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/10)
- #9 `release.yml:75` — high — [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/9)
- #8 `release.yml:372` — high — [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/8)
- #7 `release.yml:91` — high — [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/7)
- #6 `main-tip.yml:376` — high — [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/6)

## Closed findings (history)

All five closed alerts are `actions/missing-workflow-permissions` (medium):

- #5 `ci.yml:36` — dismissed
- #4 `swift.yml:15` — fixed
- #3 `ci.yml:67` — dismissed
- #2 `ci.yml:36` — fixed
- #1 `ci.yml:11` — dismissed

## Sentinel PR cross-reference

None of the open Sentinel PRs remediates a code-scanning alert — each fixes a
separate finding reported by the Jules "Sentinel" pass, not a CodeQL rule.
The five open CodeQL alerts (workflow cache poisoning) are unaddressed by all
three.

- [#339](https://github.com/abhimehro/repoprompt-ce/pull/339) — HIGH — relaxed
  POSIX permissions on the MCP IPC socket directory
  (`/tmp/repoprompt-ce-mcp-<uid>`): `createDirectory` leaves pre-existing
  directory permissions untouched, so another local user could pre-create it
  world-accessible and eavesdrop on MCP sockets. Sets `0o700` via
  `setAttributes` in `Sources/RepoPrompt/Infrastructure/MCP/AppShared/MCPFilesystemConstants.swift`
  and `Sources/RepoPromptMCPCore/Shared/MCPFilesystemConstants.swift`.
  Not a code-scanning alert. Duplicates #362 (same fix).
- [#362](https://github.com/abhimehro/repoprompt-ce/pull/362) — HIGH — same fix
  as #339: enforce `0o700` on the MCP socket directory on every
  `ensureSocketDirectoryExists()` call, in the same two files.
  Not a code-scanning alert. Duplicate of #339.
- [#414](https://github.com/abhimehro/repoprompt-ce/pull/414) — MEDIUM —
  case-sensitive env-key checks let `dyld_insert_libraries`, `ld_preload`,
  etc. bypass `ProcessEnvironmentSanitizer` (`Sources/RepoPromptProcess/`);
  also adds `LD_` prefix coverage to detection and child-launch scrubbing.
  Not a code-scanning alert.

## Supplemental local scan

`bandit` (Python static security analysis) over `Scripts/` — 37,870 LOC
scanned:

- **1 HIGH** — `B324` weak SHA1 for security use, `Scripts/test_release_tooling.py:165`
  (test helper; low real-world impact but should pass `usedforsecurity=False`).
- **33 MEDIUM** —
  `B108` insecure temp dir/file use (24×, mostly `Scripts/conductor.py`,
  `Scripts/worktree_startup_live_benchmark.py`, test files — the conductor
  daemon lock-dir findings overlap the socket-directory class fixed by #339/#362);
  `B310` `urlopen` scheme audit (3×, `Scripts/codex_runtime_artifact.py`,
  `Scripts/codex_update_candidate.py`);
  `B314` `xml.etree` parse of untrusted XML (6×,
  `Scripts/generate_xcode_workspace.py`, `Scripts/stable_rollout.py`).
- **170 LOW** — dominated by `B112` try/except/continue and informational findings.

## Going forward

- `.github/workflows/security.yml` now runs CodeQL (Swift on `macos-26`,
  Python, Actions) on every PR and push to `main` plus a weekly scheduled scan,
  and `actions/dependency-review-action` on every PR.
- Remediation owners still needed for the 5 open HIGH cache-poisoning alerts
  in `release.yml` / `main-tip.yml`.
