"""Close Sync/Native-v3 error enums and typed contexts without changing legacy errors."""
import argparse
import copy
import json

from build_sync_protocol_contracts import (BASE, CONTRACTS, SAFE, POSITIVE, UUID4, HASH, BOOL, NULL,
    const, array, nullable, object_of, ref, document, yaml)

GROUPS = {
    "protocol": "SYNC_PROTOCOL_VERSION_UNSUPPORTED SYNC_BATCH_TOO_LARGE SYNC_PAYLOAD_INVALID SYNC_PAYLOAD_HASH_MISMATCH SYNC_CAUSAL_PREDECESSOR_INVALID SYNC_ACK_WATERMARK_INVALID SYNC_IDENTITY_MISMATCH SYNC_OPERATION_UNSUPPORTED SYNC_TARGET_UNSUPPORTED SYNC_TIMEZONE_INVALID",
    "ordering": "SYNC_CLIENT_SEQUENCE_GAP SYNC_SEQUENCE_REPLAY_MISMATCH SYNC_SEQUENCE_ROUTE_MISMATCH SYNC_CLIENT_SEQUENCE_EXHAUSTED SYNC_SERVER_SEQUENCE_EXHAUSTED SYNC_TRANSPORT_GENERATION_MISMATCH SYNC_TRANSPORT_GENERATION_EXHAUSTED",
    "cursor": "SYNC_CURSOR_INVALID SYNC_CURSOR_EXPIRED SYNC_CURSOR_ACCOUNT_MISMATCH SYNC_CURSOR_DEVICE_MISMATCH SYNC_CURSOR_GENERATION_MISMATCH SYNC_BOOTSTRAP_EXPIRED SYNC_BOOTSTRAP_GENERATION_CHANGED",
    "device": "SYNC_NOT_ENABLED_FOR_ACCOUNT DEVICE_LIMIT_REACHED DEVICE_NOT_REGISTERED DEVICE_NOT_FOUND DEVICE_REVOKED DEVICE_VERSION_CONFLICT DEVICE_REAUTH_REQUIRED DEVICE_REAUTH_TARGET_MISMATCH DEVICE_DISPLAY_NAME_INVALID",
    "settings": "SYNC_POLICY_VERSION_CONFLICT LOCAL_SETTINGS_VERSION_CONFLICT",
    "workspace": "WORKSPACE_NOT_FOUND WORKSPACE_ACCOUNT_MISMATCH WORKSPACE_LOCKED WORKSPACE_KEY_UNAVAILABLE WORKSPACE_SWITCH_CONFLICT",
    "notification": "NOTIFICATION_WORKSPACE_AMBIGUOUS NOTIFICATION_WORKSPACE_UNAVAILABLE",
    "import": "IMPORT_SOURCE_CHANGED IMPORT_SOURCE_OWNED IMPORT_SOURCE_EPOCH_EXHAUSTED IMPORT_LINEAGE_MISMATCH IMPORT_VERSION_CONFLICT IMPORT_PUBLISH_INCOMPLETE IMPORT_BATCH_ABANDONED IMPORT_BATCH_SUPERSEDED SYNC_IMPORT_CAPACITY_EXCEEDED IMPORT_DUPLICATE_IDENTITY IMPORT_REFERENCE_INVALID",
    "storage": "SYNC_OUTBOX_CORRUPTED SYNC_APPLY_FAILED SYNC_BOOTSTRAP_INCOMPLETE SYNC_CHANGE_GROUP_TOO_LARGE",
    "diagnostic": "SYNC_DIAGNOSTIC_EXPORT_FAILED",
    "conflict": "SYNC_CONFLICT_NOT_FOUND SYNC_CONFLICT_VERSION_MISMATCH SYNC_CONFLICT_ALREADY_RESOLVED SYNC_ENTITY_CONFLICT_BLOCKED SYNC_ENTITY_SYNC_EFFECT_PENDING SYNC_NOTICE_HEAD_MISMATCH",
    "failed_local": "SYNC_FAILED_CHANGE_NOT_FOUND SYNC_FAILED_CHANGE_VERSION_CONFLICT",
    "auth": "AUTH_SESSION_EXPIRED AUTH_REFRESH_TOKEN_REUSED AUTH_SESSION_ACCOUNT_MISMATCH AUTH_REAUTH_FAILED",
    "retention": "RETENTION_TRUSTED_TIME_REQUIRED",
    "domain": "HABIT_HISTORY_IMMUTABLE HABIT_CHECK_IN_STATE_INVALID SYNC_HABIT_OPERATION_ID_REUSED SYNC_RESOLUTION_CANDIDATE_INVALID REMINDER_METHOD_UNSUPPORTED ANNIVERSARY_REMINDER_CONFIG_INVALID",
    "http_calibration": "API_IDEMPOTENCY_KEY_REUSED AUTH_USERNAME_INVALID AVATAR_NOT_FOUND",
}

