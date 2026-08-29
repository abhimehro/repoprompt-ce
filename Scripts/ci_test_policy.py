#!/usr/bin/env python3
"""Single source of truth for RepoPrompt CE CI test tiers."""

from __future__ import annotations

import re
from functools import lru_cache
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping

CONTRACT_TIER = "contract"
INTEGRATION_TIER = "integration"
ALL_TIER = "all"
TIERS = (CONTRACT_TIER, INTEGRATION_TIER, ALL_TIER)
TEST_ROOT = Path("Tests/RepoPromptTests")


@dataclass(frozen=True)
class TestPolicyDecision:
    tier: str
    reason: str


@dataclass(frozen=True)
class SourceWaitOccurrence:
    path: Path
    line: int
    symbol: str
    suites: tuple[str, ...]


@dataclass(frozen=True)
class SourceTestPolicy:
    integration_reasons: Mapping[str, str]
    wait_occurrences: tuple[SourceWaitOccurrence, ...]
    unmapped_wait_occurrences: tuple[SourceWaitOccurrence, ...]


EXACT_INTEGRATION_REASONS: dict[str, str] = {
    "RepoPromptTests.AgentModeViewModelInactiveRefreshTests": (
        "mixed UI/session integration fixture with wall-clock polling"
    ),
    "RepoPromptTests.BackgroundComposeTabAdmissionTests": (
        "large workspace/session integration fixture with wall-clock polling"
    ),
    "RepoPromptTests.CodexFallbackFIFOTests": (
        "host configuration and persisted-setting integration coverage"
    ),
    "RepoPromptTests.ContextBuilderRunLifecycleTests": (
        "real MCP, process, global-setting, and teardown lifecycle coverage"
    ),
    "RepoPromptTests.DebugProcessMemorySamplerTests": (
        "host process and memory sampling diagnostics"
    ),
    "RepoPromptTests.DirectHeadlessStdioTransportTests": (
        "real stdio subprocess transport coverage"
    ),
    "RepoPromptTests.GitBlobIdentityServiceTests": (
        "host Git subprocess and filesystem integration coverage"
    ),
    "RepoPromptTests.GitWorktreeInitializationAPITests": (
        "real Git worktree and subprocess integration coverage"
    ),
    "RepoPromptTests.WorkspaceRootNamespaceManifestTests": (
        "filesystem scale and spill-path integration coverage"
    ),
    "RepoPromptTests.WorkspaceRootTargetEvidenceCoordinatorTests": (
        "filesystem/Git coordination integration coverage"
    ),
    "RepoPromptTests.WorkspaceSwitchRecoveryTests": (
        "assembled workspace recovery and persisted-state integration coverage"
    ),
    "RepoPromptTests.WorktreeAPISmokeHarnessTests": (
        "assembled worktree smoke harness with host process lifecycle"
    ),
}


