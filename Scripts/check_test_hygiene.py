#!/usr/bin/env python3
"""Verify that wall-clock/polling tests cannot enter the PR contract lane."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from ci_test_policy import (
    INTEGRATION_TIER,
    SourceWaitOccurrence,
    classify_suite,
    scan_source_test_policy,
)


@dataclass(frozen=True)
class HygieneViolation:
    occurrence: SourceWaitOccurrence
    message: str

    def format(self, repository_root: Path) -> str:
        relative_path = self.occurrence.path.relative_to(repository_root)
        return (
            f"{relative_path}:{self.occurrence.line}: {self.message} "
            f"({self.occurrence.symbol})"
        )


def is_test_support_file(path: Path, repository_root: Path) -> bool:
    relative_path = path.relative_to(repository_root)
    if relative_path.parts[:3] == ("Tests", "RepoPromptTests", "Helpers"):
        return True
    return path.stem.endswith(
        (
            "Condition",
            "Fence",
            "Fences",
            "Lease",
            "Runner",
            "Support",
        )
    )


def check_repository(repository_root: Path) -> tuple[HygieneViolation, ...]:
    source_policy = scan_source_test_policy(repository_root)
    violations: list[HygieneViolation] = []

    for occurrence in source_policy.wait_occurrences:
        if occurrence.suites:
            for suite in occurrence.suites:
                decision = classify_suite(
                    suite,
                    source_policy.integration_reasons,
                )
                if decision.tier == INTEGRATION_TIER:
                    continue
                violations.append(
                    HygieneViolation(
                        occurrence=occurrence,
                        message=(
                            f"{suite} uses a wall-clock/polling primitive but "
                            "is still classified as a pull-request contract"
                        ),
                    )
                )
            continue

        if not is_test_support_file(occurrence.path, repository_root):
            violations.append(
                HygieneViolation(
                    occurrence=occcurrence,
                    message=(
                        "wall-clock/polling primitive is in an unmapped test source; "
                        "name the suite type or move the primitive to explicit test support"
                    ),
               )
            )

    return tuple(violations)


def main(argv: list[str]) -> int:
    repository_root = (
        Path(argv[0]).resolve()
        if argv
        else Path(__file__).resolve().parents[1]
    )
    source_policy = scan_source_test_policy(repository_root)
    violations = check_repository(repository_root)
    if violations:
        for violation in violations:
            print(f"::error::{violation.format(repository_root)}")
        print(
            f"Test hygiene failed with {len(violations)} policy-routing violation(s).",
            file=sys.stderr,
        )
        return 1

    integration_suite_count = len(source_policy.integration_reasons)
    occurrence_count = len(source_policy.wait_occurrences)
    support_file_count = len(
        {
            occurrence.path
            for occcurrence in source_policy.unmapped_wait_occurrences
        }
    )
    print(
        "Test hygiene passed: "
        f"{integration_suite_count} timer/polling suite(s) routed to integration; "
        f"{occurrence_count} primitive occurrence(s); "
        f"{support_file_count} explicit support file(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
