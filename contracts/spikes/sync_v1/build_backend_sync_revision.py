"""Additive Backend v1 compatibility revision; keep every released leaf unchanged."""
import argparse
import copy
import json

from build_sync_domain_contracts import CONTRACTS, BASE, object_of, read, yaml
from build_sync_protocol_contracts import SAFE, UUID, UUID4, const, ref, document


# Operation names, paths and ordering owners come from plan 02 §8.1. These
# declarations do not manufacture Controllers or activate an unimplemented route.
NEW_ENDPOINTS = {
    "system.time": ("GET", "/system/time", "backend_sync_v1/common/empty_request", "common/server_time_response", "public", "none"),
    "auth.reauthenticate": ("POST", "/auth/reauthenticate", "auth/reauthenticate_request", "auth/reauthenticate_response", "bearer", "single_use_grant"),
    "device.register": ("POST", "/devices", "device/register_device_request", "device/device_response", "bearer", "active_account_installation"),
    "device.list": ("GET", "/devices", "backend_sync_v1/common/empty_request", "device/device_list_response", "bearer", "read"),
    "device.rename": ("PATCH", "/devices/{device_id}/name", "device/rename_device_request", "device/device_response", "bearer", "device_version_cas"),
    "device.update_settings": ("PATCH", "/devices/{device_id}/settings", "device/update_device_settings_request", "device/device_response", "bearer", "current_device_version_cas"),
    "device.revoke": ("POST", "/devices/{device_id}/revoke", "device/revoke_device_request", "device/device_revocation_response", "bearer", "single_use_reauth_and_device_cas"),
    "sync.device_fence": ("POST", "/sync/device-fence", "sync/sync_device_fence_request", "sync/sync_device_fence_response", "bearer", "fence_operation_receipt"),
    "sync.exchange": ("POST", "/sync/exchange", "sync/sync_exchange_request", "sync/sync_exchange_response", "bearer", "device_sequence_receipt"),
    "sync.bootstrap": ("POST", "/sync/bootstrap", "sync/sync_bootstrap_request", "sync/sync_bootstrap_page_response", "bearer", "materialized_bootstrap_session"),
    "sync.import.status": ("GET", "/sync/imports/status", "sync/import_status_request", "sync/import_status_response", "bearer", "read"),
    "sync.import.takeover": ("POST", "/sync/imports/{import_batch_id}/takeover", "sync/import_takeover_request", "sync/import_takeover_response", "bearer", "lineage_and_origin_range_cas"),
    "sync.import.abandon": ("POST", "/sync/imports/{import_batch_id}/abandon", "sync/import_abandon_request", "sync/import_abandon_response", "bearer", "lineage_and_origin_range_cas"),
    "sync.import.cleanup_confirm": ("POST", "/sync/imports/{import_lineage_id}/cleanup-confirm", "sync/import_cleanup_confirm_request", "sync/import_cleanup_confirm_response", "bearer", "lineage_cas"),
    "sync.get_status": ("GET", "/sync/status", "backend_sync_v1/sync/get_status_request", "sync/backend_remote_sync_status_response", "bearer", "read"),
    "sync.conflict.list": ("GET", "/sync/conflicts", "sync/backend_list_sync_conflicts_request", "sync/backend_sync_conflict_list_response", "bearer", "read"),
    "sync.conflict.get": ("GET", "/sync/conflicts/{conflict_id}", "backend_sync_v1/common/empty_request", "sync/backend_sync_conflict_detail_response", "bearer", "read"),
    "sync.conflict.resolve": ("POST", "/sync/conflicts/{conflict_id}/resolve", "sync/backend_resolve_sync_conflict_request", "sync/backend_sync_conflict_resolution_response", "bearer", "device_sequence_receipt_single_route"),
}
UNREGISTERED = {"auth.token.refresh", "auth.logout", "user.get_current", "device.register"}
PENDING = UNREGISTERED | {"device.list", "auth.reauthenticate", "device.revoke"}


