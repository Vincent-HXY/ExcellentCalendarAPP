"""Durable toggles and GC compose with real frozen intents and page application."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

import test_sync_local_intents as helpers
import test_sync_local_download as downloads
from test_sync_local_download import group, revised
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, after_image
from counter_reference import MAXIMUM
from import_cleanup_reference import ImportCleanupServer
from policy_maintenance_reference import PolicyMaintenanceStore
from protocol_reference import ProtocolStore, mutation_hash
from sqlite_reference import connect

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
CRASH_POINTS = []


class PolicyMaintenanceTests(unittest.TestCase):
    bootstrap = helpers.LocalIntentTests.bootstrap
    state = helpers.LocalIntentTests.state
    response = downloads.LocalDownloadTests.response

    def setUp(self):
        helpers.LocalIntentTests.setUp(self)
        self.local = PolicyMaintenanceStore(self.local.path, workspace_id=A, runtime_id=RUNTIME, device_id=D)

    def request(self, enabled, *, revision=None, operation=None):
        return {"workspace_id": A, "runtime_instance_id": self.local.runtime_id, "device_id": D,
            "operation_id": operation or str(uuid.uuid4()), "enabled": enabled,
            "expected_sync_policy_revision": self.local.snapshot()["policy_state"][0][2] if revision is None else revision}

    def toggle(self, enabled):
        return self.local.set_enabled(self.request(enabled))

    def apply(self, response, *, reenable=False, **kwargs):
        identifier = self.local.prepare_download(run_intent="reenable_pull_only" if reenable else "normal")
        self.local.apply_download(response, request_id=identifier, **kwargs)
        return identifier

    def test_latest_receipt_replays_after_runtime_restart_and_stale_operations_do_not_toggle(self):
        first = self.request(False)
        receipt = self.local.set_enabled(first)
        self.local = PolicyMaintenanceStore(self.local.path, workspace_id=A, runtime_id=str(uuid.uuid4()), device_id=D)
        first["runtime_instance_id"] = self.local.runtime_id
        self.assertEqual(self.local.set_enabled(first), receipt)
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_POLICY_VERSION_CONFLICT"):
            self.local.set_enabled({**first, "enabled": True})
        self.assertEqual(self.local.snapshot(), before)
        self.toggle(True)
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_POLICY_VERSION_CONFLICT"):
            self.local.set_enabled(first)
        self.assertEqual(self.local.snapshot(), before)
        self.assertEqual(len(before["sync_policy_operation_receipts"]), 1)

    def test_concurrent_last_revision_commits_once_and_preserves_frozen_outbox(self):
        self.local.enqueue(helpers.mutation(self.category, patch={"description": "offline draft"}))
        pending = self.local.snapshot()["pending"]
        with connect(self.local.path) as db:
            db.execute("UPDATE policy_state SET revision=?", (MAXIMUM - 1,))
        requests = [self.request(False, revision=MAXIMUM - 1) for _ in range(2)]

        def write(request):
            try:
                return self.local.set_enabled(request)
            except ValueError as error:
                return str(error)

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(write, requests))
        self.assertEqual(sum(isinstance(row, dict) for row in outcomes), 1)
        self.assertIn("SYNC_POLICY_VERSION_CONFLICT", outcomes)
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_POLICY_REVISION_EXHAUSTED"):
            self.toggle(True)
        self.assertEqual(self.local.snapshot(), before)
        self.assertEqual(before["pending"], pending)

    def test_reenable_requires_complete_current_policy_pull_and_preserves_pending_hash(self):
        self.local.enqueue(helpers.mutation(self.category, patch={"name": "pending local"}))
        pending = self.local.snapshot()["pending"]
        old_request = self.local.prepare_download()
        self.toggle(False)
        with self.assertRaisesRegex(ValueError, "SYNC_OPERATION_INVALID"):
            self.local.prepare(1)
        self.toggle(True)
        self.local.apply_download(self.response(group(revised(self.category, description="remote")), upper=2, more=True), request_id=old_request)
        self.assertTrue(self.local.snapshot()["policy_state"][0][3])
        self.apply(self.response(upper=2), reenable=True)
        self.assertFalse(self.local.snapshot()["policy_state"][0][3])
        self.assertEqual(self.local.snapshot()["pending"], pending)
        self.assertIsInstance(self.local.prepare(1), str)

    def test_bootstrap_finalize_releases_gate_only_for_policy_bound_snapshot(self):
        self.toggle(False)
        self.toggle(True)
        server = BootstrapServer(self.directory / "new-snapshot.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        server.seed([after_image(self.category)], highest=0, confirmed=0, upper_bound=0)
        page = server.begin(now=NOW)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            self.local.finalize(expected_page_set_digest="0" * 64, final_cursor=page["terminal_sync_cursor"])
        self.assertEqual(self.local.snapshot(), before)
        self.local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        self.assertFalse(self.local.snapshot()["policy_state"][0][3])

    def actual_effect(self):
        backend = ProtocolStore(self.directory / "effect-server.db")
        backend.register(D)
        backend.seed(self.category)
        mutation = helpers.mutation(self.category, patch={"description": "accepted"})
        self.local.enqueue(mutation)
        request_id = self.local.prepare(1)
        result = backend.exchange(D, 0, [{"mutation": mutation, "payload_hash": mutation_hash(mutation)}])[0]
        self.local.acknowledge(result, request_id=request_id)
        effect = result["effect"]
        page = self.response(group(revised(self.category, description="accepted"), identifier=effect["effect_change_group_id"],
            sequence=effect["effect_group_last_server_sequence"]))
        page["retention_floor_server_sequence"] = effect["effect_group_last_server_sequence"]
        self.apply(page)
        return backend

    def test_paused_ack_flush_unpins_only_confirmed_receipts_and_gc_keeps_cursor(self):
        backend = self.actual_effect()
        self.assertEqual(self.local.maintenance()["change_receipts_deleted"], 0)
        self.toggle(False)
        identifier, request = self.local.prepare_ack_only()
        self.local.accept_ack_only(identifier, ImportCleanupServer.ack_only(backend, request))
        before = self.local.snapshot()
        result = self.local.maintenance(max_items=1)
        self.assertEqual((result["change_receipts_deleted"], result["has_more"]), (1, False))
        after = self.local.snapshot()
        for table in ("state", "live", "pending", "frozen_intents", "policy_state", "sync_policy_operation_receipts"):
            self.assertEqual(after[table], before[table])
        self.local = PolicyMaintenanceStore(self.local.path, workspace_id=A, runtime_id=RUNTIME, device_id=D)
        self.assertEqual(self.local.maintenance()["change_receipts_deleted"], 0)

    def test_resolved_payload_gc_uses_server_cutoff_and_bounded_transactions(self):
        deltas = [{"kind": "resolved", "conflict_id": str(uuid.uuid4()), "conflict_version": 2,
            "resolved_at": "2026-09-04T00:00:00Z" if index < 3 else "2026-09-05T02:00:00Z",
            "resolution_mode": "keep_remote", "resulting_entity_version": 1,
            "resolution_receipt": helpers.terminal(helpers.mutation(self.category, patch={"description": "resolved"}))["receipt"]} for index in range(4)]
        self.apply(self.response(group(sequence=1, deltas=deltas)))
        before = self.local.snapshot()
        for expected_more in (True, True, False):
            result = self.local.maintenance(max_items=1)
            self.assertEqual((result["resolved_conflicts_deleted"], result["change_receipts_deleted"], result["has_more"]),
                (1, 0, expected_more))
        after = self.local.snapshot()
        self.assertEqual([row[0] for row in after["conflict_history"]], [deltas[-1]["conflict_id"]])
        for table in ("state", "live", "pending", "policy_state", "applied_groups"):
            self.assertEqual(after[table], before[table])
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            self.local.maintenance(max_items=501)
        self.assertEqual(self.local.snapshot(), after)

    def test_cleanup_cutoff_is_durable_and_not_reconstructed_from_transient_state(self):
        response = self.response(upper=0)
        self.apply(response)
        expected = response["resolved_conflict_cleanup_before"]
        with connect(self.local.path) as db:
            row = db.execute("SELECT resolved_conflict_cleanup_before FROM sync_state").fetchone()
            self.assertEqual(row, (expected,))
            state = self.state()
            state["cleanup"] = 4102444800  # A transient 2100 cutoff must not authorize deletion.
            db.execute("UPDATE state SET payload=?", (json.dumps(state),))
        self.local = PolicyMaintenanceStore(self.local.path, workspace_id=A, runtime_id=RUNTIME, device_id=D)
        self.assertEqual(self.local.maintenance()["resolved_conflict_cleanup_before"], expected)
        with connect(self.local.path) as db:
            db.execute("UPDATE sync_state SET resolved_conflict_cleanup_before=NULL")
        self.local = PolicyMaintenanceStore(self.local.path, workspace_id=A, runtime_id=RUNTIME, device_id=D)
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            self.local.maintenance()
        self.assertEqual(self.local.snapshot(), before)

    def kill_then_retry(self, method, arguments, points):
        for point in points:
            before = self.local.snapshot()
            path = self.directory / (point + ".json")
            path.write_text(json.dumps({"path": str(self.local.path), "workspace_id": A, "runtime_id": RUNTIME, "device_id": D,
                "method": method, "arguments": arguments, "point": point}), encoding="utf8")
            result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/policy_crash_probe.py"), str(path)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 81, result.stdout + result.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, result.stdout)
            self.assertEqual(self.local.snapshot(), before)
            CRASH_POINTS.append(point)
        return getattr(self.local, method)(**arguments)

    def test_actual_process_death_rolls_back_policy_receipt_pull_gate_and_maintenance(self):
        request = self.request(False)
        self.kill_then_retry("set_enabled", {"request": request}, ["policy_state_and_pull_gate", "policy_latest_receipt"])
        self.toggle(True)
        response = self.response(upper=0)
        request_id = self.local.prepare_download(run_intent="reenable_pull_only")
        self.kill_then_retry("apply_download", {"response": response, "request_id": request_id}, ["policy_terminal_pull_gate"])
        backend = self.actual_effect()
        identifier, request = self.local.prepare_ack_only()
        self.local.accept_ack_only(identifier, ImportCleanupServer.ack_only(backend, request))
        self.kill_then_retry("maintenance", {"max_items": 1}, ["maintenance_bounded_deletes"])


if __name__ == "__main__":
    unittest.main()
