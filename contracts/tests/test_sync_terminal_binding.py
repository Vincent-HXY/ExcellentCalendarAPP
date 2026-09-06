"""Terminal replies cannot omit import publication evidence or contradict receipts."""
import copy
from pathlib import Path
import tempfile
import unittest

from build_target_fixtures import build
from build_owned_graph_fixtures import make_mutation
from domain_reference import definitions, validate_schema
from identity_reference import lineage_id
from protocol_reference import (ApplyStore, ProtocolStore, mutation_hash, validate_terminal_for_mutation)

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"


def commit_pair():
    counts = {name: 0 for name in definitions()[1]["targets"] if name not in {"user_preferences", "account_profile"}}
    manifest = {"source_workspace_id": A, "source_epoch": 0, "source_snapshot_hash": "0" * 64,
        "target_counts": counts, "portable_preferences_count": 0, "total_item_count": 0,
        "total_canonical_bytes": 0, "mapping_digest": "1" * 64, "manifest_hash": "2" * 64}
    mutation = {"protocol_version": 1, "mutation_id": C, "client_sequence": 2, "target_type": "workspace_import",
        "target_id": B, "operation_type": "import_commit", "base_entity_version": 1, "causal_predecessors": [],
        "import_lineage_id": lineage_id(C, A, 0), "import_batch_id": B, "import_source_workspace_id": A, "import_source_epoch": 0,
        "import_item_ordinal": None, "import_manifest_hash": manifest["manifest_hash"], "predecessor_batch_id": None,
        "payload": {"manifest": manifest, "takeover_reason": None, "range_close_proof_id": None},
        "conflict_recovery_snapshot": None, "created_at": "2026-09-05T01:00:00Z"}
    result = {"status": "accepted", "receipt": {"receipt_id": C, "device_id": A, "client_sequence": 2,
            "mutation_id": C, "payload_hash": mutation_hash(mutation)},
        "per_key_results": [], "effect": {"effect_change_group_id": C, "effect_group_last_server_sequence": 9},
        "conflict_ids": [], "import_batch_id": B, "import_stage": "server_confirmed",
        "import_disposition": "server_confirmed", "error": None,
        "publish_group_id": C, "commit_server_sequence": 9, "canonical_digest": "3" * 64, "import_revision": 2}
    return mutation, result