def derive():
    out = {}

    def emit(name, body, directory):
        path = "backend_sync_v1/" + directory
        data = document(name, body, "3,8.1", path)
        data.update({"x-contract-domain": "backend_api", "x-contract-version": 1, "x-compatibility-revision": "sync-v1"})
        out[CONTRACTS / path / (name + ".schema.json")] = data
        return ref(name, path)

    registration = read("auth/registration_request.schema.json")
    registration["properties"]["locale"] = const("zh-CN")
    registration["properties"]["password"]["x-sensitive"] = True
    emit("registration_request", {k: v for k, v in registration.items() if not k.startswith("$") and k != "title"}, "auth")
    update = read("user/update_current_user_request.schema.json")
    props = {name: update["properties"][name] for name in ("username", "display_name")}
    emit("update_current_user_request", {"type": "object", "additionalProperties": False, "minProperties": 1, "properties": props}, "user")
    old = read("user/current_user_response.schema.json")
    current = emit("current_user_response", object_of({"account": old["properties"]["account"], "profile": old["properties"]["profile"],
        "preferences": ref("user_preferences_fact", "sync/v1"), "account_profile_revision": SAFE, "preferences_revision": SAFE,
        "legacy_locale": {"type": "string", "minLength": 1, "maxLength": 35, "readOnly": True,
            "description": "Historical read/audit only; new registration is zh-CN. Never a portable preference or update field."}}), "user")
    authentication = emit("authentication_response", object_of({"current_user": current, "tokens": ref("token_pair_response", "auth")}), "auth")
    emit("empty_request", object_of({}), "common")
    emit("get_status_request", object_of({"device_id": UUID4}), "sync")
    changes = {
        "auth.register": {"request": "backend_sync_v1/auth/registration_request.schema.json"},
        "user.update_current": {"request": "backend_sync_v1/user/update_current_user_request.schema.json"},
        "auth.logout": {"response": "auth/server_logout_terminal_response.schema.json"},
    }
    base = yaml.safe_load((CONTRACTS / "backend_api.yaml").read_text(encoding="utf-8"))
    endpoints = copy.deepcopy(base["endpoints"])
    for operation, entry in endpoints.items():
        entry.update({"implementation_status": "planned", "release_status": "planned", "compatibility_revision": "sync-v1",
            "existing_controller": operation != "auth.registration.email.update"})
        if entry["result"]["data"] == "user/current_user_response.schema.json":
            entry["result"]["data"] = "backend_sync_v1/user/current_user_response.schema.json"
        elif entry["result"]["data"] == "auth/authentication_response.schema.json":
            entry["result"]["data"] = "backend_sync_v1/auth/authentication_response.schema.json"
        entry["result"]["envelope"] = "backend_sync_v1/common/api_result.schema.json"
        for key, value in changes.get(operation, {}).items():
            if key == "response":
                entry["result"]["data"] = value
            else:
                entry[key] = value
    for operation, (method, path, request, response, auth, ordering) in NEW_ENDPOINTS.items():
        path_fields = [part[1:-1] for part in path.split("/") if part.startswith("{")]
        endpoints[operation] = {
            "method": method, "path": path, "content_type": "application/json", "authentication": auth,
            "implementation_status": "planned", "release_status": "planned", "existing_controller": False,
            "request": request + ".schema.json", "request_location": "query" if method == "GET" else "body",
            "get_body": "forbidden" if method == "GET" else "not_applicable",
            "query_codec": "strict per-schema decimal/boolean/enum; nullable query values are omitted; duplicates/unknown names rejected" if method == "GET" else "not_applicable",
            "path_parameters": object_of({name: UUID4 if name != "import_lineage_id" else {**UUID, "pattern": r"^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"} for name in path_fields}),
            "path_payload_identity": "equality required when same identifier occurs in body, manifest or resolution payload; mismatch zero writes",
            "result": {"envelope": "backend_sync_v1/common/api_result.schema.json", "data": response + ".schema.json"},
            "idempotency": {"required": False, "behavior": ordering, "client_idempotency_key": "forbidden_use_typed_identity"},
            "account_identity": "none" if auth == "public" else "verified_principal_only_no_body_account_or_user_id",
            "error_registry": "sync/sync_error_registry.yaml", "transport_fence_check": operation.startswith("sync.") and ordering != "read",
        }
        if operation == "device.revoke":
            endpoints[operation]["reauth_header"] = {"name": "X-Reauth-Token", "required": True, "sensitive": True, "single_use": True}
        if operation == "system.time":
            endpoints[operation].update({"cache_control": "no-store", "rate_limit_scope": "ip", "account_session_device_database_access": "forbidden", "cookies": "forbidden"})
    account_operations = sorted(operation for operation, entry in endpoints.items() if entry["authentication"] != "public")
    capabilities = {"version": 1, "rule_anchor": "cloud-sync-02/8.1", "default": "deny", "implementation_status": "planned",
        "public_operations": sorted(set(endpoints) - set(account_operations)),
        "account_operations": {operation: {
            "unregistered": operation in UNREGISTERED, "pending_registration": operation in PENDING, "registered": True,
            "pending_installation_match_required": operation == "device.register",
            "additional_checks": "endpoint authentication, current Principal ownership, entitlement, device/transport/CAS remain mandatory"
        } for operation in account_operations}}
    out[CONTRACTS / "backend_sync_v1/session_capabilities.yaml"] = capabilities
    revision = {"version": 1, "contract_domain": "backend_api", "version_domain": "backend_api/v1", "compatibility_revision": "sync-v1",
        "base_path": "/api/v1", "transport": "https", "implementation_status": "planned", "release_status": "planned",
        "preserved_revision": "../backend_api.yaml", "rule_anchor": "cloud-sync-02/3,8.1",
        "http_conventions": {"success_status": 200, "application_error_http_statuses": [400, 401, 403, 404, 409, 429, 500, 503],
            "application_errors_require_valid_envelope": True, "http_status_must_match_error_mapping": True,
            "non_envelope_failure": "transport_or_protocol_failure_no_fabricated_business_code", "unknown_fields": "reject",
            "scalar_coercion": "reject_numeric_string_boolean_null_coercion", "idempotency_payload_mismatch": {"http_status": 409, "code": "API_IDEMPOTENCY_KEY_REUSED"},
            "retry_after": "optional integral Retry-After header must exactly mirror legal 1..86400 body seconds; mismatch invalidates envelope",
            "retryable_http_statuses": [429, 500, 502, 503, 504], "transport_retry_policy": "sync/sync_protocol_invariants.yaml#/retry",
            "canonical_idempotency_hash": "typed canonical body; avatar uses binary content hash plus typed operation identity; changed payload never replays a previous success"},
        "calibration": {"observed_report": "../spikes/sync_v1/backend_http_calibration_result.json", "observed_endpoint_count": 17, "existing_controller_count": 16,
            "observed_status_and_retry_mirror": "keep actual typed HTTP status/body behavior with an explicit closed mapping",
            "implementation_differences": ["reject ignored unknown fields and scalar coercions", "reject reused idempotency key with different registration/avatar payload", "restrict user.update_current to username/display_name", "register locale constant zh-CN", "separate profile/preferences revisions and canonical download-only profile changes", "broker server-logout terminal adds trustworthy server_time"]},
        "compatibility": {"old_leaf_schemas": "unchanged and protected by baseline", "old_mobile_reader": "legacy v2/v5 remains bound to old contract; sync-v1 callers select this revision only after the capability gate",
            "registration_email_update": "controller absent; remains planned and unavailable until 04 implementation and HTTP fixtures pass",
            "locale": "old values readable through legacy_locale only; no locale selector or locale sync writer", "settings": "no arbitrary settings map enters the new response/writer; existing backend JSONB is historical storage until a separately validated migration"},
        "endpoints": endpoints}
    revision["session_capabilities"] = "backend_sync_v1/session_capabilities.yaml"
    out[CONTRACTS / "backend_sync_v1/backend_api.yaml"] = revision
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out = derive()
    for path, value in out.items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            assert actual == value, path.name
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(value, sort_keys=False, allow_unicode=True) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"backend_compatibility_schemas": 6, "calibrated_operations": 17, "new_operations": len(NEW_ENDPOINTS), "status": "planned"}))
