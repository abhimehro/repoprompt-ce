#!/usr/bin/env python3
"""Deterministic weighted heavy-admission regressions; no Swift build."""

from __future__ import annotations

import json
import sys
import threading
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import conductor  # noqa: E402


class ReservationTests(unittest.TestCase):
    def test_estimate_uses_measured_peak_rss_and_fails_closed_for_legacy_records(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            conductor, 'machine_lock_dir', return_value=Path(temporary)
        ):
            env = {'REPOPROMPT_DEV_HEAVY_SLOTS': '4'}
            self.assertEqual(conductor.heavy_required_slots('test', {'module': 'CoreTests'}, env), 1)
            self.assertEqual(conductor.heavy_required_slots('swift-build', {'product': 'all'}, env), 4)
            conductor.record_heavy_rss_sample('test', {'module': 'CoreTests'}, 2 * 1024**3)
            self.assertEqual(conductor.heavy_required_slots('test', {'module': 'CoreTests'}, env), 2)
            coordinator = conductor.FairHeavyAdmission(
                {'operation': 'test', 'requiredSlots': 1, 'reservationBytes': conductor.HEAVY_RSS_UNIT_BYTES},
                env, identity_provider=lambda _pid: 'self',
            )
            try:
                self.assertEqual(coordinator._slots_for_waiter({'state': 'acquired'}), 4)
                self.assertEqual(coordinator._slots_for_waiter({'reservationBytes': 5 * 1024**3}), 4)
            finally:
                coordinator.abandon()

    def test_two_module_jobs_share_budget_and_app_waits_fifo(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            conductor, 'machine_lock_dir', return_value=Path(temporary)
        ):
            env = {'REPOPROMPT_DEV_HEAVY_SLOTS': '4'}
            metadata = lambda slots: {
                'operation': 'test', 'requiredSlots': slots,
                'reservationBytes': slots * conductor.HEAVY_RSS_UNIT_BYTES,
            }
            first = conductor.FairHeavyAdmission(metadata(1), env, identity_provider=lambda _pid: 'self')
            second = conductor.FairHeavyAdmission(metadata(1), env, identity_provider=lambda _pid: 'self')
            app = conductor.FairHeavyAdmission(metadata(4), env, identity_provider=lambda _pid: 'self')
            first_lease = second_lease = app_lease = None
            try:
                first_lease = first.wait()
                second_lease = second.wait()
                self.assertNotEqual(first_lease.lock_path, second_lease.lock_path)
                observed_wait = threading.Event()
                app_acquired = threading.Event()
                cancel = threading.Event()
                result = []
                def wait_for_app() -> None:
                    lease = app.wait(cancel_check=cancel.is_set,
                                     update=lambda _position, _earlier: observed_wait.set())
                    result.append(lease)
                    app_acquired.set()
                thread = threading.Thread(target=wait_for_app, daemon=True)
                thread.start()
                self.assertTrue(observed_wait.wait(2.0))
                snapshot = json.loads((Path(temporary) / 'global-heavy-queue.json').read_text())
                self.assertEqual([row['state'] for row in snapshot['waiters']], ['acquired', 'acquired', 'waiting'])
                self.assertFalse(app_acquired.is_set())
                first_lease.release()
                first_lease = None
                second_lease.release()
                second_lease = None
                self.assertTrue(app_acquired.wait(2.0))
                app_lease = result[0]
                self.assertIsNotNone(app_lease)
                self.assertEqual(len(app_lease.extra_locks), 3)
                thread.join(2.0)
            finally:
                if 'cancel' in locals():
                    cancel.set()
                for lease in (first_lease, second_lease, app_lease):
                    if lease is not None:
                        lease.release()
                app.abandon()
                first.abandon()
                second.abandon()


if __name__ == '__main__':
    unittest.main()
