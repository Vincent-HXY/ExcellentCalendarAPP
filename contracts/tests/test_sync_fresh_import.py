"""Fresh and other-origin recovery compose fences, bootstrap and source leases."""
import copy
import json
from pathlib import Path
import sys
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
import test_sync_full_import as helpers
from bootstrap_reference import BootstrapServer, page_set_digest, item_key
from build_bootstrap_fixtures import KEY, KEY_ID, NOW
from build_owned_graph_fixtures import make_mutation
from build_target_fixtures import build
from import_fresh_reference import FreshImportAccount
from import_client_reference import FullGraphGuestImport
from import_successor_reference import ImportSuccessorServer
from import_range_reference import binding_from_begin
from sqlite_reference import connect

A, B, S, D, W, NOW_TEXT = helpers.A, helpers.B, helpers.S, helpers.D, helpers.W, helpers.NOW_TEXT
CRASH_POINTS = []


class FreshImportTests(unittest.TestCase):
    setUpClass = classmethod(helpers.FullImportTests.setUpClass.__func__)
    tearDownClass = classmethod(helpers.FullImportTests.tearDownClass.__func__)
    setUp = helpers.FullImportTests.setUp
    bootstrap = helpers.FullImportTests.bootstrap
    freeze = helpers.FullImportTests.freeze
    complete = helpers.FullImportTests.complete
    status = helpers.FullImportTests.status
    publish = helpers.FullImportTests.publish
    apply = helpers.FullImportTests.apply
    ready = helpers.FullImportTests.ready

    def server_status(self, receipt, device, transport):
        return self.server.status({"protocol_version": 1, "device_id": device, "sync_transport_generation": transport,
                                  "import_batch_id": receipt["batch_id"]})

    def fence(self, device=D):
        return self.server.fence_transport({"protocol_version": 1, "device_id": device, "fence_operation_id": str(uuid.uuid4()),
            "expected_sync_transport_generation": 0, "reason": "fresh_recovery"})

    def fresh_bootstrap(self):
        with self.server.connect() as db:
            images = [self.server.image(db, target, identifier) for target, identifier in db.execute("SELECT target,id FROM facts")]
            recovery = self.server._recovery(db, self.account.device_id)
            upper = db.execute("SELECT COALESCE(MAX(sequence),0) FROM import_publication_lines").fetchone()[0]
        server = BootstrapServer(self.path / (str(uuid.uuid4()) + ".db"), account_id=A, device_id=self.account.device_id,
            keys={KEY_ID: KEY}, key_id=KEY_ID)
        server.seed(sorted([*images, *self.server.bootstrap_markers()], key=item_key), highest=recovery["highest_client_sequence"],
            confirmed=recovery["client_confirmed_through"], upper_bound=upper, transport=self.account.transport)
        page = server.begin(now=NOW, download_limit=500)
        self.account.begin(page)
        self.account.stage(page, request_cursor=None)
        self.account.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])

    def ack(self):
        prepared = self.account.prepare_ack_only()
        if prepared is not None:
            identifier, request = prepared
            self.account.accept_ack_only(identifier, self.server.ack_only(request))

    def new_account(self, fence, *, device=D):
        return FreshImportAccount(self.path / (str(uuid.uuid4()) + ".db"), account_id=A, device_id=device,
            transport=fence["recovery"]["sync_transport_generation"], installation_key=bytes(range(32)))

    def publish_repair(self, receipt):
        mutations = self.account.prepare_import(self.guest, receipt["operation_id"])
        state = json.loads(self.account.snapshot()["state"][0][0])
        results = self.server.exchange(self.account.device_id, self.account.transport, mutations, confirmed=state["server_ack"])
        self.assertEqual(results[-1]["status"], "accepted", results[-1])
        self.account.acknowledge_import(receipt["operation_id"], results)
        self.account.accept_server_status(receipt["operation_id"], self.server_status(receipt, self.account.device_id, self.account.transport))
        self.fresh_bootstrap()
        self.complete(receipt)

    def test_lost_commit_ack_recovers_only_from_real_bootstrap_marker_without_fake_terminals(self):
        initial = self.freeze()
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        self.assertEqual(self.server.exchange(D, 0, mutations)[-1]["status"], "accepted")
        fence = self.fence()
        self.account = self.new_account(fence)
        status = self.server_status(initial, D, 1)
        recovered = self.account.recover(self.guest, fence, status, authority=self.authority)
        self.assertEqual(recovered["batch_id"], initial["batch_id"])
        self.assertEqual(recovered, self.account.recover(self.guest, fence, status, authority=self.authority))
        self.assertFalse(self.account.snapshot()["local_import_outbox"])
        self.assertFalse(self.account.snapshot()["terminals"])
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            self.account.finish_recovery()
        self.fresh_bootstrap()
        with self.assertRaisesRegex(ValueError, "SYNC_ACK_WATERMARK_INVALID"):
            self.account.finish_recovery()
        self.ack()
        self.account.finish_recovery()
        self.assertEqual(self.account.status(initial["operation_id"])["origin_sync_transport_generation"], 0)
        self.complete(initial)
        self.assertFalse(self.account.snapshot()["terminals"])
        self.assertEqual(self.account.recover(self.guest, fence, status, authority=self.authority)["stage"], "completed")

    def test_seen_prefix_fresh_recovery_closes_old_range_before_full_successor(self):
        initial = self.freeze()
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        self.server.exchange(D, 0, mutations[:2])
        fence = self.fence()
        binding = binding_from_begin(mutations[0]["mutation"], D)
        request = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 1, **binding,
                   "expected_import_revision": 1, "takeover_reason": "local_evidence_lost"}
        proof = self.server.close_request(request, takeover=True)["proof"]
        self.account = self.new_account(fence)
        status = self.server_status(initial, D, 1)
        self.account.recover(self.guest, fence, status, authority=self.authority, proof=proof)
        self.assertFalse(self.account.snapshot()["terminals"])
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            self.guest.preview(self.account, target_workspace_id=W)
        self.fresh_bootstrap()
        self.ack()
        self.account.finish_recovery()
        repaired = self.freeze()
        self.assertEqual(repaired["begin_client_sequence"], initial["terminal_client_sequence"] + 1)
        self.publish_repair(repaired)
        with self.assertRaisesRegex(ValueError, "TRANSPORT_GENERATION|IMPORT_BATCH_SUPERSEDED"):
            self.server.exchange(D, 0, mutations)

    def test_range_closed_before_destruction_uses_later_fence_recovery_bundle(self):
        initial = self.freeze()
        messages = self.account.prepare_import(self.guest, initial["operation_id"])
        self.server.exchange(D, 0, messages[:1])
        proof = self.server.close_request({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            **binding_from_begin(messages[0]["mutation"], D), "expected_import_revision": 1,
            "predecessor_batch_id": None, "reason": "privacy_destroy"})["proof"]
        fence = self.fence()
        self.assertEqual((proof["recovery"]["sync_transport_generation"], fence["recovery"]["sync_transport_generation"]), (0, 1))
        self.account = self.new_account(fence)
        self.account.recover(self.guest, fence, self.server_status(initial, D, 1), authority=self.authority, proof=proof)
        self.fresh_bootstrap()
        self.ack()
        self.account.finish_recovery()
        self.publish_repair(self.freeze())

    def test_revoked_origin_uses_new_callers_allocator_and_preserves_mapping(self):
        initial = self.freeze()
        old_mappings = self.account.snapshot()["graph_mapping"]
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        self.server.exchange(D, 0, mutations[:2])
        self.server.revoke(D)
        self.server.register(B)
        fence = self.fence(B)
        proof = self.server.close_request({"protocol_version": 1, "device_id": B, "sync_transport_generation": 1,
            **binding_from_begin(mutations[0]["mutation"], D), "expected_import_revision": 1,
            "takeover_reason": "origin_unavailable"}, takeover=True)["proof"]
        self.assertEqual(proof["recovery"]["highest_client_sequence"], initial["terminal_client_sequence"])
        self.account = self.new_account(fence, device=B)
        self.account.recover(self.guest, fence, self.server_status(initial, B, 1), authority=self.authority, proof=proof)
        self.assertEqual(self.account.snapshot()["graph_mapping"], old_mappings)
        self.assertEqual(json.loads(self.account.snapshot()["state"][0][0])["next_sequence"], 1)
        self.fresh_bootstrap()
        self.account.finish_recovery()
        repaired = self.freeze()
        self.assertEqual(repaired["begin_client_sequence"], 1)
        self.publish_repair(repaired)

    def test_never_visible_gap_does_not_acknowledge_or_reserve_unseen_sequences(self):
        # An actual earlier local write creates the gap. It is deliberately
        # never uploaded before the isolated account cache is replaced.
        self.account.enqueue(make_mutation(build()["samples"]["category"], 1, operation="create", base=0))
        initial = self.freeze()
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        binding = binding_from_begin(mutations[0]["mutation"], D)
        absent = self.server.close_request({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0,
            **binding, "expected_import_revision": 0, "predecessor_batch_id": None, "reason": "privacy_destroy"})
        self.assertEqual(absent["disposition"], "absent_fenced")
        fence = self.fence()
        proof = fence["resolved_absent_import_fences"][0]
        self.assertEqual((proof["kind"], proof["recovery"]["highest_client_sequence"]), ("never_visible_after_transport_fence", 0))
        self.account = self.new_account(fence)
        self.account.recover(self.guest, fence, self.server_status(initial, D, 1), authority=self.authority, proof=proof)
        self.fresh_bootstrap()
        self.account.finish_recovery()
        self.assertIsNone(self.account.prepare_ack_only())
        self.assertFalse(self.account.snapshot()["terminals"])
        repaired = self.freeze()
        self.assertEqual((initial["begin_client_sequence"], repaired["begin_client_sequence"]), (2, 1))
        self.publish_repair(repaired)

    def test_modified_fence_and_proof_leave_both_stores_unchanged(self):
        initial = self.freeze()
        mutations = self.account.prepare_import(self.guest, initial["operation_id"])
        self.server.exchange(D, 0, mutations[:1])
        fence = self.fence()
        proof = self.server.close_request({"protocol_version": 1, "device_id": D, "sync_transport_generation": 1,
            **binding_from_begin(mutations[0]["mutation"], D), "expected_import_revision": 1,
            "takeover_reason": "local_evidence_lost"}, takeover=True)["proof"]
        self.account = self.new_account(fence)
        status = self.server_status(initial, D, 1)
        before = self.account.snapshot(), self.guest.snapshot()
        bad_fence = copy.deepcopy(fence)
        bad_fence["result_hash"] = "0" * 64
        bad_proof = copy.deepcopy(proof)
        bad_proof["proof_hash"] = "0" * 64
        for left, right in ((bad_fence, proof), (fence, bad_proof)):
            with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
                self.account.recover(self.guest, left, status, authority=self.authority, proof=right)
            self.assertEqual((self.account.snapshot(), self.guest.snapshot()), before)

    def test_reserved_successor_cache_loss_recovers_at_every_process_death_boundary(self):
        initial = self.ready()
        self.guest.write(copy.deepcopy(build()["samples"]["category"]))
        preview = self.guest.preview(self.account, target_workspace_id=W)

        def pause_after_reservation(point):
            if point == "import_guest_reserved_committed":
                raise RuntimeError("reservation checkpoint")

        with self.assertRaisesRegex(RuntimeError, "reservation checkpoint"):
            self.guest.commit(self.account, preview["preview_token"], hook=pause_after_reservation)
        fence = self.fence()
        status = self.server_status(initial, D, 1)
        original_guest, original_server = self.guest, self.server
        points = ["import_fresh_mapping_and_control", "import_fresh_seed_and_receipt", "import_fresh_account_committed",
                  "import_fresh_restore_previous_lease", "import_fresh_ready"]
        for point in points:
            with self.subTest(point=point):
                directory = self.path / point
                directory.mkdir()
                for name, owner in (("guest", original_guest), ("server", original_server)):
                    with connect(owner.path) as source, connect(directory / (name + ".db")) as target:
                        source.backup(target)
                self.guest = FullGraphGuestImport(directory / "guest.db", workspace_id=S)
                self.server = ImportSuccessorServer(directory / "server.db", account_id=A, authority=self.authority,
                    clock=lambda: NOW_TEXT, staging_ttl_seconds=60)
                self.account = FreshImportAccount(directory / "fresh.db", account_id=A, device_id=D, transport=1,
                    installation_key=bytes(range(32)))
                if point == "import_fresh_ready":
                    self.account.recover(self.guest, fence, status, authority=self.authority)
                    self.fresh_bootstrap()
                    self.ack()
                request = {"directory": str(directory), "source": S, "account": A, "device": D, "fence": fence,
                    "status": status, "proof": None, "binary": str(self.binary), "trust": self.authority.trust, "point": point}
                request_path = directory / "request.json"
                request_path.write_text(json.dumps(request), encoding="utf8")
                result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/fresh_import_crash_probe.py"),
                    str(request_path)], capture_output=True, text=True, timeout=90)
                self.assertEqual(result.returncode, 80, result.stdout + result.stderr)
                self.assertIn("KILL_POINT_REACHED:" + point, result.stdout)
                self.account = FreshImportAccount(directory / "fresh.db", account_id=A, device_id=D, transport=1,
                    installation_key=bytes(range(32)))
                self.account.recover(self.guest, fence, status, authority=self.authority)
                with connect(self.guest.path) as db:
                    self.assertEqual(self.guest._lease(db)["active_batch_id"], initial["batch_id"])
                    self.assertFalse(db.execute("SELECT 1 FROM guest_import_source_lease_replacements").fetchone())
                self.assertFalse(self.account.snapshot()["local_import_outbox"])
                self.assertFalse(self.account.snapshot()["terminals"])
                if point != "import_fresh_ready":
                    self.fresh_bootstrap()
                    self.ack()
                self.account.finish_recovery()
                self.publish_repair(self.freeze())
                CRASH_POINTS.append(point)


if __name__ == "__main__":
    unittest.main()
