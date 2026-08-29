#!/usr/bin/env python3
"""Pure self-tests for the CI test policy and runner."""

from __future__ import annotations

import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

import check_test_hygiene  # noqa: E402
import ci_app_test_runner as runner  # noqa: E402
import ci_test_policy as policy  # noqa: E402


@contextmanager
def synthetic_repository(sources: dict[str, str]):
    with tempfile.TemporaryDirectory() as directory:
        repository_root = Path(directory)
        test_root = repository_root / policy.TEST_ROOT
        test_root.mkdir(parents=True)
        for relative_path, source in sources.items():
            path = test_root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source, encoding="utf-8")
        yield repository_root


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

    def test_invalid_shard_arguments_are_rejected(self) -> None:
        invalid_arguments = ((0, 1), (2, 0), (2, 3))
        for shard_count, shard_index in invalid_arguments:
            with self.subTest(
                shard_count=shard_count,
                shard_index=shard_index,
            ):
                with self.assertRaises(ValueError):
                    runner.validate_shard_args(shard_count, shard_index)

        with self.assertRaisesRegex(ValueError, "greater than zero"):
            runner.assign_suites_to_shards({}, 0)

    def test_lpt_sharding_is_deterministic_balanced_and_exhaustive(self) -> None:
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
            runner.assign_suites_to_shards(dict(reversed(counts.items())), 2),
            (shards, loads),
        )

    def test_suite_with_no_methods_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "has no test methods"):
            runner.assign_suites_to_shards(
                {"RepoPromptTests.EmptyTests": 0},
                1,
            )


class TestPolicyTests(unittest.TestCase):
    def test_known_host_lifecycle_suite_is_integration_with_exact_reason(self) -> None:
        suite = "RepoPromptTests.ContextBuilderRunLifecycleTests"
        decision = policy.classify_suite(
            suite,
            {suite: "less authoritative source reason"},
        )
        self.assertEqual(decision.tier, policy.INTEGRATION_TIER)
        self.assertEqual(
            decision.reason,
            policy.EXACT_INTEGRATION_REASONS[suite],
        )

    def test_classification_precedence_is_exact_historical_source_pattern(self) -> None:
        historical = "RepoPromptTests.AgentModeRunServiceLifecycleTests"
        historical_decision = policy.classify_suite(
            historical,
            {historical: "source reason"},
        )
        self.assertEqual(
            historical_decision.reason,
            "historically required one-method-per-process CI isolation",
        )

        source_suite = "RepoPromptTests.SyntheticIntegrationTests"
        source_decision = policy.classify_suite(
            source_suite,
            {source_suite: "source reason"},
        )
        self.assertEqual(source_decision.reason, "source reason")

        pattern_decision = policy.classify_suite(
            "RepoPromptTests.SyntheticIntegrationTests",
            {},
        )
        self.assertEqual(
            pattern_decision.reason,
            "assembled integration/end-to-end fixture",
        )

    def test_semantic_suite_patterns_are_narrow(self) -> None:
        integration_suites = (
            "RepoPromptTests.HistoryIntegrationTests",
            "RepoPromptTests.GitMergeEndToEndTests",
            "RepoPromptTests.WorktreeStartupBenchmarkTests",
            "RepoPromptTests.CodemapDebugDiagnosticsTests",
            "RepoPromptTests.SomeLiveHarnessTests",
        )
        for suite in integration_suites:
            with self.subTest(suite=suite):
                self.assertEqual(
                    policy.classify_suite(suite, {}).tier,
                    policy.INTEGRATION_TIER,
                )

        contract_suites = (
            "RepoPromptTests.CodexIntegrationConfigurationTests",
            "RepoPromptTests.WorkspaceCodemapBindingIntegrationRegistryTests",
            "RepoPromptTests.WorktreeStartupBenchmarkReleaseAbsenceTests",
            "RepoPromptTests.ParserPerformanceCounterTests",
        )
        for suite in contract_suites:
            with self.subTest(suite=suite):
                self.assertEqual(
                    policy.classify_suite(suite, {}).tier,
                    policy.CONTRACT_TIER,
                )

    def test_partition_is_order_stable_disjoint_and_exhaustive(self) -> None:
        suites = (
            "RepoPromptTests.WorktreeStartupBenchmarkTests",
            "RepoPromptTests.ParserContractTests",
            "RepoPromptTests.ContextBuilderRunLifecycleTests",
            "RepoPromptTests.CodexIntegrationConfigurationTests",
            "RepoPromptTests.ParserContractTests",
        )

        contract, integration = policy.partition_suites(suites, {})

        self.assertEqual(
            contract,
            (
                "RepoPromptTests.CodexIntegrationConfigurationTests",
                "RepoPromptTests.ParserContractTests",
            ),
        )
        self.assertEqual(
            integration,
            (
                "RepoPromptTests.ContextBuilderRunLifecycleTests",
                "RepoPromptTests.WorktreeStartupBenchmarkTests",
            ),
        )
        self.assertFalse(set(contract).intersection(integration))
        self.assertEqual(set(contract).union(integration), set(suites))

    def test_unknown_tier_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown test tier"):
            policy.suites_for_tier((), "unknown", {})

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


