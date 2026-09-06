"""Shared deterministic resolution shape and candidate rules; no persistence."""
import copy

from domain_reference import check, definitions, validate_schema
from protocol_reference import digest, mutation_hash


def validate_resolution(mutation, payload_hash):
    validate_schema("sync/sync_conflict_resolution_mutation.schema.json", mutation)
    check(mutation_hash(mutation) == payload_hash, "SYNC_PAYLOAD_HASH_MISMATCH")
    keys = [row["merge_key"] for row in mutation["causal_predecessors"]]
    check(keys == sorted(set(keys)), "SYNC_CAUSAL_PREDECESSOR_INVALID")
    variants = definitions()[1]["targets"][mutation["target_type"]]["variants"]
    allowed = set().union(*(row["merge_groups"] for row in variants.values()))
    check(set(keys) <= allowed and all(row["client_sequence"] is None or row["client_sequence"] < mutation["client_sequence"]
        for row in mutation["causal_predecessors"]), "SYNC_CAUSAL_PREDECESSOR_INVALID")
    for record in (mutation["conflict_recovery_snapshot"], mutation["payload"]["resolution"]["manual_candidate"]):
        if record is not None:
            check(all(record[name] == mutation[name] for name in ("target_type", "target_id")), "SYNC_IDENTITY_MISMATCH")


def choose_resolution(detail, baseline, choice):
    mode = choice["mode"]
    if mode == "manual_edit":
        return copy.deepcopy(choice["manual_candidate"]["fact"])
    selections = {digest(item["key"]): item["source"] for item in choice["group_choices"]}
    if mode == "per_field":
        check(len(selections) == len(choice["group_choices"]) and set(selections) == {digest(row["key"]) for row in detail["conflicting_groups"]},
            "SYNC_PAYLOAD_INVALID")
    selected_rows = []
    for row in detail["conflicting_groups"]:
        source = ("local" if mode == "keep_local" else "remote") if mode != "per_field" else selections[digest(row["key"])]
        selected_rows.append((source, row["local_candidate" if source == "local" else "server_candidate"]))
    deleted = [item["kind"] == "deleted" for _, item in selected_rows]
    if any(deleted):
        # Deletion is an entity lifecycle decision. A mixture cannot reconstruct
        # a valid live fact, particularly once the old payload has been retired.
        check(all(deleted), "SYNC_RESOLUTION_CANDIDATE_INVALID")
        return copy.deepcopy(baseline.get("fact"))
    recovery = detail["recovery_snapshot"]
    candidate = copy.deepcopy(baseline.get("fact") or (recovery["fact"] if recovery else None))
    check(candidate is not None, "SYNC_CONFLICT_NOT_FOUND")
    if baseline["kind"] != "fact_after_image" and any(source == "local" for source, _ in selected_rows):
        check(recovery is not None, "SYNC_CONFLICT_NOT_FOUND")
        candidate = copy.deepcopy(recovery["fact"])
        candidate["deleted_at"] = None
    for _, selected in selected_rows:
        check(selected["kind"] == "value", "SYNC_RESOLUTION_CANDIDATE_INVALID")
        candidate.update(selected["projection"]["value"])
    return candidate


def validate_resolution_fields(target, baseline, candidate, *, manual=False):
    """Enforce identity/audit/readonly owners even for a full manual candidate."""
    if candidate is None:
        return
    from protocol_reference import typed_definition
    definition = typed_definition(target, baseline)
    for name, field in definition["fields"].items():
        if (field["role"] in {"identity", "audit"} or field["server_generated"] or name in {
                "first_check_in_at", "target_count_snapshot_hundredths", "unit_snapshot"} or
                manual and not field["update"] and name != "deleted_at"):
            check(candidate[name] == baseline[name], "HABIT_HISTORY_IMMUTABLE" if name in {
                "first_check_in_at", "target_count_snapshot_hundredths", "unit_snapshot"} else "SYNC_RESOLUTION_CANDIDATE_INVALID")
    if target == "habit" and baseline["first_check_in_at"] is not None:
        check(all(candidate[name] == baseline[name] for name in ("target_count_hundredths", "unit", "start_date")), "HABIT_HISTORY_IMMUTABLE")
