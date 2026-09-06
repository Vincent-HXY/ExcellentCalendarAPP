"""Reviewable fixed shape and lifecycle examples, with explicit validation scope.

Schema-only proof examples do not claim signature verification or saga execution.
Golden decisions are literal expectations, not values produced by the oracle.
"""
import argparse
import copy
import json
from pathlib import Path

from build_sync_lifecycle_contracts import SESSIONS

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "contracts/fixtures/sync/v1"
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"
NOW = "2026-09-05T01:00:00Z"


def derive():
    cases = []

    def shape(name, family, path, value, valid=True, anchor="8"):
        cases.append({"id": family + "-" + name, "family": family, "rule_anchor": "cloud-sync-02/" + anchor,
            "validation": "schema_only", "schema": path, "input": copy.deepcopy(value), "expected": {"valid": valid}})

    def decision(name, family, operation, value, expected=None, error=None, anchor="8"):
        cases.append({"id": family + "-" + name, "family": family, "rule_anchor": "cloud-sync-02/" + anchor,
            "validation": "reference_decision", "operation": operation, "input": value,
            "expected": {"value": expected, "error": error}})

    ack = {"protocol_version": 1, "device_id": A, "sync_transport_generation": 0, "mode": "ack_only",
           "cursor": None, "acknowledged_client_sequence_through": 0, "upload_mutations": [], "download_limit": 0}
    shape("ack-only-empty-valid", "FX-RUN", "sync/sync_exchange_request.schema.json", ack, anchor="6.2")
    for key, bad in (("cursor", "A" * 16), ("download_limit", 1), ("acknowledged_client_sequence_through", None), ("account_id", A)):
        shape("ack-only-forbids-" + key, "FX-RUN", "sync/sync_exchange_request.schema.json", {**ack, key: bad}, False, "6.2")
    normal = {**ack, "mode": "normal", "cursor": "A" * 16, "download_limit": 500}
    shape("normal-pull-only-valid", "FX-RUN", "sync/sync_exchange_request.schema.json", normal, anchor="6.2")
    for name, cursor in (("null", None), ("padding", "A" * 15 + "="), ("impossible-length", "A" * 17),
                         ("nonzero-unused-bits", "A" * 17 + "B"), ("too-long", "A" * 2052)):
        shape("opaque-cursor-" + name, "FX-CURSOR", "sync/sync_exchange_request.schema.json", {**normal, "cursor": cursor}, False, "6.3")
    recovery = {"sync_transport_generation": 1, "highest_client_sequence": 0, "next_client_sequence": 1,
                "client_confirmed_through": 0, "client_sequence_exhausted": False}
    shape("fresh-sequence-bundle", "FX-SEQUENCE", "sync/sync_sequence_recovery_bundle.schema.json", recovery, anchor="6.1")
    exhausted = {**recovery, "highest_client_sequence": 9007199254740991, "next_client_sequence": None, "client_sequence_exhausted": True}
    shape("exhausted-sequence-bundle", "FX-SEQUENCE", "sync/sync_sequence_recovery_bundle.schema.json", exhausted, anchor="6.1")
    shape("exhausted-cannot-have-next", "FX-SEQUENCE", "sync/sync_sequence_recovery_bundle.schema.json", {**exhausted, "next_client_sequence": 1}, False, "6.1")
    bootstrap = {"protocol_version": 1, "device_id": A, "sync_transport_generation": 0, "bootstrap_id": B,
        "account_generation": 0, "snapshot_upper_bound": 0, "device_highest_client_sequence_at_snapshot": 0,
        "device_client_confirmed_through_at_snapshot": 0, "device_next_client_sequence_at_snapshot": 1,
        "device_client_sequence_exhausted_at_snapshot": False, "retention_floor_server_sequence": 0,
        "resolved_conflict_cleanup_before": NOW, "expires_at": "2026-09-06T01:00:00Z", "page_ordinal": 0,
        "page_hash": "0" * 64, "items": [], "next_bootstrap_cursor": None, "has_more": False, "terminal_sync_cursor": "A" * 16,
        "snapshot_item_count": 0, "snapshot_items_hash": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        "total_page_count": 1, "page_item_limit": 500}
    shape("empty-terminal-page", "FX-BOOTSTRAP", "sync/sync_bootstrap_page_response.schema.json", bootstrap, anchor="6.3")
    for key, value in (("has_more", True), ("next_bootstrap_cursor", "A" * 16), ("terminal_sync_cursor", None),
                       ("device_next_client_sequence_at_snapshot", None), ("device_client_confirmed_through_at_snapshot", None)):
        shape("terminal-page-invalid-" + key, "FX-BOOTSTRAP", "sync/sync_bootstrap_page_response.schema.json", {**bootstrap, key: value}, False, "6.3")

    for state in ("empty", "ready", "locked"):
        value = {"route_state": state, "active_workspace_id": None if state == "empty" else A,
            "workspace_kind": None if state == "empty" else "account", "runtime_instance_id": B if state == "ready" else None,
            "lock_reason": "WORKSPACE_KEY_UNAVAILABLE" if state == "locked" else None, "active_route_revision": 0}
        shape("route-" + state, "FX-WORKSPACE", "workspace/workspace_route_state.schema.json", value)
        shape("route-" + state + "-forbids-private-key", "FX-WORKSPACE", "workspace/workspace_route_state.schema.json", {**value, "key_alias": "synthetic-private"}, False)
        if state != "ready":
            shape("route-" + state + "-forbids-old-runtime", "FX-WORKSPACE", "workspace/workspace_route_state.schema.json", {**value, "runtime_instance_id": B}, False)
    for state in SESSIONS:
        value = {"state": state, "session_generation": None if state == "empty" else 0,
            "capabilities": {"can_request_access_token": state in {"active", "refreshing"},
                             "can_manage_devices": state in {"active", "registration_pending"}, "can_open_account_workspace": state == "active"}}
        shape("session-" + state, "FX-SESSION-DEVICE", "auth/session_status_response.schema.json", value)
        shape("session-" + state + "-no-refresh-token", "FX-SESSION-DEVICE", "auth/session_status_response.schema.json", {**value, "refresh_token": "synthetic"}, False)
    for registration, operation, expected in (("unregistered", "device.list", False), ("unregistered", "auth.token.refresh", True),
        ("pending_registration", "device.list", True), ("pending_registration", "device.revoke", True),
        ("pending_registration", "preferences.update", False), ("pending_registration", "sync.exchange", False),
        ("unregistered", "future.unknown", False), ("pending_registration", "future.unknown", False)):
        decision("capability-" + registration + "-" + operation, "FX-SESSION-DEVICE", "backend_capability",
            {"registration_state": registration, "operation": operation}, expected)
    for name, manufacturer, model, expected in (("normalize", " Google\t", "Google  Pixel\n 9", "Google Pixel 9"),
        ("empty", "", "\u3000", "Android 设备"), ("codepoint-boundary", "牌", "😀" * 100, "牌 " + "😀" * 62)):
        decision("device-name-" + name, "FX-SESSION-DEVICE", "device_name", {"manufacturer": manufacturer, "model": model}, expected)
    phase_cases = [
        ({"workspace_kind": "local", "globally_blocked": True}, "local_only"),
        ({"workspace_kind": "account", "identity_valid": False, "globally_blocked": True}, "auth_required"),
        ({"workspace_kind": "account", "globally_blocked": True, "rebuilding": True}, "blocked"),
        ({"workspace_kind": "account", "rebuilding": True, "running": True}, "rebuilding"),
        ({"workspace_kind": "account", "running": True, "enabled": False}, "syncing"),
        ({"workspace_kind": "account", "logout_authorized_queued": True, "enabled": False}, "queued"),
        ({"workspace_kind": "account", "enabled": False, "pending": 2, "online": False}, "paused"),
        ({"workspace_kind": "account", "pending": 2, "online": False, "ordinary_queued": True}, "offline_pending"),
        ({"workspace_kind": "account", "ordinary_queued": True, "recoverable_failure": True}, "queued"),
        ({"workspace_kind": "account", "recoverable_failure": True}, "failed"), ({"workspace_kind": "account"}, "idle")]
    for i, (value, expected) in enumerate(phase_cases):
        decision("phase-priority-" + str(i), "FX-RUN", "sync_phase", value, expected)
    for name, request, expected, error in (("first", {"attempt": 0, "jitter_fraction": 1}, 5, None),
        ("last", {"attempt": 7, "jitter_fraction": 1}, 640, None),
        ("hint", {"attempt": 0, "jitter_fraction": 0, "retry_after": 60, "retry_after_header": 60}, 60, None),
        ("mismatch", {"attempt": 0, "jitter_fraction": 0, "retry_after": 60, "retry_after_header": 30}, None, "SYNC_PAYLOAD_INVALID"),
        ("exhausted", {"attempt": 8, "jitter_fraction": 0}, None, "RETRY_BUDGET_EXHAUSTED")):
        decision("retry-" + name, "FX-MAINTENANCE", "retry_delay", request, expected, error, "12")

    deadline = {"retention_started_at": "2026-08-06T00:00:00Z", "retained_until": "2026-09-05T00:00:00Z",
        "server_time_anchor": "2026-08-06T00:00:00Z", "elapsed_realtime_at_anchor": 1000,
        "boot_id": A, "retention_clock_state": "trusted", "lifecycle_revision": 1}
    shape("private-trusted-deadline", "FX-RETENTION-NOTIFY", "auth/private/retention_deadline_record.schema.json", deadline)
    shape("retained-cannot-null-deadline", "FX-RETENTION-NOTIFY", "auth/private/retention_deadline_record.schema.json", {**deadline, "retained_until": None}, False)
    for name, extra, expected in (("reboot", {"current_boot_id": B, "elapsed_ms": 9007199254740991}, False),
        ("before", {"https_time_lower_bound": "2026-09-04T23:59:59Z"}, False),
        ("due", {"https_time_lower_bound": "2026-09-05T00:00:00Z"}, True),
        ("same-boot", {"current_boot_id": A, "elapsed_ms": 2592001000}, True)):
        decision("retention-" + name, "FX-RETENTION-NOTIFY", "retention_due", {"record": deadline, **extra}, expected)
    history = {"workspace_id": A, "active_route_revision": 1, "history_revision": 0, "normalized_display_keywords": ["项目 😀", "会议"]}
    shape("workspace-history-valid", "FX-PREFERENCE", "native_v3/search/workspace_history_response.schema.json", history)
    shape("workspace-history-too-long", "FX-PREFERENCE", "native_v3/search/workspace_history_response.schema.json",
          {**history, "normalized_display_keywords": ["字" * 129]}, False)
    shape("workspace-history-no-target-id", "FX-PREFERENCE", "native_v3/search/workspace_history_response.schema.json", {**history, "target_id": B}, False)
    for code, context in (("SYNC_CLIENT_SEQUENCE_EXHAUSTED", {"counter_kind": "client_sequence"}),
                          ("SYNC_COUNTER_EXHAUSTED", {"counter_kind": "recurrence_revision"}),
                          ("RETENTION_TRUSTED_TIME_REQUIRED", {"logout_operation_id": A, "logout_risk_revision": 1, "allowed_cache_policies": ["destroy_now"]})):
        error = {"code": code, "message": "固定测试错误", "retryable": False, "context": context}
        shape("error-" + code, "FX-CROSS-LAYER", "native_v3/common/native_error.schema.json", error, anchor="12,13.2")
        shape("error-" + code + "-null-context", "FX-CROSS-LAYER", "native_v3/common/native_error.schema.json", {**error, "context": None}, False, "12,13.2")
    samples = json.loads((FIXTURES / "target_vectors.json").read_text(encoding="utf-8"))["samples"]
    for mode in ("keep_local", "keep_remote", "per_field", "manual_edit"):
        choice = {"mode": mode, "group_choices": [{"key": {"target_type": "category", "target_id": A, "merge_key": "name"}, "source": "local"}] if mode == "per_field" else [],
            "manual_candidate": samples["category"] if mode == "manual_edit" else None}
        request = {"workspace_id": A, "expected_active_route_revision": 0, "conflict_id": B, "expected_conflict_version": 1, "resolution": choice}
        shape("public-resolve-" + mode, "FX-CONFLICT", "sync/resolve_sync_conflict_request.schema.json", request, anchor="7.5,8")
        shape("public-resolve-no-sequence-" + mode, "FX-CONFLICT", "sync/resolve_sync_conflict_request.schema.json", {**request, "client_sequence": 1}, False, "7.5,8")
    queued = {"workspace_id": A, "runtime_instance_id": B, "active_route_revision": 0, "conflict_id": B,
        "disposition": "queued", "status": "resolving", "conflict_version": 1, "status_revision": 2}
    shape("public-resolve-queued", "FX-CONFLICT", "sync/sync_conflict_resolution_response.schema.json", queued, anchor="7.5,8")
    shape("queue-cannot-be-resolved", "FX-CONFLICT", "sync/sync_conflict_resolution_response.schema.json", {**queued, "status": "resolved"}, False, "7.5,8")
    failed = {"workspace_id": A, "runtime_instance_id": B, "active_route_revision": 0,
        "summary": {"failed_change_id": B, "failed_change_revision": 1, "target_type": "user_preferences", "target_id": samples["user_preferences"]["target_id"],
            "created_at": NOW, "failure": {"code": "SYNC_CHANGE_GROUP_TOO_LARGE", "context": None}, "state": "active"},
        "local_candidate": samples["user_preferences"], "manual_draft": None, "server_baseline": {"kind": "unavailable"}, "can_edit_as_new": True, "can_discard": True}
    shape("failed-preference-candidate", "FX-FAILED-LOCAL", "sync/sync_failed_local_change_detail.schema.json", failed, anchor="6.2,7.5,8")
    shape("failed-cannot-auto-retry", "FX-FAILED-LOCAL", "sync/sync_failed_local_change_detail.schema.json", {**failed, "retry_original_sequence": True}, False, "6.2,7.5,8")
    return {"fixture_version": 1, "scope": "schema_shapes_and_reference_decisions_not_signature_verification_or_full_saga", "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    value = derive()
    path = FIXTURES / "protocol_vectors.json"
    if args.check:
        if json.loads(path.read_text(encoding="utf-8")) != value:
            raise ValueError("Protocol/lifecycle fixture drift")
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(value["cases"])}))
