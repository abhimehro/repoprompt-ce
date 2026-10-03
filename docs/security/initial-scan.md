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
manual `swift build`, which compiles the package's products
(test targets are not built) for extraction.

## Open findings (5, all HIGH)

All five open alerts are the same CodeQL Actions rule —
`actions/cache-poisoning/poisonable-step`. What the rule flags on these
workflows: a `run:` step in a privileged workflow consumes a checkout (or
artifact lineage) whose ref arrives through cross-job output channels —
`needs.validate-ref.outputs.commit`, `needs.validate-ref.outputs.tooling-commit`,
and `needs.setup.outputs.*` in `release.yml` / `main-tip.yml`. The rule models
job outputs as potentially attacker-influenced, so a step that checks out a ref
taken from them and then runs code in a privileged context is alerted.
("cache-poisoning" is the rule name — neither file uses `actions/cache`; `rg
-n cache` over both returns zero matches.)

Actual triggers — neither workflow runs on `push`: `release.yml` is
`workflow_dispatch` only, and its `validate-ref` job additionally requires
`github.ref == 'refs/heads/main'`; `main-tip.yml` runs on `workflow_run`
after CI completes on `main` plus `workflow_dispatch`.

Guards that already narrow the exposure (CodeQL cannot see them, so the
alerts remain open rather than auto-resolved):

- `release.yml:42` — "Require a tag reachable from protected main":
  `Scripts/verify_release_ref.sh` resolves the dispatch tag to a commit and
  rejects anything outside protected-`main` ancestry.
- `main-tip.yml:92-108` — the setup job compares the tip candidate against
  live protected `main` via `git merge-base` and pins `tooling_commit` to the
  workflow-definition commit. It exits for candidates outside protected-`main`
  ancestry, emits `eligible=false` (publishing skipped) for an ancestor
  superseded by live `main`, and `eligible=true` only when the candidate
  equals live `main`.
- Both workflows check out with `persist-credentials: false`, so no token is
  carried into the consumed source.

Residual risk: the two workflows differ in what passes validation — the
normal `main-tip` path admits only the live `main` candidate, while the
release workflow accepts a selected version tag whose commit is anywhere in
protected-`main` ancestry. In both, downstream jobs trust the validator's
outputs and do not repeat the ref check, so a compromised or spoofed
`validate-ref`/`setup` output could still direct a consuming job to another
(ancestry-valid) commit. The findings are real-but-mitigated, not false
positives; remediation would recompute the requested ref inside the
consuming job.

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
The five open CodeQL alerts (untrusted-ref checkouts in privileged workflows)
are unaddressed by all three.

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

- `.github/workflows/security.yml` now runs CodeQL on the repo's first-party
  languages — Swift on `macos-26` (manual build), Python, C/C++ (buildless),
  Actions — on every PR targeting `main` and push to `main` plus a weekly
  scheduled scan, and `actions/dependency-review-action` on every PR
  targeting `main`. This is intentionally narrower than default setup's nine
  analyzed languages: the other five (`csharp`, `go`, `java-kotlin`,
  `javascript-typescript`, `rust`) exist only as traces in vendored/test
  code and produced zero-result analyses. The `c-cpp` leg is buildless — it
  extracts without real include paths or macro expansion, and it has no path
  filter, so vendored C (`sljit`, `UniversalCharsetDetection`, test
  fixtures) lands in the same alert stream as first-party code if a
  third-party bump ever lights up. CodeQL uploads are permitted on
  `pull_request`-triggered runs even
  with Dependabot's read-only `GITHUB_TOKEN`, so no actor guard is needed on
  the analysis step
  ([GitHub docs](https://docs.github.com/en/code-security/reference/code-scanning/troubleshoot-analysis-errors/resource-not-accessible)).
- `.github/dependabot.yml` refreshes SHA-pinned GitHub Actions only — this
  configuration does not enable Swift updates (a `swift` ecosystem entry
  exists but is intentionally left off as a maintainer decision), covers no
  npm globals like `@openai/codex` installed without a lockfile in `ci.yml`,
  and no runner labels such as `macos-26`; those stay manual.
- Remediation owners still needed for the 5 open HIGH poisonable-step alerts
  in `release.yml` / `main-tip.yml`.
