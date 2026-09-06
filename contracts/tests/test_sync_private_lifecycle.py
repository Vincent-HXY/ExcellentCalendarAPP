"""Private AEAD, exact final receipt authorization and safe diagnostic TTL."""
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
from build_private_lifecycle_fixtures import derive, A, W, D, S
from domain_reference import validate_schema
from import_range_reference import binding_from_begin
from private_lifecycle_reference import ProtectedRecords, cached_remote_snapshot, diagnostic_expired, JDK


class PrivateLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="excellent-calendar-private-record-")
        cls.classes = Path(cls.compiled.name)
        subprocess.run([str(JDK / "javac.exe"), "-d", str(cls.classes), str(ROOT / "contracts/spikes/sync_v1/PrivateRecordProbe.java")], check=True, capture_output=True)
        helpers.ImportCleanupTests.setUpClass()

    @classmethod
    def tearDownClass(cls):
        helpers.ImportCleanupTests.tearDownClass()
        cls.compiled.cleanup()

    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="excellent-calendar-private-store-")
        self.addCleanup(temp.cleanup)
        self.path = Path(temp.name)
        self.arguments = dict(classes=self.classes, key=bytes(range(32)), installation_id=S, account_id=A, workspace_id=W)
        self.records = ProtectedRecords(self.path, **self.arguments)

    def test_aead_blocks_wrong_account_workspace_installation_kind_key_and_tampering(self):
        value = derive()["samples"]["device/private/remote_snapshot_cache.schema.json"]
        identifier = self.records.save("remote_device_snapshot", value)
        raw = (self.path / (identifier + ".record")).read_bytes()
        self.assertNotIn(A.encode(), raw)
        self.assertEqual(self.records.load("remote_device_snapshot", identifier), value)
        self.assertEqual(cached_remote_snapshot(self.records, identifier, active_account_id=A, active_workspace_id=W, device_id=D)["remote_snapshot_state"], "stale")
        self.assertEqual(cached_remote_snapshot(self.records, None, active_account_id=A, active_workspace_id=W, device_id=D)["remote_snapshot_state"], "unavailable")
        for field in ("account_id", "workspace_id", "installation_id", "key"):
            arguments = {**self.arguments, field: bytes(reversed(range(32))) if field == "key" else D}
            with self.subTest(field=field), self.assertRaises(ValueError):
                ProtectedRecords(self.path, **arguments).load("remote_device_snapshot", identifier)
        with self.assertRaises(ValueError):
            self.records.load("crypto_destroy_final", identifier)
        with self.assertRaises(ValueError):
            cached_remote_snapshot(self.records, identifier, active_account_id=D, active_workspace_id=W, device_id=D)
        (self.path / (identifier + ".record")).write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
        with self.assertRaises(ValueError):
            self.records.load("remote_device_snapshot", identifier)

    def test_fixed_shapes_reject_business_content_and_ttl_expires_at_boundary_or_changed_boot(self):
        for case in derive()["cases"]:
            if case["expected"]["schema_valid"]:
                validate_schema(case["schema"], case["input"])
            else:
                with self.subTest(case=case["id"]), self.assertRaises(ValueError):
                    validate_schema(case["schema"], case["input"])
        journal = derive()["samples"]["sync/private/diagnostic_export_journal.schema.json"]
        self.assertFalse(diagnostic_expired(journal, boot_id=S, elapsed_ms=900009))
        self.assertTrue(diagnostic_expired(journal, boot_id=S, elapsed_ms=900010))
        self.assertTrue(diagnostic_expired(journal, boot_id=D, elapsed_ms=10))
        self.assertTrue(diagnostic_expired(journal, boot_id=S, elapsed_ms=9))
        self.assertTrue(diagnostic_expired(journal, boot_id=S, elapsed_ms=10, share_completed=True))

    def test_authenticated_final_receipt_and_real_server_abandon_release_without_account_database(self):
        helper = helpers.ImportCleanupTests(methodName="runTest")
        helper.setUp()
        self.addCleanup(helper.doCleanups)
        helper.freeze()
        helper.server.exchange(helpers.D, 0, helper.mutations[:2])
        response = helper.server.close_request({"protocol_version": 1, "device_id": helpers.D, "sync_transport_generation": 0,
            **binding_from_begin(helper.mutations[0]["mutation"], helpers.D), "expected_import_revision": 1, "predecessor_batch_id": None, "reason": "privacy_destroy"})
        request = helper.release_request({"kind": "prepublish_abandon_crypto_destroyed", "server_abandon": response,
            "crypto_destroy_final_receipt_hash": "0" * 64})
        closed = response["proof"]
        final = {**derive()["samples"]["workspace/private/crypto_destroy_final_receipt.schema.json"],
            **{key: value for key, value in request.items() if key != "proof"}, "account_id": helpers.A, "workspace_id": helpers.W,
            "device_id": helpers.D, "import_batch_id": helper.batch, "manifest_hash": closed["manifest"]["manifest_hash"]}
        journal = ProtectedRecords(self.path / "final", **{**self.arguments, "account_id": helpers.A, "workspace_id": helpers.W})
        # The trusted lifecycle owner alone supplies finality. Actual Android key
        # deletion is covered separately; this test proves AEAD/binding/lease CAS.
        request["proof"]["crypto_destroy_final_receipt_hash"] = journal.save("crypto_destroy_final", final)
        before = helper.guest.snapshot()
        bad = copy.deepcopy(request)
        bad["source_epoch"] = 1
        with self.assertRaises(ValueError):
            helper.guest.release_destroyed(bad, journal=journal, authority=helper.authority)
        self.assertEqual(helper.guest.snapshot(), before)
        bad = copy.deepcopy(request)
        bad["proof"]["crypto_destroy_final_receipt_hash"] = "f" * 64
        with self.assertRaises(ValueError):
            helper.guest.release_destroyed(bad, journal=journal, authority=helper.authority)
        self.assertEqual(helper.guest.snapshot(), before)
        bad = copy.deepcopy(request)
        bad["proof"]["server_abandon"] = {"disposition": "already_confirmed", "current_head": response["current_head"],
            "publication": {"import_publish_group_id": D, "commit_server_sequence": 1, "publish_digest": "0" * 64,
                "mapping_digest": "0" * 64, "published_at": helpers.NOW_TEXT}}
        with self.assertRaisesRegex(ValueError, "IMPORT_SOURCE_OWNED"):
            helper.guest.release_destroyed(bad, journal=journal, authority=helper.authority)
        self.assertEqual(helper.guest.snapshot(), before)
        helper.account.path.rename(helper.account.path.with_suffix(".unavailable"))
        result = helper.guest.release_destroyed(request, journal=journal, authority=helper.authority)
        self.assertEqual(result, helper.guest.release_destroyed(request, journal=journal, authority=helper.authority))
        self.assertFalse(helper.guest.snapshot()["guest_import_source_leases"])
        self.assertEqual(helper.guest.snapshot()["guest_import_source_facts"], before["guest_import_source_facts"])


if __name__ == "__main__":
    unittest.main()
