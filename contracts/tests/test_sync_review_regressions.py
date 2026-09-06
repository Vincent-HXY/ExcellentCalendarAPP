"""Review 5d8fb0a: real DDL, unchanged HTTP bytes and versioned owner boundaries."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
import test_sync_conflict_resolution as conflicts
from build_sync_storage_contract import derive
from capability_reference import registries, check_native_request, check_native_result, check_public_request, resolve_mixed_query_timezones
from domain_reference import validate_schema
from import_staging_reference import build_initial_batch
from protocol_reference import encode, digest, mutation_hash
from test_sync_protocol import A, B, samples, mutation

C = "33333333-3333-4333-8333-333333333333"
GUEST = {"workspace_id": A, "workspace_kind": "local", "runtime_instance_id": C, "device_id": None, "session_generation": None}


class ReviewRegressionTests(unittest.TestCase):
    def setUp(self):
        self.ddl = derive()
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        # Exercise the exact formal table, not a permissive projection. Foreign
        # workspace guards are tested by the full migration suite separately.
        self.db.execute(self.ddl["new_tables"]["sync_outbox"])

    def persist(self, value, route):
        codec = self.ddl["payload_codecs"]["sync_outbox"]["columns"]["payload_json"]
        validate_schema(codec, value)
        self.db.execute("INSERT INTO sync_outbox VALUES(" + ",".join(["?"] * 16) + ")", (
            value["mutation_id"], B, value["client_sequence"], value["target_type"], value["target_id"],
            value["operation_type"], value["base_entity_version"], encode(value["causal_predecessors"]),
            1, encode(value), mutation_hash(value), route, "pending", 0, None, value["created_at"]))
        return json.loads(self.db.execute("SELECT payload_json FROM sync_outbox WHERE mutation_id=?", (value["mutation_id"],)).fetchone()[0])

    def test_import_controls_items_and_ordinary_mutations_fit_exact_outbox(self):
        batch = build_initial_batch(A, C, 0, [samples()["category"]])
        self.assertEqual((batch[0]["operation_type"], batch[-1]["operation_type"]), ("import_begin", "import_commit"))
        for value in batch:
            validate_schema("sync/sync_mutation.schema.json", value)
            self.assertEqual(self.persist(value, "import_range"), value)
        self.persist(mutation(samples()["category"], sequence=len(batch) + 1, patch={"name": "ordinary"}), "exchange")
        for route in ("exchange", "conflict_resolution"):
            self.db.execute("DELETE FROM sync_outbox")
            with self.assertRaises(sqlite3.IntegrityError):
                self.persist(batch[0], route)

    def test_resolution_roundtrip_uses_exact_http_request_and_response(self):
        helper = conflicts.ConflictResolutionTests()
        helper.setUp()
        self.addCleanup(helper.doCleanups)
        identifier = helper.competing()
        value = helper.resolve_mutation(identifier)
        persisted = self.persist(value, "conflict_resolution")
        validate_schema("sync/sync_failed_change_mutation.schema.json", persisted)
        wire = {"protocol_version": 1, "device_id": B, "sync_transport_generation": 0,
            "mutation": persisted, "payload_hash": mutation_hash(persisted)}
        validate_schema("sync/backend_resolve_sync_conflict_request.schema.json", wire)
        binding = {**GUEST, "workspace_kind": "account", "device_id": B, "session_generation": 0}
        common = {"workspace_id": A, "runtime_instance_id": C, "device_id": B, "session_generation": 0,
            "sync_transport_generation": 0, "prepared_exchange_id": A, "route": "conflict_resolution"}
        prepared = {**common, "run_intent": "normal", "request_hash": digest(wire), "wire_request": wire,
            "logout_operation_id": None, "pull_gate_revision": None}
        result = {"ok": True, "data": {"binding": binding, "payload": prepared}, "error": None,
            "contract_version": 3, "request_id": "review"}
        check_native_result("internal", "sync.prepare_upload_batch", result, binding)
        self.assertEqual(encode(result["data"]["payload"]["wire_request"]), encode(wire))
        response = helper.resolve(wire["mutation"])
        ack = {**common, "reported_acknowledged_client_sequence_through": None, "response": response}
        check_native_request("sync.acknowledge_upload", {"binding": binding, "payload": ack}, binding)
        self.assertEqual(response["result"]["receipt"]["client_sequence"], value["client_sequence"])
        self.assertNotIn("results", response)
        for changes in ({"route": "exchange"}, {"reported_acknowledged_client_sequence_through": 2}):
            with self.assertRaises(ValueError):
                check_native_request("sync.acknowledge_upload", {"binding": binding, "payload": {**ack, **changes}}, binding)
        self.db.execute("DELETE FROM sync_outbox")
        with self.assertRaises(sqlite3.IntegrityError):
            self.persist(value, "exchange")

    def test_activate_target_uses_current_revision_without_current_identity_equality(self):
        route = {"route_state": "ready", "active_workspace_id": A, "active_route_revision": 7}
        request = {"workspace_id": B, "expected_active_route_revision": 7}
        check_public_request("workspace.activate", request, route)
        with self.assertRaisesRegex(ValueError, "WORKSPACE_SWITCH_CONFLICT"):
            check_public_request("workspace.activate", {**request, "expected_active_route_revision": 6}, route)
        with self.assertRaisesRegex(ValueError, "WORKSPACE_SWITCH_CONFLICT"):
            check_public_request("sync.run_now", request, route)

    def test_mixed_queries_resolve_persisted_workspace_axis_and_os_device_axis(self):
        self.db.execute(self.ddl["new_tables"]["workspace_preferences"])
        self.db.execute("INSERT INTO workspace_preferences VALUES(1,'Asia/Shanghai','teal','[\"popup\"]',0,1)")
        request = {"binding": GUEST, "payload": {"range_start_date": "2026-09-06", "range_end_date": "2026-09-07",
            "workspace_timezone": None, "device_timezone": "America/Los_Angeles"}}
        expected = {"workspace_timezone": "Asia/Shanghai", "device_timezone": "America/Los_Angeles"}
        self.assertEqual(resolve_mixed_query_timezones(self.db, "calendar.range_summary", request, GUEST), expected)
        bad = copy.deepcopy(request)
        bad["payload"]["workspace_timezone"] = "UTC"
        with self.assertRaises(ValueError):
            resolve_mixed_query_timezones(self.db, "calendar.range_summary", bad, GUEST)
        bad = copy.deepcopy(request)
        bad["payload"]["device_timezone"] = "Invalid/ReviewZone"
        with self.assertRaisesRegex(ValueError, "TIMEZONE_ID_INVALID"):
            resolve_mixed_query_timezones(self.db, "calendar.range_summary", bad, GUEST)
        for name in ("calendar.range_summary", "calendar.list_day_items", "search.query"):
            entry = registries()[1]["calls"][name]
            payload_path = ROOT / "contracts/native_v3/internal_payloads" / (name.replace(".", "_") + "_request_payload.schema.json")
            schema = json.loads(payload_path.read_text())
            self.assertNotIn("timezone", schema["properties"])
            self.assertTrue({"workspace_timezone", "device_timezone"} <= set(schema["required"]))

    def test_all_new_native_payloads_are_explicitly_planned(self):
        from build_sync_domain_contracts import DATE_TIME, derive as domain
        from build_sync_protocol_contracts import derive as protocol
        primitive, before = copy.deepcopy(DATE_TIME), copy.deepcopy(protocol())
        first, second = copy.deepcopy(domain()), copy.deepcopy(domain())
        self.assertEqual(first, second)
        self.assertEqual(DATE_TIME, primitive)
        self.assertEqual(protocol(), before)
        for path in (ROOT / "contracts/native_v3/internal_payloads").glob("*.schema.json"):
            value = json.loads(path.read_text())
            self.assertEqual(value["x-implementation-status"], "planned", path.name)