# Explicit shared domain failures. Query, notification delivery, Android system,
# legacy CAS, storage and authentication failures never become saved mutations.
TERMINAL_DOMAIN = set("""
EVENT_TITLE_EMPTY EVENT_TIME_INVALID EVENT_NOT_FOUND
RECURRENCE_RULE_INVALID RECURRENCE_TARGET_INVALID ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED
OCCURRENCE_NOT_FOUND OCCURRENCE_OPERATION_INVALID
REMINDER_TIME_INVALID REMINDER_TARGET_NOT_FOUND REMINDER_METHOD_INVALID REMINDER_METHOD_UNSUPPORTED
HABIT_TITLE_EMPTY HABIT_NOT_FOUND HABIT_TARGET_DELETED HABIT_DATE_RANGE_INVALID
HABIT_CHALLENGE_TOO_LONG HABIT_TARGET_INVALID HABIT_TARGET_LOCKED HABIT_START_DATE_LOCKED
HABIT_ALREADY_ENDED HABIT_NOT_STARTED HABIT_END_NOT_EARLY HABIT_CHECK_IN_DATE_OUT_OF_RANGE
HABIT_CHECK_IN_FUTURE_DATE HABIT_CHECK_IN_NOT_FOUND HABIT_REMINDER_CONFIG_INVALID
HABIT_HISTORY_IMMUTABLE HABIT_CHECK_IN_STATE_INVALID SYNC_HABIT_OPERATION_ID_REUSED
APPEARANCE_COLOR_TOKEN_INVALID CATEGORY_NAME_EMPTY CATEGORY_NOT_FOUND
ANNIVERSARY_TITLE_EMPTY ANNIVERSARY_DATE_INVALID ANNIVERSARY_CALENDAR_UNSUPPORTED
ANNIVERSARY_NOT_FOUND ANNIVERSARY_TARGET_DELETED ANNIVERSARY_REMINDER_CONFIG_INVALID
ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED
SYNC_ENTITY_CONFLICT_BLOCKED SYNC_CONFLICT_NOT_FOUND SYNC_CONFLICT_VERSION_MISMATCH
SYNC_CONFLICT_ALREADY_RESOLVED SYNC_CHANGE_GROUP_TOO_LARGE SYNC_RESOLUTION_CANDIDATE_INVALID
""".split())
TERMINAL_IMPORT = set("""
IMPORT_DUPLICATE_IDENTITY IMPORT_REFERENCE_INVALID IMPORT_BATCH_ABANDONED
IMPORT_BATCH_SUPERSEDED SYNC_IMPORT_CAPACITY_EXCEEDED IMPORT_SOURCE_CHANGED
""".split())
LOCAL_ONLY = set("""
IMPORT_SOURCE_OWNED IMPORT_SOURCE_EPOCH_EXHAUSTED IMPORT_PUBLISH_INCOMPLETE
SYNC_OUTBOX_CORRUPTED SYNC_APPLY_FAILED SYNC_BOOTSTRAP_INCOMPLETE
SYNC_POLICY_VERSION_CONFLICT LOCAL_SETTINGS_VERSION_CONFLICT
SYNC_DIAGNOSTIC_EXPORT_FAILED SYNC_FAILED_CHANGE_NOT_FOUND SYNC_FAILED_CHANGE_VERSION_CONFLICT
SYNC_NOTICE_HEAD_MISMATCH SYNC_ENTITY_SYNC_EFFECT_PENDING RETENTION_TRUSTED_TIME_REQUIRED
AUTH_SESSION_ACCOUNT_MISMATCH
""".split())


