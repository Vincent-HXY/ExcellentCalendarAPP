"""Fixed adversarial wire examples; expectations are independent of generators."""
import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"


def derive():
    cases = []
    def add(name, schema, value, valid, family="FX-CROSS-LAYER"):
        cases.append({"id": "FX-CAPABILITY-" + name, "family": family, "rule_anchor": "cloud-sync-02/5,6.1,8.3-8.4",
            "schema": schema, "input": copy.deepcopy(value), "expected": {"schema_valid": valid}})
    binding = {"workspace_id": A, "workspace_kind": "local", "runtime_instance_id": B, "device_id": None, "session_generation": None}
    schema = "native_v3/internal/runtime_binding.schema.json"
    add("guest_binding", schema, binding, True, "FX-WORKSPACE")
    for field in binding:
        add("binding_missing_" + field, schema, {k: v for k, v in binding.items() if k != field}, False, "FX-WORKSPACE")
    add("guest_device_forbidden", schema, {**binding, "device_id": C}, False, "FX-WORKSPACE")
    account = {**binding, "workspace_kind": "account", "device_id": C, "session_generation": 9007199254740991}
    add("account_max", schema, account, True, "FX-COUNTER")
    for name, value in (("overflow", 9007199254740992), ("negative", -1), ("string", "1"), ("bool", True), ("fraction", 1.5), ("null", None)):
        add("account_generation_" + name, schema, {**account, "session_generation": value}, False, "FX-COUNTER")
    add("account_no_device", schema, {**account, "device_id": None}, False, "FX-WORKSPACE")
    run = {"workspace_id": A, "expected_active_route_revision": 0}
    schema = "sync/run_sync_now_request.schema.json"
    add("run_now", schema, run, True)
    for field in ("client_sequence", "cursor", "run_intent", "logout_operation_id", "refresh_token"):
        add("run_forbids_" + field, schema, {**run, field: "forbidden"}, False)
    response = {"ok": True, "data": {}, "error": None, "contract_version": 3, "request_id": "fixed-test"}
    schema = "native_v3/common/native_result.schema.json"
    add("native_result_v3", schema, response, True)
    add("native_result_v2_rejected", schema, {**response, "contract_version": 2}, False)
    add("native_result_failure_has_no_error", schema, {**response, "ok": False}, False)
    tap = {"notification_id": A, "delivery_id": B, "delivery_attempt_id": C, "kind": "reminder", "reminder_id": C,
        "recovery_batch_id": None, "target_type": "event", "target_id": C, "occurrence_key": None, "route": None,
        "opened_at": "2026-09-05T00:00:00Z", "workspace_id": A, "workspace_kind": "local"}
    schema = "native_v3/notification/notification_tap_payload_v6_writer.schema.json"
    add("tap_v6", schema, tap, True, "FX-RETENTION-NOTIFY")
    for field in ("workspace_id", "workspace_kind"):
        add("tap_v6_missing_" + field, schema, {k: v for k, v in tap.items() if k != field}, False, "FX-RETENTION-NOTIFY")
    add("tap_v6_unknown_kind", schema, {**tap, "workspace_kind": "shared"}, False, "FX-RETENTION-NOTIFY")
    return {"fixture_version": 1, "scope": "planned Schema boundary examples; not product or four-language evidence", "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "contracts/fixtures/sync/v1/capability_vectors.json"
    value = derive()
    if args.check:
        assert json.loads(path.read_text(encoding="utf-8")) == value
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"fixed_capability_cases": len(value["cases"])}))
