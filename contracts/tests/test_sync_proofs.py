"""Authenticated binding, rollback and replay tests, using real Windows CNG."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
SPIKE = HERE / "spikes/sync_v1"
sys.path.insert(0, str(SPIKE))
from build_proof_capsule_fixtures import A, B, C, D, E, derive
from proof_reference import AcceptanceLedger, authenticate, authenticate_typed
from sqlite_reference import connect


class ProofTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="excellent-calendar-proof-tests-")
        cls.binary = Path(os.environ.get("SYNC_PROOF_TEST_BINARY", str(Path(cls.scratch.name) / "proof.exe")))
        if "SYNC_PROOF_TEST_BINARY" not in os.environ:
            subprocess.run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", str(SPIKE / "proof_capsule_probe.cpp"), "-o", str(cls.binary), "-lbcrypt"], check=True, capture_output=True)
        cls.fixture = json.loads((HERE / "fixtures/sync/v1/proof_capsule_vectors.json").read_text(encoding="utf-8"))
        cls.cases = {case["id"].removeprefix("FX-PROOF-"): case for case in cls.fixture["cases"]}

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="excellent-calendar-proof-ledger-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "ledger.db"
        self.ledger = AcceptanceLedger(self.path, self.binary)

    def request(self, name="fence"):
        return copy.deepcopy(self.cases[name]["input"])

    def seed(self, **kwargs):
        self.ledger.seed(account_id=A, device_id=B, runtime_id=D, **kwargs)

    def snapshot(self):
        with connect(self.path) as db:
            return tuple(db.iterdump())

    def test_fixed_public_golden_and_actual_signature_decisions(self):
        self.assertEqual(self.fixture, derive())
        results = authenticate(self.binary, [case["input"] for case in self.fixture["cases"]])
        self.assertEqual(results, [case["expected"]["authenticated"] for case in self.fixture["cases"]])
        for case in self.fixture["cases"]:
            with self.subTest(case=case["id"]):
                try:
                    authenticate_typed(self.binary, case["input"])
                    valid = True
                except ValueError:
                    valid = False
                self.assertEqual(valid, case["expected"]["typed_domain_valid"])

    def test_fence_replay_is_exact_and_survives_reopen(self):
        self.seed()
        request = self.request()
        self.assertEqual(self.ledger.accept(request, expected_runtime_id=D, expected_operation_id=C), "accepted")
        before = self.snapshot()
        reopened = AcceptanceLedger(self.path, self.binary)
        self.assertEqual(reopened.accept(request, expected_runtime_id=D, expected_operation_id=C), "duplicate")
        self.assertEqual(before, self.snapshot())

    def test_wrong_account_runtime_operation_and_generation_write_nothing(self):
        self.seed()
        for name, runtime, operation in (("wrong-account", D, C), ("fence", E, C), ("fence", D, E), ("tampered-generation", D, C)):
            with self.subTest(name=name, runtime=runtime, operation=operation):
                before = self.snapshot()
                with self.assertRaises(ValueError): self.ledger.accept(self.request(name), expected_runtime_id=runtime, expected_operation_id=operation)
                self.assertEqual(before, self.snapshot())

    def test_every_acceptance_write_boundary_rolls_back(self):
        self.seed()
        for name in ("authenticated", "state_applied", "receipt_inserted"):
            before = self.snapshot()
            with self.assertRaises(RuntimeError): self.ledger.accept(self.request(), expected_runtime_id=D, expected_operation_id=C, fail_at=name)
            self.assertEqual(before, self.snapshot())

    def test_seen_range_closes_and_acknowledges_atomically(self):
        self.seed(); request = self.request("range-seen"); self.ledger.reserve(request["claim_data"])
        for boundary in ("state_applied", "receipt_inserted"):
            before = self.snapshot()
            with self.assertRaises(RuntimeError): self.ledger.accept(request, expected_runtime_id=D, fail_at=boundary)
            self.assertEqual(before, self.snapshot())
        self.ledger.accept(request, expected_runtime_id=D)
        with connect(self.path) as db:
            self.assertEqual(db.execute("SELECT generation,highest,acknowledged,next_sequence,ack_dirty FROM proof_test_state").fetchone(), (0, 3, 3, 4, 1))
            self.assertEqual(db.execute("SELECT revision,closed FROM proof_test_imports").fetchone(), (1, 1))

    def test_another_origin_cannot_move_this_devices_allocator(self):
        self.ledger.seed(account_id=A, device_id=E, runtime_id=D)
        request = self.request("range-seen"); self.ledger.reserve(request["claim_data"])
        self.ledger.accept(request, expected_runtime_id=D)
        with connect(self.path) as db:
            self.assertEqual(db.execute("SELECT generation,highest,acknowledged,next_sequence FROM proof_test_state").fetchone(), (0, 0, 0, 1))
            self.assertEqual(db.execute("SELECT revision,closed FROM proof_test_imports").fetchone(), (1, 1))

    def test_never_visible_requires_fresh_fence_and_never_acknowledges_hole(self):
        self.seed(fresh=True); request = self.request("range-never"); self.ledger.reserve(request["claim_data"])
        before = self.snapshot()
        with self.assertRaises(ValueError): self.ledger.accept(request, expected_runtime_id=D)
        self.assertEqual(before, self.snapshot())
        self.ledger.accept(self.request(), expected_runtime_id=D, expected_operation_id=C)
        self.ledger.accept(request, expected_runtime_id=D)
        with connect(self.path) as db:
            self.assertEqual(db.execute("SELECT generation,highest,acknowledged,next_sequence,ack_dirty FROM proof_test_state").fetchone(), (1, 0, 0, 1, 0))

    def test_retained_runtime_cannot_consume_never_visible_proof(self):
        self.seed(); request = self.request("range-never"); self.ledger.reserve(request["claim_data"])
        self.ledger.accept(self.request(), expected_runtime_id=D, expected_operation_id=C)
        before = self.snapshot()
        with self.assertRaises(ValueError): self.ledger.accept(request, expected_runtime_id=D)
        self.assertEqual(before, self.snapshot())

    def test_wrong_reservation_or_revision_cannot_be_authorized_by_signature(self):
        self.seed(); request = self.request("range-seen")
        local = copy.deepcopy(request["claim_data"]); local["begin_client_sequence"] = 5
        self.ledger.reserve(local); before = self.snapshot()
        with self.assertRaises(ValueError): self.ledger.accept(request, expected_runtime_id=D)
        self.assertEqual(before, self.snapshot())
        with connect(self.path) as db:
            db.execute("UPDATE proof_test_imports SET reservation_json=?,revision=2", (json.dumps(request["claim_data"]),))
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_VERSION_CONFLICT"): self.ledger.accept(request, expected_runtime_id=D)
        self.assertEqual(before, self.snapshot())

    def test_revocation_survives_reopen_and_older_trust_store(self):
        self.seed(); request = self.request()
        import base64
        capsule = json.loads(base64.urlsafe_b64decode(request["token"] + "=" * (-len(request["token"]) % 4)))
        self.ledger.revoke([capsule["claims"]["key_id"]]); self.ledger.revoke([])
        before = self.snapshot(); reopened = AcceptanceLedger(self.path, self.binary)
        with self.assertRaises(ValueError): reopened.accept(request, expected_runtime_id=D, expected_operation_id=C)
        self.assertEqual(before, self.snapshot())
        # The pre-shipped new key remains available; old-key revocation cannot
        # poison an independently trusted rotation key.
        self.assertEqual(reopened.accept(self.request("rotated"), expected_runtime_id=D, expected_operation_id=C), "accepted")

    def test_exhausted_sequence_restores_null_allocator(self):
        self.seed(); self.ledger.accept(self.request("fence-max"), expected_runtime_id=D, expected_operation_id=C)
        with connect(self.path) as db:
            self.assertEqual(db.execute("SELECT highest,next_sequence,exhausted FROM proof_test_state").fetchone(), (9007199254740991, None, 1))

    def test_account_deletion_only_releases_matching_owner_lease(self):
        self.seed()
        with connect(self.path) as db:
            db.execute("INSERT INTO proof_test_guest_lease VALUES(?,?,0,1,1)", (D, A))
            db.execute("INSERT INTO proof_test_guest_lease VALUES(?,?,2,3,1)", (E, C))
            db.execute("INSERT INTO proof_test_guest_lease VALUES(?,?,4,5,1)", (B, A))
            db.execute("INSERT INTO proof_test_guest_epochs VALUES(?,1)", (D,))
        self.ledger.accept(self.request("deleted"), expected_runtime_id=D, source_workspace_id=D)
        with connect(self.path) as db:
            self.assertEqual(db.execute("SELECT source_id,account_id,epoch,current_epoch,cleanup_pending FROM proof_test_guest_lease ORDER BY source_id").fetchall(), [(B, A, 4, 5, 1), (E, C, 2, 3, 1)])
            self.assertEqual(db.execute("SELECT current_epoch FROM proof_test_guest_epochs WHERE source_id=?", (D,)).fetchone(), (1,))
        self.assertEqual(self.ledger.accept(self.request("deleted"), expected_runtime_id=D, source_workspace_id=B), "accepted")


if __name__ == "__main__": unittest.main()
