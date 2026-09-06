"""Planned workspace-bound Native infrastructure; binary keys are out-of-band."""
import argparse
import copy
import json

from build_sync_domain_contracts import CONTRACTS, yaml, BASE
from build_sync_protocol_contracts import (SAFE, POSITIVE, UUID, UUID4, HASH, BOOL, NULL, DATE_TIME, const, nullable,
    array, object_of, document, ref)


def derive():
    out = {}

    def emit(name, body):
        value = document(name, body, "8.3", "native_v3/internal")
        value.update({"x-contract-domain": "native", "x-contract-version": 3, "x-exposure": "kotlin_jni_cpp_only"})
        out[CONTRACTS / "native_v3/internal" / (name + ".schema.json")] = value
        return ref(name, "native_v3/internal")

    guest_binding = {"workspace_id": UUID4, "workspace_kind": const("local"), "runtime_instance_id": UUID4,
        "device_id": NULL, "session_generation": NULL}
    account_binding = {**guest_binding, "workspace_kind": const("account"), "device_id": UUID4, "session_generation": SAFE}
    binding = emit("runtime_binding", {"oneOf": [object_of(guest_binding), object_of(account_binding)]})
    account = emit("account_runtime_binding", object_of(account_binding))
    transport = emit("transport_binding", object_of({**account_binding, "sync_transport_generation": SAFE}))
    native_status = ref("native_sync_status_snapshot")
    affected = emit("affected_local_entities", object_of({
        name: {**array(UUID, 50000), "uniqueItems": True} for name in ("event_ids", "habit_ids", "anniversary_ids", "reminder_ids", "notification_ids")}))
    operation = emit("native_operation_response", object_of({"binding": binding, "native_state_revision": SAFE}))
    apply_result = emit("native_apply_result", object_of({"binding": account, "status": native_status,
        "affected": affected, "next_prepared_exchange_id": nullable(UUID4), "ack_watermark_dirty": BOOL}))
    emit("bound_empty_request", object_of({"binding": binding}))
    emit("account_bound_empty_request", object_of({"binding": account}))
    policy = {"sync_enabled": BOOL, "sync_policy_revision": SAFE}
    policy_seed = emit("workspace_policy_seed", {"oneOf": [
        object_of({"kind": const("genesis"), "sync_enabled": const(True), "sync_policy_revision": const(0), "clear_operation_id": NULL}),
        object_of({"kind": const("clear_rebuild"), **policy, "clear_operation_id": UUID4,
            "workspace_id": UUID4, "device_id": UUID4, "session_generation": SAFE, "resulting_sync_transport_generation": SAFE,
            "lifecycle_seed_hash": HASH})]})
    guest_open = {"workspace_id": UUID4, "workspace_kind": const("local"), "account_id": NULL,
        "device_id": NULL, "session_generation": NULL, "storage_format_version": const(6), "native_contract_version": const(3),
        "storage_directory": {"type": "string", "minLength": 1, "maxLength": 4096, "x-sensitive": True},
        "open_mode": {"enum": ["existing", "fresh", "migrate_v5"]}, "recovery_seed": NULL, "fence_evidence": NULL,
        "policy_seed": NULL, "open_operation_id": UUID4}
    account_open = {**guest_open, "workspace_kind": const("account"), "account_id": UUID4,
        "device_id": UUID4, "session_generation": SAFE, "open_mode": const("existing")}
    fresh_account = {**account_open, "open_mode": const("fresh"), "recovery_seed": ref("sync_sequence_recovery_bundle"),
        "fence_evidence": nullable(ref("sync_device_fence_response")), "policy_seed": policy_seed,
        "fresh_reason": {"enum": ["new_device", "destroyed_cache_relogin", "clear_rebuild", "force_local_relogin"]}}
    fresh_rules = [{"if": {"properties": {"fresh_reason": {"enum": ["clear_rebuild", "force_local_relogin"]}}},
        "then": {"properties": {"fence_evidence": ref("sync_device_fence_response")}}},
        {"if": {"properties": {"fresh_reason": const("clear_rebuild")}},
         "then": {"properties": {"policy_seed": {"properties": {"kind": const("clear_rebuild")}}}},
         "else": {"properties": {"policy_seed": {"properties": {"kind": const("genesis")}}}}}]
    emit("open_workspace_request", {"oneOf": [object_of(guest_open), object_of(account_open), object_of(fresh_account, allOf=fresh_rules)],
        "x-binary-parameters": [{"name": "database_key", "type": "byte_array", "guest_length": 0, "account_length": 32,
            "nullable": False, "encoding": "raw_octets_not_utf8_base64_hex_or_json", "lifetime": "copy only for open; securely erase every temporary buffer after synchronous native call",
            "logging": "forbidden", "binding": "Keystore unwrap AAD binds installation/account/workspace/schema; Native verifies metadata/key match before exposing runtime"}],
        "x-semantic-rules": ["metadata and key equality required for already-open; never replace a live runtime",
            "fresh_reason never bypasses durable transport_fence_required; destroyed prior database for active device consumes a fence before writable open",
            "clear seed identity, operation, generation and hash match fence and binding; no receive_reminders/settings mirror accepted here",
            "migrate_v5 only for the legacy guest; a plaintext account v5 database is not a supported source"]})
    emit("open_workspace_response", object_of({"binding": binding, "open_operation_id": UUID4,
        "disposition": {"enum": ["opened", "already_open"]}, "storage_format_version": const(6), "native_contract_version": const(3),
        "seed_consumed": {"oneOf": [NULL, object_of({"open_operation_id": UUID4, "recovery_seed_hash": HASH,
            "policy_seed_hash": HASH, "fence_receipt_hash": nullable(HASH)})]}, "status": native_status}))
    emit("close_workspace_request", object_of({"binding": binding, "close_operation_id": UUID4}))
    emit("close_workspace_response", object_of({"binding": binding, "close_operation_id": UUID4, "disposition": {"enum": ["closed", "already_closed"]}}))
    emit("get_workspace_state_request", object_of({"binding": nullable(binding)}))
    counts = object_of({name: SAFE for name in ("event_count", "anniversary_count", "habit_count", "category_count")})
    emit("get_workspace_state_response", {"oneOf": [object_of({"binding": NULL, "counts": NULL, "native_state_revision": NULL}),
        object_of({"binding": binding, "counts": counts, "native_state_revision": SAFE})]})
    emit("accept_transport_fence_request", object_of({"binding": transport, "receipt": ref("sync_device_fence_response")}))
    emit("accept_transport_fence_response", object_of({"binding": transport, "receipt_hash": HASH, "disposition": {"enum": ["accepted", "already_accepted"]},
        "native_state_revision": SAFE, "ack_watermark_dirty": BOOL}))
    emit("prepare_upload_batch_request", {"oneOf": [object_of({"binding": transport, "run_intent": const(intent),
        "run_id": UUID4, "max_items": {"type": "integer", "minimum": 1, "maximum": 100},
        "max_bytes": {"type": "integer", "minimum": 1, "maximum": 1048576},
        "logout_operation_id": UUID4 if intent == "logout_final" else NULL}) for intent in ("normal", "logout_final", "receipt_ack_flush", "reenable_pull_only")],
        "x-semantic-rules": ["only Broker's matching durable logout operation authorizes paused logout_final",
            "ack flush requires dirty watermark; reenable requires persisted pull gate; clear-rebuild never calls prepare",
            "C++ persists exact full request, identity, cursor and bytes; Kotlin adds only authenticated transport headers"]})
    bootstrap = json.loads((CONTRACTS / "sync/sync_bootstrap_page_response.schema.json").read_text(encoding="utf-8"))
    identity_names = ["bootstrap_id", "sync_transport_generation", "account_generation", "snapshot_upper_bound",
        "device_highest_client_sequence_at_snapshot", "device_client_confirmed_through_at_snapshot", "device_next_client_sequence_at_snapshot",
        "device_client_sequence_exhausted_at_snapshot", "retention_floor_server_sequence", "resolved_conflict_cleanup_before", "expires_at",
        "snapshot_item_count", "snapshot_items_hash", "total_page_count", "page_item_limit"]
    identity = emit("bootstrap_identity", object_of({name: bootstrap["properties"][name] for name in identity_names},
        allOf=copy.deepcopy(bootstrap.get("allOf", []))))
    emit("begin_bootstrap_request", object_of({"binding": transport, "identity": identity,
        "trigger_reason": {"enum": ["cursor_expired", "account_generation_changed", "fresh_database", "clear_rebuild"]}}))
    emit("apply_bootstrap_page_request", object_of({"binding": transport, "page": ref("sync_bootstrap_page_response")}))
    emit("bootstrap_staging_response", object_of({"binding": transport, "bootstrap_id": UUID4, "next_page_ordinal": SAFE,
        "staged_item_count": SAFE, "terminal_page_received": BOOL, "page_set_digest": HASH}))
    emit("finalize_bootstrap_request", object_of({"binding": transport, "identity": identity, "terminal_page_set_digest": HASH,
        "final_cursor": {**bootstrap["properties"]["terminal_sync_cursor"], "type": "string"}}))
    emit("claim_conflict_notice_request", object_of({"binding": binding, "notice_id": UUID4, "notice_sequence": POSITIVE}))
    emit("claim_conflict_notice_response", {"oneOf": [object_of({"binding": binding, "disposition": const(disposition),
        "notice_id": UUID4, "notice_sequence": POSITIVE, "count": POSITIVE if disposition == "claimed" else const(0),
        "status": native_status}) for disposition in ("claimed", "no_longer_actionable")]})
    emit("build_diagnostic_snapshot_request", object_of({"binding": account, "redaction_profile": const("sync_v1_no_business_or_identity")}))
    emit("diagnostic_snapshot_response", object_of({"schema_version": const(1), "native_contract_version": const(3),
        "sync_protocol_version": const(1), "storage_format_version": const(6), "sync_enabled": BOOL,
        "pending_count_bucket": {"enum": ["zero", "1_99", "100_4999", "5000_19999", "20000_plus"]},
        "oldest_pending_age_bucket": {"enum": ["none", "under_72h", "72h_under_14d", "14d_plus"]},
        "outbox_bytes_bucket": {"enum": ["zero", "under_64mib", "64_under_256mib", "256mib_plus"]},
        "failed_count": SAFE, "unresolved_count": SAFE, "unclaimed_notice_count": SAFE,
        "native_blocked_reason": nullable(ref("sync_error_code")), "ack_watermark_dirty": BOOL,
        "bootstrap_active": BOOL, "import_active": BOOL}))
    emit("run_local_maintenance_request", object_of({"binding": account, "max_items": {"type": "integer", "minimum": 1, "maximum": 500}}))
    emit("run_local_maintenance_response", object_of({"binding": account,
        "retention_floor_server_sequence": SAFE, "resolved_conflict_cleanup_before": nullable(DATE_TIME),
        "last_claimed_conflict_notice_sequence": SAFE, "deleted_items": {"type": "integer", "minimum": 0, "maximum": 500}, "has_more": BOOL}))
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out = derive()
    for path, value in out.items():
        if args.check:
            assert json.loads(path.read_text(encoding="utf-8")) == value, path.name
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"native_internal_schemas": len(out), "status": "planned"}))
