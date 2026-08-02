#!/usr/bin/env python3
"""Deterministic process harness for the DEBUG repoprompt-mcp parser hook."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


class HarnessError(RuntimeError):
    pass


PARSE_TIMEOUT_SECONDS = 10


def parse_command(binary: Path, command: str) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            [str(binary), "--test-parse", command],
            text=True,
            capture_output=True,
            timeout=PARSE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise HarnessError(
            f"parser command timed out after {PARSE_TIMEOUT_SECONDS} seconds: {command!r}"
        ) from error
    if completed.returncode != 0:
        raise HarnessError(
            f"parser command failed with status {completed.returncode}: {command!r}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise HarnessError(f"parser command returned invalid JSON for {command!r}: {error}\n{completed.stdout}") from error
    if not isinstance(payload, dict):
        raise HarnessError(f"parser command returned non-object JSON for {command!r}: {payload!r}")
    return payload


def require_equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise HarnessError(f"{label}: expected {expected!r}, got {actual!r}")


def run(binary: Path) -> None:
    shorthand = parse_command(binary, "manage_worktree op=list include_graph=true graph_limit=8")
    require_equal(shorthand.get("success"), True, "shorthand success")
    require_equal(shorthand.get("command"), "aliasCall", "shorthand command")
    require_equal(shorthand.get("toolName"), "manage_worktree", "shorthand toolName")
    require_equal(
        shorthand.get("args"),
        {"op": "list", "include_graph": True, "graph_limit": 8},
        "shorthand converted args",
    )

    json_call = parse_command(binary, 'manage_worktree {"op":"list"}')
    require_equal(json_call.get("success"), True, "JSON success")
    require_equal(json_call.get("command"), "call", "JSON command")
    require_equal(json_call.get("toolName"), "manage_worktree", "JSON toolName")
    require_equal(json_call.get("jsonPayload"), '{"op":"list"}', "JSON payload")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "binary",
        nargs="?",
        default=Path(".build/debug/repoprompt-mcp"),
        type=Path,
        help="path to the coordinated DEBUG repoprompt-mcp artifact (default: .build/debug/repoprompt-mcp)",
    )
    args = parser.parse_args()
    binary = args.binary.expanduser()
    if not binary.is_file():
        print(f"ERROR: repoprompt-mcp binary not found: {binary}", file=sys.stderr)
        return 1
    if not os.access(binary, os.X_OK):
        print(f"ERROR: repoprompt-mcp binary is not executable: {binary}", file=sys.stderr)
        return 1
    try:
        run(binary)
    except HarnessError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("repoprompt-mcp --test-parse harness passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
