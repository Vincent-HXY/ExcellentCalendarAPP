"""Independent boundary and crash-window examples for the planned Sync protocol."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_protocol_contracts import derive as derive_protocol
from build_sync_import_contracts import derive as derive_import
from protocol_reference import (ApplyStore, ProtocolStore, canonical, digest, mutation_hash, mutation_keys, validate_mutation)
from domain_reference import validate_schema

FIXED_TIME = "2026-09-05T01:00:00Z"
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"


def samples():
    return json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf-8"))["samples"]


def mutation(sample, sequence=1, *, patch=None, predecessor=None, base=1, operation="update"):
    fact = copy.deepcopy(sample["fact"])
    result = {"protocol_version": 1, "mutation_id": str(uuid.uuid4()), "client_sequence": sequence,
        "target_type": sample["target_type"], "target_id": sample["target_id"], "operation_type": operation,
        "base_entity_version": base, "causal_predecessors": [], "import_lineage_id": None, "import_batch_id": None,
        "import_source_workspace_id": None, "import_source_epoch": None, "import_item_ordinal": None,
        "import_manifest_hash": None, "predecessor_batch_id": None,
        "payload": {"patch": patch, "owned_dependencies": []} if operation == "update" else {"deleted_at": FIXED_TIME},
        "conflict_recovery_snapshot": fact if operation == "update" else None, "created_at": FIXED_TIME}
    if patch:
        result["conflict_recovery_snapshot"].update(patch)
    result["causal_predecessors"] = [{"merge_key": key, "client_sequence": predecessor} for key in mutation_keys(result)]
    return result


def hashed(m):
    return {"mutation": m, "payload_hash": mutation_hash(m)}


class ProtocolTests(unittest.TestCase):
    def test_future_base_entity_version_cannot_bypass_concurrent_field_checks(self):
        m = mutation(self.category, patch={"name": "unverified future"}, base=2)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"):
            self.send(m)
        self.assertEqual(self.server.snapshot(), before)

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="excellent-calendar-protocol-")
        self.addCleanup(self.scratch.cleanup)
        self.path = Path(self.scratch.name)
        self.server = ProtocolStore(self.path / "server.db")
        self.server.register(A)
        self.server.register(B)
        self.category = samples()["category"]
        self.server.seed(self.category)

    def send(self, m, device=A, **options):
        result = self.server.exchange(device, 0, [hashed(m)], **options)[0]
        validate_schema("sync/sync_upload_result.schema.json", result)
        return result

    def test_generated_definitions_are_exact_and_references_are_closed(self):
        for path, expected in {**derive_protocol(), **derive_import()}.items():
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), expected, path.name)

    def test_hash_covers_causal_recovery_and_import_identity_but_not_diagnostic_clock(self):
        m = mutation(self.category, patch={"name": "第二个名字"})
        original = mutation_hash(m)
        m["created_at"] = "2040-01-01T00:00:00Z"
        self.assertEqual(mutation_hash(m), original)
        for key, value in (("base_entity_version", 0), ("import_source_epoch", 2),
                           ("conflict_recovery_snapshot", None), ("causal_predecessors", [])):
            altered = {**m, key: value}
            self.assertNotEqual(mutation_hash(altered), original, key)
        self.assertEqual(canonical({"💩": 1.0, "€": -0.0}), '{"€":0,"💩":1}'.encode())
        self.assertNotEqual(digest("é"), digest("e\u0301"))
        for bad in (float("nan"), 1.5, "\ud800"):
            with self.assertRaises((ValueError, UnicodeError)):
                canonical(bad)

    def test_same_device_pending_chain_and_duplicate_preserve_original_effect(self):
        first = mutation(self.category, patch={"name": "A"})
        second = mutation(self.category, 2, patch={"name": "B"}, predecessor=1)
        original = self.server.exchange(A, 0, [hashed(first), hashed(second)])
        self.assertEqual([r["status"] for r in original], ["accepted", "accepted"])
        replay = self.server.exchange(A, 0, [hashed(first), hashed(second)])
        self.assertEqual([r["original_result"] for r in replay], original)
        for r in replay:
            validate_schema("sync/sync_upload_result.schema.json", r)
        snap = self.server.snapshot()
        self.assertEqual(len(snap["groups"]), 2)
        self.assertEqual(json.loads(snap["facts"][0][3])["name"], "B")
        self.assertEqual(snap["anchors"][0][-2:], (2, 3))

    def test_cross_device_insert_conflicts_only_same_key_and_keeps_auto_merged_projection(self):
        self.send(mutation(self.category, patch={"name": "远端"}), B)
        result = self.send(mutation(self.category, patch={"name": "本机", "description": "独立修改"}))
        self.assertEqual(result["status"], "partially_merged")
        snapshot = self.server.snapshot()
        fact = json.loads(snapshot["facts"][0][3])
        self.assertEqual((fact["name"], fact["description"]), ("远端", "独立修改"))
        conflict = json.loads(snapshot["conflicts"][0][-1])
        self.assertEqual(conflict["conflicting_groups"][0]["merge_key"], "name")
        self.assertEqual(conflict["auto_merged_groups"][0]["merge_key"], "description")
        blocked = self.send(mutation(self.category, 2, patch={"description": "也被对象门禁阻止"}))
        self.assertEqual((blocked["status"], blocked["failure_code"]), ("rejected", "SYNC_ENTITY_CONFLICT_BLOCKED"))
        self.assertEqual(len(self.server.snapshot()["groups"]), 2)

    def test_independent_keys_and_equal_value_do_not_create_conflict_or_extra_group(self):
        self.send(mutation(self.category, patch={"name": "共同值"}), A)
        same = self.send(mutation(self.category, patch={"name": "共同值"}), B)
        self.assertEqual(same["status"], "accepted")
        self.assertEqual(same["per_key_results"][0]["causal_disposition"], "no_effect")
        independent = self.send(mutation(self.category, 2, patch={"description": "独立"}), B)
        self.assertEqual(independent["status"], "accepted")
        self.assertEqual(len(self.server.snapshot()["groups"]), 2)
        self.assertFalse(self.server.snapshot()["conflicts"])

    def test_terminal_rejected_predecessor_does_not_poison_frozen_successor(self):
        habit = samples()["habit"]
        habit["fact"]["first_check_in_at"] = FIXED_TIME
        self.server.seed(habit)
        first = mutation(habit, patch={"target_count_hundredths": 999, "unit": "页"})
        second = mutation(habit, 2, patch={"target_count_hundredths": habit["fact"]["target_count_hundredths"],
                                        "unit": habit["fact"]["unit"]}, predecessor=1)
        result = self.server.exchange(A, 0, [hashed(first), hashed(second)])
        self.assertEqual(result[0]["failure_code"], "HABIT_HISTORY_IMMUTABLE")
        self.assertEqual(result[1]["status"], "accepted")
        self.assertEqual([r["per_key_results"][0]["causal_disposition"] for r in result], ["no_effect", "no_effect"])
        self.assertFalse(self.server.snapshot()["anchors"])

    def test_future_cross_object_missing_predecessor_and_whole_batch_failure_are_zero_write(self):
        first = mutation(self.category, patch={"name": "A"})
        future = mutation(self.category, 2, patch={"name": "B"}, predecessor=3)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"):
            self.server.exchange(A, 0, [hashed(first), hashed(future)])
        self.assertEqual(self.server.snapshot(), before)
        self.send(first)
        second_category = copy.deepcopy(self.category)
        second_category["target_id"] = second_category["fact"]["id"] = "33333333-3333-4333-8333-333333333333"
        self.server.seed(second_category)
        wrong = mutation(second_category, 2, patch={"name": "B"}, predecessor=1)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"):
            self.send(wrong)
        self.assertEqual(self.server.snapshot(), before)

    def test_gap_replay_mismatch_transport_fence_and_infrastructure_rollback(self):
        first = mutation(self.category, patch={"name": "A"})
        before = self.server.snapshot()
        with self.assertRaisesRegex(RuntimeError, "infrastructure"):
            self.send(first, rollback_before_commit=True)
        self.assertEqual(self.server.snapshot(), before)
        with self.assertRaisesRegex(ValueError, "SYNC_CLIENT_SEQUENCE_GAP"):
            self.send(mutation(self.category, 2, patch={"name": "gap"}))
        self.assertEqual(self.server.snapshot(), before)
        self.send(first)
        operation = str(uuid.uuid4())
        fence = self.server.fence(A, operation, 0)
        self.assertEqual(self.server.fence(A, operation, 0), fence)
        self.assertEqual(fence["next_client_sequence"], 2)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_TRANSPORT_GENERATION_MISMATCH"):
            self.send(mutation(self.category, 2, patch={"name": "迟到"}))
        self.assertEqual(self.server.snapshot(), before)
        altered = copy.deepcopy(first)
        altered["payload"]["patch"]["name"] = "伪造重放"
        with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_REPLAY_MISMATCH"):
            self.server.exchange(A, 1, [hashed(altered)])
        after = self.server.snapshot()
        self.assertEqual(after["facts"], before["facts"])
        self.assertEqual(after["receipts"], before["receipts"])
        self.assertEqual(after["devices"][0][-1], 1)

    def test_delete_then_day_181_edit_uses_recovery_snapshot_without_resurrection(self):
        self.send(mutation(self.category, operation="delete"), B)
        with self.server.connect() as db:
            db.execute("UPDATE facts SET fact=NULL WHERE target='category'")
        result = self.send(mutation(self.category, patch={"name": "保留下来的编辑"}))
        self.assertEqual(result["status"], "conflict")
        fact = self.server.snapshot()["facts"][0]
        self.assertIsNone(fact[3])
        self.assertEqual(fact[4], 1)
        conflict = json.loads(self.server.snapshot()["conflicts"][0][-1])
        self.assertEqual(conflict["recovery_snapshot"]["name"], "保留下来的编辑")

    def test_ack_apply_crash_window_and_duplicate_do_not_publish_early_or_recreate_gate(self):
        m = mutation(self.category, patch={"name": "A"})
        result = self.send(m)
        local = ApplyStore(self.path / "local.db", device_id=A)
        local.enqueue(m)
        before = local.snapshot()
        with self.assertRaisesRegex(RuntimeError, "ack_rollback"):
            local.acknowledge(result, rollback=True)
        self.assertEqual(local.snapshot(), before)
        local.acknowledge(result)
        self.assertTrue(local.snapshot()["gates"])
        self.assertFalse(local.snapshot()["applied"])
        self.assertEqual(local.snapshot()["state"], [(0, 0, 0)])
        with self.assertRaisesRegex(ValueError, "SYNC_ACK_WATERMARK_INVALID"):
            local.flush_ack(1, 1)
        with self.assertRaisesRegex(ValueError, "SYNC_ENTITY_SYNC_EFFECT_PENDING"):
            local.enqueue(mutation(self.category, 2, patch={"name": "B"}))
        group_id, sequence, raw = self.server.snapshot()["groups"][0]
        before = local.snapshot()
        with self.assertRaisesRegex(RuntimeError, "apply_rollback"):
            local.apply(group_id, sequence, json.loads(raw), rollback=True)
        self.assertEqual(local.snapshot(), before)
        reopened = ApplyStore(self.path / "local.db", device_id=A)
        reopened.apply(group_id, sequence, json.loads(raw))
        duplicate = self.send(m)
        reopened.acknowledge(duplicate)
        self.assertFalse(reopened.snapshot()["gates"])
        self.assertEqual(len(reopened.snapshot()["applied"]), 1)
        before = reopened.snapshot()
        reopened.flush_ack(1, 1)
        after = reopened.snapshot()
        self.assertEqual(after["state"], [(1, 1, 1)])
        self.assertEqual(after["applied"], before["applied"])
        with self.assertRaisesRegex(ValueError, "SYNC_ACK_WATERMARK_INVALID"):
            reopened.flush_ack(1, 0)

    def test_no_effect_receipt_is_pinned_by_pending_and_rejected_intent_survives_restart(self):
        habit = samples()["habit"]
        habit["fact"]["first_check_in_at"] = FIXED_TIME
        self.server.seed(habit)
        a = mutation(habit, patch={"target_count_hundredths": 999, "unit": "页"})
        b = mutation(habit, 2, patch={"target_count_hundredths": habit["fact"]["target_count_hundredths"], "unit": habit["fact"]["unit"]}, predecessor=1)
        local = ApplyStore(self.path / "local.db", device_id=A)
        local.enqueue(a)
        local.enqueue(b)
        local.acknowledge(self.send(a))
        self.assertEqual(local.snapshot()["state"], [(0, 0, 0)])
        self.assertEqual(json.loads(local.snapshot()["failed"][0][1]), a)
        reopened = ApplyStore(self.path / "local.db", device_id=A)
        self.assertEqual(reopened.snapshot(), local.snapshot())
        reopened.acknowledge(self.send(b))
        self.assertEqual(reopened.snapshot()["state"], [(2, 0, 0)])
        self.assertEqual(len(reopened.snapshot()["failed"]), 1)

    def test_wire_union_rejects_mixed_ack_bootstrap_terminal_and_sensitive_keys(self):
        ack = {"protocol_version": 1, "device_id": A, "sync_transport_generation": 0, "mode": "ack_only",
               "cursor": None, "acknowledged_client_sequence_through": 0, "upload_mutations": [], "download_limit": 0}
        validate_schema("sync/sync_exchange_request.schema.json", ack)
        for key, value in (("cursor", "A" * 16), ("download_limit", 1), ("account_id", B),
                           ("acknowledged_client_sequence_through", None)):
            with self.assertRaises(ValueError):
                validate_schema("sync/sync_exchange_request.schema.json", {**ack, key: value})
        ordinary = {**ack, "mode": "normal", "cursor": "A" * 16, "download_limit": 1}
        validate_schema("sync/sync_exchange_request.schema.json", ordinary)
        for bad_cursor in (None, "A" * 15 + "=", "A" * 17, "A" * 17 + "B"):
            with self.assertRaises(ValueError):
                validate_schema("sync/sync_exchange_request.schema.json", {**ordinary, "cursor": bad_cursor})
        m = mutation(self.category, patch={"name": "A"})
        for key, value in (("account_id", B), ("payload_hash", "0" * 64), ("protocol_version", 2),
                           ("conflict_recovery_snapshot", None), ("import_source_epoch", 0)):
            with self.assertRaises(ValueError):
                validate_mutation({**m, key: value}, mutation_hash({**m, key: value}))


if __name__ == "__main__":
    unittest.main()
