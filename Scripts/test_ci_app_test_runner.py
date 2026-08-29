#!/usr/bin/env python3
"""Pure self-tests for the CI test policy and runner."""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

import check_test_hygiene  # noqa: E402
import ci_app_test_runner as runner  # noqa: E402
import ci_test_policy as policy  # noqa: E402


class TestDiscoveryTests(unittest.TestCase):
    def test_parse_suite_methods_deduplicates_and_sorts(self) -> None:
        output = "\n".join(
            [
                "RepoPromptTests.SecondTests/testB",
                "noise",
                "RepoPromptTests.FirstTests/testZ",
                "RepoPromptTests.FirstTests/testA",
                "RepoPromptTests.FirstTests/testA",
            ]
        )

        self.assertEqual(
            runner.parse_suite_methods(output),
            {
                "RepoPromptTests.FirstTests": (
                    "RepoPromptTests.FirstTests/testA",
                    "RepoPromptTests.FirstTests/testZ",
                ),
                "RepoPromptTests.SecondTests": (
                    "RepoPromptTests.SecondTests/testB",
                ),
            },
        )

    def test_lpt_sharding_is_deterministic_and_balanced(self) -> None:
        counts = {
            "RepoPromptTests.A": 8,
            "RepoPromptTests.B": 7,
            "RepoPromptTests.C": 4,
            "RepoPromptTests.D": 3,
            "RepoPromptTests.E": 2,
        }

        shards, loads = runner.assign_suites_to_shards(counts, 2)

        self.assertEqual(loads, (13, 11))
        self.assertLessEqual(max(loads) - min(loads), 2)
        self.assertEqual(set(shards[0] + shards[1]), set(counts))
        self.assertEqual(
            runner.assign_suites_to_shards(counts, 2),
            (shards, loads),
        )


class TestPolicyTests(unittest.TestCase):
    def test_known_host_lifecycle_suite_is_integration(self) -> None:
        decision = policy.classify_suite(
            "RepoPromptTests.ContextBuilderRunLifecycleTests"
        )
        self.assertEqual(decision.tier, policy.INTEGRATION_TIER)
        self.assertIn("real MCP", decision.reason)

    def test_measurement_and_harness_names_are_integration(self) -> None:
        for suite in (
            "RepoPromptTests.WorktreeStartupBenchmarkTests",
            "RepoPromptTests.AgentTranscriptPerformanceTests",
            "RepoPromptTests.CodemapFullLoadDebugHarnessTests",
            "RepoPromptTests.SomeLiveHarnessTests",
        ):
            with self.subTest(suite=suite):
                self.assertEqual(
                    policy.classify_suite(suite).tier,
                    policy.INTEGRATION_TIER,
                )

    def test_unlisted_deterministic_suite_is_contract(self) -> None:
        self.assertEqual(
            policy.classify_suite("RepoPromptTests.ParserContractTests").tier,
            policy.CONTRACT_TIER,
        )

    def test_partition_is_disjoint_and_exhaustive(self) -> None:
        suites = (
            "RepoPromptTests.ParserContractTests",
            "RepoPromptTests.ContextBuilderRunLifecycleTests",
            "RepoPromptTests.WorktreeStartupBenchmarkTests",
        )

        contract, integration = policy.partition_suites(suites)

        self.assertFalse(set(contract).intersection(integration))
        self.assertEqual(set(contract).union(integration), set(suites))

    def test_quarantined_mixed_suites_have_contract_replacements(self) -> None:
        self.assertEqual(
            policy.CONTRACT_REPLACEMENTS[
                "RepoPromptTests.ContextBuilderRunLifecycleTests"
            ],
            ("RepoPromptTests.ContextBuilderRunStateContractTests",),
        )
        self.assertEqual(
            policy.CONTRACT_REPLACEMENTS[
                "RepoPromptTests.BackgroundComposeTabAdmissionTests"
            ],
            ("RepoPromptTests.AgentSessionLifecycleAuthorityContractTests",),
        )


