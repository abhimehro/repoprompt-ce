# Test Coverage Value Audit: Plan

## Goal
Fully rebalance RepoPrompt CE's first-party Swift tests around current contract value: remove tests that do not earn retention, consolidate true overlap, preserve distinct layered protections, and add focused coverage where shipped behavior is materially exposed. Method count is an outcome measure, not the optimization target; use **500 executable XCTest methods as a provisional ceiling**, not a desired quota.

## Background

### Scope decisions locked during planning

- **Counting boundary:** method accounting includes both first-party Swift test targets: root `RepoPromptTests` (`Package.swift:98-106`) and nested `RepoPromptClaudeCompatibleProviderTests` (`Packages/RepoPromptAgentProviders/Package.swift:18-22`). Report their subtotals separately because they execute separately via `make dev-test` and `make dev-provider-test` (`Makefile:67-71`). Live CE MCP smoke remains a validation lane, not a counted XCTest method.
- **Counting unit:** count executable/discoverable `func test...` XCTest methods; separately inventory parameterized fixtures/goldens so a loop-backed method is not mistaken for a single behavior boundary.
- **Allowed enabling work:** narrowly scoped, deterministic testability seams may be proposed where they unlock important current contracts; broad production redesign is outside this effort.
- **Contract boundary:** protect current CE behavior, including current JSON-only/rejection boundaries where shipped; do not restore deleted legacy or migration behavior solely to test it.

### Current baseline and prior-art reset

- A verified declaration search finds **478** `func test...` methods in `Tests/RepoPromptTests` and **5** in `Packages/RepoPromptAgentProviders/Tests`: **483 total**. This is already close to the provisional 500-method ceiling, but the present number is not itself a defect: the audit may delete, consolidate, retain, or add methods according to contract value.
- Verified declaration searches show root concentration around `MCP` (103 methods), `AgentMode` (103), and `WorkspaceContext` (92); the most concentrated single suite is `Tests/RepoPromptTests/WorkspaceContext/WorkspaceFileContextStoreTests.swift` (53 methods across store loading, selection, mutation, search freshness, and concurrency). These concentrations require contract-by-contract review rather than indiscriminate trimming.
- Earlier May 13 cleanup/recovery work is prior art, not a current baseline: it assumed a much smaller root suite and separate provider execution. Its continuing constraints remain useful (CE-applicable behavior, explicit provider validation, bounded golden/resources), but the numerical targets are obsolete.
- CodeMap test resources are now explicitly wired in `Package.swift:98-106`; any additional resource-backed lane should be intentional rather than incidental.

### Verified signals that some existing tests must justify retention

- `Tests/RepoPromptTests/AgentMode/Transcript/AgentTranscriptCrawlRefreshBenchmarkTests.swift:1-45` is DEBUG/opt-in and emits a performance report without a behavioral assertion in its test body; it should be classified as a diagnostic harness rather than automatically charged against the retained behavioral budget.
- `Tests/RepoPromptTests/WorkspaceContext/Search/SearchRuntimeCutoverGuardTests.swift:1-17` protects source-string/deletion shape rather than executable runtime behavior. Architecture/removal guards may remain valuable, but they need a small, explicit budget and a reason they cannot be replaced by a behavior or guardrail check.
- `Tests/RepoPromptTests/MCP/CECLINamingAndRoutingTests.swift:36-112` similarly validates source text/help exposure for CLI surfaces; it does not establish runtime parser/forwarding behavior.
- `Tests/RepoPromptTests/CodeMap/CodeMapGoldenTests.swift:6-24,64-97` confirms substantial fixture coverage inside a small method count, while the `auto` tree assertion uses the same compact expected tree as the full rendering path and the helper enforces maximum fixture counts. Golden value must be assessed by behavioral breadth, not method count alone.

### Apparent high-value gaps to validate in the audit

These are grounded candidates from static source/test mapping; the audit must confirm indirect coverage before adding tests.

