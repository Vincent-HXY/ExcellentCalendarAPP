"""Actual receipt/apply/cleanup chain, epoch gates and process-death recovery."""
import base64
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import KEY, KEY_ID, NOW
from build_owned_graph_fixtures import derive
from counter_reference import MAXIMUM
from import_cleanup_reference import AccountImportCleanup, GuestImportCleanup, ImportCleanupServer
from import_proof_authority import ImportProofAuthority
from import_range_reference import binding_from_begin
from sqlite_reference import connect

A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
S = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
W = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
NOW_TEXT = "2026-09-06T07:00:00Z"
CRASH_POINTS = []


class ImportCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-cleanup-proof-")
        cls.binary = Path(cls.compiled.name) / "proof.exe"
        subprocess.run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", str(ROOT / "contracts/spikes/sync_v1/proof_capsule_probe.cpp"),
            "-o", str(cls.binary), "-lbcrypt"], check=True, capture_output=True, timeout=90)
        cls.authority = ImportProofAuthority(cls.binary)

    @classmethod
    def tearDownClass(cls):
        cls.authority.close()
        cls.compiled.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-cleanup-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.records = derive()["cases"][2]["input"]["seed"]
        self.guest = GuestImportCleanup(self.path / "guest.db", workspace_id=S)
        self.guest.seed(self.records)
        self.account = AccountImportCleanup(self.path / "account.db", account_id=A, device_id=D, installation_key=bytes(range(32)))
        self.server = ImportCleanupServer(self.path / "server.db", account_id=A, authority=self.authority, clock=lambda: NOW_TEXT)
        self.server.register(D)
        bootstrap = BootstrapServer(self.path / "bootstrap.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        bootstrap.seed([], highest=0, confirmed=0, upper_bound=0)
        page = bootstrap.begin(now=NOW)
        self.account.begin(page)
        self.account.stage(page, request_cursor=None)
        self.account.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        root = next(row for row in self.records if row["target_type"] == "event")
        with connect(self.guest.path) as db:
            db.executemany("INSERT INTO guest_execution_reminders VALUES(?,'event',?,?,NULL)",
                [("open-reminder", root["target_id"], "open"), ("old-reminder", root["target_id"], "delivered")])
            db.executemany("INSERT INTO guest_execution_notifications VALUES(?,?,?,NULL)",
                [("prepared-attempt", "open-reminder", "prepared"), ("past-attempt", "old-reminder", "delivered")])
            db.execute("INSERT INTO guest_search_history VALUES(0,'guest only keyword')")

    def freeze(self, epoch=0):
        if epoch:
            with connect(self.guest.path) as db:
                db.execute("UPDATE workspace_metadata SET current_import_source_epoch=?", (epoch,))
        preview = self.guest.preview(self.account, target_workspace_id=W)
        self.receipt = self.guest.commit(self.account, preview["preview_token"])
        self.operation, self.batch = self.receipt["operation_id"], self.receipt["batch_id"]
        self.mutations = self.account.prepare_import(self.guest, self.operation)

    def publish(self, *, acknowledge=True):
        self.results = self.server.exchange(D, 0, self.mutations)
        self.assertEqual(self.results[-1]["status"], "accepted")
        if acknowledge:
            self.account.acknowledge_import(self.operation, self.results)
        self.lines = [json.loads(row[2]) for row in self.server.snapshot()["import_publication_lines"]]

    def apply(self):
        response = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
            "changes": self.lines, "account_generation": 0, "snapshot_upper_bound": self.lines[-1]["server_sequence"],
            "next_cursor": base64.urlsafe_b64encode(b"isolated-cleanup-cursor-" + uuid.uuid4().bytes).decode().rstrip("="), "has_more": False,
            "accepted_client_sequence_through": self.state()["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
        self.account.apply_download(response, request_id=self.account.prepare_download())

    def state(self):
        return json.loads(self.account.snapshot()["state"][0][0])

    def ready(self, epoch=0):
        self.freeze(epoch)
        self.publish()
        self.apply()

    def retire(self):
        receipt = self.guest.retire(self.account, self.operation, now=NOW_TEXT)
        self.account.observe_retirement(self.guest, receipt, operation=self.operation)
        return receipt

    def complete(self, receipt):
        response = self.server.cleanup_confirm(self.account.cleanup_request(self.operation))
        completed = self.account.accept_cleanup(receipt, response)
        self.guest.release_completed(self.account, completed)
        return response, completed

    def test_real_ack_apply_retire_confirm_and_late_notification_keep_exact_boundaries(self):
        self.freeze()
        self.publish()
        self.assertEqual(self.account.receipt(self.operation)["stage"], "server_confirmed")
        self.assertEqual(self.state()["local_ack"], 4)
        self.assertFalse(self.account.snapshot()["live"])
        self.assertFalse(self.account.snapshot()["failed"])
        self.assertFalse(self.account.snapshot()["local_anchors"])
        with self.assertRaisesRegex(ValueError, "IMPORT_PUBLISH_INCOMPLETE"):
            self.guest.retire(self.account, self.operation, now=NOW_TEXT)
        self.apply()
        self.assertEqual(self.state()["local_ack"], 5)
        self.assertFalse(self.account.snapshot()["local_import_effect_gates"])
        self.assertFalse(self.account.reminder_materialization_allowed(self.batch))
        receipt = self.retire()
        self.assertTrue(self.account.reminder_materialization_allowed(self.batch))
        self.assertEqual(len(self.guest.snapshot()["guest_import_audit_anchors"]), 2)
        reminders = {row[0]: row for row in self.guest.snapshot()["guest_execution_reminders"]}
        self.assertEqual(reminders["open-reminder"][-2:], ("cancelled", "source_migrated"))
        self.assertEqual(reminders["old-reminder"][-2:], ("delivered", None))
        before = self.guest.snapshot()
        self.assertEqual(self.guest.finalize_notification("prepared-attempt"), "no_effect")
        self.assertEqual(self.guest.snapshot(), before)
        self.assertEqual(self.guest.snapshot()["guest_search_history"], [(0, "guest only keyword")])
        self.assertEqual(self.guest.preview(self.account, target_workspace_id=W)["disposition"], "previous_epoch_cleanup_pending")
        request = self.account.cleanup_request(self.operation)
        response, completed = self.complete(receipt)
        self.assertEqual(self.server.cleanup_confirm(request), {**response, "disposition": "already_cleanup_confirmed"})
        before = self.guest.snapshot()
        self.assertEqual(self.guest.release_completed(self.account, completed)["disposition"], "released")
        self.assertEqual(self.guest.snapshot(), before)
        ack_id, ack = self.account.prepare_ack_only()
        response = self.server.ack_only(ack)
        self.account.accept_ack_only(ack_id, response)
        self.assertEqual((self.state()["local_ack"], self.state()["server_ack"]), (5, 5))
        self.assertIsNone(self.account.prepare_ack_only())

    def test_lost_commit_ack_can_arrive_after_download_without_regressing_visibility(self):
        self.freeze()
        self.publish(acknowledge=False)
        self.apply()
        self.assertEqual(self.account.receipt(self.operation)["stage"], "publish_applied")
        self.assertEqual(self.state()["local_ack"], 0)
        duplicate = self.server.exchange(D, 0, self.mutations)
        self.assertTrue(all(row["status"] == "duplicate" for row in duplicate))
        self.account.acknowledge_import(self.operation, duplicate)
        self.assertEqual(self.account.receipt(self.operation)["stage"], "publish_applied")
        self.assertEqual(self.state()["local_ack"], 5)
        self.assertFalse(self.account.snapshot()["local_import_effect_gates"])
        self.complete(self.retire())

    def test_source_change_rejects_entire_retirement(self):
        self.ready()
        self.guest.write(copy.deepcopy(self.records[0]))
        before = self.guest.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            self.guest.retire(self.account, self.operation, now=NOW_TEXT)
        self.assertEqual(self.guest.snapshot(), before)
    def test_old_receipt_never_retires_new_epoch(self):
        self.ready()
        receipt = self.retire()
        # A complete new guest graph may be written locally during pending cleanup.
        with connect(self.guest.path) as db:
            db.executemany("INSERT INTO guest_import_source_facts VALUES(?,?,?,1)",
                ((row["target_type"], row["target_id"], json.dumps(row)) for row in self.records))
        live = self.guest.snapshot()["guest_import_source_facts"]
        self.assertEqual(self.guest.retire(self.account, self.operation, now=NOW_TEXT), receipt)
        self.complete(receipt)
        self.assertEqual(self.guest.snapshot()["guest_import_source_facts"], live)
        preview = self.guest.preview(self.account, target_workspace_id=W)
        self.assertEqual(preview["source_epoch"], 1)
        self.assertNotEqual(preview["import_lineage_id"], receipt["import_lineage_id"])

    def test_max_epoch_still_retires_confirms_and_releases_then_rejects_new_import(self):
        self.ready(MAXIMUM)
        receipt = self.retire()
        self.complete(receipt)
        before = self.guest.snapshot()
        self.assertEqual(before["workspace_metadata"][0][-4:], (MAXIMUM, None, 1, 0))
        with self.assertRaisesRegex(ValueError, "IMPORT_SOURCE_EPOCH_EXHAUSTED"):
            self.guest.preview(self.account, target_workspace_id=W)
        self.assertEqual(self.guest.snapshot(), before)

    def release_request(self, proof):
        lease = self.guest.snapshot()["guest_import_source_leases"][0]
        return {"source_workspace_id": S, "source_epoch": self.receipt["source_epoch"], "import_lineage_id": self.receipt["import_lineage_id"],
            "protected_owner_binding_digest": self.account.owner_binding, "expected_source_lease_revision": lease[-1], "proof": proof}

    def test_signed_partial_abandon_preserves_actual_receipts_closes_range_and_flushes_ack(self):
        self.freeze()
        result = self.server.exchange(D, 0, self.mutations[:2])
        self.account.acknowledge_import(self.operation, result)
        actual = self.account.snapshot()["terminals"]
        original_guest = self.guest.snapshot()["guest_import_source_facts"]
        response = self.server.close_request({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            **binding_from_begin(self.mutations[0]["mutation"], D), "expected_import_revision": 1,
            "predecessor_batch_id": None, "reason": "privacy_destroy"})
        with connect(self.account.path) as db:
            sequence, original = db.execute("SELECT sequence,mutation FROM local_import_outbox ORDER BY sequence LIMIT 1").fetchone()
            corrupted = json.loads(original)
            corrupted["mutation_id"] = str(uuid.uuid4())
            db.execute("UPDATE local_import_outbox SET mutation=? WHERE sequence=?", (json.dumps(corrupted), sequence))
        before = self.account.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_OUTBOX_CORRUPTED"):
            self.account.accept_range_close(self.operation, response["proof"], authority=self.authority)
        self.assertEqual(self.account.snapshot(), before)
        with connect(self.account.path) as db:
            db.execute("UPDATE local_import_outbox SET mutation=? WHERE sequence=?", (original, sequence))
        terminal = self.account.accept_range_close(self.operation, response["proof"], authority=self.authority)
        self.assertEqual(self.account.snapshot()["terminals"], actual)
        self.assertFalse(self.account.snapshot()["local_import_outbox"])
        self.assertEqual((self.state()["local_ack"], self.state()["next_sequence"]), (5, 6))
        self.assertEqual(self.account.prepare_import(self.guest, self.operation), [])
        request = self.release_request({"kind": "prepublish_abandon_range_terminal", "server_abandon": response,
            "terminal_local_range_receipt_hash": terminal["terminal_local_range_receipt_hash"]})
        bad = copy.deepcopy(request)
        bad["proof"]["terminal_local_range_receipt_hash"] = "0" * 64
        before = self.guest.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            self.guest.release_abandoned(bad, self.account, authority=self.authority)
        self.assertEqual(self.guest.snapshot(), before)
        self.guest.release_abandoned(request, self.account, authority=self.authority)
        self.assertEqual(self.guest.snapshot()["guest_import_source_facts"], original_guest)
        self.assertFalse(self.guest.snapshot()["guest_import_source_leases"])
        identifier, ack = self.account.prepare_ack_only()
        self.account.accept_ack_only(identifier, self.server.ack_only(ack))
        self.assertEqual(self.state()["server_ack"], 5)
        self.assertEqual(len(self.server.snapshot()["receipts"]), 2)

    def test_owner_bound_account_deleted_proof_releases_pending_gate_without_retiring_new_writes(self):
        self.ready()
        receipt = self.retire()
        with connect(self.guest.path) as db:
            db.executemany("INSERT INTO guest_import_source_facts VALUES(?,?,?,1)",
                ((row["target_type"], row["target_id"], json.dumps(row)) for row in self.records))
        live = self.guest.snapshot()["guest_import_source_facts"]
        token, value = self.authority.sign(A, "account_deleted", {"account_id": A, "state": "deleted"})
        request = self.release_request({"kind": "account_deleted", "owner_bound_account_deleted_proof": token, "deletion_receipt_hash": value})
        before = self.guest.snapshot()
        for wrong in (B, A):
            bad = copy.deepcopy(request)
            if wrong == A:
                bad["proof"]["deletion_receipt_hash"] = "0" * 64
            with self.assertRaises(ValueError):
                self.guest.release_account_deleted(bad, expected_account_id=wrong, installation_key=bytes(range(32)), authority=self.authority)
            self.assertEqual(self.guest.snapshot(), before)
        self.guest.release_account_deleted(request, expected_account_id=A, installation_key=bytes(range(32)), authority=self.authority)
        self.assertEqual(self.guest.snapshot()["guest_import_source_facts"], live)
        self.assertFalse(self.guest.snapshot()["guest_import_source_leases"])
        self.assertIsNone(self.guest.snapshot()["workspace_metadata"][0][-3])
        self.assertEqual(self.guest.snapshot()["guest_import_cleanup_receipts"][0][-1], "account_deleted")
        after = self.guest.snapshot()
        self.guest.release_account_deleted(request, expected_account_id=A, installation_key=bytes(range(32)), authority=self.authority)
        self.assertEqual(self.guest.snapshot(), after)

    def test_each_actual_transaction_death_rolls_back_and_replays_without_losing_next_epoch(self):
        self.ready()

        def check_phase(phase, points, arguments):
            for point in points:
                directory = self.path / point
                directory.mkdir()
                for name, owner in (("guest", self.guest), ("account", self.account), ("server", self.server)):
                    with connect(owner.path) as source, connect(directory / (name + ".db")) as target:
                        source.backup(target)
                guest = GuestImportCleanup(directory / "guest.db", workspace_id=S)
                account = AccountImportCleanup(directory / "account.db", account_id=A, device_id=D, installation_key=bytes(range(32)))
                server = ImportCleanupServer(directory / "server.db", account_id=A, authority=self.authority, clock=lambda: NOW_TEXT)
                before = (guest.snapshot(), account.snapshot(), server.snapshot())
                data = {"directory": str(directory), "phase": phase, "point": point, "operation": self.operation, "now": NOW_TEXT,
                    "source": S, "account_id": A, "device": D, "binary": str(self.binary), **arguments}
                path = directory / "request.json"
                path.write_text(json.dumps(data), encoding="utf8")
                process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_cleanup_crash_probe.py"), str(path)],
                    capture_output=True, text=True, timeout=90)
                self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
                self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
                self.assertEqual((guest.snapshot(), account.snapshot(), server.snapshot()), before, point)
                self.assertEqual(guest.snapshot()["guest_search_history"], [(0, "guest only keyword")])
                CRASH_POINTS.append(point)

        check_phase("retire", ["import_guest_execution_retired", "import_guest_facts_retired", "import_guest_retirement_receipt_epoch"], {})
        receipt = self.guest.retire(self.account, self.operation, now=NOW_TEXT)
        check_phase("observe", ["import_account_retirement_observed"], {"receipt": receipt})
        self.account.observe_retirement(self.guest, receipt, operation=self.operation)
        request = self.account.cleanup_request(self.operation)
        check_phase("confirm", ["import_server_cleanup_stage", "import_server_cleanup_receipt"], {"request": request})
        response = self.server.cleanup_confirm(request)
        check_phase("accept", ["import_native_cleanup_completed"], {"receipt": receipt, "response": response})
        completed = self.account.accept_cleanup(receipt, response)
        check_phase("release", ["import_guest_completed_release"], {"completed": completed})
        self.guest.release_completed(self.account, completed)
        identifier, ack = self.account.prepare_ack_only()
        ack_response = self.server.ack_only(ack)
        check_phase("ack", ["import_ack_only_accepted"], {"identifier": identifier, "response": ack_response})
        self.account.accept_ack_only(identifier, ack_response)
        self.assertEqual(self.state()["server_ack"], 5)


if __name__ == "__main__":
    unittest.main()