# The deleted runner had to execute these classes one method per process to keep
# them alive. That is historical evidence of host/process coupling, not a
# deterministic pull-request contract. Preserve the evidence after removing the
# workaround so it cannot quietly regain merge-veto power.
HISTORICALLY_METHOD_ISOLATED_SUITES: frozenset[str] = frozenset(
    {
        "RepoPromptTests.AgentModeRunServiceLifecycleTests",
        "RepoPromptTests.AgentModeTranscriptProjectionSharedSubscriptionTests",
        "RepoPromptTests.AgentModeViewModelSharedSubscriptionTests",
        "RepoPromptTests.AgentRunWorktreeStartGitSeedTestCase",
        "RepoPromptTests.CLIProcessRunnerLifecycleTests",
        "RepoPromptTests.ClaudeAgentModeCoordinatorLifecycleTests",
        "RepoPromptTests.CodexAgentModeCoordinatorLivenessTests",
        "RepoPromptTests.CodexAppServerClientDisconnectTests",
        "RepoPromptTests.CodexAppServerClientProcessExitTests",
        "RepoPromptTests.CodexFallbackFIFOTests",
        "RepoPromptTests.CodexMCPBootstrapReadinessTests",
        "RepoPromptTests.CodexMCPRoutingReadinessTests",
        "RepoPromptTests.ContextBuilderMCPProgressTimelineTests",
        "RepoPromptTests.ContextBuilderNestedMCPFailureTests",
        "RepoPromptTests.ContextBuilderWorktreeInheritanceTests",
        "RepoPromptTests.DirectHeadlessCompositionTests",
        "RepoPromptTests.DirectHeadlessProcessTests",
        "RepoPromptTests.DirectHeadlessRuntimeConfigurationTests",
        "RepoPromptTests.DirectHeadlessStdioTransportTests",
        "RepoPromptTests.GitProcessTimeoutTests",
        "RepoPromptTests.GrokBuildCLIProviderProcessTests",
        "RepoPromptTests.MCPSocketDescriptorHardeningTests",
        "RepoPromptTests.ProcessTerminationExitStatusTests",
        "RepoPromptTests.RepoPromptAgentCodexRateLimitsSnapshotIsolationTests",
        "RepoPromptTests.TextCodexRateLimitsSnapshotStoreIsolationTests",
        "RepoPromptTests.WorktreeAPISmokeHarnessTests",
    }
)

INTEGRATION_CLASS_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"(?:Integration|EndToEnd)"),
        "assembled integration/end-to-end fixture",
    ),
    (
        re.compile(r"(?:Benchmark|Performance)"),
        "measurement workload; diagnostics are not pull-request contracts",
    ),
    (
        re.compile(r"(?:Instrumentation|DebugHarness|Diagnostics)"),
        "runtime instrumentation or diagnostics harness",
    ),
    (
        re.compile(r"(?:SmokeHarness|LiveSmoke|LiveHarness)"),
        "assembled live/smoke harness",
    ),
)

CONTRACT_REPLACEMENTS: dict[str, tuple[str, ...]] = {
    "RepoPromptTests.ContextBuilderRunLifecycleTests": (
        "RepoPromptTests.ContextBuilderRunStateContractTests",
    ),
    "RepoPromptTests.BackgroundComposeTabAdmissionTests": (
        "RepoPromptTests.AgentSessionLifecycleAuthorityContractTests",
    ),
}

TEST_TYPE_RE = re.compile(
    r"\b(?:private\s+|fileprivate\s+|internal\s+|public\s+|open\s+)?"
    r"(?:final\s+)?(?:class|struct|actor)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*(?:Tests|TestCase))\b"
)

# These primitives make the clock part of the assertion. They are useful in an
# integration/soak lane, but they do not get veto power over unrelated PRs.
SOURCE_INTEGRATION_PRIMITIVES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Task.sleep", re.compile(r"\bTask\.sleep\s*\(")),
    ("Thread.sleep", re.compile(r"\bThread\.sleep\s*\(")),
    ("usleep", re.compile(r"\busleep\s*\(")),
    ("DispatchQueue.asyncAfter", re.compile(r"\.asyncAfter\s*\(")),
    ("AsyncTestWait", re.compile(r"\bAsyncTestWait\.")),
)


def suite_class_name(suite: str) -> str:
    return suite.rsplit(".", 1)[-1]


def test_suites_in_source(source: str, path: Path) -> tuple[str, ...]:
    class_names = set(TEST_TYPE_RE.findall(source))
    stem_is_test_type = path.stem.endswith(("Tests", "TestCase"))
    stem_has_extension = re.search(
        rf"\bextension\s+{re.escape(path.stem)}\b",
        source,
    ) is not None
    if stem_is_test_type and (not class_names or stem_has_extension):
        class_names.add(path.stem)
    return tuple(
        f"RepoPromptTests.{class_name}"
        for class_name in sorted(class_names)
    )


def matching_lines(source: str, pattern: re.Pattern[str]) -> tuple[int, ...]:
    return tuple(
        source.count("\n", 0, match.start()) + 1
        for match in pattern.finditer(source)
    )


