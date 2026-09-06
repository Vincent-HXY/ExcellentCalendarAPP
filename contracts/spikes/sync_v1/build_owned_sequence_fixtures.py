"""Fixed cross-device owned-graph histories with explicit actor/sequence inputs."""
import copy
import json
from pathlib import Path

from build_owned_graph_fixtures import derive as owned_examples, make_mutation
from build_target_fixtures import build
from build_bootstrap_fixtures import A, D, identifier

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/owned_sequence_vectors.json"


def derive():
    cases = []
    examples = owned_examples()["cases"]
    samples = build()["samples"]
    root, child = samples["event"], samples["reminder_intent_event"]
    seed = [root, child]

    def command(sequence, title, advance, *, prior=None, base=1, serial=1, content=False):
        patch = {name: copy.deepcopy(child["fact"][name]) for name in ("is_enabled", "templates")}
        patch["templates"][0]["advance_minutes"] = advance
        child_node = make_mutation(child, sequence, patch=patch, base=base)
        child_node["causal_predecessors"] = [{**row, "client_sequence": prior} for row in child_node["causal_predecessors"]]
        dependency = {name: child_node[name] for name in ("target_type", "target_id", "operation_type", "base_entity_version", "causal_predecessors", "conflict_recovery_snapshot")}
        dependency["payload"] = patch
        result = make_mutation(root, sequence, patch={"content" if content else "title": title}, dependencies=[dependency], base=base)
        result["mutation_id"] = identifier(serial)
        result["causal_predecessors"] = [{**row, "client_sequence": prior} for row in result["causal_predecessors"]]
        return result

    def add(name, graph, operations, statuses, facts, groups, conflicts=0, absent=False):
        cases.append({"id": "FX-MERGE-OWNED-SEQUENCE-" + name, "family": "FX-MERGE", "rule_anchor": "cloud-sync-01/9.1,9.4;cloud-sync-02/6.2,7.1-7.3,7.5",
            "input": {"seed": copy.deepcopy(graph), "operations": [{"device_id": device, "mutation": value} for device, value in operations]},
            "expected": {"statuses": statuses, "facts": facts, "groups": groups, "conflicts": conflicts, "has_absent_server_candidate": absent}})
    for number, name in enumerate(("EVENT-CREATE", "HABIT-CREATE")):
        add(name, [], [(A, copy.deepcopy(examples[number]["input"]["mutations"][0]))], ["accepted"], 3, 1)
    first = command(1, "第一次", 2)
    second = command(2, "第二次", 3, prior=1, serial=2)
    add("CAUSAL-SUCCESSOR", seed, [(A, first), (A, second)], ["accepted", "accepted"], 2, 2)
    add("NO-EFFECT-SUCCESSOR", seed, [(A, command(1, "第一次", 15)), (A, second)], ["accepted", "accepted"], 2, 2)
    remote = command(1, "远端内容", 4, base=2, serial=3, content=True)
    add("REMOTE-INTERLEAVING", seed, [(A, first), (D, remote), (A, second)], ["accepted", "accepted", "partially_merged"], 2, 3, 1)
    for absent, name in ((False, "IMMUTABLE-REVISION-COLLISION"), (True, "UNPUBLISHED-RULE-ABSENT")):
        original = examples[2]["input"]
        left, right = copy.deepcopy(original["mutations"])
        right["client_sequence"] = 1
        if absent:
            right["payload"]["patch"]["recurrence_revision"] = 3
            right["conflict_recovery_snapshot"]["recurrence_revision"] = 3
            rule = right["payload"]["owned_dependencies"][0]
            rule["target_id"] = rule["target_id"].split("#")[0] + "#3"
            rule["payload"]["revision"] = 3
        add(name, original["seed"], [(A, left), (D, right)], ["accepted", "partially_merged"], 4, 2, 1, absent)
    return {"fixture_version": 1, "scope": "device ordering, qualified child causal receipts, immutable revision collision and typed unpublished candidates",
        "cases": cases}


if __name__ == "__main__":
    FIXTURE.write_text(json.dumps(derive(), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"cases": len(derive()["cases"])}))
