"""Pure presentation rebase. Never mutates authoritative facts or frozen intents.

The durable download/bootstrap owner must call this within its own transaction.
This module does not claim that integration, receipt authentication, or storage.
"""
import copy

from counter_reference import integer
from domain_reference import check, validate_fact, validate_graph, validate_patch
from habit_operation_reference import HabitOperationStore
from owned_graph_reference import nodes_for
from protocol_reference import typed_definition, mutation_dependencies, validate_mutation


def target_key(value):
    return value["target_type"], value["target_id"]


def _project_one(graph, mutation, conflicts, *, deleted_anchors=frozenset()):
    result = copy.deepcopy(graph)
    target, key, operation = mutation["target_type"], target_key(mutation), mutation["operation_type"]
    old = graph.get(key)
    payload = mutation["payload"]
    if operation == "resolve_conflict":
        from resolution_contract_reference import choose_resolution
        detail = conflicts.get(payload["conflict_id"])
        check(detail is not None, "SYNC_CONFLICT_NOT_FOUND")
        check(detail["conflict_version"] == payload["expected_conflict_version"], "SYNC_CONFLICT_VERSION_MISMATCH")
        baseline = {"kind": "deleted_entity_anchor"} if old is None else {
            "kind": "tombstone" if old["fact"].get("deleted_at") else "fact_after_image", "fact": old["fact"]}
        if payload["prepared_owned_dependencies"] or any(target_key(row["key"]) != key for row in detail["conflicting_groups"]):
            from owned_resolution_reference import compose_resolution
            result, _ = compose_resolution(detail, graph, payload["resolution"], payload["prepared_owned_dependencies"], root_baseline=baseline)
        else:
            candidate = choose_resolution(detail, baseline, payload["resolution"])
            if candidate is None:
                result.pop(key, None)
            else:
                result[key] = {"target_type": target, "target_id": key[1], "fact": candidate}
                validate_fact(result[key])
    elif target == "habit_check_in":
        parent_key = "habit", payload["habit_id"]
        parent = graph.get(parent_key)
        check(parent is not None, "HABIT_NOT_FOUND")
        parent_fact = parent["fact"]
        check(parent_fact["deleted_at"] is None, "HABIT_TARGET_DELETED")
        check(parent_fact["is_active"] and parent_fact["ended_date"] is None, "HABIT_ALREADY_ENDED")
        fact = HabitOperationStore._candidate(parent_fact, old["fact"] if old else None, mutation)
        if fact is not None:
            result[key] = {"target_type": target, "target_id": key[1], "fact": fact}
            if parent_fact["first_check_in_at"] is None:
                result[parent_key]["fact"]["first_check_in_at"] = payload["occurred_at"]
    elif target in {"event", "anniversary", "habit", "reminder_intent"} and operation in {"create", "update", "restore"}:
        check(operation != "create" or old is None or old["fact"] == payload["fact"], "SYNC_ENTITY_CONFLICT_BLOCKED")
        for _, record in nodes_for(mutation, graph, require_null_predecessors=False):
            existing = graph.get(target_key(record))
            check(existing is None or not typed_definition(record["target_type"], record["fact"])["immutable_fact"]
                  or existing["fact"] == record["fact"], "SYNC_ENTITY_CONFLICT_BLOCKED")
            result[target_key(record)] = record
    else:
        if operation in {"create", "restore"}:
            check(operation != "create" or old is None or old["fact"] == payload["fact"], "SYNC_ENTITY_CONFLICT_BLOCKED")
            fact = copy.deepcopy(payload["fact"])
        elif operation == "update":
            check(old is not None, "SYNC_TARGET_UNSUPPORTED")
            validate_patch(target, payload["patch"], old,
                variant=old["fact"]["owner_type"] if target == "reminder_intent" else "default")
            fact = {**old["fact"], **payload["patch"]}
        elif operation == "delete":
            check(old is not None and "deleted_at" in old["fact"], "SYNC_TARGET_UNSUPPORTED")
            fact = {**old["fact"], "deleted_at": payload["deleted_at"]}
        else:
            raise ValueError("REFERENCE_PROJECTION_OPERATION_NOT_IMPLEMENTED")
        record = {"target_type": target, "target_id": key[1], "fact": fact}
        validate_fact(record)
        result[key] = record
    validate_graph(list(result.values()), deleted_anchors=set(deleted_anchors) - set(result))
    return result