def scan_source_test_policy(repository_root: Path) -> SourceTestPolicy:
    test_root = repository_root / TEST_ROOT
    if not test_root.is_dir():
        raise FileNotFoundError(f"missing test root: {test_root}")

    reasons: dict[str, str] = {}
    occurrences: list[SourceWaitOccurrence] = []
    unmapped: list[SourceWaitOccurrence] = []

    for path in sorted(test_root.rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        symbols: list[str] = []
        file_occurrences: list[tuple[str, int]] = []
        for symbol, pattern in SOURCE_INTEGRATION_PRIMITIVES:
            lines = matching_lines(source, pattern)
            if lines:
                symbols.append(symbol)
                file_occurrences.extend((symbol, line) for line in lines)
        if not file_occurrences:
            continue

        suites = test_suites_in_source(source, path)
        relative_path = path.relative_to(repository_root)
        reason = (
            f"source uses wall-clock/polling primitive(s) "
            f"{', '.join(sorted(set(symbols)))} in {relative_path}"
        )
        for suite in suites:
            reasons[suite] = reason

        for symbol, line in sorted(file_occurrences, key=lambda item: (item[1], item[0])):
            occurrence = SourceWaitOccurrence(
                path=path,
                line=line,
                symbol=symbol,
                suites=suites,
            )
            occurrences.append(occurrence)
            if not suites:
                unmapped.append(occcurrence)

    return SourceTestPolicy(
        integration_reasons=dict(sorted(reasons.items())),
        wait_occurrences=tuple(occurrences),
        unmapped_wait_occurrences=tuple(unmapped),
    )


@lru_cache(maxsize=1)
def repository_source_integration_reasons() -> Mapping[str, str]:
    repository_root = Path(__file__).resolve().parents[1]
    try:
        return scan_source_test_policy(repository_root).integration_reasons
    except FileNotFoundError:
        return {}


def classify_suite(
    suite: str,
    source_integration_reasons: Mapping[str, str] | None = None,
) -> TestPolicyDecision:
    exact_reason = EXACT_INTEGRATION_REASONS.get(suite)
    if exact_reason is not None:
        return TestPolicyDecision(INTEGRATION_TIER, exact_reason)

    if suite in HISTORICALLY_METHOD_ISOLATED_SUITES:
        return TestPolicyDecision(
            INTEGRATION_TIER,
            "historically required one-method-per-process CI isolation",
        )

    effective_source_reasons = (
        source_integration_reasons
        if source_integration_reasons is not None
        else repository_source_integration_reasons()
    )
    source_reason = effective_source_reasons.get(suite)
    if source_reason is not None:
        return TestPolicyDecision(INTEGRATION_TIER, source_reason)

    class_name = suite_class_name(suite)
    for pattern, reason in INTEGRATION_CLASS_PATTERNS:
        if pattern.search(class_name):
            return TestPolicyDecision(INTEGRATION_TIER, reason)

    return TestPolicyDecision(
        CONTRACT_TIER,
        "deterministic pull-request contract coverage",
    )


def suites_for_tier(
    suites: Iterable[str],
    tier: str,
    source_integration_reasons: Mapping[str, str] | None = None,
) -> tuple[str, ...]:
    if tier not in TIERS:
        raise ValueError(f"unknown test tier: {tier}")
    suite_list = tuple(sorted(set(suites)))
    if tier == ALL_TIER:
        return suite_list
    return tuple(
        suite
        for suite in suite_list
        if classify_suite(suite, source_integration_reasons).tier == tier
    )


def partition_suites(
    suites: Iterable[str],
    source_integration_reasons: Mapping[str, str] | None = None,
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    suite_list = tuple(sorted(set(suites)))
    return (
        suites_for_tier(
            suite_list,
            CONTRACT_TIER,
            source_integration_reasons,
        ),
        suites_for_tier(
            suite_list,
            INTEGRATION_TIE,
            source_integration_reasons,
        ),
    )
