"""Full typed guest/account saga, successor recovery and cleanup composition."""
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
from build_target_fixtures import build
from import_capacity_reference import combined_graph
from import_client_reference import FullGraphAccountImport, FullGraphGuestImport
from import_proof_authority import ImportProofAuthority
from import_range_reference import binding_from_begin
from import_successor_reference import ImportSuccessorServer
from sqlite_reference import connect

A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
S = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
W = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
NOW_TEXT = "2026-09-06T07:00:00Z"
CRASH_POINTS = []


class FullImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="excellent-calendar-full-import-proof-")
        cls.binary = Path(cls.compiled.name) / "proof.exe"
        subprocess.run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", str(ROOT / "contracts/spikes/sync_v1/proof_capsule_probe.cpp"),
            "-o", str(cls.binary), "-lbcrypt"], check=True, capture_output=True, timeout=90)
        cls.authority = ImportProofAuthority(cls.binary)

    @classmethod
    def tearDownClass(cls):
        cls.authority.close()
        cls.compiled.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-full-import-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.records = combined_graph(12)
        self.guest = FullGraphGuestImport(self.path / "guest.db", workspace_id=S)
        self.guest.seed(self.records)
        self.account = FullGraphAccountImport(self.path / "account.db", account_id=A, device_id=D, installation_key=bytes(range(32)))
        self.server = ImportSuccessorServer(self.path / "server.db", account_id=A, authority=self.authority, clock=lambda: NOW_TEXT, staging_ttl_seconds=60)
        self.server.register(D)
        self.bootstrap(self.account, A)

    def bootstrap(self, account, principal):
        server = BootstrapServer(self.path / (str(uuid.uuid4()) + ".db"), account_id=principal, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        server.seed([], highest=0, confirmed=0, upper_bound=0)
        page = server.begin(now=NOW)
        account.begin(page)
        account.stage(page, request_cursor=None)
        account.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])

    def freeze(self):
        before = self.account.snapshot()
        preview = self.guest.preview(self.account, target_workspace_id=W)
        self.assertEqual(self.account.snapshot(), before, "preview cannot create account staging, assignments or Outbox")
        receipt = self.guest.commit(self.account, preview["preview_token"])
        self.assertEqual(receipt, self.guest.commit(self.account, preview["preview_token"]))
        return receipt

    def status(self, receipt):
        response = self.server.status({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            "import_batch_id": receipt["batch_id"]})
        self.account.accept_server_status(receipt["operation_id"], response)
        return response

    def publish(self, receipt):
        mutations = self.account.prepare_import(self.guest, receipt["operation_id"])
        state = json.loads(self.account.snapshot()["state"][0][0])
        results = self.server.exchange(D, 0, mutations, confirmed=state["server_ack"])
        self.assertEqual(results[-1]["status"], "accepted", results[-1])
        self.account.acknowledge_import(receipt["operation_id"], results)
        self.status(receipt)
        return results

    def apply(self, receipt):
        with self.server.connect() as db:
            lines = [json.loads(raw) for raw, in db.execute("SELECT payload FROM import_publication_lines ORDER BY sequence")]
            header = next(row for row in lines if row.get("import_batch_id") == receipt["batch_id"])
            lines = [row for row in lines if row["import_publish_group_id"] == header["import_publish_group_id"]]
        state = json.loads(self.account.snapshot()["state"][0][0])
        response = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
            "changes": lines, "account_generation": 0, "snapshot_upper_bound": header["commit_server_sequence"],
            "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes * 2).decode().rstrip("="), "has_more": False,
            "accepted_client_sequence_through": state["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
        self.account.apply_download(response, request_id=self.account.prepare_download())

    def ready(self):
        receipt = self.freeze()
        self.publish(receipt)
        self.apply(receipt)
        return receipt

    def complete(self, receipt):
        retired = self.guest.retire(self.account, receipt["operation_id"], now=NOW_TEXT)
        self.account.observe_retirement(self.guest, retired, operation=receipt["operation_id"])
        response = self.server.cleanup_confirm(self.account.cleanup_request(receipt["operation_id"]))
        completed = self.account.accept_cleanup(retired, response)
        self.guest.release_completed(self.account, completed)
        return retired

    def test_all_ten_targets_use_real_dual_store_freeze_apply_and_cleanup(self):
        initial = self.freeze()
        self.assertEqual(len(initial["manifest"]["target_counts"]), 10)
        self.assertFalse(self.account.snapshot()["live"])
        self.publish(initial)
        self.assertFalse(self.account.snapshot()["live"])
        with self.assertRaisesRegex(ValueError, "IMPORT_PUBLISH_INCOMPLETE"):
            self.guest.retire(self.account, initial["operation_id"], now=NOW_TEXT)
        self.apply(initial)
        self.complete(initial)
        self.assertFalse(self.guest.snapshot()["guest_import_source_facts"])
        self.assertFalse(self.guest.snapshot()["guest_import_source_leases"])
        self.assertEqual(self.account.receipt(initial["operation_id"])["stage"], "completed")

    def test_changed_private_assignment_is_rejected_before_any_account_write(self):
        preview = self.guest.preview(self.account, target_workspace_id=W)
        before = self.account.snapshot()
        with connect(self.guest.path) as db:
            value = json.loads(db.execute("SELECT payload FROM guest_import_previews WHERE token=?", (preview["preview_token"],)).fetchone()[0])
            value["prepared"]["mappings"][0][3] = str(uuid.uuid4())
            db.execute("UPDATE guest_import_previews SET payload=? WHERE token=?", (json.dumps(value), preview["preview_token"]))
        with self.assertRaisesRegex(ValueError, "IMPORT_LINEAGE_MISMATCH"):
            self.guest.commit(self.account, preview["preview_token"])
        self.assertEqual(self.account.snapshot(), before)
        self.assertEqual(self.guest.recover_reserved(self.account), "released_never_active")

    def test_capacity_range_close_can_repair_on_same_generation_after_ack_only(self):
        initial = self.freeze()
        messages = self.account.prepare_import(self.guest, initial["operation_id"])
        self.account.acknowledge_import(initial["operation_id"], self.server.exchange(D, 0, messages[:2]))
        proof = self.server.close_request({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            **binding_from_begin(messages[0]["mutation"], D), "expected_import_revision": 1,
            "predecessor_batch_id": None, "reason": "capacity_rejected"})["proof"]
        self.account.accept_range_close(initial["operation_id"], proof, authority=self.authority)
        self.status(initial)
        with self.assertRaisesRegex(ValueError, "SYNC_ACK_WATERMARK_INVALID"):
            self.guest.preview(self.account, target_workspace_id=W)
        identifier, request = self.account.prepare_ack_only()
        self.account.accept_ack_only(identifier, self.server.ack_only(request))
        repaired = self.freeze()
        begin = self.account.prepare_import(self.guest, repaired["operation_id"])[0]["mutation"]
        self.assertIsNone(begin["payload"]["takeover_reason"])
        self.assertIsNone(begin["payload"]["range_close_proof_id"])
        self.assertEqual(repaired["begin_client_sequence"], initial["terminal_client_sequence"] + 1)
        self.publish(repaired)
        self.apply(repaired)
        self.complete(repaired)

    def test_published_epoch_cannot_be_released_by_abandoning_its_successor(self):
        first = self.ready()
        self.guest.write(copy.deepcopy(build()["samples"]["category"]))
        successor = self.freeze()
        messages = self.account.prepare_import(self.guest, successor["operation_id"])
        self.account.acknowledge_import(successor["operation_id"], self.server.exchange(D, 0, messages[:1]))
        current = self.status(successor)
        request = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            **binding_from_begin(messages[0]["mutation"], D), "expected_import_revision": current["import_revision"],
            "predecessor_batch_id": first["batch_id"], "reason": "user_cancelled"}
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_SOURCE_OWNED"):
            self.server.close_request(request)
        with self.assertRaisesRegex(ValueError, "IMPORT_LINEAGE_MISMATCH"):
            self.server.close_request({**request, "predecessor_batch_id": None})
        self.assertEqual(self.server.snapshot(), before)
        abandoned = self.server.close_request({**request, "reason": "privacy_destroy"})
        self.assertTrue(abandoned["proof"]["lineage_ever_published"])
        terminal = self.account.accept_range_close(successor["operation_id"], abandoned["proof"], authority=self.authority)
        self.assertEqual(self.status(successor)["stage"], "superseded")
        with connect(self.guest.path) as db:
            lease = self.guest._lease(db)
        release = {"source_workspace_id": S, "source_epoch": 0, "import_lineage_id": successor["import_lineage_id"],
            "protected_owner_binding_digest": self.account.owner_binding, "expected_source_lease_revision": lease["lease_revision"],
            "proof": {"kind": "prepublish_abandon_range_terminal", "server_abandon": abandoned,
                      "terminal_local_range_receipt_hash": terminal["terminal_local_range_receipt_hash"]}}
        before = self.guest.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_SOURCE_OWNED"):
            self.guest.release_abandoned(release, self.account, authority=self.authority)
        self.assertEqual(self.guest.snapshot(), before)

    def test_source_changed_successor_deletes_historical_graph_and_new_epoch_is_isolated(self):
        initial = self.ready()
        old_live = self.account.snapshot()["live"]
        added = copy.deepcopy(build()["samples"]["category"])
        self.guest.write(added)
        with connect(self.guest.path) as db:
            db.execute("DELETE FROM guest_import_source_facts WHERE target IN('event','event_recurrence','event_occurrence_state') OR "
                       "(target='reminder_intent' AND json_extract(payload,'$.fact.owner_type')='event')")
            self.guest._source(db)
        before = self.guest.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            self.guest.retire(self.account, initial["operation_id"], now=NOW_TEXT)
        self.assertEqual(self.guest.snapshot(), before)
        successor = self.freeze()
        self.assertEqual(successor["import_lineage_id"], initial["import_lineage_id"])
        self.assertNotEqual(successor["batch_id"], initial["batch_id"])
        mutations = self.account.prepare_import(self.guest, successor["operation_id"])
        self.assertEqual(sum(row["mutation"]["operation_type"] == "import_delete" for row in mutations), 4)
        self.assertEqual(self.account.snapshot()["live"], old_live)
        self.publish(successor)
        with self.assertRaisesRegex(ValueError, "IMPORT_PUBLISH_INCOMPLETE|IMPORT_SOURCE_OWNED"):
            self.guest.retire(self.account, initial["operation_id"], now=NOW_TEXT)
        self.apply(successor)
        self.complete(successor)
        self.guest.write(added)
        next_epoch = self.freeze()
        self.assertEqual(next_epoch["source_epoch"], 1)
        self.assertNotEqual(next_epoch["import_lineage_id"], initial["import_lineage_id"])
        next_messages = self.account.prepare_import(self.guest, next_epoch["operation_id"])
        self.assertFalse(any(row["mutation"]["operation_type"] == "import_delete" for row in next_messages))
        self.assertNotEqual(next_messages[1]["mutation"]["target_id"], added["target_id"])

    def test_another_account_cannot_replace_active_source_lease_or_write_staging(self):
        initial = self.ready()
        other = FullGraphAccountImport(self.path / "other.db", account_id=B, device_id=D, installation_key=bytes(range(32)))
        self.bootstrap(other, B)
        before = other.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_SOURCE_OWNED"):
            self.guest.preview(other, target_workspace_id=W)
        self.assertEqual(other.snapshot(), before)
        self.assertEqual(self.account.receipt(initial["operation_id"])["stage"], "publish_applied")

    def test_ttl_close_requires_real_proof_and_ack_before_successor_outbox(self):
        initial = self.freeze()
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        results = self.server.exchange(D, 0, mutations[:2])
        self.account.acknowledge_import(initial["operation_id"], results)
        proof = self.server.reclaim_expired_payload(initial["batch_id"], now="2026-09-06T07:02:00Z")
        self.account.accept_range_close(initial["operation_id"], proof, authority=self.authority)
        self.status(initial)
        before = self.account.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_ACK_WATERMARK_INVALID"):
            self.guest.preview(self.account, target_workspace_id=W)
        self.assertEqual(self.account.snapshot(), before)
        identifier, request = self.account.prepare_ack_only()
        response = self.server.ack_only(request)
        self.account.accept_ack_only(identifier, response)
        successor = self.freeze()
        messages = self.account.prepare_import(self.guest, successor["operation_id"])
        self.assertEqual(messages[0]["mutation"]["payload"]["range_close_proof_id"], proof["proof_id"])
        self.assertEqual(messages[0]["mutation"]["client_sequence"], initial["terminal_client_sequence"] + 1)
        self.publish(successor)
        self.apply(successor)
        self.complete(successor)

    def test_account_changed_since_preview_preserves_previous_lease_and_has_zero_new_outbox(self):
        initial = self.ready()
        self.guest.write(copy.deepcopy(build()["samples"]["category"]))
        preview = self.guest.preview(self.account, target_workspace_id=W)
        identifier, request = self.account.prepare_ack_only()
        self.account.accept_ack_only(identifier, self.server.ack_only(request))
        before = self.account.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_VERSION_CONFLICT"):
            self.guest.commit(self.account, preview["preview_token"])
        self.assertEqual(self.account.snapshot(), before)
        self.assertEqual(self.guest.recover_reserved(self.account), "restored_previous_active")
        with connect(self.guest.path) as db:
            lease = self.guest._lease(db)
        self.assertEqual(lease["active_batch_id"], initial["batch_id"])
        self.assertEqual(lease["state"], "active")

    def test_every_successor_dual_store_process_death_restores_or_completes_exact_receipt(self):
        initial = self.ready()
        self.guest.write(copy.deepcopy(build()["samples"]["category"]))
        preview = self.guest.preview(self.account, target_workspace_id=W)
        original = (self.guest, self.account, self.server)
        points = ["import_guest_reserved", "import_guest_reserved_committed", "import_client_mapping", "import_account_outbox",
                  "import_account_operation_receipt", "import_account_allocator", "import_account_receipt_committed", "import_guest_active"]
        for point in points:
            directory = self.path / point
            directory.mkdir()
            for name, owner in zip(("guest", "account", "server"), original):
                with connect(owner.path) as source, connect(directory / (name + ".db")) as target:
                    source.backup(target)
            request = {"directory": str(directory), "source": S, "account": A, "device": D,
                       "token": preview["preview_token"], "point": point}
            path = directory / "request.json"
            path.write_text(json.dumps(request), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/full_import_crash_probe.py"), str(path)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            self.guest = FullGraphGuestImport(directory / "guest.db", workspace_id=S)
            self.account = FullGraphAccountImport(directory / "account.db", account_id=A, device_id=D, installation_key=bytes(range(32)))
            self.server = ImportSuccessorServer(directory / "server.db", account_id=A, authority=self.authority, clock=lambda: NOW_TEXT, staging_ttl_seconds=60)
            with connect(self.guest.path) as db:
                lease = self.guest._lease(db)
            if point == "import_guest_reserved":
                self.assertEqual(lease["active_batch_id"], initial["batch_id"])
                receipt = self.guest.commit(self.account, preview["preview_token"])
            else:
                recovered = self.guest.recover_reserved(self.account)
                if recovered == "restored_previous_active":
                    self.assertFalse(self.account.snapshot()["local_import_outbox"])
                    receipt = self.freeze()
                else:
                    self.assertEqual(recovered, "active")
                    receipt = self.guest.commit(self.account, preview["preview_token"])
                    self.assertEqual(receipt["batch_id"], preview["proposed_import_batch_id"])
            self.publish(receipt)
            self.apply(receipt)
            self.complete(receipt)
            self.assertFalse(self.guest.snapshot()["guest_import_source_lease_replacements"])
            CRASH_POINTS.append(point)
        self.guest, self.account, self.server = original


if __name__ == "__main__":
    unittest.main()
