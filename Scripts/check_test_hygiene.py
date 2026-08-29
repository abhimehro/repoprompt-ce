#!/usr/bin/env python3
"""Reject wall-clock waiting in pull-request XCTest classes."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

from ci_test_policy import CONTRACT_TIER, classify_suite

TEST_ROOT = Path("Tests/RepoPromptTests")
XCTEST_CLASS_RE = re.compile(
    r"\b(?:private\s+|fileprivate\s+|internal\s+|public\s+|open\s+)?"
    r"(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase\b"
)
FORBIDDEN_TIMER_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Task.sleep", re.compile(r"\bTask\.sleep\s*\(")),
    ("Thread.sleep", re.compile(r"\bThread\.sleep\s*\(")),
    ("usleep", re.compile(r"\busleep\s*\(")),
    ("DispatchQueue.asyncAfter", re.compile(r"\.asyncAfter\s*\(")),
)


@dataclass(frozen=True)
class HygieneViolation:
    path: Path
    line: int
    symbol: str
    suites: tuple[str, ...]

    def format(self, repository_root: Path) -> str:
        relative_path = self.path.relative_to(repository_root)
        suite_list = ", ".join(self.suites) if self.suites else "unknown test type"
        return (
            f"{relative_path}:{self.line}: pull-request test uses {self.symbol}; "
            f"move host/timing coverage to the integration tier or replace the wait "
            f"with an explicit gate ({suite_list})"
        )


def test_suites_in_source(source: str) -> tuple[str, ...]:
    return tuple(
        sorted(
            {
                f"RepoPromptTests.{class_name}"
                for class_name in XCTEST_CLASS_RE.findall(source)
            }
        )
    )


def matching_lines(source: str, pattern: re.Pattern[str]) -> tuple[int, ...]:
    line_starts = [0]
    for match in re.finditer("\n", source):
        line_starts.append(match.end())

    lines: list[int] = []
    for match in pattern.finditer(source):
        lines.append(1 + sum(start <= match.start() for start in line_starts) - 1)
    return tuple(lines)


def check_file(path: Path, repository_root: Path) -> tuple[HygieneViolation, ...]:
    relative_path = path.relative_to(repository_root)
    if relative_path.parts[:3] == ("Tests", "RepoPromptTests", "Helpers"):
        return ()

    source = path.read_text(encoding="utf-8")
    suites = test_suites_in_source(source)
    if suites and all(classify_suite(suite).tier != CONTRACT_TIER for suite in suites):
        return ()

    violations: list[HygieneViolation] = []
    for symbol, pattern in FORBIDDEN_TIMER_PATTERNS:
        for line in matching_lines(source, pattern):
            violations.append(
                HygieneViolation(
                    path=path,
                    line=line,
                    symbol=symbol,
                    suites=suites,
                )
            )
    return tuple(violations)


def check_repository(repository_root: Path) -> tuple[HygieneViolation, ...]:
    test_root = repository_root / TEST_ROOT
    if not test_root.is_dir():
        raise FileNotFoundError(f"missing test root: {test_root}")

    violations: list[HygieneViolation] = []
    for path in sorted(test_root.rglob("*.swift")):
        violations.extend(check_file(path, repository_root))
    return tuple(violations)


def main(argv: list[str]) -> int:
    repository_root = (
        Path(argv[0]).resolve()
        if argv
        else Path(__file__).resolve().parents[1]
    )
    violations = check_repository(repository_root)
    if not violations:
        print("Test hygiene passed: no pull-request XCTest class uses wall-clock waiting.")
        return 0

    for violation in violations:
        print(f"::error::{violation.format(repository_root)}")
    print(
        f"Test hygiene failed with {len(violations)} wall-clock wait violation(s).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