def project_local_intents(snapshot_items, intents, *, server_highest):
    """Return derived facts and retained draft reasons in original sequence order.

    `server_highest` comes from validated sync/bootstrap identity, never a clock.
    Pending <= highest awaits its exact receipt; it is not implicitly accepted,
    failed, removed, or applied again on top of already included server changes.
    """
    integer(server_highest)
    graph, deleted, blocked, conflicts = {}, {}, set(), {}
    for item in snapshot_items:
        if item["kind"] in {"fact_after_image", "tombstone"}:
            graph[target_key(item)] = {name: copy.deepcopy(item[name]) for name in ("target_type", "target_id", "fact")}
            if item["kind"] == "tombstone":
                deleted[target_key(item)] = item["entity_version"]
        elif item["kind"] == "deleted_entity_anchor":
            deleted[target_key(item)] = item["entity_version"]
        elif item["kind"] == "unresolved_conflict":
            blocked.add(target_key(item["conflict"]))
            conflicts[item["conflict"]["conflict_id"]] = item["conflict"]
    deleted_anchors = set(deleted) - set(graph)
    validate_graph(list(graph.values()), deleted_anchors=deleted_anchors)
    sequences, normalized = set(), []
    for row in intents:
        check(set(row) == {"kind", "state", "mutation", "payload_hash"}, "SYNC_OUTBOX_CORRUPTED")
        check(row["kind"] in {"pending", "receipt_unknown", "failed", "awaiting_effect"} and
            row["state"] in ({"active", "superseded_pending"} if row["kind"] == "failed" else {"active"}), "SYNC_OUTBOX_CORRUPTED")
        m = row["mutation"]
        validate_mutation(m, row["payload_hash"])
        check(not m["operation_type"].startswith("import_"), "SYNC_OUTBOX_CORRUPTED")
        sequence = m["client_sequence"]
        check(sequence not in sequences, "SYNC_OUTBOX_CORRUPTED")
        sequences.add(sequence)
        normalized.append(row)
    applied, drafts = [], []
    for row in sorted(normalized, key=lambda row: row["mutation"]["client_sequence"]):
        m = row["mutation"]
        sequence, key = m["client_sequence"], target_key(m)
        targets = {key} | {target_key(node) for node in mutation_dependencies(m)}
        reason, error = None, None
        if row["state"] == "superseded_pending":
            reason = "superseded_draft"
        elif row["kind"] == "receipt_unknown" or (row["kind"] == "pending" and sequence <= server_highest):
            reason = "awaiting_exact_receipt"
        elif targets & blocked and m["operation_type"] != "resolve_conflict":
            reason = "unresolved_conflict"
        elif key in deleted and m["operation_type"] not in {"restore", "delete", "clear", "resolve_conflict"} and not (
            m["target_type"] == "habit_check_in" and m["base_entity_version"] >= deleted[key]):
            reason = "deleted_baseline"
        else:
            try:
                graph = _project_one(graph, m, conflicts, deleted_anchors=deleted_anchors)
                applied.append(sequence)
            except ValueError as failure:
                reason, error = "domain_or_graph_not_applicable", str(failure)
        if reason:
            drafts.append({"client_sequence": sequence, "reason": reason, "error": error,
                "candidate": copy.deepcopy(m["conflict_recovery_snapshot"] or m["payload"].get("fact")),
                "mutation": copy.deepcopy(m), "payload_hash": row["payload_hash"]})
    return {"facts": [graph[key] for key in sorted(graph)], "projected_sequences": applied, "retained_drafts": drafts}
