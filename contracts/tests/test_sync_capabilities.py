"""Adversarial boundary and legacy isolation tests for the planned capability graph."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
    str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_domain_contracts import CONTRACTS, BASE, yaml
from build_sync_capability_graph import derive as graph, BLOCKED
from build_sync_native_contracts import derive as native
from build_native_v3_business_contracts import derive as business
from build_sync_registry_revisions import derive as registries, extension, REVISION_PATHS
from capability_reference import (check_public_request, check_native_request, check_native_result,
    check_binary_open_arguments, resolve_notification_workspace)
from domain_reference import validate_schema
from validate_sync_v1 import validate_baseline, read_json, walk

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"
D = "44444444-4444-4444-8444-444444444444"
ROUTE = {"route_state": "ready", "active_workspace_id": A, "active_route_revision": 7}
GUEST = {"workspace_id": A, "workspace_kind": "local", "runtime_instance_id": B, "device_id": None, "session_generation": None}


class CapabilityTests(unittest.TestCase):
    def invalid(self, path, value):
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            validate_schema(path, value)

    def test_exact_generated_definitions_and_root_links(self):
        for path, expected in {**business(), **native(), **graph(), **registries()}.items():
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(actual, expected, str(path))
        for path in REVISION_PATHS:
            self.assertEqual(yaml.safe_load((CONTRACTS / path).read_text(encoding="utf-8"))["planned_revisions"], extension(path))

    def test_original_220_contracts_still_match_historical_projection(self):
        baseline = read_json(CONTRACTS / "sync/sync_v1_baseline.json")
        self.assertEqual(validate_baseline(baseline), 220)

    def test_all_edges_and_schema_paths_are_closed_without_fake_implementation(self):
        definitions = graph()
        methods = definitions[CONTRACTS / "native_v3/method_channels.yaml"]["methods"]
        calls = definitions[CONTRACTS / "native_v3/native_calls.yaml"]["calls"]
        backend = yaml.safe_load((CONTRACTS / "backend_sync_v1/backend_api.yaml").read_text(encoding="utf-8"))["endpoints"]
        old = yaml.safe_load((CONTRACTS / "method_channels.yaml").read_text(encoding="utf-8"))["methods"]
        self.assertTrue(set(old) <= set(methods))
        self.assertTrue({"category.update", "category.delete", "category.restore"} <= set(methods))
        for name, row in methods.items():
            self.assertTrue(set(row["native_calls"]) <= set(calls), name)
            self.assertTrue(set(row["http_operations"]) <= set(backend), name)
            self.assertIn(row["implementation_status"], {"planned", "not_implemented"})
            if name in BLOCKED:
                self.assertEqual(row["release_status"], "blocked")
            for path in (row["request"], row["result"]["data"], row["result"]["envelope"]):
                self.assertTrue((CONTRACTS / path).is_file(), path)
        for name, row in calls.items():
            self.assertEqual(row["visibility"], "internal")
            self.assertEqual(row["implementation_status"], "planned")
            for path in (row["request"], row["result"]["data"], row["result"]["envelope"]):
                self.assertTrue((CONTRACTS / path).is_file(), path)
        for internal in ("runtime.open_workspace", "workspace.import_accept_range_close", "workspace.import_finalize_source_lease", "sync.accept_transport_fence", "sync.begin_bootstrap", "sync.run_local_maintenance"):
            self.assertNotIn(internal, methods)
        self.assertNotIn("runtime.initialize", calls)
        self.assertNotIn("sync.apply", calls)

    def test_typed_legacy_request_requires_exact_workspace_route(self):
        request = {"workspace_id": A, "expected_active_route_revision": 7,
            "payload": {"name": "  分类  ", "description": None, "color": "#39afbd", "icon": None, "sort_order": None}}
        entry = check_public_request("category.create", request, ROUTE)
        for field, value in (("workspace_id", C), ("expected_active_route_revision", 6)):
            with self.assertRaisesRegex(ValueError, "WORKSPACE_SWITCH_CONFLICT"):
                check_public_request("category.create", {**request, field: value}, ROUTE)
        for field in request:
            self.invalid(entry["request"], {k: v for k, v in request.items() if k != field})
        self.invalid(entry["request"], {**request, "account_id": C})
        self.invalid(entry["request"], {**request, "payload": {**request["payload"], "color": 42}})

    def test_one_dto_symbol_cannot_alias_different_public_and_internal_wire_shapes(self):
        generated = graph()
        symbols = {}
        for file, key in (("method_channels.yaml", "methods"), ("native_calls.yaml", "calls")):
            for row in generated[CONTRACTS / "native_v3" / file][key].values():
                for field, name in row["planned_dtos"].items():
                    schema = row["request"] if field.endswith("_request") else row["result"]["data"]
                    identity = (field.split("_")[0], name)
                    self.assertEqual(symbols.setdefault(identity, schema), schema, str(identity))

    def test_device_rename_response_keeps_route_and_revocation_consistency(self):
        device = {"device_id": C, "display_name": "测试手机", "platform": "android", "app_version": "isolated",
            "protocol_version": 1, "receive_reminders": True, "sync_enabled": True, "device_version": 1,
            "status": "active", "registered_at": "2026-09-05T00:00:00Z", "last_seen_at": None, "last_sync_at": None, "revoked_at": None}
        data = {"workspace_id": A, "runtime_instance_id": B, "active_route_revision": 7, "device": device}
        result = {"ok": True, "data": data, "error": None, "contract_version": 3, "request_id": "isolated"}
        check_native_result("public", "device.rename", result)
        for changed in (device, {**data, "runtime_instance_id": None}, {**data, "device": {**device, "status": "revoked"}}):
            with self.assertRaises(ValueError):
                check_native_result("public", "device.rename", {**result, "data": changed})

    def test_v6_delivery_requires_both_nested_workspace_identities(self):
        payload = json.loads((CONTRACTS / "fixtures/habit/prepare_habit_delivery.valid.json").read_text(encoding="utf-8"))
        for field in ("tap_payload", "habit_action_payload"):
            payload[field].update(workspace_id=A, workspace_kind="local")
        data = {"binding": GUEST, "payload": payload}
        result = {"ok": True, "data": data, "error": None, "contract_version": 3, "request_id": "isolated"}
        check_native_result("internal", "reminder.prepare_delivery", result, GUEST)
        for field in ("tap_payload", "habit_action_payload"):
            missing = copy.deepcopy(result)
            del missing["data"]["payload"][field]["workspace_id"]
            with self.assertRaises(ValueError):
                check_native_result("internal", "reminder.prepare_delivery", missing, GUEST)
            wrong = copy.deepcopy(result)
            wrong["data"]["payload"][field]["workspace_id"] = C
            with self.assertRaisesRegex(ValueError, "WORKSPACE_ACCOUNT_MISMATCH"):
                check_native_result("internal", "reminder.prepare_delivery", wrong, GUEST)

    def test_v3_events_preserve_all_existing_capabilities_with_closed_new_envelope(self):
        definitions = graph()
        registry = definitions[CONTRACTS / "native_v3/method_channels.yaml"]["event_channels"]
        old = yaml.safe_load((CONTRACTS / "method_channels.yaml").read_text(encoding="utf-8"))["event_channels"]
        self.assertEqual(set(registry["events"]), set(old) | {"sync.status_changed", "workspace.state_changed"})
        data = {"route_state": "empty", "active_workspace_id": None, "workspace_kind": None, "runtime_instance_id": None,
                "lock_reason": None, "active_route_revision": 0}
        value = {"contract_version": 3, "event_name": "workspace.state_changed", "data": data}
        validate_schema(registry["envelope"], value)
        for patch in ({"contract_version": 2}, {"event_name": "new.unreviewed"}, {"data": {}}, {"refresh_token": "forbidden"}):
            self.invalid(registry["envelope"], {**value, **patch})

    def test_native_runtime_instance_cannot_be_reused_after_switch(self):
        request = {"binding": GUEST, "payload": {"name": "分类", "description": None, "color": "#39AFBD", "icon": None, "sort_order": None}}
        check_native_request("category.create", request, GUEST)
        for field, value in (("workspace_id", C), ("runtime_instance_id", D)):
            with self.assertRaisesRegex(ValueError, "WORKSPACE_ACCOUNT_MISMATCH"):
                check_native_request("category.create", {**request, "binding": {**GUEST, field: value}}, GUEST)
        self.invalid("native_v3/internal/runtime_binding.schema.json", {**GUEST, "device_id": C})
        self.invalid("native_v3/internal/runtime_binding.schema.json", {**GUEST, "workspace_kind": "account"})

    def test_public_never_dispatches_raw_sequence_refresh_or_lifecycle_internal_routes(self):
        for method in ("sync.apply", "auth.refresh_token.read", "runtime.open_workspace", "sync.prepare_upload_batch", "device.register", "future.method"):
            with self.assertRaisesRegex(ValueError, "FEATURE_NOT_IMPLEMENTED"):
                check_public_request(method, {})
        request = {"workspace_id": A, "expected_active_route_revision": 7}
        entry = check_public_request("sync.run_now", request, ROUTE)
        for name in ("client_sequence", "cursor", "run_intent", "logout_operation_id", "sync_transport_generation"):
            self.invalid(entry["request"], {**request, name: 1})

    def test_native_result_version_and_data_error_exclusivity(self):
        result = {"ok": True, "data": {"run_id": C, "disposition": "queued", "status_revision": 1}, "error": None, "contract_version": 3, "request_id": "fixed-contract-case"}
        check_native_result("public", "sync.run_now", result)
        for field, value in (("contract_version", 2), ("data", {}), ("ok", False)):
            with self.assertRaises(ValueError):
                check_native_result("public", "sync.run_now", {**result, field: value})

    def test_category_lifecycle_typed_patch_and_readonly_fields(self):
        request = {"workspace_id": A, "expected_active_route_revision": 7, "id": C, "expected_native_state_revision": 12, "patch": {"name": "更新"}}
        entry = check_public_request("category.update", request, ROUTE)
        for patch in ({}, {"id": D}, {"reorder_revision": 4}, {"created_at": "2026-09-05T00:00:00Z"}, {"name": None}, {"sort_order": 9007199254740992}):
            self.invalid(entry["request"], {**request, "patch": patch})
        check_public_request("category.update", {**request, "patch": {"description": None, "sort_order": 9007199254740991}}, ROUTE)
        check_public_request("category.update", {**request, "patch": {"color": "#39afbd"}}, ROUTE)

    def test_binary_key_is_never_a_json_field_and_embedded_nul_is_valid(self):
        guest = {"workspace_id": A, "workspace_kind": "local", "account_id": None, "device_id": None, "session_generation": None,
            "storage_format_version": 6, "native_contract_version": 3, "storage_directory": "isolated-test-only", "open_mode": "fresh",
            "recovery_seed": None, "fence_evidence": None, "policy_seed": None, "open_operation_id": B}
        check_binary_open_arguments(guest, b"")
        account = {**guest, "workspace_kind": "account", "account_id": C, "device_id": D, "session_generation": 2, "open_mode": "existing"}
        check_binary_open_arguments(account, bytes(range(32)))
        for key in (b"", bytes(31), bytes(33), "encoded-key", None):
            with self.assertRaisesRegex(ValueError, "WORKSPACE_KEY_UNAVAILABLE"):
                check_binary_open_arguments(account, key)
        for field in ("key", "database_key", "key_base64", "receive_reminders"):
            self.invalid("native_v3/internal/open_workspace_request.schema.json", {**account, field: "forbidden"})

    def test_fresh_account_requires_sequence_and_genesis_seed(self):
        account = {"workspace_id": A, "workspace_kind": "account", "account_id": C, "device_id": D, "session_generation": 2,
            "storage_format_version": 6, "native_contract_version": 3, "storage_directory": "isolated-test-only", "open_mode": "fresh",
            "open_operation_id": B, "fresh_reason": "new_device", "fence_evidence": None,
            "recovery_seed": {"sync_transport_generation": 0, "highest_client_sequence": 0, "next_client_sequence": 1,
                "client_confirmed_through": 0, "client_sequence_exhausted": False},
            "policy_seed": {"kind": "genesis", "sync_enabled": True, "sync_policy_revision": 0, "clear_operation_id": None}}
        check_binary_open_arguments(account, bytes(32))
        for field in ("policy_seed", "recovery_seed"):
            self.invalid("native_v3/internal/open_workspace_request.schema.json", {**account, field: None})
        self.invalid("native_v3/internal/open_workspace_request.schema.json", {**account, "fresh_reason": "clear_rebuild"})
        self.invalid("native_v3/internal/open_workspace_request.schema.json", {**account, "policy_seed": {**account["policy_seed"], "sync_enabled": False}})

    def test_notification_legacy_pair_new_writer_and_ambiguous_routing(self):
        payload = {"notification_id": A, "delivery_id": B, "delivery_attempt_id": C, "kind": "reminder", "reminder_id": D,
            "recovery_batch_id": None, "target_type": "event", "target_id": C, "occurrence_key": None, "route": None, "opened_at": "2026-09-05T00:00:00Z"}
        workspaces = [{"workspace_id": A, "workspace_kind": "local", "unlockable": True}, {"workspace_id": B, "workspace_kind": "account", "unlockable": True}]
        self.assertEqual(resolve_notification_workspace(payload, workspaces, [A]), A)
        for candidates in ([], [A, B]):
            with self.assertRaisesRegex(ValueError, "NOTIFICATION_WORKSPACE_AMBIGUOUS"):
                resolve_notification_workspace(payload, workspaces, candidates)
        writer = "native_v3/notification/notification_tap_payload_v6_writer.schema.json"
        self.invalid(writer, payload)
        current = {**payload, "workspace_id": A, "workspace_kind": "local"}
        validate_schema(writer, current)
        self.assertEqual(resolve_notification_workspace(current, workspaces, []), A)
        for field in ("workspace_id", "workspace_kind"):
            with self.assertRaises(ValueError):
                resolve_notification_workspace({**payload, field: current[field]}, workspaces, [A])
        with self.assertRaisesRegex(ValueError, "NOTIFICATION_WORKSPACE_UNAVAILABLE"):
            resolve_notification_workspace({**current, "workspace_id": B, "workspace_kind": "account"}, workspaces[:1], [])

    def test_recurrence_counter_width_has_explicit_new_reader_and_old_reader_protection(self):
        mapping = yaml.safe_load((CONTRACTS / "native_v3/business_compatibility.yaml").read_text(encoding="utf-8"))["schema_mapping"]
        original = json.loads((CONTRACTS / "event/event_response.schema.json").read_text(encoding="utf-8"))
        revised = json.loads((CONTRACTS / mapping["event/event_response.schema.json"]).read_text(encoding="utf-8"))
        self.assertNotIn("maximum", original["properties"]["recurrence_revision"])
        self.assertEqual(revised["properties"]["recurrence_revision"]["maximum"], 9007199254740991)
        from jsonschema import Draft202012Validator
        schema = revised["properties"]["recurrence_revision"]
        for valid in (None, 1, 2147483648, 9007199254740991):
            self.assertTrue(Draft202012Validator(schema).is_valid(valid))
        for invalid in (0, -1, 9007199254740992, "2147483648", 1.5, True):
            self.assertFalse(Draft202012Validator(schema).is_valid(invalid))

    def test_fixed_boundary_fixtures_are_executed_not_just_counted(self):
        from build_capability_fixtures import derive
        data = json.loads((CONTRACTS / "fixtures/sync/v1/capability_vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(data, derive())
        for case in data["cases"]:
            with self.subTest(case=case["id"]):
                if case["expected"]["schema_valid"]:
                    validate_schema(case["schema"], case["input"])
                else:
                    self.invalid(case["schema"], case["input"])


if __name__ == "__main__":
    unittest.main()
