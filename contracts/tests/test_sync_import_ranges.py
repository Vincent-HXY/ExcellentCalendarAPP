"""Range fences, capacity and concurrent commit use real receipts and signatures."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from build_owned_graph_fixtures import make_mutation
from build_target_fixtures import build
from import_contract_reference import manifest_digest
from import_proof_authority import ImportProofAuthority
from import_range_reference import ImportRangeStore, binding_from_begin
from import_staging_reference import build_initial_batch
from protocol_reference import mutation_hash
from proof_reference import AcceptanceLedger

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"
CRASH_POINTS = []


class ImportRangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-range-binary-")
        cls.binary = Path(cls.compiled.name) / "proof.exe"
        subprocess.run(["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", str(ROOT / "contracts/spikes/sync_v1/proof_capsule_probe.cpp"),
            "-o", str(cls.binary), "-lbcrypt"], check=True, capture_output=True, timeout=90)
        cls.authority = ImportProofAuthority(cls.binary)

    @classmethod
    def tearDownClass(cls):
        cls.authority.close()
        cls.compiled.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-ranges-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.server = ImportRangeStore(self.path / "server.db", account_id=A, authority=self.authority)
        self.server.register(A)
        self.server.register(B)
        self.record = build()["samples"]["category"]
        self.batch = build_initial_batch(A, C, 0, [self.record])

    def send(self, messages, *, generation=0, device=A):
        return self.server.exchange(device, generation, [{"mutation": row, "payload_hash": mutation_hash(row)} for row in messages])

    def request(self, *, batch=None, revision=1, actor=A, generation=0, takeover=None):
        value = {"protocol_version": 1, "device_id": actor, "sync_transport_generation": generation,
            **binding_from_begin((batch or self.batch)[0], A), "expected_import_revision": revision}
        return {**value, "takeover_reason": takeover} if takeover else {**value, "predecessor_batch_id": None, "reason": "privacy_destroy"}

    def assert_proof(self, proof):
        self.assertTrue(self.authority.verify(A, "import_range_close", {name: value for name, value in proof.items()
            if name not in {"proof_token", "proof_hash"}}, proof["proof_token"], proof["proof_hash"]))

    def assert_zero(self, code, action):
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, code):
            action()
        self.assertEqual(self.server.snapshot(), before)

    def test_seen_partial_range_closes_without_fabricated_item_receipts_and_replays_same_proof(self):
        self.send(self.batch[:1])
        result = self.server.close_request(self.request())
        self.assert_proof(result["proof"])
        self.assertEqual(result["proof"]["kind"], "seen_range_closed")
        self.assertEqual(self.server.snapshot()["devices"][0][1], 3)
        self.assertEqual(len(self.server.snapshot()["receipts"]), 1)
        self.assertFalse(self.server.snapshot()["facts"])
        self.assertEqual(self.server.close_request(self.request())["proof"], result["proof"])
        for message in self.batch:
            self.assert_zero("IMPORT_BATCH_ABANDONED", lambda m=message: self.send([m]))
        created = self.send([make_mutation(self.record, 4, operation="create", base=0)])[0]
        self.assertEqual(created["status"], "accepted")

    def test_absent_gap_is_only_a_fence_until_prior_sequences_are_filled(self):
        batch = build_initial_batch(A, C, 0, [self.record], begin_sequence=3)
        request = self.request(batch=batch, revision=0)
        result = self.server.close_request(request)
        self.assertEqual((result["disposition"], result["proof"]), ("absent_fenced", None))
        self.assertFalse(self.server.snapshot()["receipts"])
        self.assertEqual(self.server.snapshot()["devices"][0][1], 0)
        self.assert_zero("IMPORT_BATCH_ABANDONED", lambda: self.send(batch[:1]))
        self.send([make_mutation(self.record, 1, operation="create", base=0), make_mutation(self.record, 2, patch={"description": "前序"})])
        with self.assertRaisesRegex(ValueError, "IMPORT_BATCH_ABANDONED"):
            self.send(batch[:1])
        after = self.server.snapshot()
        self.assertEqual((after["devices"][0][1], len(after["receipts"])), (5, 2))
        proof = self.server.close_request(request)["proof"]
        self.assert_proof(proof)
        self.assertEqual(proof["terminal_client_sequence"], 5)

    def test_occupied_absent_range_never_replays_or_blocks_an_unrelated_receipt(self):
        self.send([make_mutation(self.record, 1, operation="create", base=0)])
        request = self.request(revision=0)
        self.assertEqual(self.server.close_request(request)["disposition"], "absent_fenced")
        self.assert_zero("IMPORT_BATCH_ABANDONED", lambda: self.send(self.batch[:1]))
        fence_request = {"protocol_version": 1, "device_id": A, "fence_operation_id": str(uuid.uuid4()),
            "expected_sync_transport_generation": 0, "reason": "fresh_recovery"}
        response = self.server.fence_transport(fence_request)
        proof = response["resolved_absent_import_fences"][0]
        self.assert_proof(proof)
        self.assertEqual((proof["kind"], proof["sequence_advanced"], proof["recovery"]["highest_client_sequence"]),
            ("never_visible_after_transport_fence", False, 1))
        self.assertEqual(self.server.fence_transport(fence_request), response)
        self.assertEqual((len(self.server.snapshot()["receipts"]), self.server.snapshot()["devices"][0][-1]), (1, 0))
        self.assert_zero("IMPORT_BATCH_ABANDONED", lambda: self.send(self.batch[:1]))
        self.assertEqual(self.send([make_mutation(self.record, 2, patch={"description": "新 lifecycle"})], generation=1)[0]["status"], "accepted")

    def test_takeover_requires_real_origin_state_and_fences_late_origin(self):
        self.send(self.batch[:1])
        request = self.request(actor=B, takeover="origin_unavailable")
        self.assert_zero("IMPORT_SOURCE_OWNED", lambda: self.server.close_request(request, takeover=True))
        self.server.revoke(A)
        result = self.server.close_request(request, takeover=True)
        self.assert_proof(result["proof"])
        self.assertEqual(result["proof"]["reason"], "superseded")
        self.assert_zero("IMPORT_BATCH_SUPERSEDED", lambda: self.send(self.batch[-1:]))

    def test_commit_and_abandon_share_the_same_real_database_lock(self):
        self.send(self.batch[:-1])
        request = self.request()

        def commit():
            try:
                return self.send(self.batch[-1:])[0]["status"]
            except ValueError as error:
                return str(error)

        with ThreadPoolExecutor(max_workers=2) as pool:
            left = pool.submit(commit)
            right = pool.submit(self.server.close_request, request)
            committed, closed = left.result(), right.result()
        if committed == "accepted":
            self.assertEqual(closed["disposition"], "already_confirmed")
            self.assertEqual(len(self.server.snapshot()["facts"]), 1)
            self.assertFalse(self.server.snapshot()["import_range_fences"])
        else:
            self.assertEqual(committed, "IMPORT_BATCH_ABANDONED")
            self.assertEqual(closed["disposition"], "abandoned")
            self.assertFalse(self.server.snapshot()["facts"])
            self.assertFalse(self.server.snapshot()["import_publication_lines"])

    def test_oversized_begin_preserves_declared_manifest_in_real_signed_capacity_proof(self):
        begin = copy.deepcopy(self.batch[0])
        manifest = begin["payload"]["manifest"]
        manifest["target_counts"]["category"] = manifest["total_item_count"] = 50001
        result = self.send([begin])[0]
        self.assertEqual(result["failure_code"], "SYNC_IMPORT_CAPACITY_EXCEEDED")
        proof = json.loads(self.server.snapshot()["import_range_fences"][0][-1])
        self.assert_proof(proof)
        self.assertEqual(proof["manifest"], manifest)
        self.assertEqual((proof["reason"], proof["terminal_client_sequence"]), ("capacity_rejected", 50003))
        snapshot = self.server.snapshot()
        self.assertEqual((snapshot["devices"][0][1], len(snapshot["receipts"])), (50003, 1))
        self.assertFalse(snapshot["import_stage_items"])
        self.assertFalse(snapshot["facts"])

    def test_underreported_item_bytes_terminate_the_remaining_range_and_preserve_exact_duplicates(self):
        batch = copy.deepcopy(self.batch)
        manifest = batch[0]["payload"]["manifest"]
        manifest["total_canonical_bytes"] = 1
        manifest["manifest_hash"] = manifest_digest(manifest, batch[1:-1])
        for message in batch:
            message["import_manifest_hash"] = manifest["manifest_hash"]
            if message["operation_type"] in {"import_begin", "import_commit"}:
                message["payload"]["manifest"] = manifest
        results = self.send(batch)
        self.assertEqual([row["status"] for row in results], ["staged", "rejected", "rejected"])
        self.assertEqual(results[-1]["error"]["code"], "SYNC_IMPORT_CAPACITY_EXCEEDED")
        self.assertEqual([row["original_result"] for row in self.send(batch)], results)
        self.assertEqual(self.server.snapshot()["devices"][0][1], 3)
        self.assertFalse(self.server.snapshot()["import_stage_items"])
        self.assertFalse(self.server.snapshot()["facts"])

    def test_seen_range_after_fresh_transport_fence_binds_the_current_recovery_generation(self):
        self.send(self.batch[:1])
        fence = self.server.fence_transport({"protocol_version": 1, "device_id": A, "fence_operation_id": str(uuid.uuid4()),
            "expected_sync_transport_generation": 0, "reason": "fresh_recovery"})
        result = self.server.close_request(self.request(generation=1, takeover="local_evidence_lost"), takeover=True)
        self.assert_proof(result["proof"])
        self.assertEqual((result["proof"]["origin_sync_transport_generation"], result["proof"]["recovery"]["sync_transport_generation"]), (0, 1))
        for fresh in (True, False):
            local = AcceptanceLedger(self.path / ("fresh-proof.db" if fresh else "retained-proof.db"), self.binary)
            local.seed(account_id=A, device_id=A, runtime_id=B, fresh=fresh)
            proofs = []
            for purpose, wire, token_field, hash_field in (("device_fence", fence, "fence_receipt", "result_hash"),
                    ("import_range_close", result["proof"], "proof_token", "proof_hash")):
                proofs.append({"trust_store": self.authority.trust, "locally_revoked_keys": [], "token": wire[token_field],
                    "expected_account_id": A, "expected_purpose": purpose, "claimed_hash": wire[hash_field],
                    "claim_data": {name: value for name, value in wire.items() if name not in {token_field, hash_field}}})
            local.accept(proofs[0], expected_runtime_id=B, expected_operation_id=fence["fence_operation_id"])
            local.reserve(proofs[1]["claim_data"])
            if fresh:
                self.assertEqual(local.accept(proofs[1], expected_runtime_id=B), "accepted")
            else:
                with self.assertRaisesRegex(ValueError, "SYNC_TRANSPORT_GENERATION_MISMATCH"):
                    local.accept(proofs[1], expected_runtime_id=B)

    def test_actual_process_death_rolls_back_range_and_fence_transactions(self):
        self.send(self.batch[:1])
        self.kill("close_request", self.request(), ("import_range_highest", "import_range_proof_and_stage"))
        self.assertFalse(self.server.snapshot()["import_range_fences"])
        self.server = ImportRangeStore(self.path / "absent.db", account_id=A, authority=self.authority)
        self.server.register(A)
        batch = build_initial_batch(A, C, 0, [self.record], begin_sequence=2)
        request = self.request(batch=batch, revision=0)
        self.kill("close_request", request, ("import_absent_identity_fence",))
        self.server.close_request(request)
        fence_request = {"protocol_version": 1, "device_id": A, "fence_operation_id": str(uuid.uuid4()),
            "expected_sync_transport_generation": 0, "reason": "fresh_recovery"}
        self.kill("fence_transport", fence_request, ("import_fence_generation", "import_range_highest", "import_range_proof_and_stage", "import_fence_receipt"))
        self.assertEqual(self.server.fence_transport(fence_request)["recovery"]["highest_client_sequence"], 0)

    def kill(self, method, request, points):
        for point in points:
            before = self.server.snapshot()
            path = self.path / "kill.json"
            path.write_text(json.dumps({"path": str(self.server.path), "account": A, "binary": str(self.binary), "method": method,
                "request": request, "point": point}), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_range_crash_probe.py"), str(path)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            self.server = ImportRangeStore(self.server.path, account_id=A, authority=self.authority)
            self.assertEqual(self.server.snapshot(), before)
            CRASH_POINTS.append(point)


if __name__ == "__main__":
    unittest.main()
