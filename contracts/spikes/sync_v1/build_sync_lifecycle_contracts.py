"""Planned Native v3/HTTP lifecycle DTOs with exact ownership and null unions."""
import argparse
import copy
import json

from build_sync_protocol_contracts import (CONTRACTS, SAFE, POSITIVE, UUID, UUID4, HASH, BOOL, NULL, OPAQUE,
    DATE_TIME, const, array, nullable, object_of, ref, document)

PHASES = ["local_only", "idle", "queued", "syncing", "offline_pending", "paused", "auth_required", "rebuilding", "blocked", "failed"]
SESSIONS = ["empty", "pending_adoption", "registration_pending", "active", "refreshing", "reauth_required", "terminating"]
TERMINAL_CODES = ["SYNC_PROTOCOL_VERSION_UNSUPPORTED", "SYNC_SEQUENCE_REPLAY_MISMATCH", "SYNC_SEQUENCE_ROUTE_MISMATCH",
    "SYNC_CLIENT_SEQUENCE_EXHAUSTED", "SYNC_SERVER_SEQUENCE_EXHAUSTED", "SYNC_CURSOR_INVALID",
    "SYNC_CURSOR_ACCOUNT_MISMATCH", "SYNC_CURSOR_DEVICE_MISMATCH", "SYNC_OUTBOX_CORRUPTED", "SYNC_APPLY_FAILED"]


