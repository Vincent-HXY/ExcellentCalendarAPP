"""Source/epoch discovery and TTL never manufacture local visibility or leases."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
import test_sync_import_cleanup as helpers
from domain_reference import validate_schema
from import_proof_authority import ImportProofAuthority
from import_status_reference import AccountImportStatus, ImportStatusServer

CRASH_POINTS = []
OBSERVATIONS = []


class ImportStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-status-proof-")
        cls.binary = Path(cls.compiled.name) / "proof.exe"
        subprocess.run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", str(ROOT / "contracts/spikes/sync_v1/proof_capsule_probe.cpp"),
            "-o", str(cls.binary), "-lbcrypt"], check=True, capture_output=True, timeout=90)
        cls.authority = ImportProofAuthority(cls.binary)

    @classmethod
    def tearDownClass(cls):
        cls.authority.close()
        cls.compiled.cleanup()

    def setUp(self):
        helpers.ImportCleanupTests.setUp(self)
        self.account = AccountImportStatus(self.account.path, account_id=helpers.A, device_id=helpers.D, installation_key=bytes(range(32)))
        self.now = helpers.NOW_TEXT
        self.server = ImportStatusServer(self.server.path, account_id=helpers.A, authority=self.authority, clock=lambda: self.now, staging_ttl_seconds=60)

    freeze = helpers.ImportCleanupTests.freeze
    publish = helpers.ImportCleanupTests.publish
    apply = helpers.ImportCleanupTests.apply
    state = helpers.ImportCleanupTests.state
    ready = helpers.ImportCleanupTests.ready
    retire = helpers.ImportCleanupTests.retire
    complete = helpers.ImportCleanupTests.complete

    def query(self, *, exact=True, epoch=0, source_hash=None, device=helpers.D):
        identity = {"import_batch_id": self.batch} if exact else {"source_workspace_id": helpers.S, "source_epoch": epoch, "source_snapshot_hash": source_hash}
        result = self.server.status({"protocol_version": 1, "device_id": device, "sync_transport_generation": 0, **identity})
        OBSERVATIONS.append({"schema": "sync/import_status_response.schema.json", "value": result})
        return result

    def test_initial_native_revision_zero_and_server_shape_owns_only_server_stages(self):
        self.freeze()
        local = self.account.status(self.operation)
        self.assertEqual((local["stage"], local["import_revision"]), ("local_staging", 0))
        self.assertEqual(self.query()["disposition"], "none")
        staged = self.server.exchange(helpers.D, 0, self.mutations[:2])
        self.account.acknowledge_import(self.operation, staged)
        remote = self.query(exact=False)
        self.assertEqual(remote["server_staged_item_count"], 1)
        self.assertNotIn("local_staged_item_count", remote)
        self.assertNotIn("cleanup_receipt", remote)
        self.assertEqual(self.account.status(self.operation, server_snapshot=remote)["stage"], "server_staging")
        for stage in ("local_staging", "publish_applied", "cleanup_pending"):
            bad = {**remote, "stage": stage}
            with self.assertRaises(ValueError):
                validate_schema("sync/import_status_response.schema.json", bad)

    def test_offline_status_after_commit_receipt_never_invents_server_timestamp(self):
        self.freeze()
        self.publish()
        value = self.account.status(self.operation)
        self.assertEqual(value["stage"], "server_confirmed")
        self.assertIsNone(value["publication"]["published_at"])
        validate_schema("workspace/native_import_status_response.schema.json", value)
        self.apply()
        self.assertEqual(self.account.status(self.operation)["stage"], "publish_applied")
        remote = self.query()
        self.assertEqual(self.account.status(self.operation, server_snapshot=remote)["publication"]["published_at"], self.now)

    def test_status_and_restart_cannot_promote_server_confirmation_to_local_visibility(self):
        self.freeze()
        self.publish(acknowledge=False)
        remote = self.query(exact=False)
        self.assertEqual(self.account.status(self.operation, server_snapshot=remote)["stage"], "server_confirmed")
        self.assertFalse(self.account.snapshot()["live"])
        self.assertEqual(len(self.account.snapshot()["local_import_outbox"]), 5)
        with self.assertRaisesRegex(ValueError, "IMPORT_PUBLISH_INCOMPLETE"):
            self.guest.retire(self.account, self.operation, now=self.now)
        self.account = AccountImportStatus(self.account.path, account_id=helpers.A, device_id=helpers.D, installation_key=bytes(range(32)))
        self.assertEqual(self.account.status(self.operation)["stage"], "server_confirmed")
        self.account.acknowledge_import(self.operation, self.results)
        self.apply()
        self.assertEqual(self.account.status(self.operation)["stage"], "publish_applied")

    def test_completed_exact_status_and_new_epoch_discovery_are_distinct(self):
        self.ready()
        self.account.accept_server_status(self.operation, self.query())
        receipt = self.retire()
        self.assertEqual(self.account.status(self.operation)["stage"], "cleanup_pending")
        self.complete(receipt)
        remote = self.query()
        self.assertEqual(remote["stage"], "completed")
        self.assertEqual(remote["cleanup_confirmation"]["guest_cleanup_receipt_hash"], receipt["receipt_hash"])
        self.assertNotIn("cleaned_at", json.dumps(remote))
        self.assertEqual(self.account.status(self.operation, server_snapshot=remote)["stage"], "completed")
        self.assertEqual(self.query(exact=False)["disposition"], "none")
        self.assertEqual(self.query(exact=False, epoch=1)["disposition"], "none")

    def test_payload_ttl_preserves_receipts_range_identity_and_guest_lease(self):
        self.freeze()
        result = self.server.exchange(helpers.D, 0, self.mutations[:3])
        self.account.acknowledge_import(self.operation, result)
        before = self.server.snapshot()
        guest = self.guest.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_VERSION_CONFLICT"):
            self.server.reclaim_expired_payload(self.batch, now="2026-09-06T07:00:59Z")
        self.assertEqual(self.server.snapshot(), before)
        self.now = "2026-09-06T07:01:00Z"
        proof = self.server.reclaim_expired_payload(self.batch, now=self.now)
        self.assertEqual(proof["reason"], "ttl_payload_reclaimed")
        self.assertEqual(self.server.snapshot()["receipts"], before["receipts"])
        self.assertFalse(self.server.snapshot()["import_stage_items"])
        self.assertEqual(self.query(exact=False)["stage"], "superseded")
        self.assertEqual(self.query()["manifest"], self.receipt["manifest"])
        self.assertEqual(self.server.reclaim_expired_payload(self.batch, now=self.now), proof)
        self.assertEqual(self.guest.snapshot(), guest)
        self.account.accept_range_close(self.operation, proof, authority=self.authority)
        self.assertEqual(self.account.receipt(self.operation)["stage"], "superseded")
        self.assertEqual(self.guest.snapshot(), guest)
        with self.assertRaisesRegex(ValueError, "IMPORT_BATCH_SUPERSEDED"):
            self.server.exchange(helpers.D, 0, self.mutations[-1:])

    def test_fixed_source_hash_filter_and_other_device_do_not_enable_ordinal_upload(self):
        self.freeze()
        self.server.exchange(helpers.D, 0, self.mutations[:1])
        self.assertEqual(self.query(exact=False, source_hash="f" * 64)["disposition"], "none")
        self.server.register(helpers.B)
        self.assertEqual(self.query(device=helpers.B)["resume_disposition"], "close_range_then_successor")
        before = self.server.snapshot()
        with self.assertRaises(ValueError):
            self.server.exchange(helpers.B, 0, self.mutations[1:2])
        self.assertEqual(self.server.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
