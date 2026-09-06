"""Build planned, exact Sync v1 wire definitions; never mutate a released v2 definition.

Shape validation is deliberately separate from transaction/graph invariants. The latter
are exercised by the isolated protocol model and must also be implemented by each owner.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from build_sync_domain_contracts import BASE, CONTRACTS, MAX, DATE_TIME, UUID, object_of, nullable, yaml

SAFE = {"type": "integer", "minimum": 0, "maximum": MAX}
POSITIVE = {**SAFE, "minimum": 1}
UUID4 = {**UUID, "pattern": r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"}
HASH = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
BOOL = {"type": "boolean"}
NULL = {"type": "null"}
# Canonical Base64URL without padding. The final sextet has zero unused bits.
OPAQUE = {"type": "string", "minLength": 16, "maxLength": 2048,
          "pattern": r"^(?:[A-Za-z0-9_-]{4})*(?:[A-Za-z0-9_-]{2}[AEIMQUYcgkosw048]|[A-Za-z0-9_-][AQgw])?$"}
TARGET_ID = {"type": "string", "minLength": 36, "maxLength": 53}
RESOLUTIONS = ["keep_local", "keep_remote", "per_field", "manual_edit"]
TERMINAL = ["accepted", "partially_merged", "conflict", "rejected", "staged"]
OWNED = {
    "event": ["event_recurrence", "reminder_intent"],
    "anniversary": ["anniversary_recurrence", "reminder_intent"],
    "habit": ["habit_recurrence", "reminder_intent"],
    "habit_check_in": ["habit"],
    "reminder_intent": ["event", "event_recurrence"],
}


def const(value):
    return {"const": value}


def array(items, maximum, minimum=0):
    return {"type": "array", "minItems": minimum, "maxItems": maximum, "items": items}


def ref(name, directory="sync"):
    return {"$ref": BASE + directory + "/" + name + ".schema.json"}


def target_id(target):
    return ({"type": "string", "pattern": r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#[1-9][0-9]{0,15}$"}
            if target == "event_recurrence" else UUID)


def document(name, body, anchor="6-7", directory="sync"):
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE + directory + "/" + name + ".schema.json",
            "title": "SyncV1 " + name, "x-contract-domain": "sync_protocol", "x-contract-version": 1,
            "x-implementation-status": "planned", "x-release-status": "planned", "x-rule-anchor": "cloud-sync-02/" + anchor,
            **copy.deepcopy(body)}


def derive():
    registry = yaml.safe_load((CONTRACTS / "sync/sync_field_registry.yaml").read_text(encoding="utf-8"))
    targets = registry["targets"]
    out = {}

    def emit(name, body, anchor="6-7", directory="sync"):
        out[CONTRACTS / directory / (name + ".schema.json")] = document(name, body, anchor, directory)
        return ref(name, directory)

    identity = {"target_type": {"enum": list(targets)}, "target_id": TARGET_ID}
    qualified_key = {**identity, "merge_key": {"type": "string", "minLength": 1, "maxLength": 64}}
    predecessor = object_of({"merge_key": qualified_key["merge_key"], "client_sequence": nullable(POSITIVE)})
    predecessors = array(predecessor, 64)
    provenance = emit("sync_import_provenance", object_of({"import_lineage_id": UUID,
        "source_workspace_id": UUID4, "source_epoch": SAFE, "source_target_type": {"enum": list(targets)},
        "source_id": {"type": "string", "minLength": 1, "maxLength": 256}}), "7.6/IMP-05,6.3")

    # A field-group projection is generated from the same whitelist as the fact.
    # Qualifying the key by target avoids confusing an owned child with its root.
    projections = []
    key_variants = []
    for target, config in targets.items():
        for variant, definition in config["variants"].items():
            for merge_key, fields in definition["merge_groups"].items():
                properties = {name: definition["fields"][name]["schema"] for name in fields}
                key = {"target_type": const(target), "target_id": target_id(target), "merge_key": const(merge_key)}
                if target == "reminder_intent":
                    key["owner_type"] = const(variant)
                projections.append(object_of({**key, "value": object_of(properties)}))
                key_variants.append(object_of(key))
    projection = emit("sync_field_projection", {"oneOf": projections}, "7.2,7.5")
    key_ref = emit("sync_merge_key", {"oneOf": key_variants}, "7.2-7.3")

    # Dependencies cannot contain further dependencies or lifecycle capabilities.
    # The graph validator additionally checks ownership, actual touched keys and
    # the root/child coherence component before *any* canonical publication.
    dependency_variants = []
    for target in sorted({child for children in OWNED.values() for child in children}):
        operations = ["create"] if target.endswith("recurrence") else ["create", "update"]
        for variant, definition in targets[target]["variants"].items():
            for operation in operations:
                if operation == "update" and not definition["patch_schema"]:
                    continue
                name = target + ("_" + variant if target == "reminder_intent" else "")
                shape = ref(name + ("_fact" if operation == "create" else "_patch"), "sync/v1")
                dependency_variants.append(object_of({"target_type": const(target), "target_id": target_id(target),
                    "operation_type": const(operation), "base_entity_version": SAFE,
                    "causal_predecessors": predecessors, "payload": shape,
                    "conflict_recovery_snapshot": NULL if operation == "create" else ref(name + "_fact", "sync/v1")}))
    dependency = emit("sync_owned_dependency", {"oneOf": dependency_variants}, "7.1-7.3")
    dependencies = array(dependency, 2)

    source = {"enum": ["manual", "notification_action"]}
    check_in_common = {"operation_id": UUID4, "habit_id": UUID, "check_date": {"type": "string", "format": "date"},
                       "source": source, "occurred_at": DATE_TIME}
    check_in_fields = targets["habit_check_in"]["variants"]["default"]["fields"]
    snapshot = object_of({name: check_in_fields[name]["schema"] for name in
                          ("target_count_snapshot_hundredths", "unit_snapshot")})
    snapshot["oneOf"] = [{"properties": {"target_count_snapshot_hundredths": NULL, "unit_snapshot": NULL}},
                         {"properties": {"target_count_snapshot_hundredths": POSITIVE, "unit_snapshot": {"type": "string"}}}]
    mutable_payloads = {}
    for target, config in targets.items():
        if target == "account_profile":
            continue
        target_payloads = []
        for variant, definition in config["variants"].items():
            name = target + ("_" + variant if target == "reminder_intent" else "")
            fact_ref = ref(name + "_fact", "sync/v1")
            owned = dependencies if target in OWNED else array(dependency, 0)
            # Create includes every fact field. Backend-owned genesis fields must
            # carry their genesis values; import has a separate, typed branch.
            create_fact = copy.deepcopy(fact_ref)
            if target == "category":
                create_fact = {"allOf": [fact_ref, {"properties": {"reorder_revision": const(0), "deleted_at": NULL}}]}
            elif target == "habit":
                create_fact = {"allOf": [fact_ref, {"properties": {"first_check_in_at": NULL, "deleted_at": NULL}}]}
            elif "deleted_at" in definition["fields"]:
                create_fact = {"allOf": [fact_ref, {"properties": {"deleted_at": NULL}}]}
            operations = {"create": object_of({"fact": create_fact, "owned_dependencies": owned})}
            if definition["patch_schema"]:
                operations["update"] = object_of({"patch": ref(name + "_patch", "sync/v1"), "owned_dependencies": owned})
            if "deleted_at" in definition["fields"] and target != "habit_check_in":
                operations["delete"] = object_of({"deleted_at": DATE_TIME})
                operations["restore"] = object_of({"fact": {"allOf": [fact_ref, {"properties": {"deleted_at": NULL}}]},
                                                     "owned_dependencies": owned})
            if target == "user_preferences":
                operations.pop("create")
            if target == "habit_check_in":
                operations = {
                    "increment": object_of({**check_in_common, "delta_hundredths": POSITIVE, "snapshot": snapshot}),
                    "decrement": object_of({**check_in_common, "delta_hundredths": POSITIVE, "snapshot": snapshot}),
                    "replace_total": object_of({**check_in_common, "fact": fact_ref}),
                    "clear": object_of({**check_in_common, "deleted_at": DATE_TIME}),
                }
            for operation, body in operations.items():
                payload_ref = emit(name + "_" + operation + "_payload", body, "7.1-7.3,7.7", "sync/v1")
                target_payloads.append((operation, payload_ref, fact_ref))
            # Import facts and deletions are typed separately; no hidden device
            # state or profile is allowed to enter an import range.
            imported = object_of({"fact": fact_ref, "source_id": {"type": "string", "minLength": 1, "maxLength": 256}})
            if target == "user_preferences":
                imported = object_of({"habit_progress_color": definition["fields"]["habit_progress_color"]["schema"]})
            import_ref = emit(name + "_import_payload", imported, "7.6/IMP-01-IMP-05", "sync/v1")
            target_payloads.append(("import_put", import_ref, NULL))
            if target != "user_preferences" and variant == next(iter(config["variants"])):
                target_payloads.append(("import_delete", emit(name + "_import_delete_payload", object_of({
                    "source_id": {"type": "string", "minLength": 1, "maxLength": 256}, "deleted_at": DATE_TIME}),
                    "7.6/IMP-05", "sync/v1"), NULL))
        mutable_payloads[target] = target_payloads

    # Exact mutation envelope: hash is carried alongside it by the upload item,
    # avoiding a self-referential payload_hash field in the canonical input.
    envelope = {"protocol_version": const(1), "mutation_id": UUID4, "client_sequence": POSITIVE,
        "target_type": {}, "target_id": {}, "operation_type": {}, "base_entity_version": SAFE,
        "causal_predecessors": predecessors, "import_lineage_id": nullable(UUID), "import_batch_id": nullable(UUID4),
        "import_source_workspace_id": nullable(UUID4), "import_source_epoch": nullable(SAFE),
        "import_item_ordinal": nullable(SAFE), "import_manifest_hash": nullable(HASH),
        "predecessor_batch_id": nullable(UUID4), "payload": {}, "conflict_recovery_snapshot": {}, "created_at": DATE_TIME}
    variants = []
    for target, operations in mutable_payloads.items():
        for operation, payload_ref, fact_ref in operations:
            properties = {**envelope, "target_type": const(target), "target_id": target_id(target),
                          "operation_type": const(operation), "payload": payload_ref}
            imported = operation.startswith("import_")
            for key in ("import_lineage_id", "import_batch_id", "import_source_workspace_id", "import_source_epoch",
                        "import_item_ordinal", "import_manifest_hash", "predecessor_batch_id"):
                properties[key] = envelope[key] if imported else NULL
                if imported and key != "predecessor_batch_id":
                    properties[key] = {"oneOf": [envelope[key]], "not": NULL}
            properties["conflict_recovery_snapshot"] = (fact_ref if operation in {"update", "increment", "decrement", "replace_total", "clear"}
                                                        and target != "user_preferences" else NULL)
            if imported:
                properties["causal_predecessors"] = array(predecessor, 0)
            if operation == "create":
                properties["base_entity_version"] = const(0)
            variants.append(object_of(properties))

    target_counts = {name: SAFE for name in targets if name not in {"account_profile", "user_preferences"}}
    manifest = emit("sync_import_manifest", object_of({"source_workspace_id": UUID4, "source_epoch": SAFE,
        "source_snapshot_hash": HASH, "target_counts": object_of(target_counts),
        "portable_preferences_count": {"type": "integer", "minimum": 0, "maximum": 1},
        # Declarations also survive in signed capacity-rejected range proofs.
        # IMP-11 operational limits are enforced before local allocation and in
        # the Backend reservation transaction, not by erasing the declaration.
        "total_item_count": SAFE,
        "total_canonical_bytes": SAFE,
        "mapping_digest": HASH, "manifest_hash": HASH}), "7.1,7.6/IMP-01,IMP-11")
    for operation in ("import_begin", "import_commit"):
        properties = {**envelope, "target_type": const("workspace_import"), "target_id": UUID4,
            "operation_type": const(operation), "base_entity_version": SAFE, "causal_predecessors": array(predecessor, 0),
            "import_lineage_id": UUID, "import_batch_id": UUID4, "import_source_workspace_id": UUID4,
            "import_source_epoch": SAFE, "import_item_ordinal": NULL, "import_manifest_hash": HASH,
            "conflict_recovery_snapshot": NULL, "payload": object_of({"manifest": manifest,
                "takeover_reason": nullable({"enum": ["local_evidence_lost", "origin_unavailable", "ttl_payload_reclaimed"]}),
                "range_close_proof_id": nullable(UUID4)})}
        variants.append(object_of(properties))
    mutation = emit("sync_mutation", {"oneOf": variants}, "7.1")
    upload = emit("sync_hashed_mutation", object_of({"mutation": mutation, "payload_hash": HASH}), "6.1,7.1")

    versions = array(object_of({"key": key_ref, "field_version": SAFE}), 64)
    typed_after = []
    typed_tombstones = []
    for target in targets:
        properties = {"target_type": const(target), "target_id": target_id(target), "entity_version": POSITIVE,
                      "field_versions": versions, "import_provenance": nullable(provenance),
                      "fact": ref(target + "_fact", "sync/v1")}
        typed_after.append(object_of({"kind": const("fact_after_image"), **properties}))
        if target not in {"account_profile", "user_preferences", "event_recurrence", "event_occurrence_state", "reminder_intent"}:
            typed_tombstones.append(object_of({"kind": const("tombstone"), **properties,
                "deleted_at": DATE_TIME, "delete_server_sequence": POSITIVE}))
    after = emit("sync_fact_after_image", {"oneOf": typed_after}, "6.3,7.7")
    tombstone = emit("sync_tombstone", {"oneOf": typed_tombstones}, "6.3,7.5")
    deleted = emit("sync_deleted_entity_anchor", object_of({"kind": const("deleted_entity_anchor"), **identity,
        "entity_version": POSITIVE, "delete_server_sequence": POSITIVE, "import_provenance": nullable(provenance)}), "6.3,7.5")
    candidate = {"oneOf": [object_of({"kind": const("value"), "projection": projection}),
                            object_of({"kind": const("deleted"), "entity_version": POSITIVE, "delete_server_sequence": POSITIVE})]}
    # A proposed owned row can lose its parent's atomic component before that
    # child ever existed. It has neither a value nor a deletion history.
    server_candidate = {"oneOf": [*candidate["oneOf"], object_of({"kind": const("absent")})]}
    conflict_groups = array(object_of({"key": key_ref, "server_candidate": server_candidate, "local_candidate": candidate},
        allOf=[{"if": {"properties": {"server_candidate": {"properties": {"kind": const("absent")}}}},
            "then": {"properties": {"key": {"properties": {"target_type": {"enum": ["event_recurrence", "anniversary_recurrence", "habit_recurrence", "reminder_intent"]}}}}}}]), 64, 1)
    merged_groups = array(object_of({"projection": projection, "resulting_entity_version": POSITIVE,
                                    "resulting_field_version": POSITIVE}), 64)
    conflict = emit("sync_conflict_detail", object_of({"conflict_id": UUID4, "conflict_version": POSITIVE,
        **identity, "status": const("unresolved"), "source_device_id": UUID4, "received_at": DATE_TIME,
        "conflicting_groups": conflict_groups, "auto_merged_groups": merged_groups,
        "recovery_snapshot": nullable(ref("sync_fact", "sync/v1"))}), "7.5")
    receipt_identity = object_of({"receipt_id": UUID4, "device_id": UUID4, "client_sequence": POSITIVE,
                                 "mutation_id": UUID4, "payload_hash": HASH})
    conflict_delta = emit("sync_conflict_delta", {"oneOf": [
        object_of({"kind": const("created"), "conflict": conflict}),
        object_of({"kind": const("resolved"), "conflict_id": UUID4, "conflict_version": POSITIVE,
            "resolved_at": DATE_TIME, "resolution_mode": {"enum": RESOLUTIONS},
            "resulting_entity_version": POSITIVE, "resolution_receipt": receipt_identity})]}, "6.3,7.5")
    changes = array({"oneOf": [after, tombstone, deleted]}, 64)
    deltas = array(conflict_delta, 64)
    group = emit("sync_change_group", object_of({"kind": const("change_group"), "change_group_id": UUID4,
        "server_sequence": POSITIVE, "payload_hash": HASH, "entity_changes": changes, "conflict_deltas": deltas},
        anyOf=[{"properties": {"entity_changes": {"minItems": 1}}}, {"properties": {"conflict_deltas": {"minItems": 1}}}]), "6.3")

    effect = object_of({"effect_change_group_id": UUID4, "effect_group_last_server_sequence": POSITIVE})
    causal_result = {"oneOf": [
        object_of({"key": key_ref, "causal_disposition": const("applied"), "resulting_field_version": POSITIVE,
                   "effective_prior_sequence": nullable(POSITIVE), "effective_prior_version": SAFE}),
        object_of({"key": key_ref, "causal_disposition": const("no_effect"), "resulting_field_version": NULL,
                   "effective_prior_sequence": nullable(POSITIVE), "effective_prior_version": SAFE})]}
    # Preserve the exact safe context with the stable rejected receipt. Import
    # lifecycle failures cannot be projected as ordinary failed local changes.
    from build_sync_error_contracts import derive as error_definitions
    error_registry = error_definitions()[CONTRACTS / "sync/sync_error_registry.yaml"]["errors"]
    terminal_failures = []
    for code, definition in error_registry.items():
        if not definition["allows_terminal_rejection"]:
            continue
        normal = definition["allows_local_saved_intent"]
        stage = "abandoned" if code == "IMPORT_BATCH_ABANDONED" else "superseded" if code == "IMPORT_BATCH_SUPERSEDED" else "repair_required"
        bindings = [] if definition["terminal_scope"] in {"habit_operation_only", "resolution_only"} else [{"properties": {"import_batch_id": UUID4, "import_stage": const(stage)}}]
        if normal: bindings.append({"properties": {"import_batch_id": NULL, "import_stage": NULL}})
        terminal_failures.append({"properties": {"failure_code": const(code), "failure_context": definition["context_schema"]}, "oneOf": bindings})
    result_payloads = []
    for status in TERMINAL:
        properties = {"status": const(status), "receipt": receipt_identity,
            "effect": NULL if status == "staged" else nullable(effect),
            "per_key_results": array(causal_result, 64), "conflict_ids": array(UUID4, 64),
            "failure_code": {"type": "string"} if status == "rejected" else NULL,
            "failure_context": {} if status == "rejected" else NULL,
            "import_batch_id": UUID4 if status == "staged" else nullable(UUID4) if status == "rejected" else NULL,
            "import_stage": const("server_staging") if status == "staged" else nullable({"enum": ["repair_required", "abandoned", "superseded"]}) if status == "rejected" else NULL}
        if status == "staged":
            properties.update(per_key_results=array(causal_result, 0), conflict_ids=array(UUID4, 0))
        elif status == "conflict":
            properties.update(effect=effect, conflict_ids=array(UUID4, 64, 1))
        elif status == "partially_merged":
            properties.update(effect=effect, conflict_ids=array(UUID4, 64, 1), per_key_results=array(causal_result, 64, 1))
        result_payloads.append(object_of(properties, **({"oneOf": terminal_failures} if status == "rejected" else {})))
    import_errors = {"oneOf": [object_of({"code": const(code), "context": definition["context_schema"]})
        for code, definition in error_registry.items() if definition["allows_terminal_rejection"] and
        definition["terminal_scope"] not in {"habit_operation_only", "resolution_only"} and
        code not in {"IMPORT_BATCH_ABANDONED", "IMPORT_BATCH_SUPERSEDED", "SYNC_CONFLICT_NOT_FOUND", "SYNC_CONFLICT_VERSION_MISMATCH", "SYNC_CONFLICT_ALREADY_RESOLVED"}]}
    commit_common = {"receipt": receipt_identity, "per_key_results": array(causal_result, 0), "import_batch_id": UUID4}
    commit_result = emit("sync_import_commit_result", {"oneOf": [
        object_of({**commit_common, "status": const("accepted"), "effect": effect, "conflict_ids": array(UUID4, 64),
            "import_stage": const("server_confirmed"), "import_disposition": const("server_confirmed"), "error": NULL,
            "publish_group_id": UUID4, "commit_server_sequence": POSITIVE, "canonical_digest": HASH, "import_revision": POSITIVE}),
        object_of({**commit_common, "status": const("rejected"), "effect": NULL, "conflict_ids": array(UUID4, 0),
            "import_stage": const("repair_required"), "import_disposition": const("repair_required"),
            "error": import_errors, "next_revision": POSITIVE})]}, "6.2,7.6/IMP-03")
    result_payloads.append(commit_result)
    terminal = emit("sync_terminal_upload_result", {"oneOf": result_payloads}, "6.2,7.3")
    duplicate_variants = [object_of({"status": const("duplicate"), "original_status": const(status),
        "client_sequence": POSITIVE, "mutation_id": UUID4, "payload_hash": HASH,
        "original_result": {"allOf": [terminal, {"properties": {"status": const(status)}}]}}) for status in TERMINAL]
    result = emit("sync_upload_result", {"oneOf": [terminal, *duplicate_variants]}, "6.2")

    publish_identity = {"import_publish_group_id": UUID4, "import_lineage_id": UUID,
        "import_batch_id": UUID4, "source_workspace_id": UUID4, "source_epoch": SAFE, "manifest_hash": HASH,
        "mapping_digest": HASH, "begin_server_sequence": POSITIVE, "commit_server_sequence": POSITIVE,
        "total_chunk_count": SAFE, "total_item_count": SAFE, "publish_digest": HASH}
    publish_item = emit("sync_import_publish_item", {"oneOf": [
        object_of({"kind": const("import_publish_begin"), "server_sequence": POSITIVE, **publish_identity}),
        object_of({"kind": const("import_publish_chunk"), "server_sequence": POSITIVE, "import_publish_group_id": UUID4,
            "chunk_ordinal": SAFE, "first_item_ordinal": SAFE, "payload_hash": HASH,
            "items": array({"oneOf": [after, tombstone, deleted, conflict_delta]}, 500, 1)}),
        object_of({"kind": const("import_publish_commit"), "server_sequence": POSITIVE, **publish_identity})]}, "6.3,7.6/IMP-04")
    marker = emit("sync_import_publish_marker", object_of({"kind": const("import_publish_marker"), **publish_identity,
        "snapshot_provenance_digest": HASH, "snapshot_provenance_count": SAFE}), "6.3,7.6/IMP-04")
    anchor = emit("sync_requesting_device_causal_anchor", object_of({"kind": const("requesting_device_causal_anchor"),
        "key": key_ref, "client_sequence": POSITIVE, "resulting_field_version": POSITIVE}), "6.1,6.3,7.3")
    bootstrap_item = emit("sync_bootstrap_item", {"oneOf": [after, tombstone, deleted, marker, anchor,
        object_of({"kind": const("unresolved_conflict"), "conflict": conflict})]}, "6.3")

    transport = {"protocol_version": const(1), "device_id": UUID4, "sync_transport_generation": SAFE}
    request_properties = {**transport, "mode": const("normal"), "cursor": OPAQUE,
        "acknowledged_client_sequence_through": SAFE, "upload_mutations": array(upload, 100),
        "download_limit": {"type": "integer", "minimum": 1, "maximum": 500}}
    normal_request = object_of(request_properties)
    ack_request = object_of({**request_properties, "mode": const("ack_only"), "cursor": NULL,
        "upload_mutations": array(upload, 0), "download_limit": const(0)})
    exchange_request = emit("sync_exchange_request", {"oneOf": [normal_request, ack_request]}, "6.2-6.3")
    response_properties = {**transport, "mode": const("normal"), "results": array(result, 100),
        "changes": array({"oneOf": [group, publish_item]}, 500), "account_generation": SAFE,
        "snapshot_upper_bound": SAFE, "next_cursor": OPAQUE, "has_more": BOOL,
        "accepted_client_sequence_through": SAFE, "retention_floor_server_sequence": SAFE,
        "resolved_conflict_cleanup_before": DATE_TIME}
    normal_response = object_of(response_properties, allOf=[{"if": {"properties": {"has_more": const(True)}},
        "then": {"properties": {"changes": {"minItems": 1}}}}])
    ack_response = object_of({**response_properties, "mode": const("ack_only"), "results": array(result, 0),
        "changes": array(group, 0), "account_generation": NULL, "snapshot_upper_bound": NULL,
        "next_cursor": NULL, "has_more": const(False), "retention_floor_server_sequence": NULL,
        "resolved_conflict_cleanup_before": NULL})
    exchange_response = emit("sync_exchange_response", {"oneOf": [normal_response, ack_response]}, "6.2-6.3")

    recovery = emit("sync_sequence_recovery_bundle", object_of({"sync_transport_generation": SAFE,
        "highest_client_sequence": SAFE, "next_client_sequence": nullable(POSITIVE),
        "client_confirmed_through": SAFE, "client_sequence_exhausted": BOOL}, oneOf=[
        {"properties": {"highest_client_sequence": {"maximum": MAX - 1}, "client_sequence_exhausted": const(False), "next_client_sequence": POSITIVE}},
        {"properties": {"highest_client_sequence": const(MAX), "client_sequence_exhausted": const(True), "next_client_sequence": NULL}}]), "6.1")
    emit("sync_bootstrap_request", object_of({**transport, "bootstrap_cursor": nullable(OPAQUE),
        "download_limit": {"type": "integer", "minimum": 1, "maximum": 500}}), "6.3")
    bootstrap_identity = {**transport, "bootstrap_id": UUID4, "account_generation": SAFE, "snapshot_upper_bound": SAFE,
        "device_highest_client_sequence_at_snapshot": SAFE, "device_client_confirmed_through_at_snapshot": SAFE,
        "device_next_client_sequence_at_snapshot": nullable(POSITIVE), "device_client_sequence_exhausted_at_snapshot": BOOL,
        "retention_floor_server_sequence": SAFE, "resolved_conflict_cleanup_before": DATE_TIME, "expires_at": DATE_TIME,
        "snapshot_item_count": SAFE, "snapshot_items_hash": HASH, "total_page_count": POSITIVE,
        "page_item_limit": {"type": "integer", "minimum": 1, "maximum": 500}}
    emit("sync_bootstrap_page_response", object_of({**bootstrap_identity, "page_ordinal": SAFE, "page_hash": HASH,
        "items": array(bootstrap_item, 500), "next_bootstrap_cursor": nullable(OPAQUE), "has_more": BOOL,
        "terminal_sync_cursor": nullable(OPAQUE)}, allOf=[{"oneOf": [
        {"properties": {"device_highest_client_sequence_at_snapshot": {"maximum": MAX - 1},
            "device_next_client_sequence_at_snapshot": POSITIVE, "device_client_sequence_exhausted_at_snapshot": const(False)}},
        {"properties": {"device_highest_client_sequence_at_snapshot": const(MAX),
            "device_next_client_sequence_at_snapshot": NULL, "device_client_sequence_exhausted_at_snapshot": const(True)}}]}], oneOf=[
        {"properties": {"has_more": const(True), "items": {"minItems": 1}, "next_bootstrap_cursor": OPAQUE, "terminal_sync_cursor": NULL}},
        {"properties": {"has_more": const(False), "next_bootstrap_cursor": NULL, "terminal_sync_cursor": OPAQUE}}]), "6.3")

    runtime = {"workspace_id": UUID4, "runtime_instance_id": UUID4, "device_id": UUID4,
               "session_generation": SAFE, "sync_transport_generation": SAFE}
    prepared = []
    for intent in ("normal", "logout_final", "reenable_pull_only", "receipt_ack_flush"):
        wire = copy.deepcopy(ack_request if intent == "receipt_ack_flush" else normal_request)
        if intent == "reenable_pull_only":
            wire["properties"]["upload_mutations"] = array(upload, 0)
        prepared.append(object_of({**runtime, "prepared_exchange_id": UUID4, "run_intent": const(intent),
            "request_hash": HASH, "wire_request": wire,
            "logout_operation_id": UUID4 if intent == "logout_final" else NULL,
            "pull_gate_revision": SAFE if intent == "reenable_pull_only" else NULL}))
    emit("native_prepared_exchange_request", {"oneOf": prepared}, "6.2,8.3")
    emit("native_apply_exchange_response", object_of({**runtime, "prepared_exchange_id": UUID4,
        "response": normal_response}), "6.2,8.3")
    emit("native_acknowledge_upload_request", {"oneOf": [object_of({**runtime, "prepared_exchange_id": UUID4,
        "reported_acknowledged_client_sequence_through": SAFE, "response": response}) for response in (normal_response, ack_response)]}, "6.2,8.3")
    emit("sync_device_fence_request", object_of({"protocol_version": const(1), "device_id": UUID4,
        "fence_operation_id": UUID4, "expected_sync_transport_generation": SAFE,
        "reason": {"enum": ["clear_rebuild", "fresh_recovery", "force_local_relogin"]}}), "6.1")
    emit("sync_device_fence_response", object_of({"protocol_version": const(1), "device_id": UUID4,
        "fence_operation_id": UUID4, "previous_sync_transport_generation": SAFE,
        "recovery": recovery, "fence_receipt": OPAQUE, "result_hash": HASH,
        "resolved_absent_import_fences": array(ref("import_range_close_proof"), 20000)}), "6.1,7.6/IMP-12")

    return out


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = derive()
    for path, value in outputs.items():
        if args.check:
            if json.loads(path.read_text(encoding="utf-8")) != value:
                raise ValueError("Sync protocol definition drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"schemas": len(outputs), "status": "planned_not_frozen"}))


if __name__ == "__main__":
    main()
