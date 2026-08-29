# CI test lanes

RepoPrompt CE has two XCTest lanes with different jobs. They are deliberately not
interchangeable.

## Pull-request contract lane

The `contract` tier is the required pull-request gate. A suite belongs here only
when it has all of the following properties:

- a concrete behavior contract and observable result;
- deterministic inputs, ordering, environment, and cleanup;
- no wall-clock waiting, host process lifecycle, real network transport, or
  machine-persisted settings;
- no retry-based pass semantics;
- a failure that a contributor can reproduce with the named suite.

Every suite runs in its own XCTest process with a fresh `HOME`,
`CFFIXED_USER_HOME`, `TMPDIR`, and XDG directory set. `swift test list` still
compiles every root test target, so moving a suite to the integration tier does
not permit it to rot at compile time.

The runner intentionally has no suite watchdog, silent-startup retry, process
walker, or method-isolation registry. The workflow has one job-level circuit
breaker for broken infrastructure. Test code is not allowed to reinterpret a
hang or a retry as evidence that the product is correct.

Run or inspect the lane locally:

```bash
python3 Scripts/check_test_hygiene.py
python3 Scripts/ci_app_test_runner.py --tier contract --list-only
python3 Scripts/ci_app_test_runner.py --tier contract --shard-count 1 --shard-index 1
```

## Integration and soak lane

The `integration` tier contains assembled-app, real subprocess, filesystem/Git,
transport, host instrumentation, benchmark, and recovery scenarios. It runs on
every push to `main`, nightly, and by manual dispatch. It is intentionally not a
pull-request event, so an unstable host fixture cannot block unrelated work.
Failures remain red and visible; this is quarantine, not `/dev/null` wearing a
lab coat.

Run or inspect it locally:

```bash
python3 Scripts/ci_app_test_runner.py --tier integration --list-only
python3 Scripts/ci_app_test_runner.py --tier integration --keep-going
```

The current explicit quarantine is maintained in `Scripts/ci_test_policy.py`.
The largest mixed suites include Context Builder lifecycle, Codex fallback FIFO,
headless stdio, Git/worktree APIs, workspace recovery, namespace/evidence
coordination, background compose admission, and inactive transcript refresh.
Benchmark, performance, instrumentation, debug-harness, and live/smoke-harness
suite names are classified automatically.

## Recovered contract coverage

Moving a mixed suite out of the pull-request lane must not discard deterministic
logic hidden inside it. This refactor extracts focused replacements:

| Mixed integration suite | Pull-request contract replacement |
| --- | --- |
| `ContextBuilderRunLifecycleTests` | `ContextBuilderRunStateContractTests` |
| `BackgroundComposeTabAdmissionTests` | `AgentSessionLifecycleAuthorityContractTests` |

The replacements test state transitions and admission policy directly. They do
not launch MCP, create process trees, mutate global settings, poll clocks, or
wait for the host to become lucky.

## Graduation criteria

An integration suite may return to the contract lane after it is split or
rewritten so that:

1. the contract is expressed at the lowest faithful layer;
2. every asynchronous boundary is driven by an explicit gate, continuation, or
   injected clock;
3. host processes, real sockets, user defaults, and ambient filesystem state are
   absent;
4. one run has one verdict—no rerun changes failure into success;
5. the focused command reproduces a deliberately injected defect and passes
   after the defect is fixed.

Add exact exceptions sparingly and include the reason in
`EXACT_INTEGRATION_REASONS`. A vague “flaky on CI” entry is not a permanent home;
it is an unpaid debt with a filename.