class TerminalBindingTests(unittest.TestCase):
    def test_resolution_domain_error_cannot_be_used_by_ordinary_or_import_routes(self):
        sample = build()["samples"]["category"]
        mutation = make_mutation(sample, 1, patch={"name": "changed"})
        result = {"status": "rejected", "receipt": {"receipt_id": A, "device_id": A, "client_sequence": 1,
            "mutation_id": mutation["mutation_id"], "payload_hash": mutation_hash(mutation)}, "effect": None,
            "per_key_results": [{"key": {"target_type": "category", "target_id": sample["target_id"], "merge_key": "name"},
                "causal_disposition": "no_effect", "resulting_field_version": None, "effective_prior_sequence": None, "effective_prior_version": 1}],
            "conflict_ids": [], "failure_code": "SYNC_RESOLUTION_CANDIDATE_INVALID", "failure_context": None, "import_batch_id": None, "import_stage": None}
        validate_schema("sync/sync_upload_result.schema.json", result)
        with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"):
            validate_terminal_for_mutation(result, mutation)
        with self.assertRaises(ValueError):
            validate_schema("sync/sync_upload_result.schema.json", {**result, "import_batch_id": B, "import_stage": "repair_required"})

    def test_commit_success_requires_exact_publication_identity_and_all_metadata(self):
        mutation, result = commit_pair()
        validate_terminal_for_mutation(result, mutation)
        for field in ("import_disposition", "publish_group_id", "commit_server_sequence", "canonical_digest", "import_revision"):
            missing = copy.deepcopy(result); missing.pop(field)
            with self.assertRaises(ValueError): validate_terminal_for_mutation(missing, mutation)
        for name, value in (("publish_group_id", A), ("commit_server_sequence", 8), ("import_batch_id", A), ("import_stage", "publish_applied")):
            with self.assertRaises(ValueError): validate_terminal_for_mutation({**result, name: value}, mutation)

    def test_commit_rejection_is_repair_with_typed_error_and_monotone_next_revision(self):
        mutation, accepted = commit_pair()
        rejected = {name: accepted[name] for name in ("receipt", "per_key_results", "import_batch_id")}
        rejected.update(status="rejected", effect=None, conflict_ids=[], import_stage="repair_required", import_disposition="repair_required",
                        error={"code": "IMPORT_REFERENCE_INVALID", "context": None}, next_revision=2)
        validate_terminal_for_mutation(rejected, mutation)
        for name, value in (("next_revision", 1), ("effect", accepted["effect"]), ("error", {"code": "API_UNAUTHENTICATED", "context": None}),
                            ("import_disposition", "server_confirmed")):
            with self.assertRaises(ValueError): validate_terminal_for_mutation({**rejected, name: value}, mutation)
        duplicate = {"status": "duplicate", "original_status": "rejected", "original_result": rejected,
                     **{name: rejected["receipt"][name] for name in ("client_sequence", "mutation_id", "payload_hash")}}
        self.assertEqual(validate_terminal_for_mutation(duplicate, mutation), rejected)

    def test_import_errors_cannot_claim_an_ordinary_user_write_or_published_staging(self):
        mutation, result = commit_pair()
        staged = {"status": "staged", "receipt": result["receipt"], "effect": None, "per_key_results": [], "conflict_ids": [],
            "failure_code": None, "failure_context": None, "import_batch_id": B, "import_stage": "server_staging"}
        validate_schema("sync/sync_upload_result.schema.json", staged)
        with self.assertRaises(ValueError): validate_terminal_for_mutation(staged, mutation)
        with self.assertRaises(ValueError): validate_schema("sync/sync_upload_result.schema.json", {**staged, "import_stage": "server_confirmed"})
        bad = {**staged, "status": "rejected", "failure_code": "IMPORT_REFERENCE_INVALID", "import_batch_id": None, "import_stage": None}
        with self.assertRaises(ValueError): validate_schema("sync/sync_upload_result.schema.json", bad)

    def test_wrong_duplicate_wrapper_and_key_effect_are_rejected_even_after_ack(self):
        with tempfile.TemporaryDirectory() as directory:
            sample = build()["samples"]["category"]
            mutation = make_mutation(sample, 1, patch={"name": "changed"})
            server = ProtocolStore(Path(directory) / "server.sqlite"); server.register(A); server.seed(sample)
            result = server.exchange(A, 0, [{"mutation": mutation, "payload_hash": mutation_hash(mutation)}])[0]
            local = ApplyStore(Path(directory) / "local.sqlite", device_id=A); local.enqueue(mutation)
            before = local.snapshot()
            missing = copy.deepcopy(result); missing["per_key_results"] = []
            with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"): local.acknowledge(missing)
            self.assertEqual(local.snapshot(), before)
            local.acknowledge(result); acknowledged = local.snapshot()
            bad = {"status": "duplicate", "original_status": "accepted", "original_result": result, "client_sequence": 2,
                   "mutation_id": mutation["mutation_id"], "payload_hash": mutation_hash(mutation)}
            with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_REPLAY_MISMATCH"): local.acknowledge(bad)
            self.assertEqual(local.snapshot(), acknowledged)

    def test_local_receipt_cannot_cross_device_or_ack_a_different_effect_sequence(self):
        with tempfile.TemporaryDirectory() as directory:
            sample = build()["samples"]["category"]
            mutation = make_mutation(sample, 1, patch={"name": "changed"})
            server = ProtocolStore(Path(directory) / "server.sqlite"); server.register(A); server.seed(sample)
            result = server.exchange(A, 0, [{"mutation": mutation, "payload_hash": mutation_hash(mutation)}])[0]
            path = Path(directory) / "local.sqlite"
            local = ApplyStore(path, device_id=A); local.enqueue(mutation)
            before = local.snapshot()
            foreign = copy.deepcopy(result); foreign["receipt"]["device_id"] = B
            with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"): local.acknowledge(foreign)
            with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"): ApplyStore(path, device_id=B)
            self.assertEqual(local.snapshot(), before)
            local.acknowledge(result)
            group_id, sequence, raw = server.snapshot()["groups"][0]
            import json
            before = local.snapshot()
            with self.assertRaisesRegex(ValueError, "SYNC_APPLY_FAILED"): local.apply(group_id, sequence + 1, json.loads(raw))
            self.assertEqual(local.snapshot(), before)
            local.apply(group_id, sequence, json.loads(raw))
            self.assertEqual(local.snapshot()["state"], [(1, 0, sequence)])


if __name__ == "__main__": unittest.main()
