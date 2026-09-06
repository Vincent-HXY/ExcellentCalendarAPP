"""Untrusted boundary checks only; no fabricated runtime, HTTP or Keystore."""
from functools import lru_cache
import json

from build_sync_domain_contracts import CONTRACTS, yaml
from domain_reference import validate_schema, check


@lru_cache(maxsize=1)
def registries():
    return [yaml.safe_load((CONTRACTS / path).read_text(encoding="utf-8")) for path in (
        "native_v3/method_channels.yaml", "native_v3/native_calls.yaml", "backend_sync_v1/backend_api.yaml")]


def check_public_request(operation, request, route=None):
    entry = registries()[0]["methods"].get(operation)
    check(entry is not None and entry["release_status"] != "blocked", "FEATURE_NOT_IMPLEMENTED")
    validate_schema(entry["request"], request)
    if entry["route_policy"] == "explicit_workspace_and_route_cas":
        check(route is not None and route["route_state"] == "ready", "WORKSPACE_LOCKED")
        check(request["workspace_id"] == route["active_workspace_id"] and request["expected_active_route_revision"] == route["active_route_revision"], "WORKSPACE_SWITCH_CONFLICT")
    return entry


def check_native_request(operation, request, pinned_binding):
    entry = registries()[1]["calls"].get(operation)
    check(entry is not None, "FEATURE_NOT_IMPLEMENTED")
    validate_schema(entry["request"], request)
    if "binding" in request:
        check(request["binding"] == pinned_binding, "WORKSPACE_ACCOUNT_MISMATCH")
        payload = request.get("payload", {})
        for field in ("workspace_id", "runtime_instance_id", "device_id", "session_generation", "sync_transport_generation"):
            if field in payload and field in pinned_binding:
                check(payload[field] == pinned_binding[field], "WORKSPACE_ACCOUNT_MISMATCH")
        if operation.split(".")[0] in {"event", "event_occurrence", "reminder", "habit", "anniversary", "category", "calendar", "search"}:
            check_business_workspace(request.get("payload"), pinned_binding)
    return entry


def check_business_workspace(value, binding):
    if isinstance(value, dict):
        for field in ("workspace_id", "workspace_kind", "runtime_instance_id"):
            if field in value:
                check(value[field] == binding[field], "WORKSPACE_ACCOUNT_MISMATCH")
        for child in value.values():
            check_business_workspace(child, binding)
    elif isinstance(value, list):
        for child in value:
            check_business_workspace(child, binding)


def check_native_result(lane, operation, result, pinned_binding=None):
    entry = registries()[0 if lane == "public" else 1]["methods" if lane == "public" else "calls"].get(operation)
    check(entry is not None and entry["release_status"] != "blocked", "FEATURE_NOT_IMPLEMENTED")
    validate_schema(entry["result"]["envelope"], result)
    if result["ok"]:
        validate_schema(entry["result"]["data"], result["data"])
        if lane == "internal" and pinned_binding is not None and "binding" in result["data"]:
            check(result["data"]["binding"] == pinned_binding, "WORKSPACE_ACCOUNT_MISMATCH")
            if operation.split(".")[0] in {"event", "event_occurrence", "reminder", "habit", "anniversary", "category", "calendar", "search"}:
                check_business_workspace(result["data"].get("payload"), pinned_binding)


def check_binary_open_arguments(metadata, key):
    validate_schema("native_v3/internal/open_workspace_request.schema.json", metadata)
    check(type(key) is bytes, "WORKSPACE_KEY_UNAVAILABLE")
    check(len(key) == (32 if metadata["workspace_kind"] == "account" else 0), "WORKSPACE_KEY_UNAVAILABLE")
    # Signature verification, cipher opening and seed consumption are deliberately
    # outside this shape check; this function cannot authorize writable open.


def resolve_notification_workspace(payload, visible_workspaces, legacy_candidates):
    compat = yaml.safe_load((CONTRACTS / "native_v3/business_compatibility.yaml").read_text(encoding="utf-8"))
    validate_schema(compat["schema_mapping"]["notification/notification_tap_payload.schema.json"], payload)
    if "workspace_id" in payload:
        candidates = [row for row in visible_workspaces if row["workspace_id"] == payload["workspace_id"] and row["workspace_kind"] == payload["workspace_kind"]]
    else:
        check(len(legacy_candidates) == 1, "NOTIFICATION_WORKSPACE_AMBIGUOUS")
        candidates = [row for row in visible_workspaces if row["workspace_id"] == legacy_candidates[0]]
    check(len(candidates) == 1 and candidates[0]["unlockable"], "NOTIFICATION_WORKSPACE_UNAVAILABLE")
    return candidates[0]["workspace_id"]