class TestExecutionTests(unittest.TestCase):
    def empty_bundle_selection(self) -> runner.BundleSelection:
        return runner.BundleSelection(None, {}, None)

    def test_suite_environment_is_unique_and_machine_state_isolated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = runner.isolated_suite_environment(
                root,
                "RepoPromptTests.FirstTests",
                {"PATH": "/usr/bin"},
            )
            second = runner.isolated_suite_environment(
                root,
                "RepoPromptTests.SecondTests",
                {"PATH": "/usr/bin"},
            )

            self.assertNotEqual(first["HOME"], second["HOME"])
            self.assertEqual(first["HOME"], first["CFFIXED_USER_HOME"])
            self.assertTrue(Path(first["TMPDIR"]).is_dir())
            self.assertTrue(Path(first["XDG_CONFIG_HOME"]).is_dir())
            self.assertEqual(first["PATH"], "/usr/bin")

    def test_runner_stops_on_first_failure(self) -> None:
        calls: list[tuple[str, ...]] = []

        def executor(command, _cwd, _environment) -> int:
            calls.append(tuple(command))
            return 9

        with tempfile.TemporaryDirectory() as directory:
            result = runner.run_selected_suites(
                ("RepoPromptTests.FirstTests", "RepoPromptTests.SecondTests"),
                swift_binary="swift",
                cwd=None,
                bundle_selection=self.empty_bundle_selection(),
                sandbox_root=Path(directory),
                keep_going=False,
                executor=executor,
                output=io.StringIO(),
            )

        self.assertEqual(result, 9)
        self.assertEqual(len(calls), 1)
        self.assertEqual(
            calls[0],
            (
                "swift",
                "test",
                "--skip-build",
                "--filter",
                "RepoPromptTests.FirstTests",
            ),
        )

    def test_keep_going_reports_all_failures(self) -> None:
        calls: list[str] = []

        def executor(command, _cwd, _environment) -> int:
            calls.append(command[-1])
            return 1 if command[-1].endswith("FirstTests") else 0

        with tempfile.TemporaryDirectory() as directory:
            result = runner.run_selected_suites(
                ("RepoPromptTests.FirstTests", "RepoPromptTests.SecondTests"),
                swift_binary="swift",
                cwd=None,
                bundle_selection=self.empty_bundle_selection(),
                sandbox_root=Path(directory),
                keep_going=True,
                executor=executor,
                output=io.StringIO(),
            )

        self.assertEqual(result, 1)
        self.assertEqual(
            calls,
            ["RepoPromptTests.FirstTests", "RepoPromptTests.SecondTests"],
        )

    def test_xctest_command_uses_target_bundle(self) -> None:
        selection = runner.BundleSelection(
            None,
            {"RepoPromptTests": Path("/tmp/RepoPromptTests.xctest")},
            ("/usr/bin/xctest",),
        )

        self.assertEqual(
            runner.command_for_suite(
                "RepoPromptTests.ParserContractTests",
                swift_binary="swift",
                bundle_selection=selection,
            ),
            (
                "/usr/bin/xctest",
                "-XCTest",
                "RepoPromptTests.ParserContractTests",
                "/tmp/RepoPromptTests.xctest",
            ),
        )


class RepositoryContractTests(unittest.TestCase):
    def test_runner_contains_no_watchdog_or_retry_machinery(self) -> None:
        source = (SCRIPT_DIR / "ci_app_test_runner.py").read_text(encoding="utf-8")
        forbidden = (
            "import signal",
            "import threading",
            "time.sleep",
            "TimeoutExpired",
            "silent-startup",
            "silent_timeout_retries",
            "stop_process_tree",
            "METHOD_ISOLATED_SUITES",
        )
        for value in forbidden:
            with self.subTest(value=value):
                self.assertNotIn(value, source)

    def test_workflows_route_contract_and_integration_tiers(self) -> None:
        pull_request_workflow = (
            REPOSITORY_ROOT / ".github/workflows/ci.yml"
        ).read_text(encoding="utf-8")
        integration_workflow = (
            REPOSITORY_ROOT / ".github/workflows/integration-tests.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("--tier contract", pull_request_workflow)
        self.assertNotIn("--suite-timeout-seconds", pull_request_workflow)
        self.assertNotIn("--silent-timeout-retries", pull_request_workflow)
        self.assertIn("--tier integration", integration_workflow)
        self.assertNotIn("pull_request:", integration_workflow)

    def test_contract_tests_do_not_use_wall_clock_waiting(self) -> None:
        violations = check_test_hygiene.check_repository(REPOSITORY_ROOT)
        self.assertEqual(
            violations,
            (),
            "\n".join(
                violation.format(REPOSITORY_ROOT)
                for violation in violations
            ),
        )


if __name__ == "__main__":
    unittest.main()
