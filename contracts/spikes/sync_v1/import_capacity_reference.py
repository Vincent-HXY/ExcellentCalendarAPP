"""Deterministic combined business graphs, not opaque row-count substitutes."""
import copy

from build_owned_graph_fixtures import derive
from build_target_fixtures import build
from domain_reference import validate_graph
from identity_reference import check_in_id, occurrence_key, reminder_intent_id


def combined_graph(count):
    if count < 12:
        raise ValueError("Combined graph needs every business target")
    samples = build()["samples"]
    event_seed = derive()["cases"][2]["input"]["seed"]
    unit = [record for record in samples.values() if record["target_type"] not in {"user_preferences", "account_profile", "event", "event_recurrence"}
        and record["target_id"] != samples["reminder_intent_event"]["target_id"]] + event_seed
    validate_graph(unit)
    records = []
    for cohort in range(1, count // len(unit) + 1):
        remap = {samples[kind]["target_id"]: f"{cohort * 32 + slot:08x}-1111-4111-8111-111111111111"
            for slot, kind in enumerate(("category", "event", "anniversary", "anniversary_recurrence", "habit", "habit_recurrence"), 1)}
        rule = samples["event_recurrence"]["fact"]["recurrence_id"]
        remap[rule] = f"{cohort * 32 + 10:08x}-1111-4111-8111-111111111111"
        remap[samples["event_recurrence"]["target_id"]] = remap[rule] + "#1"
        check_in = samples["habit_check_in"]
        remap[check_in["target_id"]] = check_in_id(remap[check_in["fact"]["habit_id"]], check_in["fact"]["check_date"])
        occurrence = samples["event_occurrence_state"]
        remap[occurrence["target_id"]] = occurrence_key(remap[occurrence["fact"]["event_id"]], occurrence["fact"]["recurrence_revision"], occurrence["fact"]["original_local_start"])
        for owner in ("event", "anniversary", "habit"):
            old = samples["reminder_intent_" + owner]
            remap[old["target_id"]] = reminder_intent_id(owner, remap[old["fact"]["owner_id"]])

        def mapped(value):
            if isinstance(value, dict):
                return {key: mapped(member) for key, member in value.items()}
            if isinstance(value, list):
                return [mapped(member) for member in value]
            return remap.get(value, value) if isinstance(value, str) else value

        records.extend(mapped(record) for record in unit)
    for index in range(count - len(records)):
        row = copy.deepcopy(samples["category"])
        row["target_id"] = row["fact"]["id"] = f"f{index:07x}-2222-4222-8222-222222222222"
        records.append(row)
    validate_graph(records)
    return records
