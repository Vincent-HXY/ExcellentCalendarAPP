"""Planned conflict/failed-intent capabilities with public and private projections."""
import argparse
import copy
import json

from build_sync_protocol_contracts import (CONTRACTS, SAFE, POSITIVE, UUID, UUID4, HASH, BOOL, NULL, OPAQUE,
    DATE_TIME, const, array, nullable, object_of, ref, document, target_id)
from build_sync_domain_contracts import yaml


def derive():
    out = {}

    def emit(name, body, *, native=False):
        value = document(name, body, "7.5,8,12")
        if native:
            value.update({"x-contract-domain": "native", "x-contract-version": 3})
        out[CONTRACTS / "sync" / (name + ".schema.json")] = value
        return ref(name)

    registry = yaml.safe_load((CONTRACTS / "sync/sync_field_registry.yaml").read_text(encoding="utf-8"))
    targets = [t for t, c in registry["targets"].items() if c["conflict_center"]]
    route = {"workspace_id": UUID4, "expected_active_route_revision": SAFE}
    response_route = {"workspace_id": UUID4, "runtime_instance_id": UUID4, "active_route_revision": SAFE}
    identity = {"target_type": {"enum": targets}, "target_id": {"type": "string", "minLength": 36, "maxLength": 53}}
    group = ref("sync_field_projection")
    key = ref("sync_merge_key")
    selection = object_of({"key": key, "source": {"enum": ["local", "remote"]}})
    fact = {"allOf": [ref("sync_fact", "sync/v1"), {"properties": {"target_type": {"enum": targets}}}]}
    resolution_variants = []
    for mode in ("keep_local", "keep_remote", "per_field", "manual_edit"):
        resolution_variants.append(object_of({"mode": const(mode),
            "group_choices": array(selection, 64, 1) if mode == "per_field" else array(selection, 0),
            "manual_candidate": fact if mode == "manual_edit" else NULL}))
    resolution = emit("sync_resolution_choice", {"oneOf": resolution_variants})
    summary_fields = {"conflict_id": UUID4, "conflict_version": POSITIVE, **identity,
        "source_device_id": UUID4, "received_at": DATE_TIME,
        "conflicting_merge_keys": array(key, 64, 1), "auto_merged_group_count": SAFE}
    summary = emit("sync_conflict_summary", {"oneOf": [
        object_of({**summary_fields, "status": {"enum": ["unresolved", "resolving"]}, "resolved_at": NULL, "retain_until": NULL}),
        object_of({**summary_fields, "status": const("resolved"), "resolved_at": DATE_TIME, "retain_until": DATE_TIME})]}, native=True)
    # Cursor here is a local read-snapshot token, never a server sync cursor.
    list_fields = {"status": {"enum": ["unresolved", "resolved", "all"]}, "target_type": nullable({"enum": targets}),
        "page_token": nullable(OPAQUE), "page_size": {"type": "integer", "minimum": 1, "maximum": 100}}
    emit("list_sync_conflicts_request", object_of({**route, **list_fields}), native=True)
    emit("get_sync_conflict_request", object_of({**route, "conflict_id": UUID4}), native=True)
    emit("sync_conflict_list_response", object_of({**response_route, "items": array(summary, 100),
        "next_page_token": nullable(OPAQUE), "read_snapshot_revision": SAFE, "unresolved_count": SAFE}), native=True)
    ui_candidate = {"oneOf": [object_of({"kind": const("value"), "projection": group}), object_of({"kind": const("deleted")})]}
    ui_server_candidate = {"oneOf": [*ui_candidate["oneOf"], object_of({"kind": const("absent")})]}
    ui_groups = array(object_of({"key": key, "server_candidate": ui_server_candidate, "local_candidate": ui_candidate},
        allOf=[{"if": {"properties": {"server_candidate": {"properties": {"kind": const("absent")}}}},
            "then": {"properties": {"key": {"properties": {"target_type": {"enum": ["event_recurrence", "anniversary_recurrence", "habit_recurrence", "reminder_intent"]}}}}}}]), 64, 1)
    emit("native_sync_conflict_detail_response", object_of({**response_route, "summary": summary,
        "conflicting_groups": ui_groups, "auto_merged_groups": array(object_of({"projection": group,
            "resulting_entity_version": POSITIVE, "resulting_field_version": POSITIVE}), 64),
        "recovery_candidate": nullable(fact), "manual_draft": nullable(fact), "allowed_resolution_modes": array({"enum": ["keep_local", "keep_remote", "per_field", "manual_edit"]}, 4)}), native=True)
    public_request = emit("resolve_sync_conflict_request", object_of({**route, "conflict_id": UUID4,
        "expected_conflict_version": POSITIVE, "resolution": resolution}), native=True)
    emit("sync_conflict_resolution_response", object_of({**response_route, "conflict_id": UUID4,
        "disposition": {"enum": ["queued", "already_resolving"]}, "status": const("resolving"),
        "conflict_version": POSITIVE, "status_revision": SAFE}), native=True)
    # Resolution uses the same immutable sequencing/hash envelope on its own
    # route. Flutter supplies none of these transport fields.
    sample = json.loads((CONTRACTS / "sync/sync_mutation.schema.json").read_text(encoding="utf-8"))["oneOf"][0]
    envelope = copy.deepcopy(sample["properties"])
    envelope.update({**identity, "operation_type": const("resolve_conflict"), "base_entity_version": SAFE,
        "causal_predecessors": array(object_of({"merge_key": {"type": "string", "minLength": 1, "maxLength": 64}, "client_sequence": nullable(POSITIVE)}), 64),
        "payload": object_of({"conflict_id": UUID4, "expected_conflict_version": POSITIVE, "resolution": resolution,
            "prepared_owned_dependencies": array(ref("sync_owned_dependency"), 2)}),
        "conflict_recovery_snapshot": nullable(fact)})
    for name in ("import_lineage_id", "import_batch_id", "import_source_workspace_id", "import_source_epoch", "import_item_ordinal", "import_manifest_hash", "predecessor_batch_id"):
        envelope[name] = NULL
    resolution_mutation = emit("sync_conflict_resolution_mutation", object_of(envelope))
    emit("backend_resolve_sync_conflict_request", object_of({"protocol_version": const(1), "device_id": UUID4,
        "sync_transport_generation": SAFE, "mutation": resolution_mutation, "payload_hash": HASH}))
    current = {"oneOf": [object_of({"kind": const("missing")}), object_of({"kind": const("unresolved"), "conflict_id": UUID4, "conflict_version": POSITIVE}),
        object_of({"kind": const("resolved"), "conflict_id": UUID4, "conflict_version": POSITIVE, "resolved_at": DATE_TIME,
            "effect_change_group_id": UUID4, "effect_group_last_server_sequence": POSITIVE})]}
    emit("backend_sync_conflict_resolution_response", object_of({"protocol_version": const(1), "device_id": UUID4,
        "sync_transport_generation": SAFE, "result": ref("sync_upload_result"), "current_conflict": current}))
    emit("backend_list_sync_conflicts_request", object_of(list_fields))
    remote_summary = emit("backend_sync_conflict_summary", {"oneOf": [
        object_of({**summary_fields, "status": const("unresolved"), "resolved_at": NULL, "retain_until": NULL}),
        object_of({**summary_fields, "status": const("resolved"), "resolved_at": DATE_TIME, "retain_until": DATE_TIME})]})
    emit("backend_sync_conflict_detail_response", {"oneOf": [
        object_of({"status": const("unresolved"), "detail": ref("sync_conflict_detail")}),
        object_of({"status": const("resolved"), "summary": {"allOf": [remote_summary, {"properties": {"status": const("resolved")}}]},
            "resolution_mode": {"enum": ["keep_local", "keep_remote", "per_field", "manual_edit"]},
            "resulting_entity_version": POSITIVE, "effect_change_group_id": UUID4, "effect_group_last_server_sequence": POSITIVE})]})
    emit("backend_sync_conflict_list_response", object_of({"items": array(remote_summary, 100),
        "next_page_token": nullable(OPAQUE), "read_snapshot_revision": SAFE}))
    emit("backend_remote_sync_status_response", object_of({"device_id": UUID4, "sync_transport_generation": SAFE,
        "account_generation": SAFE, "highest_client_sequence": SAFE, "client_confirmed_through": SAFE,
        "unresolved_conflict_count": SAFE, "last_sync_at": nullable(DATE_TIME), "blocked_reason": nullable(ref("sync_error_code"))}))

    # Failed intent is device-local. No mutation, sequence, hash or retransmit
    # switch appears in a public list/detail/discard response.
    errors = yaml.safe_load((CONTRACTS / "sync/sync_error_registry.yaml").read_text(encoding="utf-8"))["errors"]
    safe_context_fields = {"counter_kind", "conflict_id", "current_conflict_version", "current_failed_change_revision", "target_type", "target_id",
        "current_import_revision", "current_stage", "current_head_batch_id", "current_enabled", "current_sync_policy_revision",
        "current_local_settings_revision", "workspace_id", "limit_bytes", "actual_bytes"}
    failure_variants = []
    for code, config in errors.items():
        if not config["allows_local_saved_intent"]:
            continue
        original_context = config["context_schema"]
        if original_context.get("type") == "object":
            context = object_of({k: v for k, v in original_context["properties"].items() if k in safe_context_fields})
        else:
            # Non-object contexts are redacted in this public failed-intent
            # projection; original private terminal evidence remains unchanged.
            context = NULL
        failure_variants.append(object_of({"code": const(code), "context": context}))
    failure = emit("sync_saved_intent_failure", {"oneOf": failure_variants})
    upload_targets = [target for target, config in registry["targets"].items() if config["direction"] != "download"]
    failed_fact = {"allOf": [ref("sync_fact", "sync/v1"), {"properties": {"target_type": {"enum": upload_targets}}}]}
    failed_identity = {"failed_change_id": UUID4, "failed_change_revision": POSITIVE, **identity,
        "target_type": {"enum": upload_targets}}
    failed_summary = emit("sync_failed_local_change_summary", object_of({**failed_identity,
        "created_at": DATE_TIME, "failure": failure, "state": {"enum": ["active", "superseded_pending"]}}), native=True)
    emit("list_sync_failed_local_changes_request", object_of({**route, "page_token": nullable(OPAQUE),
        "page_size": {"type": "integer", "minimum": 1, "maximum": 100}}), native=True)
    emit("sync_failed_local_change_list_response", object_of({**response_route, "items": array(failed_summary, 100),
        "next_page_token": nullable(OPAQUE), "read_snapshot_revision": SAFE}), native=True)
    emit("get_sync_failed_local_change_request", object_of({**route, "failed_change_id": UUID4}), native=True)
    baseline = {"oneOf": [object_of({"kind": const("fact"), "value": failed_fact}), object_of({"kind": const("deleted")}), object_of({"kind": const("unavailable")})]}
    emit("sync_failed_local_change_detail", object_of({**response_route, "summary": failed_summary,
        "local_candidate": failed_fact, "manual_draft": nullable(failed_fact), "server_baseline": baseline,
        "can_edit_as_new": BOOL, "can_discard": BOOL}), native=True)
    emit("discard_sync_failed_local_change_request", object_of({**route, "failed_change_id": UUID4,
        "expected_failed_change_revision": POSITIVE}), native=True)
    emit("discard_sync_failed_local_change_response", object_of({**response_route, "failed_change_id": UUID4,
        "disposition": const("discarded"), "status": ref("sync_status_response")}), native=True)
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = derive()
    for path, value in result.items():
        if args.check:
            assert json.loads(path.read_text(encoding="utf-8")) == value, path.name
        else:
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"conflict_failed_schemas": len(result)}))