| Candidate contract seam | Evidence in shipped code | Current coverage signal |
| --- | --- | --- |
| Edit/diff generation routing, search-block ambiguity and failure behavior | `Sources/RepoPrompt/Infrastructure/Diffing/DiffGenerationUtility.swift:72-140` routes create/delete/rewrite/search-block behavior and throws on unmatched selection | Existing direct diff tests concentrate on application/parser/rendering; no direct test reference to `DiffGenerationUtility` was found. |
| DEBUG secure-storage persistence policy and write path | `Sources/RepoPrompt/Infrastructure/Security/SecureKeyValueStorageBackend.swift:22-82` chooses Keychain vs ephemeral storage from marker/signing identity; `Tests/RepoPromptTests/Security/KeychainServiceTests.swift:7-77` covers reads/delete only | Current behavior is security-sensitive and deterministic, but no direct policy test reference was found. |
| Pure app close decision behavior | `Sources/RepoPrompt/App/WindowCloseCoordinator.swift:114-140` branches on active work and MCP continuity | No focused test reference was found despite a deterministic contract. |
| Slice persistence/rebase correctness | `Sources/RepoPrompt/Infrastructure/WorkspaceContext/Slices/PartitionStore.swift:37-109` persists partitioned selections; `SliceRebaseEngine.swift:4-70` handles rebasing/dropped ranges and a P0-described cache edge | Existing broad workspace tests cover selection/store outcomes; no direct reference to either seam was found. |
| Agent-mode provider/run lifecycle | `Sources/RepoPrompt/Features/AgentMode/Runtime/AgentModeRunService.swift:125-152` begins provider-specific run dispatch and startup-failure handling (with later steer/cancel paths in the same type) | AgentMode has substantial surrounding coverage, but no direct `AgentModeRunService` test reference was found during mapping. |
| Executable CE MCP CLI parsing/forwarding | `Sources/RepoPromptMCP/CommandRunner/MCPCommandParser.swift:430-461` exposes actual command parsing; the CLI product also owns execution/transport paths | `CECLINamingAndRoutingTests.swift:75-112` reads parser/help source strings; a suite search found that as the only test occurrence of `MCPCommandParser`. |

### Ownership and integration boundary

- Provider-specific pure protocol/runtime/catalog behavior belongs in `Packages/RepoPromptAgentProviders`, while root tests should cover app adapter/controller wiring, catalog persistence-facing conversion, launch-environment integration, and permission/binding policy (`docs/architecture/provider-plugins.md:240-255`). Existing provider tests remain intentionally separate from root execution.
- The value audit must avoid deleting legitimate vertical coverage simply because two tests mention the same identifier: package DTO behavior and root bridge conversion are separate contracts; likewise a runtime service assertion and an external MCP serialization assertion can both earn retention.

## Approach

This effort is a **contract-value audit followed by bounded suite reshaping**, not a quota-driven deletion pass. The later implementation begins by creating one authoritative audit artifact at `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md`; this plan sets its rules and the ledger records method-level decisions and completion evidence.

1. Build a lightweight exhaustive census of all 483 declared XCTest methods, recording primary counting ownership and scenario/fixture breadth separately from declaration count.
2. Create detailed decision records only for tests proposed for deletion/consolidation, retained non-behavioral exceptions, cross-layer overlap decisions, and candidate additions/seams.
3. Classify each validation as behavioral coverage, structural/deletion guard, diagnostic benchmark, or uncounted live smoke.
4. Confirm whether each apparent coverage gap is actually uncovered after direct/indirect coverage review, including target accessibility where the executable boundary is separate.
5. Freeze root/provider subtotals, class totals, method deltas, dependency-safe edit batches, and validation lanes only after the value audit; do not force net reduction. The proposed final total must be justified contract-by-contract and should remain at or below the provisional 500-method ceiling unless the plan is explicitly revisited.
6. Execute later changes in validated batches; where a removal depends on replacement protection, land the replacement first or atomically with the removal.

