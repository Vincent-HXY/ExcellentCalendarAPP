"""Reviewable, fixed operation sequences for master plan 9.3."""
import copy
import json
from pathlib import Path
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/habit_operation_vectors.json"
TIME = "2026-09-05T01:00:00Z"
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"


def stable_id(n):
    return str(uuid.UUID(int=n, version=4))


def operation(sample, kind, sequence=1, *, number=100, base=1, op=1, predecessor=None, total=600):
    from protocol_reference import mutation_keys
    fact = copy.deepcopy(sample["fact"])
    payload = {"operation_id": stable_id(1000 + op), "habit_id": fact["habit_id"], "check_date": fact["check_date"],
               "source": "manual", "occurred_at": TIME}
    if kind in {"increment", "decrement"}:
        payload.update(delta_hundredths=number, snapshot={key: fact[key] for key in ("target_count_snapshot_hundredths", "unit_snapshot")})
        # Valid local candidate evidence is independent of the server state.
        candidate_total = (fact["completed_count_hundredths"] or 0) + number * (1 if kind == "increment" else -1)
        if 1 <= candidate_total <= 9007199254740991:
            fact["completed_count_hundredths"] = candidate_total
            fact["status"] = "done" if candidate_total >= fact["target_count_snapshot_hundredths"] else "partial"
    elif kind == "replace_total":
        fact["completed_count_hundredths"] = total
        fact["status"] = "done" if total >= fact["target_count_snapshot_hundredths"] else "partial"
        fact["deleted_at"] = None
        payload["fact"] = copy.deepcopy(fact)
    else:
        payload["deleted_at"] = TIME
        fact["deleted_at"] = TIME
    value = {"protocol_version": 1, "mutation_id": stable_id(100000 + op * 100 + sequence), "client_sequence": sequence,
        "target_type": "habit_check_in", "target_id": sample["target_id"], "operation_type": kind,
        "base_entity_version": base, "causal_predecessors": [], "import_lineage_id": None, "import_batch_id": None,
        "import_source_workspace_id": None, "import_source_epoch": None, "import_item_ordinal": None,
        "import_manifest_hash": None, "predecessor_batch_id": None, "payload": payload,
        "conflict_recovery_snapshot": fact, "created_at": TIME}
    value["causal_predecessors"] = [{"merge_key": key, "client_sequence": predecessor if key == "completion" else None}
                                     for key in mutation_keys(value)]
    return value