class SourcePolicyScannerTests(unittest.TestCase):
    def test_deterministic_suite_without_timers_remains_contract(self) -> None:
        with synthetic_repository(
            {
                "ParserContractTests.swift": (
                    "final class ParserContractTests: XCTestCase {\n"
                    "    func testParse() {}\n"
                    "}\n"
                )
            }
        ) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(source_policy.integration_reasons, {})
        self.assertEqual(source_policy.wait_occurrences, ())
        self.assertEqual(
            policy.classify_suite(
                "RepoPromptTests.ParserContractTests",
                source_policy.integration_reasons,
            ).tier,
            policy.CONTRACT_TIER,
        )

    def test_all_wait_primitives_route_suite_with_stable_lines_and_reason(self) -> None:
        source = "\n".join(
            [
                "final class TimerTests: XCTestCase {",
                "    func testTimers() async throws {",
                "        try await Task.sleep(nanoseconds: 1)",
                "        Thread.sleep(forTimeInterval: 0.1)",
                "        usleep(1)",
                "        DispatchQueue.main.asyncAfter(deadline: .now()) {}",
                "        _ = AsyncTestWait.until",
                "    }",
                "}",
            ]
        )
        with synthetic_repository({"TimerTests.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            [occurrence.line for occurrence in source_policy.wait_occurrences],
            [3, 4, 5, 6, 7],
        )
        self.assertEqual(
            [occurrence.symbol for occurrence in source_policy.wait_occurrences],
            [
                "Task.sleep",
                "Thread.sleep",
                "usleep",
                "asyncAfter",
                "AsyncTestWait",
            ],
        )
        self.assertEqual(
            source_policy.integration_reasons,
            {
                "RepoPromptTests.TimerTests": (
                    "source uses wall-clock/polling primitive(s) "
                    "AsyncTestWait, Task.sleep, Thread.sleep, asyncAfter, usleep "
                    "in Tests/RepoPromptTests/TimerTests.swift"
                )
            },
        )

    def test_multiple_xctest_classes_in_one_file_are_all_routed(self) -> None:
        source = "\n".join(
            [
                "final class SecondTests: XCTestCase {}",
                "Task.sleep(nanoseconds: 1)",
                "final class FirstTests: XCTestCase {}",
            ]
        )
        with synthetic_repository({"Mixed.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            source_policy.wait_occurrences[0].suites,
            (
                "RepoPromptTests.FirstTests",
                "RepoPromptTests.SecondTests",
            ),
        )
        self.assertEqual(
            tuple(source_policy.integration_reasons),
            (
                "RepoPromptTests.FirstTests",
                "RepoPromptTests.SecondTests",
            ),
        )

    def test_extension_only_file_routes_suite_declared_elsewhere(self) -> None:
        sources = {
            "SharedTests.swift": "final class SharedTests: XCTestCase {}\n",
            "SharedTiming.swift": (
                "extension SharedTests {\n"
                "    func testTiming() async { Task.sleep(nanoseconds: 1) }\n"
                "}\n"
            ),
        }
        with synthetic_repository(sources) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            tuple(source_policy.integration_reasons),
            ("RepoPromptTests.SharedTests",),
        )
        self.assertEqual(
            source_policy.wait_occurrences[0].suites,
            ("RepoPromptTests.SharedTests",),
        )

    def test_no_suite_file_is_unmapped_even_when_filename_looks_like_suite(self) -> None:
        source = "func helper() async {\n    Task.sleep(nanoseconds: 1)\n}\n"
        with synthetic_repository({"TimerOnlyTests.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)
            violations = check_test_hygiene.check_repository(repository_root)
            diagnostic = violations[0].format(repository_root)

        self.assertEqual(source_policy.integration_reasons, {})
        self.assertEqual(source_policy.wait_occurrences[0].suites, ())
        self.assertEqual(source_policy.unmapped_wait_occurrences[0].line, 2)
        self.assertEqual(len(violations), 1)
        self.assertEqual(
            diagnostic,
            "Tests/RepoPromptTests/TimerOnlyTests.swift:2: "
            "wall-clock/polling primitive is in an unmapped test source; "
            "name the suite type or move the primitive to explicit test support "
            "(Task.sleep)",
        )

    def test_xctestcase_support_extension_is_not_invented_as_a_suite(self) -> None:
        source = "\n".join(
            [
                "extension XCTestCase {",
                "    func waitForHelper() { Task.sleep(nanoseconds: 1) }",
                "}",
            ]
        )
        with synthetic_repository({"XCTestHelpers.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(source_policy.integration_reasons, {})
        self.assertEqual(source_policy.wait_occurrences[0].suites, ())

    def test_malformed_but_readable_source_is_scanned(self) -> None:
        source = "\n".join(
            [
                "final class BrokenTests: XCTestCase {",
                "    func testBroken() async {",
                "        Task.sleep(",
            ]
        )
        with synthetic_repository({"Broken.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            tuple(source_policy.integration_reasons),
            ("RepoPromptTests.BrokenTests",),
        )
        self.assertEqual(source_policy.wait_occurrences[0].line, 3)

    def test_duplicate_discoveries_and_same_line_occurrences_are_deduplicated(self) -> None:
        source = "\n".join(
            [
                "final class DuplicateTests: XCTestCase {}",
                "extension DuplicateTests {}",
                "Task.sleep(nanoseconds: 1); Task.sleep(nanoseconds: 2)",
                "Task.sleep(nanoseconds: 3)",
            ]
        )
        with synthetic_repository({"Duplicate.swift": source}) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            [occurrence.line for occurrence in source_policy.wait_occurrences],
            [3, 4],
        )
        self.assertEqual(
            source_policy.wait_occurrences[0].suites,
            ("RepoPromptTests.DuplicateTests",),
        )

    def test_explicit_support_is_exact_and_filename_folklore_is_rejected(self) -> None:
        sources = {
            "Helpers/AsyncTestCondition.swift": "Task.sleep(nanoseconds: 1)\n",
            "Helpers/OrdinaryTimerSupport.swift": "Task.sleep(nanoseconds: 1)\n",
        }
        with synthetic_repository(sources) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)
            violations = check_test_hygiene.check_repository(repository_root)
            allowed_path = (
                repository_root
                / policy.TEST_ROOT
                / "Helpers/AsyncTestCondition.swift"
            )

            self.assertEqual(
                policy.explicit_test_support_reason(allowed_path, repository_root),
                "shared asynchronous condition wait primitive",
            )
            self.assertEqual(len(source_policy.unmapped_wait_occurrences), 2)
            self.assertEqual(len(violations), 1)
            self.assertEqual(
                violations[0].occurrence.path.name,
                "OrdinaryTimerSupport.swift",
            )

    def test_duplicate_suite_files_produce_one_sorted_combined_reason(self) -> None:
        sources = {
            "ZTiming.swift": (
                "extension SharedTests {\n"
                "    func z() { usleep(1) }\n"
                "}\n"
            ),
            "ATiming.swift": (
                "extension SharedTests {\n"
                "    func a() { Task.sleep(nanoseconds: 1) }\n"
                "}\n"
            ),
        }
        with synthetic_repository(sources) as repository_root:
            source_policy = policy.scan_source_test_policy(repository_root)

        self.assertEqual(
            source_policy.integration_reasons["RepoPromptTests.SharedTests"],
            "source uses wall-clock/polling primitive(s) Task.sleep, usleep in "
            "Tests/RepoPromptTests/ATiming.swift, "
            "Tests/RepoPromptTests/ZTiming.swift",
        )


class TestBundleResolutionTests(unittest.TestCase):
    def test_discover_test_bundles_parses_show_bin_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bin_path = Path(directory)
            first = bin_path / "RepoPromptTests.xctest"
            second = bin_path / "RepoPromptCodeMapCoreTests.xctest"
            first.mkdir()
            second.mkdir()
            completed = subprocess.CompletedProcess(
                args=["swift", "build", "--show-bin-path"],
                returncode=0,
                stdout=f"{bin_path}\n",
                stderr="",
            )
            with mock.patch.object(runner.subprocess, "run", return_value=completed):
                discovered = runner.discover_test_bundles("swift", None)

        self.assertEqual(
            discovered,
            {
                "RepoPromptCodeMapCoreTests": second,
                "RepoPromptTests": first,
            },
        )

    def test_unique_package_bundle_is_preferred(self) -> None:
        package_bundle = Path("/tmp/RepoPromptPackageTests.xctest")
        discovered = {
            "RepoPromptPackageTests": package_bundle,
            "RepoPromptTests": Path("/tmp/RepoPromptTests.xctest"),
        }
        with mock.patch.object(
            runner,
            "discover_test_bundles",
            return_value=discovered,
        ), mock.patch.object(
            runner,
            "xctest_binary_path",
            return_value=("/usr/bin/xctest",),
        ):
            selection = runner.resolve_bundle_selection(
                swift_binary="swift",
                cwd=None,
                suites=("RepoPromptTests.ParserTests",),
                explicit_bundle=None,
                explicit_bundle_name=None,
                disable_bundle_discovery=False,
            )

        self.assertEqual(selection.package_bundle, package_bundle)
        self.assertEqual(selection.target_bundles, {})

    def test_target_bundle_resolution_and_missing_target_diagnostic(self) -> None:
        root_bundle = Path("/tmp/RepoPromptTests.xctest")
        discovered = {
            "RepoPromptTests": root_bundle,
            "RepoPromptCodeMapCoreTests": Path(
                "/tmp/RepoPromptCodeMapCoreTests.xctest"
            ),
        }
        with mock.patch.object(
            runner,
            "discover_test_bundles",
            return_value=discovered,
        ), mock.patch.object(
            runner,
            "xctest_binary_path",
            return_value=("/usr/bin/xctest",),
        ):
            selection = runner.resolve_bundle_selection(
                swift_binary="swift",
                cwd=None,
                suites=("RepoPromptTests.ParserTests",),
                explicit_bundle=None,
                explicit_bundle_name=None,
                disable_bundle_discovery=False,
            )
            with self.assertRaisesRegex(
                ValueError,
                r"missing XCTest bundles for selected targets: \['MissingTests'\]",
            ):
                runner.resolve_bundle_selection(
                    swift_binary="swift",
                    cwd=None,
                    suites=("MissingTests.ParserTests",),
                    explicit_bundle=None,
                    explicit_bundle_name=None,
                    disable_bundle_discovery=False,
                )

        self.assertEqual(
            selection.target_bundles,
            {"RepoPromptTests": root_bundle},
        )

    def test_explicit_bundle_name_reports_missing_and_foreign_suites(self) -> None:
        discovered = {
            "RepoPromptTests": Path("/tmp/RepoPromptTests.xctest"),
        }
        with mock.patch.object(
            runner,
            "discover_test_bundles",
            return_value=discovered,
        ), mock.patch.object(
            runner,
            "xctest_binary_path",
            return_value=("/usr/bin/xctest",),
        ):
            with self.assertRaisesRegex(ValueError, "did not resolve exactly one"):
                runner.resolve_bundle_selection(
                    swift_binary="swift",
                    cwd=None,
                    suites=("RepoPromptTests.ParserTests",),
                    explicit_bundle=None,
                    explicit_bundle_name="MissingTests",
                    disable_bundle_discovery=False,
                )
            with self.assertRaisesRegex(ValueError, "other targets"):
                runner.resolve_bundle_selection(
                    swift_binary="swift",
                    cwd=None,
                    suites=("RepoPromptCodeMapCoreTests.ParserTests",),
                    explicit_bundle=None,
                    explicit_bundle_name="RepoPromptTests",
                    disable_bundle_discovery=False,
                )

    def test_command_construction_uses_xctest_or_swift_fallback(self) -> None:
        xctest_selection = runner.BundleSelection(
            None,
            {"RepoPromptTests": Path("/tmp/RepoPromptTests.xctest")},
            ("/usr/bin/xctest",),
        )
        self.assertEqual(
            runner.command_for_suite(
                "RepoPromptTests.ParserContractTests",
                swift_binary="swift",
                bundle_selection=xctest_selection,
            ),
            (
                "/usr/bin/xctest",
                "-XCTest",
                "RepoPromptTests.ParserContractTests",
                "/tmp/RepoPromptTests.xctest",
            ),
        )

        self.assertEqual(
            runner.command_for_suite(
                "RepoPromptTests.ParserContractTests",
                swift_binary="custom-swift",
                bundle_selection=runner.BundleSelection(None, {}, None),
            ),
            (
                "custom-swift",
                "test",
                "--skip-build",
                "--filter",
                "RepoPromptTests.ParserContractTests",
            ),
        )


class TestExecutionTests(unittest.TestCase):
    def empty_bundle_selection(self) -> runner.BundleSelection:
        return runner.BundleSelection(None, {}, None)

    def test_suite_environment_preserves_inherited_values_and_replaces_state(self) -> None:
        inherited = {
            "PATH": "/usr/bin",
            "CUSTOM_TOKEN": "preserved",
            "HOME": "/old/home",
            "CFFIXED_USER_HOME": "/old/fixed-home",
            "TMPDIR": "/old/tmpdir",
            "TMP": "/old/tmp",
            "TEMP": "/old/temp",
            "XDG_CONFIG_HOME": "/old/config",
            "XDG_CACHE_HOME": "/old/cache",
            "XDG_DATA_HOME": "/old/data",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = runner.isolated_suite_environment(
                root,
                "RepoPromptTests.FirstTests",
                inherited,
            )
            second = runner.isolated_suite_environment(
                root,
                "RepoPromptTests.SecondTests",
                inherited,
            )

            self.assertNotEqual(first["HOME"], second["HOME"])
            self.assertEqual(first["HOME"], first["CFFIXED_USER_HOME"])
            self.assertEqual(first["TMPDIR"], first["TMP"])
            self.assertEqual(first["TMPDIR"], first["TEMP"])
            self.assertEqual(first["PATH"], "/usr/bin")
            self.assertEqual(first["CUSTOM_TOKEN"], "preserved")
            for key in (
                "HOME",
                "TMPDIR",
                "XDG_CONFIG_HOME",
                "XDG_CACHE_HOME",
                "XDG_DATA_HOME",
            ):
                self.assertTrue(Path(first[key]).is_dir(), key)
                self.assertNotEqual(first[key], inherited[key])

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
        self.assertEqual(calls[0][-1], "RepoPromptTests.FirstTests")

    def test_keep_going_runs_every_suite_and_returns_aggregate_failure(self) -> None:
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

    def test_empty_selection_succeeds_without_launching(self) -> None:
        def executor(_command, _cwd, _environment) -> int:
            self.fail("empty selection must not launch a command")

        with tempfile.TemporaryDirectory() as directory:
            result = runner.run_selected_suites(
                (),
                swift_binary="swift",
                cwd=None,
                bundle_selection=self.empty_bundle_selection(),
                sandbox_root=Path(directory),
                keep_going=False,
                executor=executor,
                output=io.StringIO(),
            )

        self.assertEqual(result, 0)


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

    def test_workflows_preserve_contract_and_integration_routing_contracts(self) -> None:
        pull_request_workflow = (
            REPOSITORY_ROOT / ".github/workflows/ci.yml"
        ).read_text(encoding="utf-8")
        integration_workflow = (
            REPOSITORY_ROOT / ".github/workflows/integration-tests.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("--tier contract", pull_request_workflow)
        self.assertNotIn("--tier integration", pull_request_workflow)
        self.assertIn(
            "name: Build and Test (contract shard ${{ matrix.shard }})",
            pull_request_workflow,
        )
        self.assertIn("persist-credentials: false", pull_request_workflow)
        self.assertIn("set -euo pipefail", pull_request_workflow)
        self.assertNotIn("--suite-timeout-seconds", pull_request_workflow)
        self.assertNotIn("--silent-timeout-retries", pull_request_workflow)

        self.assertIn("workflow_dispatch:", integration_workflow)
        self.assertIn("schedule:", integration_workflow)
        self.assertIn("push:", integration_workflow)
        self.assertNotIn("pull_request:", integration_workflow)
        self.assertIn("--tier integration", integration_workflow)
        self.assertIn(
            "name: Integration (shard ${{ matrix.shard }})",
            integration_workflow,
        )
        self.assertIn("persist-credentials: false", integration_workflow)
        self.assertIn("set -euo pipefail", integration_workflow)
        self.assertIn("swiftpm-integration-", integration_workflow)
        self.assertNotIn("swiftpm-integration-", pull_request_workflow)

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
