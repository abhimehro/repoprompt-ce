#!/usr/bin/env python3
"""Measure the user-visible launch path of a RepoPrompt build.

The caller supplies a readiness probe (for example, a small script which
checks that the first window is visible and usable).  This deliberately does
not measure process creation alone.  Run the same command against two builds,
with the same probe and workload, and compare the JSON reports.
"""
from __future__ import annotations

import argparse
import json
import os
import resource
import subprocess
import threading
import time
from pathlib import Path


def contend(stop: threading.Event) -> None:
    value = 1
    while not stop.is_set():
        value = (value * 1664525 + 1013904223) & 0xFFFFFFFF


def run_once(args: argparse.Namespace) -> dict[str, float | int | str]:
    stop = threading.Event()
    workers = [threading.Thread(target=contend, args=(stop,), daemon=True)
               for _ in range(args.contention)]
    for worker in workers:
        worker.start()

    before_usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic_ns()
    child = subprocess.Popen(args.command, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            probe = subprocess.run(args.ready, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, check=False)
            if probe.returncode == 0:
                break
            time.sleep(args.poll)
        else:
            child.kill()
            raise RuntimeError("readiness probe timed out")
        elapsed_ms = (time.monotonic_ns() - started) / 1_000_000
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        return {
            "launch_to_ready_ms": elapsed_ms,
            "child_user_cpu_ms": (usage.ru_utime - before_usage.ru_utime) * 1000,
            "child_system_cpu_ms": (usage.ru_stime - before_usage.ru_stime) * 1000,
            # macOS reports this as the child's maximum resident footprint.
            "peak_resident_kb": usage.ru_maxrss,
            "allocation_count": "unavailable (use Instruments Allocations)",
        }
    finally:
        stop.set()
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        for worker in workers:
            worker.join(timeout=1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", nargs="+", required=True,
                        help="application command, including its arguments")
    parser.add_argument("--ready", nargs="+", required=True,
                        help="probe that exits 0 when the first usable window is ready")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--contention", type=int, default=2,
                        help="busy worker threads used to model CPU contention")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--poll", type=float, default=.05)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reports = [run_once(args) for _ in range(args.runs)]
    result = {"runs": reports, "command": args.command, "ready_probe": args.ready,
              "contention_workers": args.contention}
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
