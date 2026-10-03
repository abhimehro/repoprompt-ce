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

## Scan coverage (latest completed analyses on `main`, 2026-10-03, commit `8a5c905`)

| Language | Results |
|----------|---------|
| actions  | 5 |
| python   | 0 |
| swift    | 0 |
| c-cpp    | 0 |
| csharp / go / java-kotlin / javascript-typescript / rust | 0 |

Note on Swift coverage: default setup runs Swift on standard runners via
autobuild, which looks for a committed Xcode project/workspace. This repo
generates its Xcode workspace (`.build/xcode`) and builds via SwiftPM, so the
`0 results` for Swift should be read as *no findings reported*, not *complete
coverage confirmed*. The new `security.yml` scans Swift on `macos-26` with a
manual `swift build`, which compiles every SwiftPM target for extraction.

## Open findings (5, all HIGH)

All open alerts are the same CodeQL Actions rule —
[`actions/cache-poisoning/poisonable-step`](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning):
a step that runs code controlled by a fork/PR while reusing a cache scoped to
the base ref, allowing cache poisoning of trusted builds.

| # | Location | Severity | Link |
|---|----------|----------|------|
| 10 | `.github/workflows/main-tip.yml:742` | high | [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/10) |
| 9  | `.github/workflows/release.yml:75` | high | [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/9) |
| 8  | `.github/workflows/release.yml:372` | high | [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/8) |
| 7  | `.github/workflows/release.yml:91` | high | [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/7) |
| 6  | `.github/workflows/main-tip.yml:376` | high | [alert](https://github.com/abhimehro/repoprompt-ce/security/code-scanning/6) |

## Closed findings (history)

| # | Rule | Location | Severity | State |
|---|------|----------|----------|-------|
| 5 | actions/missing-workflow-permissions | `.github/workflows/ci.yml:36` | medium | dismissed |
| 4 | actions/missing-workflow-permissions | `.github/workflows/swift.yml:15` | medium | fixed |
| 3 | actions/missing-workflow-permissions | `.github/workflows/ci.yml:67` | medium | dismissed |
| 2 | actions/missing-workflow-permissions | `.github/workflows/ci.yml:36` | medium | fixed |
| 1 | actions/missing-workflow-permissions | `.github/workflows/ci.yml:11` | medium | dismissed |

## Sentinel PR cross-reference

None of the open Sentinel PRs remediates a code-scanning alert — each fixes a
separate finding reported by the Jules "Sentinel" pass, not a CodeQL rule.
The five open CodeQL alerts (workflow cache poisoning) are unaddressed by all
three.

| PR | Severity | What it fixes | Addresses a code-scanning finding? |
|----|----------|---------------|------------------------------------|
| [#339](https://github.com/abhimehro/repoprompt-ce/pull/339) | HIGH | Relaxed POSIX permissions on the MCP IPC socket directory (`/tmp/repoprompt-ce-mcp-<uid>`): `createDirectory` leaves pre-existing directory permissions untouched, so another local user could pre-create it world-accessible and eavesdrop on MCP sockets. Sets `0o700` via `setAttributes` in `Sources/RepoPrompt/Infrastructure/MCP/AppShared/MCPFilesystemConstants.swift` and `Sources/RepoPromptMCPCore/Shared/MCPFilesystemConstants.swift`. | No — no corresponding code-scanning alert. Duplicates #362 (same fix). |
| [#362](https://github.com/abhimehro/repoprompt-ce/pull/362) | HIGH | Same fix as #339 — enforce `0o700` on the MCP socket directory on every `ensureSocketDirectoryExists()` call, in the same two files. | No — no corresponding code-scanning alert. Duplicate of #339. |
| [#414](https://github.com/abhimehro/repoprompt-ce/pull/414) | MEDIUM | Case-sensitive env-key checks let `dyld_insert_libraries`, `ld_preload`, etc. bypass `ProcessEnvironmentSanitizer` (`Sources/RepoPromptProcess/`); also adds `LD_` prefix coverage to detection and child-launch scrubbing. | No — no corresponding code-scanning alert. |

## Supplemental local scan

`bandit` (Python static security analysis) over `Scripts/` — 37,870 LOC scanned:

- **1 HIGH** — `B324` weak SHA1 for security use, `Scripts/test_release_tooling.py:165`
  (test helper; low real-world impact but should pass `usedforsecurity=False`).
- **33 MEDIUM** —
  `B108` insecure temp dir/file use (24×, mostly `Scripts/conductor.py`,
  `Scripts/worktree_startup_live_benchmark.py`, test files — the conductor
  daemon lock-dir findings overlap the socket-directory class fixed by #339/#362);
  `B310` `urlopen` scheme audit (3×, `Scripts/codex_runtime_artifact.py`,
  `Scripts/codex_update_candidate.py`);
  `B314` `xml.etree` parse of untrusted XML (6×, `Scripts/generate_xcode_workspace.py`,
  `Scripts/stable_rollout.py`).
- **170 LOW** — dominated by `B112` try/except/continue and informational findings.

## Going forward

- `.github/workflows/security.yml` now runs CodeQL (Swift on `macos-26`,
  Python, Actions) on every PR and push to `main` plus a weekly scheduled scan,
  and `actions/dependency-review-action` on every PR.
- Remediation owners still needed for the 5 open HIGH cache-poisoning alerts
  in `release.yml` / `main-tip.yml`.