def derive():
    out = {}

    def emit(name, body, directory, *, native=False, private=False):
        schema = document(name, body, "8", directory)
        if native:
            schema.update({"x-contract-domain": "native", "x-contract-version": 3})
        if private:
            schema.update({"x-contract-domain": "android_private", "x-contract-version": 1, "x-sensitive": True,
                           "x-exposure": "kotlin_local_only_never_HTTP_MethodChannel_EventChannel_or_JNI"})
        out[CONTRACTS / directory / (name + ".schema.json")] = schema
        return ref(name, directory)

    route = {"workspace_id": UUID4, "expected_active_route_revision": SAFE}
    response_route = {"workspace_id": UUID4, "runtime_instance_id": UUID4, "active_route_revision": SAFE}
    runtime = {"workspace_id": UUID4, "runtime_instance_id": UUID4, "device_id": nullable(UUID4)}
    error = ref("sync_error_code")
    empty = object_of({})
    counts = object_of({"event_count": SAFE, "anniversary_count": SAFE, "habit_count": SAFE, "category_count": SAFE})
    import_handle = object_of({"import_lineage_id": UUID, "import_batch_id": UUID4, "source_workspace_id": UUID4,
                               "source_epoch": SAFE, "import_revision": POSITIVE})
    route_variants, state_variants = [], []
    for state in ("ready", "locked", "empty"):
        p = {"route_state": const(state), "active_workspace_id": NULL if state == "empty" else UUID4,
            "workspace_kind": NULL if state == "empty" else {"enum": ["local", "account"]},
            "runtime_instance_id": UUID4 if state == "ready" else NULL,
            "lock_reason": error if state == "locked" else NULL, "active_route_revision": SAFE}
        route_variants.append(object_of(p))
        state_variants.append(object_of({**p, "counts": counts if state == "ready" else NULL,
            "active_import": nullable(import_handle) if state == "ready" else NULL}))
    route_state = emit("workspace_route_state", {"oneOf": route_variants}, "workspace", native=True)
    workspace_state = emit("workspace_state_response", {"oneOf": state_variants}, "workspace", native=True)
    emit("get_workspace_state_request", object_of({"known_active_route_revision": nullable(SAFE)}), "workspace", native=True)
    workspace_list = emit("workspace_list_response", object_of({"active_route_revision": SAFE,
        "workspaces": array(object_of({"workspace_id": UUID4, "workspace_kind": {"enum": ["local", "account"]},
            "is_active": BOOL, "is_unlockable": const(True)}), 2, 1)}), "workspace", native=True)
    emit("activate_workspace_request", object_of(route), "workspace", native=True)
    emit("clear_account_cache_request", object_of({**route, "expected_session_generation": SAFE,
        "observed_active_workspace_id": UUID4, "expected_lifecycle_revision": SAFE, "confirmation_id": UUID4}), "workspace", native=True)

    status_fields = {"workspace_id": UUID4, "workspace_kind": {"enum": ["local", "account"]}, "runtime_instance_id": UUID4,
        "active_route_revision": SAFE, "device_id": nullable(UUID4), "sync_enabled": BOOL,
        "sync_policy_revision": nullable(SAFE), "phase": {"enum": PHASES}, "pending_upload_count": SAFE,
        "failed_local_change_count": SAFE, "next_failed_local_change_id": nullable(UUID4), "unresolved_conflict_count": SAFE,
        "unclaimed_conflict_notice_count": SAFE, "next_conflict_notice_id": nullable(UUID4), "next_conflict_notice_count": SAFE,
        "next_conflict_notice_sequence": nullable(POSITIVE), "backlog_state": {"enum": ["normal", "warning", "critical"]},
        "backlog_reason_codes": {**array({"enum": ["pending_count", "oldest_pending_age", "outbox_bytes"]}, 3), "uniqueItems": True},
        "diagnostics_export_available": BOOL, "last_attempt_at": nullable(DATE_TIME), "last_success_at": nullable(DATE_TIME),
        "next_retry_at": nullable(DATE_TIME), "failure_code": nullable(error), "retryable": BOOL,
        "status_revision": SAFE, "active_run_id": nullable(UUID4)}
    count_matrix = [
        {"if": {"properties": {"failed_local_change_count": const(0)}},
         "then": {"properties": {"next_failed_local_change_id": NULL}}, "else": {"properties": {"next_failed_local_change_id": UUID4}}},
        {"if": {"properties": {"unclaimed_conflict_notice_count": const(0)}},
         "then": {"properties": {"next_conflict_notice_id": NULL, "next_conflict_notice_count": const(0), "next_conflict_notice_sequence": NULL}},
         "else": {"properties": {"next_conflict_notice_id": UUID4, "next_conflict_notice_count": POSITIVE, "next_conflict_notice_sequence": POSITIVE}}},
        {"if": {"properties": {"backlog_state": const("normal")}}, "then": {"properties": {"backlog_reason_codes": {"maxItems": 0}}},
         "else": {"properties": {"backlog_reason_codes": {"minItems": 1}}}},
    ]
    guest = {**status_fields, "workspace_kind": const("local"), "device_id": NULL, "sync_enabled": const(False),
        "sync_policy_revision": NULL, "phase": const("local_only"), "pending_upload_count": const(0),
        "failed_local_change_count": const(0), "next_failed_local_change_id": NULL, "unresolved_conflict_count": const(0),
        "unclaimed_conflict_notice_count": const(0), "next_conflict_notice_id": NULL, "next_conflict_notice_count": const(0),
        "next_conflict_notice_sequence": NULL, "backlog_state": const("normal"), "backlog_reason_codes": array(error, 0),
        "diagnostics_export_available": const(False), "last_attempt_at": NULL, "last_success_at": NULL,
        "next_retry_at": NULL, "failure_code": NULL, "retryable": const(False), "active_run_id": NULL}
    account = {**status_fields, "workspace_kind": const("account"), "device_id": UUID4,
               "sync_policy_revision": SAFE, "phase": {"enum": PHASES[1:]}}
    status = emit("sync_status_response", {"oneOf": [object_of(guest), object_of(account, allOf=count_matrix)]}, "sync", native=True)
    # C++ owns neither Work/Broker phases nor the aggregated status revision.
    native_fields = {key: value for key, value in status_fields.items() if key not in {
        "active_route_revision", "phase", "last_attempt_at", "last_success_at", "next_retry_at", "failure_code", "retryable", "status_revision", "active_run_id"}}
    native_fields.update(native_state_revision=SAFE, native_blocked_reason=nullable({"enum": TERMINAL_CODES}))
    native_guest = {key: guest[key] for key in native_fields if key in guest}
    native_guest.update(native_state_revision=SAFE, native_blocked_reason=NULL)
    native_account = {**native_fields, "workspace_kind": const("account"), "device_id": UUID4, "sync_policy_revision": SAFE}
    native_status = emit("native_sync_status_snapshot", {"oneOf": [object_of(native_guest),
        object_of(native_account, allOf=count_matrix)]}, "sync", native=True)
    emit("get_sync_status_request", object_of(route), "sync", native=True)
    emit("set_sync_enabled_request", object_of({**route, "enabled": BOOL, "expected_sync_policy_revision": SAFE}), "sync", native=True)
    emit("native_set_sync_enabled_request", object_of({**runtime, "operation_id": UUID4,
        "enabled": BOOL, "expected_sync_policy_revision": SAFE}), "sync", native=True)
    emit("run_sync_now_request", object_of(route), "sync", native=True)
    emit("run_sync_now_response", object_of({"run_id": UUID4, "disposition": {"enum": ["queued", "already_running"]}, "status_revision": SAFE}), "sync", native=True)
    emit("claim_conflict_notice_request", object_of({**route, "notice_id": UUID4, "notice_sequence": POSITIVE}), "sync", native=True)
    emit("claim_conflict_notice_response", {"oneOf": [
        object_of({"disposition": const("claimed"), "notice_id": UUID4, "notice_sequence": POSITIVE, "count": POSITIVE, "status": status}),
        object_of({"disposition": const("no_longer_actionable"), "notice_id": UUID4, "notice_sequence": POSITIVE, "count": const(0), "status": status})]}, "sync", native=True)
    emit("export_diagnostics_request", object_of(route), "sync", native=True)
    emit("export_diagnostics_response", object_of({"export_id": UUID4, "sha256": HASH, "generated_at": DATE_TIME,
        "disposition": {"enum": ["share_opened", "share_cancelled"]}}), "sync", native=True)
    emit("record_transport_terminal_request", object_of({**runtime, "session_generation": SAFE,
        "sync_transport_generation": SAFE, "code": {"enum": TERMINAL_CODES}, "error_envelope_sha256": HASH}), "sync", native=True)

    preference = emit("preferences_response", object_of({**response_route,
        "preferences": ref("user_preferences_fact", "sync/v1"), "preferences_revision": SAFE}), "preferences", native=True)
    emit("get_preferences_request", object_of(route), "preferences", native=True)
    emit("update_preferences_request", object_of({**route, "expected_preferences_revision": SAFE,
        "patch": ref("user_preferences_patch", "sync/v1")}), "preferences", native=True)
    history = copy.deepcopy(json.loads((CONTRACTS / "search/search_history_response.schema.json").read_text(encoding="utf-8"))["properties"]["items"])
    emit("get_workspace_history_request", object_of(route), "native_v3/search", native=True)
    emit("replace_workspace_history_request", object_of({**route, "expected_history_revision": SAFE,
        "normalized_display_keywords": history}), "native_v3/search", native=True)
    emit("workspace_history_response", object_of({"workspace_id": UUID4, "active_route_revision": SAFE,
        "history_revision": SAFE, "normalized_display_keywords": history}), "native_v3/search", native=True)
    profile = emit("account_profile_snapshot", object_of({"profile": ref("account_profile_fact", "sync/v1"),
        "account_profile_revision": SAFE, "preferences_revision": SAFE, "server_received_at": DATE_TIME}), "user")
    emit("get_cached_profile_request", object_of(route), "user", native=True)
    emit("cached_profile_response", {"oneOf": [
        object_of({**response_route, "disposition": const("not_applicable"), "profile": NULL, "freshness": const("not_applicable")}),
        object_of({**response_route, "disposition": const("available"), "profile": profile, "freshness": {"enum": ["fresh", "stale"]}}),
        object_of({**response_route, "disposition": const("unavailable"), "profile": NULL, "freshness": const("unavailable")})]}, "user", native=True)
    emit("accept_server_profile_snapshot_request", object_of({**route, "snapshot": profile}), "user", native=True)

    # Backend DTOs and MethodChannel projections are intentionally distinct.
    device_name = {"type": "string", "minLength": 1, "maxLength": 64}
    device_fields = {"device_id": UUID4, "display_name": device_name, "platform": const("android"),
        "app_version": {"type": "string", "minLength": 1, "maxLength": 64}, "protocol_version": const(1),
        "receive_reminders": BOOL, "sync_enabled": BOOL, "device_version": SAFE, "status": {"enum": ["active", "revoked"]},
        "registered_at": DATE_TIME, "last_seen_at": nullable(DATE_TIME), "last_sync_at": nullable(DATE_TIME),
        "revoked_at": nullable(DATE_TIME), "sequence_recovery": ref("sync_sequence_recovery_bundle")}
    device = emit("device_response", object_of(device_fields, oneOf=[
        {"properties": {"status": const("active"), "revoked_at": NULL}},
        {"properties": {"status": const("revoked"), "revoked_at": DATE_TIME}}]), "device")
    device_summary = emit("method_device_summary", object_of({key: value for key, value in device_fields.items()
        if key not in {"sequence_recovery"}}, oneOf=[
        {"properties": {"status": const("active"), "revoked_at": NULL}},
        {"properties": {"status": const("revoked"), "revoked_at": DATE_TIME}}]), "device", native=True)
    emit("register_device_request", object_of({"installation_id": UUID4, "display_name": device_name, "platform": const("android"),
        "app_version": device_fields["app_version"], "protocol_version": const(1)}), "device")
    emit("rename_device_request", object_of({"display_name": device_name, "expected_device_version": SAFE}), "device")
    patch = object_of({"receive_reminders": BOOL, "sync_enabled": BOOL}, minProperties=1)
    patch["required"] = []
    emit("update_device_settings_request", object_of({"patch": patch, "expected_device_version": SAFE}), "device")
    emit("revoke_device_request", object_of({"expected_device_version": SAFE}), "device")
    revoked = emit("device_revocation_response", object_of({"device_id": UUID4, "device_version": SAFE,
        "status": const("revoked"), "revoked_at": DATE_TIME}), "device")
    remote_list = emit("device_list_response", object_of({"registration_pending": BOOL, "current_device_id": nullable(UUID4),
        "devices": array(device, 10)}, oneOf=[
        {"properties": {"registration_pending": const(True), "current_device_id": NULL}},
        {"properties": {"registration_pending": const(False), "current_device_id": UUID4}}]), "device")
    local_settings = object_of({"receive_reminders": BOOL, "sync_enabled": BOOL, "settings_remote_pending": BOOL, "local_settings_revision": SAFE})
    emit("method_device_list_request", empty, "device", native=True)
    emit("method_device_list_response", object_of({"remote_snapshot_state": {"enum": ["fresh", "stale", "unavailable"]},
        "remote_snapshot_at": nullable(DATE_TIME), "registration_pending": BOOL, "remote_devices": array(device_summary, 10),
        "current_device_local_settings": nullable(local_settings)}, allOf=[
        {"if": {"properties": {"remote_snapshot_state": const("unavailable")}}, "then": {"properties": {"remote_snapshot_at": NULL, "remote_devices": {"maxItems": 0}}},
         "else": {"properties": {"remote_snapshot_at": DATE_TIME}}},
        {"if": {"properties": {"registration_pending": const(True)}}, "then": {"properties": {"remote_snapshot_state": const("fresh"), "current_device_local_settings": NULL}},
         "else": {"properties": {"current_device_local_settings": local_settings}}}]), "device", native=True)
    emit("method_rename_device_request", object_of({**route, "device_id": UUID4, "display_name": device_name,
        "expected_device_version": SAFE}), "device", native=True)
    emit("method_rename_device_response", object_of({**response_route, "device": device_summary}), "device", native=True)
    emit("method_update_device_settings_request", {"oneOf": [object_of({**route, "device_id": UUID4,
        "expected_local_settings_revision": SAFE, "expected_sync_policy_revision": SAFE if field == "sync_enabled" else NULL,
        "patch": object_of({field: BOOL})}) for field in ("receive_reminders", "sync_enabled")]}, "device", native=True)
    emit("method_update_device_settings_response", object_of({"disposition": const("local_saved"),
        "workspace_id": UUID4, "active_route_revision": SAFE, "local_settings": local_settings, "sync_status": status}), "device", native=True)
    emit("method_revoke_device_request", object_of({"target_device_id": UUID4, "expected_device_version": SAFE, "reauth_grant_id": UUID4}), "device", native=True)
    emit("method_revoke_device_response", {"oneOf": [
        object_of({"registration_outcome": const("not_applicable"), "revocation": revoked}),
        object_of({"registration_outcome": const("registered"), "revocation": revoked, "workspace_state": workspace_state}),
        object_of({"registration_outcome": const("still_limited"), "revocation": nullable(revoked), "registration_pending": const(True)})]}, "device", native=True)

    emit("server_time_response", object_of({"server_time": DATE_TIME}), "common")
    password = {"type": "string", "minLength": 1, "maxLength": 128, "x-sensitive": True, "writeOnly": True}
    token = {"type": "string", "minLength": 32, "maxLength": 4096, "x-sensitive": True,
             "x-cache-policy": "broker_memory_or_encrypted_broker_record_only", "x-log-policy": "never"}
    emit("reauthenticate_request", object_of({"current_password": password, "purpose": const("device_revoke"), "target_device_id": UUID4}), "auth")
    emit("reauthenticate_response", object_of({"reauth_token": token, "expires_at": DATE_TIME,
        "purpose": const("device_revoke"), "target_device_id": UUID4}), "auth")
    session_variants = []
    for state in SESSIONS:
        session_variants.append(object_of({"state": const(state), "session_generation": NULL if state == "empty" else SAFE,
            "capabilities": object_of({"can_request_access_token": const(state in {"active", "refreshing"}),
                "can_manage_devices": const(state in {"active", "registration_pending"}),
                "can_open_account_workspace": const(state == "active")})}))
    session = emit("session_status_response", {"oneOf": session_variants}, "auth", native=True)
    emit("session_adopt_request", object_of({"authentication": ref("authentication_response", "backend_sync_v1/auth")}), "auth", native=True)
    emit("session_get_access_token_request", object_of({"minimum_validity_seconds": {"type": "integer", "minimum": 0, "maximum": 900},
        "rejected_access_token_generation": nullable(SAFE)}), "auth", native=True)
    emit("session_access_token_response", object_of({"access_token": token, "expires_at": DATE_TIME,
        "session_id": UUID4, "access_token_generation": SAFE}), "auth", native=True)
    emit("session_reauthenticate_request", object_of({"password": password, "purpose": const("device_revoke"), "target_device_id": UUID4}), "auth", native=True)
    emit("session_reauthenticate_response", object_of({"reauth_grant_id": UUID4, "purpose": const("device_revoke"),
        "target_device_id": UUID4, "expires_at": DATE_TIME}), "auth", native=True)

    # Boot identity and trusted elapsed-time anchors are Android-private. They are
    # never embedded in the public retention result, route event or diagnostics.
    boot = emit("boot_epoch_record", {"oneOf": [object_of({"schema_version": const(1), "source": const(source),
        **({"observed_boot_count": {"type": "integer", "minimum": 0, "maximum": 2147483647}} if source == "global_boot_count" else {}),
        "boot_id": UUID4, "last_elapsed_realtime_ms": SAFE}) for source in ("global_boot_count", "process_only")]}, "auth/private", private=True)
    deadline_variants = []
    for state in ("trusted", "untrusted", "expired", "deleting", "destroyed", "not_applicable"):
        active = state not in {"destroyed", "not_applicable"}
        deadline_variants.append(object_of({"retention_clock_state": const(state),
            "retention_started_at": DATE_TIME if active else NULL, "retained_until": DATE_TIME if active else NULL,
            "server_time_anchor": DATE_TIME if state == "trusted" else nullable(DATE_TIME) if active else NULL,
            "elapsed_realtime_at_anchor": SAFE if state == "trusted" else nullable(SAFE) if active else NULL,
            "boot_id": UUID4 if state == "trusted" else nullable(UUID4) if active else NULL, "lifecycle_revision": SAFE}))
    emit("retention_deadline_record", {"oneOf": deadline_variants}, "auth/private", private=True)
    cache = emit("session_cache_result", {"oneOf": [
        object_of({"cache_action": const("retained"), "retained_until": DATE_TIME,
            "retention_clock_state": {"enum": ["trusted", "untrusted"]}, "lifecycle_revision": SAFE}),
        object_of({"cache_action": const("destroyed"), "retained_until": NULL,
            "retention_clock_state": const("destroyed"), "lifecycle_revision": SAFE}),
        object_of({"cache_action": const("not_applicable"), "retained_until": NULL,
            "retention_clock_state": const("not_applicable"), "lifecycle_revision": SAFE})]}, "auth", native=True)
    policies = {"oneOf": [const(["retain_30d", "destroy_now"]), const(["destroy_now"])]}
    logout_fields = {"expected_session_generation": SAFE, "session_state": const("active"),
        "mode": const("server_then_local"), "final_sync_policy": {}, "cache_policy": {"enum": ["retain_30d", "destroy_now"]},
        "observed_active_workspace_id": UUID4, "expected_active_route_revision": SAFE,
        "logout_operation_id": nullable(UUID4), "expected_logout_risk_revision": nullable(SAFE), "confirmation_id": nullable(UUID4)}
    logout_branches = [object_of({**logout_fields, "final_sync_policy": const("attempt_once"),
        "logout_operation_id": NULL, "expected_logout_risk_revision": NULL, "confirmation_id": NULL})]
    for policy in ("retry_after_review", "skip_after_confirmation", "cancel_after_review"):
        logout_branches.append(object_of({**logout_fields, "final_sync_policy": const(policy), "logout_operation_id": UUID4,
            "expected_logout_risk_revision": SAFE, "confirmation_id": UUID4 if policy == "skip_after_confirmation" else NULL}))
    logout_branches.append(object_of({**logout_fields, "mode": const("force_local"), "final_sync_policy": const("skip_after_confirmation"),
        "logout_operation_id": UUID4, "expected_logout_risk_revision": SAFE, "confirmation_id": UUID4}))
    logout_branches.append(object_of({**logout_fields, "session_state": {"enum": ["pending_adoption", "registration_pending"]},
        "final_sync_policy": NULL, "observed_active_workspace_id": NULL, "expected_active_route_revision": NULL,
        "logout_operation_id": NULL, "expected_logout_risk_revision": NULL, "confirmation_id": NULL}))
    emit("session_logout_request", {"oneOf": logout_branches}, "auth", native=True)
    risk = object_of({"pending_upload_count": SAFE, "failed_local_change_count": SAFE, "nonterminal_import": nullable(import_handle)})
    emit("session_logout_response", {"oneOf": [
        object_of({"disposition": const("completed"), "server_logout_status": {"enum": ["succeeded", "already_invalid", "unreachable"]},
            "server_time": nullable(DATE_TIME), "cache": cache,
            "session": {"allOf": [session, {"properties": {"state": const("empty")}}]}, "workspace_state": workspace_state},
            oneOf=[{"properties": {"server_logout_status": {"enum": ["succeeded", "already_invalid"]}, "server_time": DATE_TIME}},
                   {"properties": {"server_logout_status": const("unreachable"), "server_time": NULL}}]),
        object_of({"disposition": const("review_required"), "logout_operation_id": UUID4, "logout_risk_revision": SAFE,
            "risk": risk, "server_logout_status": {"enum": ["not_attempted", "unreachable"]}, "allowed_cache_policies": policies}),
        object_of({"disposition": const("cancelled"), "logout_operation_id": UUID4, "session": session, "workspace_state": workspace_state})]}, "auth", native=True)
    emit("server_logout_terminal_response", object_of({"server_logout_status": {"enum": ["succeeded", "already_invalid"]},
        "server_time": DATE_TIME}), "auth")
    emit("session_clear_local_request", object_of({"reason": const("user_requested_destroy"), "confirmation_id": UUID4,
        "expected_session_generation": SAFE}), "auth", native=True)
    return out


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = derive()
    for path, value in outputs.items():
        if args.check:
            if json.loads(path.read_text(encoding="utf-8")) != value:
                raise ValueError("Lifecycle schema drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"schemas": len(outputs), "status": "planned_not_frozen"}))


if __name__ == "__main__":
    main()