### Validation classes and review triggers

| Class | Meaning | Count treatment | Retention rule |
| --- | --- | --- | --- |
| Behavioral coverage | Executable assertion of a current CE output, failure/rejection boundary, transformation, integration, or external contract | Counts as XCTest methods | Primary retained coverage; preserve layers that protect distinct contracts |
| Structural/deletion guard | Source shape, removed-symbol absence, layering, naming/help exposure, or architecture constraint without executable behavior | Counts if implemented as XCTest | Retain only with a rationale that behavior or an existing guardrail is insufficient; a final allocation above **10** methods requires explicit justification at the retention freeze |
| Diagnostic benchmark | DEBUG/opt-in measurement/report harness rather than behavior protection | Counts if declared as XCTest | Track separately; a final allocation above **2** methods requires explicit justification at the retention freeze |
| Live smoke | Running-app/MCP/CLI/runtime validation outside deterministic XCTest coverage | Does not count | Record separately and run only for affected live boundaries |

The numeric structural/diagnostic thresholds are **review triggers, not pre-approved hard caps**; evidence determines the retained allocation. A rejection test protecting a current JSON-only or unsupported-input contract is behavioral coverage, not legacy scope and not automatically a structural guard.

## Audit Ledger

The implementation pass creates `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md` before editing Swift. It contains two linked layers, avoiding both count ambiguity and an over-engineered full decision matrix.

### Exhaustive method census

One census row owns the count for each existing declared method. If a method protects multiple behaviors, it receives one primary `contract_id` for counting and additional contract tags for traceability; it is never counted twice.

| Census field | Purpose |
| --- | --- |
| `method_id`, `file`, `target`, `domain` | Reconcile every `func test...` declaration to root or provider totals |
| `primary_contract_id`, `secondary_contract_tags` | Assign one counting owner without losing multi-contract traceability |
| `validation_class`, `layer` | Separate behavior, structural, diagnostic, and live evidence; identify unit/bridge/integration/runtime ownership |
| `scenario_or_fixture_note` | Record breadth hidden inside golden, fixture-loop, or table-driven methods |
| `tentative_disposition` | Identify methods needing a detailed decision record: retain, review, delete, or consolidate |

### Detailed decision records

Create a detailed record for every deletion, consolidation, retained structural/diagnostic exception, ownership-layer overlap decision, apparent-gap candidate, approved addition, or production testability seam.

| Decision field | Purpose |
| --- | --- |
| `contract_id`, `current_contract`, `affected_methods` | State the current CE boundary being changed or protected |
| `surviving_or_added_protection`, `preserved_scenarios` | Prove deletion/consolidation/addition does not erase meaningful behavior |
| `direct_or_indirect_evidence` | Establish whether nearby coverage is sufficient or a current gap remains |
| `disposition`, `count_delta`, `batch_dependency` | Freeze the result and require add-first/atomic sequencing where a reduction depends on replacement |
| `validation_lane`, `testability_seam_required` | Bind focused evidence and allow only narrowly justified deterministic seams |

### Ledger invariants

- The census accounts exactly once for all **478 root** and **5 provider** declared methods before edits begin.
- Fixture/golden/parameter breadth is recorded independently of method count; consolidation cannot silently drop protected scenarios.
- Every deletion or consolidation has a decision record naming surviving protection, or explaining why no meaningful current contract is lost.
- Every addition is blocked until direct and indirect coverage is checked and the contract is confirmed current and uncovered.
- Provider-package pure behavior and root app integration remain separate ownership layers even when they share identifiers.
- Current JSON-only decode/rejection guarantees may remain behavioral coverage without reviving migration behavior.

## Count and Allocation Gates

Because the provider package owns distinct pure behavior and currently contributes only five methods, the plan does not assign deletion quotas by domain in advance. Exact subtotals and whether the suite shrinks or grows are set only after value review; a larger root domain is an audit priority, not an automatic reduction target.

