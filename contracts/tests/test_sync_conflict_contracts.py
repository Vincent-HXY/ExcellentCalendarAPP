"""Public UI choices and private terminal outcomes are distinct contracts."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_conflict_contracts import derive
from domain_reference import validate_schema

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
NOW = "2026-09-05T00:00:00Z"


class ConflictContractTests(unittest.TestCase):
    def setUp(self):
        self.samples = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf-8"))["samples"]
        self.route = {"workspace_id": A, "expected_active_route_revision": 0}
        self.response_route = {"workspace_id": A, "runtime_instance_id": B, "active_route_revision": 0}

    def invalid(self, path, value):
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            validate_schema("sync/" + path + ".schema.json", value)

    def valid(self, path, value):
        validate_schema("sync/" + path + ".schema.json", value)

    def test_generator_and_all_four_resolution_shapes(self):
        self.assertEqual(len(derive()), 24)
        for path, expected in derive().items():
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), expected)
        for mode in ("keep_local", "keep_remote", "per_field", "manual_edit"):
            value = {**self.route, "conflict_id": B, "expected_conflict_version": 1,
                "resolution": {"mode": mode, "group_choices": [{"key": {"target_type": "category", "target_id": A, "merge_key": "name"}, "source": "local"}] if mode == "per_field" else [],
                    "manual_candidate": self.samples["category"] if mode == "manual_edit" else None}}
            self.valid("resolve_sync_conflict_request", value)
            bad = copy.deepcopy(value)
            bad["resolution"]["mode"] = "merge_arbitrary"
            self.invalid("resolve_sync_conflict_request", bad)
            bad = {**value, "client_sequence": 1}
            self.invalid("resolve_sync_conflict_request", bad)

    def test_resolution_choice_branch_cannot_carry_unused_input(self):
        value = {**self.route, "conflict_id": B, "expected_conflict_version": 1,
            "resolution": {"mode": "keep_remote", "group_choices": [], "manual_candidate": self.samples["category"]}}
        self.invalid("resolve_sync_conflict_request", value)
        value["resolution"] = {"mode": "per_field", "group_choices": [], "manual_candidate": None}
        self.invalid("resolve_sync_conflict_request", value)
        value["resolution"] = {"mode": "manual_edit", "group_choices": [], "manual_candidate": self.samples["account_profile"]}
        self.invalid("resolve_sync_conflict_request", value)

    def test_public_resolution_queue_never_claims_server_resolved(self):
        value = {**self.response_route, "conflict_id": B, "disposition": "queued", "status": "resolving", "conflict_version": 1, "status_revision": 2}
        self.valid("sync_conflict_resolution_response", value)
        self.invalid("sync_conflict_resolution_response", {**value, "status": "resolved"})
        self.invalid("sync_conflict_resolution_response", {**value, "effect_change_group_id": A})

    def test_failed_preferences_are_supported_without_enabling_profile_upload(self):
        sample = self.samples["user_preferences"]
        summary = {"failed_change_id": B, "failed_change_revision": 1, "target_type": sample["target_type"], "target_id": sample["target_id"],
            "created_at": NOW, "failure": {"code": "SYNC_CHANGE_GROUP_TOO_LARGE", "context": None}, "state": "active"}
        value = {**self.response_route, "summary": summary, "local_candidate": sample, "manual_draft": None,
            "server_baseline": {"kind": "unavailable"}, "can_edit_as_new": True, "can_discard": True}
        self.valid("sync_failed_local_change_detail", value)
        self.invalid("sync_failed_local_change_detail", {**value, "local_candidate": self.samples["account_profile"]})
        self.invalid("sync_failed_local_change_detail", {**value, "retry_original_sequence": True})

    def test_failed_public_context_cannot_echo_transport_or_raw_payload(self):
        self.valid("sync_saved_intent_failure", {"code": "SYNC_CHANGE_GROUP_TOO_LARGE", "context": None})
        self.invalid("sync_saved_intent_failure", {"code": "SYNC_CHANGE_GROUP_TOO_LARGE", "context": {"raw_mutation": {}, "client_sequence": 1}})
        request = {**self.route, "failed_change_id": B, "expected_failed_change_revision": 1}
        self.valid("discard_sync_failed_local_change_request", request)
        self.invalid("discard_sync_failed_local_change_request", {**request, "upload": True})

    def test_resolved_summary_requires_both_retention_times(self):
        summary = {"conflict_id": B, "conflict_version": 1, "target_type": "category", "target_id": A, "source_device_id": A,
            "received_at": NOW, "conflicting_merge_keys": [{"target_type": "category", "target_id": A, "merge_key": "name"}],
            "auto_merged_group_count": 0, "status": "resolved", "resolved_at": NOW, "retain_until": "2026-10-05T00:00:00Z"}
        self.valid("backend_sync_conflict_summary", summary)
        self.invalid("backend_sync_conflict_summary", {**summary, "retain_until": None})
        self.invalid("backend_sync_conflict_summary", {**summary, "status": "resolving"})


if __name__ == "__main__":
    unittest.main()