def derive():
    samples = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]
    sample, parent = samples["habit_check_in"], samples["habit"]
    cases = []

    def step(value, total, *, device=A, status="accepted", error=None, deleted=False):
        return {"device": device, "mutation": value, "expected": {"status": status, "failure_code": error,
            "total": total, "deleted": deleted}}

    def case(name, steps, *, initial=sample, habit=parent):
        cases.append({"id": "HABIT-OP-" + name, "family": "FX-TARGET", "rule_anchor": "cloud-sync-01/9.3;cloud-sync-02/7.1-7.3,7.7",
            "input": {"habit": copy.deepcopy(habit), "initial": copy.deepcopy(initial), "steps": steps},
            "expected": [s["expected"] for s in steps]})

    inc = operation(sample, "increment")
    inc2 = operation(sample, "increment", op=2, number=200)
    dec = operation(sample, "decrement", op=3, number=100)
    case("independent-increments", [step(inc, 600), step(inc2, 800, device=B)])
    case("independent-increments-reversed", [step(inc2, 700, device=B), step(inc, 800)])
    case("increment-decrement", [step(inc, 600), step(dec, 500, device=B)])
    case("increment-decrement-reversed", [step(dec, 400, device=B), step(inc, 500)])
    case("exact-network-replay", [step(inc, 600), step(inc, 600, status="duplicate")])
    rebased = copy.deepcopy(inc)
    rebased.update(client_sequence=2, mutation_id=stable_id(999999), base_entity_version=2)
    case("new-envelope-same-operation", [step(inc, 600), step(rebased, 600)])
    changed = copy.deepcopy(rebased)
    changed["payload"]["delta_hundredths"] = 200
    case("operation-id-content-reuse", [step(inc, 600), step(changed, 600, status="rejected", error="SYNC_HABIT_OPERATION_ID_REUSED")])
    case("clear-versus-increment", [step(operation(sample, "clear"), 500, deleted=True),
        step(inc2, 500, device=B, status="conflict", deleted=True)])
    case("clear-versus-decrement", [step(operation(sample, "clear"), 500, deleted=True),
        step(dec, 500, device=B, status="conflict", deleted=True)])
    case("increment-versus-clear", [step(inc, 600), step(operation(sample, "clear", op=4), 600, device=B, status="conflict")])
    case("replace-versus-increment", [step(operation(sample, "replace_total", total=700), 700), step(inc2, 700, device=B, status="conflict")])
    case("increment-versus-replace", [step(inc, 600), step(operation(sample, "replace_total", total=700, op=4), 600, device=B, status="conflict")])
    case("same-value-replace", [step(operation(sample, "replace_total", total=500), 500), step(inc2, 700, device=B)])
    case("clear-recreate-same-identity", [step(operation(sample, "clear"), 500, deleted=True),
        step(operation(sample, "increment", 2, base=2, op=2), 100)])
    case("decrement-zero-is-rejected", [step(operation(sample, "decrement", number=500), 500, status="rejected", error="HABIT_CHECK_IN_STATE_INVALID")])
    case("decrement-underflow-is-rejected", [step(operation(sample, "decrement", number=501), 500, status="rejected", error="HABIT_CHECK_IN_STATE_INVALID")])
    maximum = copy.deepcopy(sample)
    maximum["fact"]["completed_count_hundredths"] = 9007199254740991
    case("increment-overflow-is-rejected", [step(operation(maximum, "increment", number=1), 9007199254740991,
         status="rejected", error="HABIT_CHECK_IN_STATE_INVALID")], initial=maximum)
    wrong_snapshot = operation(sample, "increment")
    wrong_snapshot["payload"]["snapshot"]["unit_snapshot"] = "different unit"
    case("snapshot-cannot-change-history", [step(wrong_snapshot, 500, status="rejected", error="HABIT_HISTORY_IMMUTABLE")])
    ended = copy.deepcopy(parent)
    ended["fact"]["ended_date"] = "2026-09-05"
    ended["fact"]["is_active"] = False
    case("ended-parent-readonly", [step(inc, 500, status="rejected", error="HABIT_ALREADY_ENDED")], habit=ended)
    deleted = copy.deepcopy(parent)
    deleted["fact"]["deleted_at"] = TIME
    case("deleted-parent-readonly", [step(inc, 500, status="rejected", error="HABIT_TARGET_DELETED")], habit=deleted)
    fresh_parent = copy.deepcopy(parent)
    fresh_parent["fact"]["first_check_in_at"] = None
    case("first-increment-with-atomic-parent-guard", [step(operation(sample, "increment", base=0), 100)], initial=None, habit=fresh_parent)
    case("clear-absent-no-fact", [step(operation(sample, "clear", base=0), None, deleted=False)], initial=None, habit=fresh_parent)
    same_chain = operation(sample, "increment", 2, op=3, predecessor=1)
    case("same-device-causal-plus-other-increment", [step(inc, 600), step(inc2, 800, device=B), step(same_chain, 900)])
    retry = operation(sample, "decrement", 2, op=5, number=600, base=2)
    case("rejected-operation-explicit-new-attempt", [step(operation(sample, "decrement", op=5, number=600), 500,
        status="rejected", error="HABIT_CHECK_IN_STATE_INVALID"), step(inc2, 700, device=B), step(retry, 100)])
    binary_parent, binary = copy.deepcopy(parent), copy.deepcopy(sample)
    binary_parent["fact"].update(target_count_hundredths=None, unit=None)
    binary["fact"].update(completed_count_hundredths=None, target_count_snapshot_hundredths=None, unit_snapshot=None)
    binary_replace = operation(sample, "replace_total")
    binary_replace["payload"]["fact"] = copy.deepcopy(binary["fact"])
    binary_replace["conflict_recovery_snapshot"] = copy.deepcopy(binary["fact"])
    case("binary-replace-done", [step(binary_replace, None)], initial=binary, habit=binary_parent)
    binary_increment = copy.deepcopy(inc)
    binary_increment["payload"]["snapshot"] = {"target_count_snapshot_hundredths": None, "unit_snapshot": None}
    binary_increment["conflict_recovery_snapshot"] = copy.deepcopy(binary["fact"])
    case("binary-increment-refused", [step(binary_increment, None, status="rejected", error="HABIT_CHECK_IN_STATE_INVALID")], initial=binary, habit=binary_parent)
    skipped = copy.deepcopy(sample)
    skipped["fact"].update(status="skipped", completed_count_hundredths=None, target_count_snapshot_hundredths=None, unit_snapshot=None, completed_at=None)
    skip = operation(sample, "replace_total")
    skip["payload"]["fact"] = copy.deepcopy(skipped["fact"])
    skip["conflict_recovery_snapshot"] = copy.deepcopy(skipped["fact"])
    case("quantity-replace-skipped", [step(skip, None)])
    from_skipped = copy.deepcopy(inc)
    from_skipped["conflict_recovery_snapshot"].update(completed_count_hundredths=100, status="partial")
    case("skipped-quantity-increment-starts-at-zero", [step(from_skipped, 100)], initial=skipped)
    case("skipped-clear-retains-null-snapshot", [step(operation(skipped, "clear"), None, deleted=True)], initial=skipped)
    return {"fixture_version": 1, "scope": "synthetic SQLite operation and transport oracle; not production business owners", "cases": cases}


if __name__ == "__main__":
    value = derive()
    FIXTURE.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"fixed_cases": len(value["cases"])}))