| Target | Current methods | Behavioral retained/added | Structural retained | Diagnostic retained | Removed/consolidated away | Final subtotal |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `RepoPromptTests` | 478 | Ledger-derived | Ledger-derived | Ledger-derived | Ledger-derived | `R` |
| `RepoPromptClaudeCompatibleProviderTests` | 5 | Ledger-derived | Ledger-derived | Ledger-derived | Ledger-derived | `P` |
| **Counted total** | **483** | Ledger-derived | Ledger-derived; justify if >10 | Ledger-derived; justify if >2 | Ledger-derived | **`R + P ≤ 500` provisionally; no minimum** |

| Gate | Required evidence |
| --- | --- |
| **0 — Baseline** | The verified `478 + 5 = 483` declaration baseline and count policy are recorded. |
| **1 — Ledger complete** | The census reconciles every current method once; detailed decision records cover every change, exception, overlap decision, and candidate; fixture/golden breadth is captured; no Swift edits have begun. |
| **2 — Retention freeze** | Exact `R` and `P`, all dispositions/additions, class totals and any threshold rationale, dependency-safe batch deltas, and validation lanes are recorded; final count is value-justified and `R + P ≤ 500` unless this provisional ceiling is explicitly revisited. |
| **3 — Batch reconciliation** | Each later reduction/addition batch matches its declared delta, lands replacement protection first or atomically when required, and passes focused coordinated validation before another batch lands. |
| **4 — Acceptance** | Final method recount matches frozen subtotals; class totals and rationales are recorded; complete coordinated root/provider validation passes; applicable live smoke is recorded separately. |

## Candidate Gap Confirmation Protocol

The preliminary gaps in `## Background` require detailed ledger decisions; they are not automatic additions. For each seam, inspect existing direct and outcome-level coverage before approving a focused new test or a narrowly enabling seam.

| Candidate seam | If still uncovered, ownership | Confirmation question before addition | Allowed disposition |
| --- | --- | --- | --- |
| `DiffGenerationUtility` routing/search-block ambiguity/failure (`Sources/RepoPrompt/Infrastructure/Diffing/DiffGenerationUtility.swift:72-140`) | Root Diffing/MCP apply-edits boundary | Do existing parser, applicator, or ApplyEdits tests assert routing and unmatched/ambiguity outcomes, not merely adjacent output rendering? | Retain indirect coverage or add narrow behavior tests |
| DEBUG storage selection and successful secure write (`Sources/RepoPrompt/Infrastructure/Security/SecureKeyValueStorageBackend.swift:22-82`) | Root Security | Do security suites execute backend selection and successful write behavior, beyond Keychain read/delete and permission-store outcomes? | Add deterministic policy/write tests; allow only minimal injection if required |
| `WindowCloseCoordinator.decide` (`Sources/RepoPrompt/App/WindowCloseCoordinator.swift:114-140`) | Root App | Is active-work/MCP-continuity close policy already asserted through another focused test? | Add pure decision cases only for uncovered branches |
| `PartitionStore` / `SliceRebaseEngine` (`Sources/RepoPrompt/Infrastructure/WorkspaceContext/Slices/PartitionStore.swift:37-109`; `SliceRebaseEngine.swift:4-70`) | Root WorkspaceContext | Do existing selection/store tests protect partition persistence, dropped-range rebasing, and the stated cache edge at the observable layer? | Prefer sufficient integration tests; otherwise add missing direct outcomes |
| `AgentModeRunService` provider/run lifecycle (`Sources/RepoPrompt/Features/AgentMode/Runtime/AgentModeRunService.swift:125-152`) | Root AgentMode | Do current coordinator/view-model tests actually execute provider dispatch/startup failure/steer/cancel service paths? | Add focused lifecycle tests; use live smoke only where runtime-sensitive |
| Executable CLI parsing/forwarding (`Sources/RepoPromptMCP/CommandRunner/MCPCommandParser.swift:430-461`) | To be assigned only after accessibility review: existing root harness, executable/process harness, or live smoke | Is there runtime parser/forwarding coverage beyond `CECLINamingAndRoutingTests.swift:75-112`; can an existing test target reach the CLI boundary without changing target dependencies or production design? | Prefer an existing executable/harness boundary; otherwise classify live-only or approve a narrow seam before retention freeze |

