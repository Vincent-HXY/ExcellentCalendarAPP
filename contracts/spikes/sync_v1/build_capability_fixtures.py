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
    # Review regressions use complete facts and the actual versioned readers.
    samples = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]
    habit = next(row for row in samples.values() if row["target_type"] == "habit")["fact"]
    for text, valid in [("2026-09-06", True), ("0000-01-01", False), ("0001-01-01", True),
                        ("9999-12-31", True), ("2024-02-29", True), ("2026-02-29", False)]:
        add("review_date_" + text, "sync/v1/habit_fact.schema.json", {**habit, "start_date": text}, valid)
    event = next(row for row in samples.values() if row["target_type"] == "event")["fact"]
    for field in ("completed_at", "created_at", "updated_at", "deleted_at", "start_at"):
        for value, valid in [("2026-09-06T00:00:00Z", True), ("2026-09-06T08:00:00+08:00", False),
                             ("0000-01-01T00:00:00Z", False)]:
            add("review_utc_" + field + "_" + value, "sync/v1/event_fact.schema.json", {**event, field: value}, valid)
    from audit_fixture import reminder, notification
    parent = reminder(C, "open-reminder")
    parent.update(status="cancelled", is_enabled=False, last_cancellation_reason="source_migrated", last_cancelled_at="2026-09-06T07:00:00Z")
    public_parent = {key: value for key, value in parent.items() if key not in {"source", "recovery_batch_id"}}
    for schema, valid in [("storage/v6/reminder_record.schema.json", True), ("native_v3/business_compat/reminder/reminder_response.schema.json", True),
                           ("reminder/reminder_response.schema.json", False)]:
        add("review_retired_" + schema, schema, parent if schema.startswith("storage/") else public_parent, valid)
    attempt = notification(parent, "prepared-attempt")
    attempt.update(status="abandoned", abandon_reason="source_migrated", finalized_at="2026-09-06T07:00:00Z")
    for schema, valid in [("notification/notification_response.schema.json", False),
                          ("native_v3/business_compat/notification/notification_response.schema.json", True)]:
        add("review_retired_" + schema, schema, attempt, valid)
    for status in ("prepared", "sent", "cancelled"):
        add("review_retired_notification_illegal_" + status, "native_v3/business_compat/notification/notification_response.schema.json",
            {**attempt, "status": status}, False)
    native = {"workspace_id": A, "runtime_instance_id": B, "conflict_id": C, "disposition": "queued",
        "status": "resolving", "conflict_version": 1, "native_state_revision": 7}
    schema = "native_v3/internal_payloads/sync_conflict_resolve_response_payload.schema.json"
    add("review_native_revision", schema, native, True)
    add("review_wrong_revision_owner", schema, {**{k: v for k, v in native.items() if k != "native_state_revision"}, "status_revision": 7}, False)
    query = {"range_start_date": "2026-09-06", "range_end_date": "2026-09-07", "workspace_timezone": None, "device_timezone": "America/Los_Angeles"}
    schema = "native_v3/internal_payloads/calendar_range_summary_request_payload.schema.json"
    add("review_two_timezone_inputs", schema, query, True)
    add("review_workspace_timezone_cannot_be_overridden", schema, {**query, "workspace_timezone": "Asia/Shanghai"}, False)
    add("review_single_timezone_forbidden", schema, {"range_start_date": query["range_start_date"], "range_end_date": query["range_end_date"], "timezone": "UTC"}, False)
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
