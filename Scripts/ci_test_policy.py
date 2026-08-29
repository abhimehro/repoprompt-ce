#!/usr/bin/env python3
"""Single source of truth for RepoPrompt CE CI test tiers."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable

CONTRACT_TIER = "contract"
INTEGRATION_TIER = "integration"
ALL_TIER = "all"
TIERS = (CONTRACT_TIER, INTEGRATION_TIER, ALL_TIER)


@dataclass(frozen=True)
class TestPolicyDecision:
    tier: str
    reason: str


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

INTEGRATION_CLASS_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"(?:Benchmark|Performance)"),
        "measurement workload; diagnostics are not pull-request contracts",
    ),
    (
        re.compile(r"(?:Instrumentation|DebugHarness)"),
        "runtime instrumentation or debug harness",
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


def suite_class_name(suite: str) -> str:
    return suite.rsplit(".", 1)[-1]


def classify_suite(suite: str) -> TestPolicyDecision:
    exact_reason = EXACT_INTEGRATION_REASONS.get(suite)
    if exact_reason is not None:
        return TestPolicyDecision(INTEGRATION_TIER, exact_reason)

    class_name = suite_class_name(suite)
    for pattern, reason in INTEGRATION_CLASS_PATTERNS:
        if pattern.search(class_name):
            return TestPolicyDecision(INTEGRATION_TIER, reason)

    return TestPolicyDecision(
        CONTRACT_TIER,
        "deterministic pull-request contract coverage",
    )


def suites_for_tier(suites: Iterable[str], tier: str) -> tuple[str, ...]:
    if tier not in TIERS:
        raise ValueError(f"unknown test tier: {tier}")
    suite_list = tuple(sorted(set(suites)))
    if tier == ALL_TIER:
        return suite_list
    return tuple(
        suite
        for suite in suite_list
        if classify_suite(suite).tier == tier
    )


def partition_suites(
    suites: Iterable[str],
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    suite_list = tuple(sorted(set(suites)))
    return (
        suites_for_tier(suite_list, CONTRACT_TIER),
        suites_for_tier(suite_list, INTEGRATION_TIER),
    )
