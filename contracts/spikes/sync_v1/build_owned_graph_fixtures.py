"""Owned graph test inputs with literal, reviewable outcomes."""
import copy
import json
from pathlib import Path

from build_target_fixtures import build
from build_sync_domain_contracts import yaml

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/owned_graph_vectors.json"
TIME = "2026-09-05T01:00:00Z"


def make_mutation(record, number, *, operation="update", patch=None, dependencies=(), base=1):
    registry = yaml.safe_load((ROOT / "contracts/sync/sync_field_registry.yaml").read_text(encoding="utf-8"))["targets"]
    target, fact = record["target_type"], copy.deepcopy(record["fact"])
    definition = registry[target]["variants"][fact["owner_type"] if target == "reminder_intent" else "default"]
    payload = {"fact": fact, "owned_dependencies": list(dependencies)} if operation == "create" else {"patch": patch, "owned_dependencies": list(dependencies)}
    keys = sorted(definition["merge_groups"] if operation == "create" else {definition["fields"][name]["merge_key"] for name in patch})
    if patch: fact.update(patch)
    return {"protocol_version": 1, "mutation_id": f"{number:08x}-2222-4222-8222-222222222222", "client_sequence": number,
        "target_type": target, "target_id": record["target_id"], "operation_type": operation,
        "base_entity_version": 0 if operation == "create" else base,
        "causal_predecessors": [{"merge_key": name, "client_sequence": None} for name in keys],
        "import_lineage_id": None, "import_batch_id": None, "import_source_workspace_id": None, "import_source_epoch": None,
        "import_item_ordinal": None, "import_manifest_hash": None, "predecessor_batch_id": None,
        "payload": payload, "conflict_recovery_snapshot": fact if operation == "update" else None, "created_at": TIME}


def dependency(record):
    m = make_mutation(record, 1, operation="create")
    return {name: m[name] for name in ("target_type", "target_id", "operation_type", "base_entity_version", "causal_predecessors", "conflict_recovery_snapshot")} | {"payload": m["payload"]["fact"]}


def derive():
    samples = build()["samples"]
    event = copy.deepcopy(samples["event"])
    event["fact"].update(has_recurrence=True, recurrence_id=samples["event_recurrence"]["fact"]["recurrence_id"], recurrence_revision=1)
    rule = copy.deepcopy(samples["event_recurrence"])
    reminder = copy.deepcopy(samples["reminder_intent_event"])
    seed = [event, rule, reminder]

    def edit(number, hour, mode, title=None):
        next_rule = copy.deepcopy(rule)
        next_rule["target_id"] = rule["target_id"].split("#")[0] + "#2"
        next_rule["fact"].update(revision=2, frequency="weekly" if mode == 2 else "monthly",
            days_of_week=[6] if mode == 2 else [], day_of_month=None if mode == 2 else 5,
            start_at=f"2026-09-05T{hour:02d}:00:00Z")
        patch = {name: event["fact"][name] for name in ("is_all_day", "start_at", "end_at", "start_date", "end_date", "timezone", "has_recurrence", "recurrence_id", "recurrence_revision")}
        patch.update(start_at=next_rule["fact"]["start_at"], end_at=f"2026-09-05T{hour+1:02d}:00:00Z", recurrence_revision=2)
        if title: patch["title"] = title
        return make_mutation(event, number, patch=patch, dependencies=[dependency(next_rule)])

    create = make_mutation(event, 1, operation="create", dependencies=[dependency(rule), dependency(reminder)])
    habit = copy.deepcopy(samples["habit"]); habit["fact"]["first_check_in_at"] = None
    habit_create = make_mutation(habit, 1, operation="create",
        dependencies=[dependency(samples["habit_recurrence"]), dependency(samples["reminder_intent_habit"])])
    cases = []

    def add(name, graph, mutations, expected, family="FX-MERGE"):
        cases.append({"id": "OWNED-" + name, "family": family, "rule_anchor": "cloud-sync-02/7.1-7.3,7.7",
                      "input": {"seed": graph, "mutations": mutations}, "expected": expected})
    add("event-create-with-rule-and-intent", [], [create], {"statuses": ["accepted"], "fact_count": 3, "conflicts": 0})
    add("habit-create-with-rule-and-intent", [], [habit_create], {"statuses": ["accepted"], "fact_count": 3, "conflicts": 0})
    add("offline-same-revision-different-content", seed, [edit(1, 2, 2), edit(2, 3, 3, "独立标题")],
        {"statuses": ["accepted", "partially_merged"], "fact_count": 4, "conflicts": 1,
         "event_start": "2026-09-05T02:00:00Z", "event_title": "独立标题", "revision_two_frequency": "weekly"})
    add("same-candidate-is-no-effect", seed, [edit(1, 2, 2), edit(2, 2, 2)],
        {"statuses": ["accepted", "accepted"], "fact_count": 4, "conflicts": 0, "second_changed_count": 0})
    bad_owner = copy.deepcopy(create)
    bad_owner["payload"]["owned_dependencies"][1]["payload"]["owner_id"] = samples["habit"]["target_id"]
    add("wrong-owned-intent-owner", [], [bad_owner], {"error": "SYNC_IDENTITY_MISMATCH", "fact_count": 0}, "FX-TARGET")
    nested = copy.deepcopy(create)
    nested["payload"]["owned_dependencies"][0]["payload"]["owned_dependencies"] = []
    add("recursive-dependency-rejected", [], [nested], {"error": "SYNC_PAYLOAD_INVALID", "fact_count": 0}, "FX-TARGET")
    add("standalone-orphan-rule-rejected", [], [make_mutation(rule, 1, operation="create")],
        {"error": "RECURRENCE_TARGET_INVALID", "fact_count": 0}, "FX-TARGET")
    return {"fixture_version": 1, "scope": "owned graph coherence component and atomic publication; transport/causal chain remain separate",
            "cases": cases}


if __name__ == "__main__":
    value = derive(); FIXTURE.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(value["cases"])}))
