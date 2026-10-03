#!/usr/bin/env python3
"""Unit tests for the build-modularization metrics and ratchet checks."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import modularization_metrics as mm  # noqa: E402


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_fixture(root: Path) -> None:
    # Foundation-level utility wrongly depends upward on an App-level type.
    write(root, "Sources/RepoPrompt/Infrastructure/Utilities/Helper.swift",
          "struct HelperThing {\n    let font = FontPresetValue()\n}\n")
    write(root, "Sources/RepoPrompt/App/FontPresetValue.swift",
          "struct FontPresetValue {\n    static let shared = FontPresetValue()\n    let helper = HelperThing()\n}\n"
          "// HelperThing.shared in a comment must not count\n"
          "let label = \"UserDefaults.standard\"\n")
    write(root, "Sources/RepoPrompt/Features/Chat/ChatThing.swift",
          "struct ChatThingModel {\n    func run() { _ = FontPresetValue.shared; _ = UserDefaults.standard }\n}\n")
    write(root, "Sources/RepoPromptShared/Shared.swift", "struct SharedValue {}\n")
    write(root, "Tests/RepoPromptTests/ChatTests.swift",
          "@testable import RepoPromptApp\nfunc testIt() async throws { try await Task.sleep(for: .seconds(1)) }\n")


class StripTests(unittest.TestCase):
    def test_strips_comments_and_strings(self) -> None:
        stripped = mm.strip_swift('let a = "x.shared" // Foo.shared\n/* Bar.shared */ let b = 1\n')
        self.assertNotIn("shared", stripped)
        self.assertIn("let b = 1", stripped)


class ComponentTests(unittest.TestCase):
    def test_component_and_rank(self) -> None:
        self.assertEqual(mm.component_for("App/WindowState.swift"), "App")
        self.assertEqual(mm.component_for("App/Sparkle/X.swift"), "App/Sparkle")
        self.assertEqual(mm.component_for("Features/AgentMode/Runtime/Codex/A.swift"), "Features/AgentMode/Runtime")
        self.assertEqual(mm.layer_rank("Infrastructure/Utilities"), 0)
        self.assertEqual(mm.layer_rank("Infrastructure/MCP/ViewModels"), 9)
        self.assertEqual(mm.layer_rank("App"), 12)


class SCCTests(unittest.TestCase):
    def test_finds_cycle(self) -> None:
        graph = {"a": {"b"}, "b": {"c"}, "c": {"a"}, "d": {"a"}}
        components = mm.strongly_connected_components(graph)
        self.assertIn(["a", "b", "c"], components)
        self.assertIn(["d"], components)

    def test_deep_chain_is_iterative(self) -> None:
        graph = {str(i): {str(i + 1)} for i in range(5000)}
        self.assertEqual(len(mm.strongly_connected_components(graph)), 5001)


class CollectTests(unittest.TestCase):
    def test_collects_fixture_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_fixture(root)
            metrics, details = mm.collect(root)
        self.assertEqual(metrics["app_target_swift_files"], 3)
        self.assertEqual(metrics["app_static_shared_declarations"], 1)
        self.assertEqual(metrics["app_shared_accessor_uses"], 1)  # only the real call site; comment excluded
        self.assertEqual(metrics["app_userdefaults_standard_uses"], 1)
        self.assertEqual(metrics["tests_testable_import_app_files"], 1)
        self.assertEqual(metrics["tests_sleep_calls"], 1)
        self.assertEqual(metrics["app_wrong_way_file_edges"], 1)  # Utilities -> App; unranked Features/Chat ignored
        self.assertEqual(metrics["app_largest_cycle_components"], 2)
        self.assertEqual(details["top_wrong_way_targets"][0]["file"], "App/FontPresetValue.swift")


class RatchetCommandTests(unittest.TestCase):
    def test_lexical_collision_and_fake_clock_are_informational(self) -> None:
        self.assertIn("app_largest_cycle_components", mm.TRACKED_METRICS)
        self.assertIn("tests_sleep_calls", mm.TRACKED_METRICS)
        self.assertEqual(len(mm._SLEEP.findall("func sleep(until deadline: Instant) {}")), 1)
        baseline = {name: 0 for name in mm.RATCHETED_METRICS}
        baseline["app_target_swift_lines"] = 0
        current = {**baseline, "app_largest_cycle_components": 68, "tests_sleep_calls": 50}
        self.assertEqual(mm.regressions(current, baseline), [])

    def run_main(self, *args: str) -> int:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return mm.main(list(args))

    def test_update_then_check_and_refuse_regression(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_fixture(root)
            baseline = root / "ratchets.json"
            self.assertEqual(self.run_main("update", "--root", tmp, "--baseline", str(baseline)), 0)
            self.assertEqual(self.run_main("check", "--root", tmp, "--baseline", str(baseline)), 0)
            document = json.loads(baseline.read_text())
            self.assertEqual(document["ratcheted"], list(mm.RATCHETED_METRICS))

            write(root, "Sources/RepoPrompt/Features/Chat/More.swift",
                  "struct MoreThing { static let shared = MoreThing() }\n")
            self.assertEqual(self.run_main("check", "--root", tmp, "--baseline", str(baseline)), 1)
            self.assertEqual(self.run_main("update", "--root", tmp, "--baseline", str(baseline)), 1)
            self.assertEqual(
                self.run_main("update", "--root", tmp, "--baseline", str(baseline), "--allow-regression"), 0
            )
            self.assertEqual(self.run_main("check", "--root", tmp, "--baseline", str(baseline)), 0)

    def test_update_refuses_app_lines_growth_within_headroom(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_fixture(root)
            baseline = root / "ratchets.json"
            self.assertEqual(self.run_main("update", "--root", tmp, "--baseline", str(baseline)), 0)
            before = json.loads(baseline.read_text())["metrics"]["app_target_swift_lines"]
            write(root, "Sources/RepoPrompt/Features/Chat/Growth.swift", "let growth = 0\n" * 1500)
            # Within headroom: `check` passes, but `update` must not raise the baseline.
            self.assertEqual(self.run_main("check", "--root", tmp, "--baseline", str(baseline)), 0)
            self.assertEqual(self.run_main("update", "--root", tmp, "--baseline", str(baseline)), 1)
            self.assertEqual(json.loads(baseline.read_text())["metrics"]["app_target_swift_lines"], before)
            self.assertEqual(
                self.run_main("update", "--root", tmp, "--baseline", str(baseline), "--allow-regression"), 0
            )
            self.assertEqual(json.loads(baseline.read_text())["metrics"]["app_target_swift_lines"], before + 1500)

    def test_baseline_raises_covers_tracked_metrics(self) -> None:
        baseline = {name: 5 for name in mm.RATCHETED_METRICS + mm.TRACKED_METRICS}
        current = dict(baseline, tests_sleep_calls=6)
        self.assertEqual(mm.baseline_raises(current, baseline), ["tests_sleep_calls: 5 -> 6"])
        self.assertEqual(mm.baseline_raises(dict(baseline, tests_sleep_calls=4), baseline), [])

    def test_check_fails_without_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            make_fixture(Path(tmp))
            self.assertEqual(self.run_main("check", "--root", tmp, "--baseline", str(Path(tmp) / "none.json")), 1)

    def test_regressions_reports_missing_metric(self) -> None:
        problems = mm.regressions({name: 0 for name in mm.RATCHETED_METRICS}, {})
        self.assertEqual(len(problems), len(mm.RATCHETED_METRICS) + 1)


if __name__ == "__main__":
    unittest.main()