def derive():
    old = yaml.safe_load((CONTRACTS / "error_codes.yaml").read_text(encoding="utf-8"))["errors"]
    counters = yaml.safe_load((CONTRACTS / "sync/sync_counter_registry.yaml").read_text(encoding="utf-8"))["counter_kinds"]
    error_groups = {code: group for group, codes in GROUPS.items() for code in codes.split()}
    for row in counters.values():
        error_groups[row["error"]] = "counter"
    codes = sorted(set(old) | set(error_groups))
    context = {code: NULL for code in codes}
    for code in {row["error"] for row in counters.values()}:
        context[code] = object_of({"counter_kind": {"enum": sorted(kind for kind, row in counters.items() if row["error"] == code)}})
    context.update({
        "SYNC_HABIT_OPERATION_ID_REUSED": object_of({"operation_id": UUID4}),
        "SYNC_PROTOCOL_VERSION_UNSUPPORTED": object_of({"supported_protocol_versions": const([1]), "received_protocol_version": SAFE}),
        "SYNC_BATCH_TOO_LARGE": object_of({"maximum_items": const(100), "maximum_bytes": const(1048576)}),
        "SYNC_CLIENT_SEQUENCE_GAP": object_of({"expected_client_sequence": POSITIVE}),
        "SYNC_TRANSPORT_GENERATION_MISMATCH": object_of({"current_sync_transport_generation": SAFE}),
        "DEVICE_LIMIT_REACHED": object_of({"device_limit": const(10), "registration_pending": const(True)}),
        "DEVICE_VERSION_CONFLICT": object_of({"current_device_version": SAFE}),
        "SYNC_POLICY_VERSION_CONFLICT": object_of({"current_sync_enabled": BOOL, "current_sync_policy_revision": SAFE}),
        "LOCAL_SETTINGS_VERSION_CONFLICT": object_of({"receive_reminders": BOOL, "sync_enabled": BOOL,
            "current_sync_policy_revision": SAFE, "current_local_settings_revision": SAFE}),
        "IMPORT_VERSION_CONFLICT": object_of({"current_stage": {"enum": ["local_staging", "server_staging", "repair_required", "server_confirmed", "publish_applied", "cleanup_pending", "completed", "superseded", "abandoned"]},
            "current_head_batch_id": UUID4, "current_import_revision": POSITIVE}),
        "SYNC_CONFLICT_VERSION_MISMATCH": object_of({"conflict_id": UUID4, "current_conflict_version": POSITIVE}),
        "SYNC_FAILED_CHANGE_VERSION_CONFLICT": object_of({"failed_change_id": UUID4, "current_failed_change_revision": POSITIVE}),
        "SYNC_NOTICE_HEAD_MISMATCH": object_of({"current_notice_id": nullable(UUID4), "current_notice_sequence": nullable(POSITIVE)}),
        "RETENTION_TRUSTED_TIME_REQUIRED": object_of({"logout_operation_id": UUID4, "logout_risk_revision": SAFE,
            "allowed_cache_policies": const(["destroy_now"])}),
        "API_IDEMPOTENCY_KEY_REUSED": object_of({"field": const("Idempotency-Key")}),
    })
    # Keep the already typed verification context, including its strict challenge
    # shape; it belongs to the Auth response, never a Sync/diagnostic payload.
    if "AUTH_EMAIL_UNVERIFIED" in context:
        context["AUTH_EMAIL_UNVERIFIED"] = ref("api_error_context", "common")
    registry = {"version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/12",
                "legacy_registry": "../error_codes.yaml", "errors": {}}
    native_variants, api_variants = [], []
    for code in codes:
        group = error_groups.get(code, "legacy_domain")
        retry = bool(old.get(code, {}).get("retryable", False))
        if group in {"protocol", "ordering", "counter", "cursor", "workspace", "import", "retention"}:
            retry = False
        recovery = ("bootstrap" if code in {"SYNC_CURSOR_EXPIRED", "SYNC_CURSOR_GENERATION_MISMATCH"} else
                    "restart_bootstrap" if code in {"SYNC_BOOTSTRAP_EXPIRED", "SYNC_BOOTSTRAP_GENERATION_CHANGED"} else
                    "current_lifecycle_transport_recovery" if code == "SYNC_TRANSPORT_GENERATION_MISMATCH" else
                    "bounded_backoff" if retry else "caller_or_owner_action_no_automatic_retry")
        backend = (old.get(code, {}).get("module") in {"api", "auth", "user"}
            or group in {"protocol", "ordering", "cursor", "device", "import", "auth", "http_calibration"}
            or code in TERMINAL_DOMAIN or code in TERMINAL_IMPORT)
        backend_kinds = sorted(kind for kind, row in counters.items() if row["error"] == code and row["owner"].startswith("backend."))
        if group == "counter":
            backend = bool(backend_kinds)
        if code in LOCAL_ONLY:
            backend = False
        boundaries = ["native_v3"] + (["backend_v1_sync"] if backend else [])
        backend_context = object_of({"counter_kind": {"enum": backend_kinds}}) if backend_kinds else context[code]
        saved_intent = code in TERMINAL_DOMAIN
        terminal = code in TERMINAL_DOMAIN | TERMINAL_IMPORT
        registry["errors"][code] = {"category": group, "boundaries": boundaries, "retryable": retry,
            "allows_local_saved_intent": saved_intent, "allows_terminal_rejection": terminal,
            "terminal_scope": "resolution_only" if code == "SYNC_RESOLUTION_CANDIDATE_INVALID" else "habit_operation_only" if code == "SYNC_HABIT_OPERATION_ID_REUSED" else "ordinary_or_resolution" if saved_intent else "import_lifecycle_only" if terminal else "none",
            "sequence_consumption": "only_valid_typed_mutation_terminal_receipt" if terminal else "request_failure_never_consumes_sequence",
            "recovery": recovery, "context_schema": context[code], "legacy_semantics": code in old,
            "boundary_context_schemas": {"native_v3": context[code], **({"backend_v1_sync": backend_context} if backend else {})},
            "counter_actions": {kind: {key: row[key] for key in ("owner", "at_last_increment", "at_max")}
                                for kind, row in counters.items() if row["error"] == code}}
        properties = {"code": const(code), "message": {"type": "string", "minLength": 1, "maxLength": 512},
                      "retryable": const(retry), "context": context[code]}
        native_variants.append(object_of(properties))
        if backend:
            api_variants.append(object_of({**properties, "context": backend_context, "field_errors": array(ref("api_field_error", "common"), 64),
                "retry_after_seconds": nullable({"type": "integer", "minimum": 1, "maximum": 86400}) if retry else NULL}))
    outputs = {CONTRACTS / "sync/sync_error_registry.yaml": registry}
    for name, value, directory, domain, version in (
        ("sync_error_code", {"enum": codes}, "sync", "sync_protocol", 1),
        ("native_error", {"oneOf": native_variants}, "native_v3/common", "native", 3),
        ("api_error", {"oneOf": api_variants}, "backend_sync_v1/common", "backend_api", 1),
    ):
        schema = document(name, value, "12", directory)
        schema.update({"x-contract-domain": domain, "x-contract-version": version})
        outputs[CONTRACTS / directory / (name + ".schema.json")] = schema
    # Envelope data is bound to a concrete Schema by the capability ledger.
    # API and Native envelopes are independent; neither references the other.
    for name, directory, version in (("native_result", "native_v3/common", 3), ("api_result", "backend_sync_v1/common", 1)):
        body = object_of({"ok": BOOL, "data": {"type": ["object", "array", "string", "number", "boolean", "null"]},
            "error": nullable(ref("native_error" if version == 3 else "api_error", directory)),
            "contract_version": const(version), "request_id": {"type": "string", "minLength": 1, "maxLength": 128}},
            oneOf=[{"properties": {"ok": const(True), "error": NULL}},
                   {"properties": {"ok": const(False), "data": NULL, "error": ref("native_error" if version == 3 else "api_error", directory)}}])
        schema = document(name, body, "5,8,12", directory)
        schema.update({"x-contract-domain": "native" if version == 3 else "backend_api", "x-contract-version": version})
        outputs[CONTRACTS / directory / (name + ".schema.json")] = schema
    return outputs


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            if actual != value:
                raise ValueError("Error registry/schema drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            text = yaml.safe_dump(value, sort_keys=False, allow_unicode=True) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n"
            path.write_text(text, encoding="utf-8")
    print(json.dumps({"errors": len(derive()[CONTRACTS / "sync/sync_error_registry.yaml"]["errors"]), "status": "planned_not_frozen"}))


if __name__ == "__main__":
    main()