Each candidate row must finish as one of: `covered-directly — no addition`, `covered-indirectly — no addition`, `uncovered-current-contract — focused addition approved`, `uncovered-but-live-only — smoke lane recorded`, or `not-current-contract — no addition`.

## Work Items

### Item 1 — Create the audit ledger and executable-method census
**Goal:** Establish a stable audit artifact and count ownership for the verified 483-method baseline without forcing full decision prose for every retained method.

**Done when:** `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md` exists; its census accounts once for every root/provider method with primary contract, class, layer, scenario/fixture note, and tentative disposition; its subtotals equal 478 root and 5 provider.

**Key files:** `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md` (new implementation artifact); `Tests/RepoPromptTests/**`; `Packages/RepoPromptAgentProviders/Tests/**`; `Package.swift:98-106`; `Packages/RepoPromptAgentProviders/Package.swift:18-22`.

**Dependencies:** Gate 0 and the scope decisions in `## Background`.

**Size:** Large.

### Item 2 — Make retention and consolidation decisions by value and ownership layer
**Goal:** Decide which existing tests earn retention, consolidation, or deletion while preserving distinct package/root, unit/integration, and current rejection-contract protection.

**Done when:** Detailed ledger records cover every proposed deletion/consolidation, every retained structural/diagnostic exception, and every cross-layer overlap decision; non-behavioral class totals are explicit, with rationale if structural guards exceed 10 or diagnostic benchmarks exceed 2; CodeMap is judged by recorded fixture/golden breadth; package-owned behavior and root bridge/policy coverage are not collapsed merely for sharing identifiers.

**Key files:** `Tests/RepoPromptTests/AgentMode/Transcript/AgentTranscriptCrawlRefreshBenchmarkTests.swift:1-45`; `Tests/RepoPromptTests/WorkspaceContext/Search/SearchRuntimeCutoverGuardTests.swift:1-17`; `Tests/RepoPromptTests/MCP/CECLINamingAndRoutingTests.swift:36-112`; `Tests/RepoPromptTests/CodeMap/CodeMapGoldenTests.swift:6-97`; `docs/architecture/provider-plugins.md:240-255`; concentrated suites under `Tests/RepoPromptTests/{MCP,AgentMode,WorkspaceContext}`; provider and root Claude-compatible tests.

**Dependencies:** Item 1.

**Size:** Large.

### Item 3 — Confirm missing coverage, including executable-boundary accessibility
**Goal:** Replace apparent-gap speculation with evidence-backed addition, live-only, or no-addition decisions for important shipped seams.

**Done when:** Each candidate in `## Candidate Gap Confirmation Protocol` has a detailed ledger disposition backed by direct/indirect coverage evidence; the CLI row records whether an existing target/harness can reach `RepoPromptMCP` behavior before any seam is considered; approved additions name target, scenarios, count delta, and validation; any production seam is minimal, deterministic, behavior-preserving, and paired with protection.

**Key files:** The six source seams and adjacent tests cited in the candidate table; especially `Tests/RepoPromptTests/{Diffing,Security,App,WorkspaceContext,AgentMode,MCP}` and `Sources/RepoPromptMCP/CommandRunner/MCPCommandParser.swift:430-461`.

**Dependencies:** Items 1–2; additions remain blocked until this item completes.

**Size:** Large.

### Item 4 — Freeze retained subtotals and dependency-safe batches
**Goal:** Convert audit conclusions into a value-justified implementation sequence that does not temporarily delete required protection or manufacture changes solely to hit a number.

**Done when:** The ledger records exact root subtotal `R`, provider subtotal `P`, class totals and any threshold rationale, every delete/consolidate/add delta, touched files, focused validation lanes, and ordered batches; the resulting total is justified by retained/added contracts and stays within the provisional 500-method ceiling unless explicitly revisited; any reduction relying on a new test or seam is marked add-first or atomic in its batch dependency.

**Key files:** The audit ledger; test/source files selected by Items 2–3; `Makefile:67-76`; `AGENTS.md` coordinated validation guidance.

**Dependencies:** Items 1–3.

**Size:** Medium.

### Item 5 — Execute evidence-approved change batches
**Goal:** Apply only frozen reductions and confirmed additions/seams while continuously demonstrating current contract protection.

**Done when:** Each future batch preserves documented scenario breadth, installs prerequisite replacement protection before or atomically with dependent removals, reconciles actual method deltas against the ledger, and passes its focused daemon tests before the next batch begins; independent low-value reductions need no invented replacement.

**Key files:** Ledger-selected files under `Tests/RepoPromptTests/**`, justified provider tests, and only the narrowly approved source seams from Item 3.

**Dependencies:** Item 4; implementation workflow (`rp-build`/`rp-orchestrate`), not this plan-writing pass.

**Size:** Large.

### Item 6 — Prove final allocation and validation acceptance
**Goal:** Close with a fully rebalanced, high-value, explainable suite and separate evidence for any live boundary, regardless of whether the net method count decreases or increases.

**Done when:** Final recount equals frozen `R + P`; class totals and required rationales are recorded; candidate dispositions and batch deltas are complete; full root/provider coordinated suites pass; formatting/lint/build/smoke evidence is recorded where the implemented changes require it.

**Key files:** `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md`; `Makefile:61-76`; `AGENTS.md` validation rules.

**Dependencies:** Item 5.

**Size:** Medium.

## Validation and Completion Evidence

Later implementation must use daemon-coordinated validation rather than uncoordinated `swift test` unless the daemon is unavailable.

| Later batch type | Required evidence |
| --- | --- |
| Root test reduction/addition | `make dev-test FILTER=<touched-suite>` and method-delta reconciliation |
| Provider-package test change | `make dev-provider-test FILTER=<touched-suite>` and provider-subtotal reconciliation |
| CodeMap resource-backed change | `make dev-test FILTER=CodeMapGoldenTests` plus retained fixture/golden inventory |
| Narrow root source seam | Relevant focused tests and `make dev-swift-build PRODUCT=RepoPrompt` |
| MCP CLI/server source seam | Relevant focused MCP tests and `make dev-swift-build PRODUCT=repoprompt-mcp`; live smoke if runtime flow changes |
| AgentMode or other running-app-sensitive seam | Relevant focused tests and the applicable CE live MCP smoke flow |
| Any Swift-file completion pass | `make dev-format` only when formatting mutation is intended, followed by `make dev-lint` |
| Final acceptance | Root/provider recount, class totals plus threshold rationale where triggered, `make dev-test`, and `make dev-provider-test`; live smoke recorded separately when triggered |

Completion evidence appended to `docs/investigations/test-coverage-value-audit-ledger-2026-05-29.md` must include final root/provider subtotals, class totals and threshold rationales where required, fixture/golden breadth notes for retained consolidated methods, candidate-gap dispositions, batch dependencies and count deltas, daemon commands/results, and any uncounted live-smoke outcome.

## Open Questions

- None requiring product input before the audit. Implementation must use the audit ledger to determine the earned final method set and domain allocation; the provisional 500-method ceiling may be revisited if the evidence demonstrates additional worthwhile contracts.

## References

- `docs/architecture/provider-plugins.md`
- `Package.swift`
- `Packages/RepoPromptAgentProviders/Package.swift`
- `Makefile`
- `AGENTS.md`
