"""Executable typed domain Contract checks, not a synchronization engine or product adapter."""
from __future__ import annotations

from datetime import date, datetime
from functools import lru_cache
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT / "contracts"), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from validate_sync_v1 import read_json, read_yaml, validate_schemas, Draft202012Validator, FormatChecker
from identity_reference import check_in_id, occurrence_key, reminder_intent_id
from counter_reference import integer


@lru_cache(maxsize=1)
def definitions():
    _, registry = validate_schemas()
    return registry, read_yaml(ROOT / "contracts/sync/sync_field_registry.yaml")


def validate_schema(path: str, value) -> None:
    from schema_validation_reference import validate_schema as dispatched_validation
    dispatched_validation(path, value)


def check(value: bool, error: str):
    if not value:
        raise ValueError(error)


def validate_fact(record: dict) -> None:
    validate_schema("sync/v1/sync_fact.schema.json", record)
    target, identifier, fact = record["target_type"], record["target_id"], record["fact"]
    if target in {"category", "event", "anniversary", "habit", "habit_recurrence"}:
        check(identifier == fact["id"], "SYNC_IDENTITY_MISMATCH")
    elif target == "anniversary_recurrence":
        check(identifier == fact["recurrence_id"], "SYNC_IDENTITY_MISMATCH")
    elif target == "event_recurrence":
        check(identifier == fact["recurrence_id"] + "#" + str(integer(fact["revision"])), "SYNC_IDENTITY_MISMATCH")
    elif target == "habit_check_in":
        check(identifier == check_in_id(fact["habit_id"], fact["check_date"]), "SYNC_IDENTITY_MISMATCH")
    elif target == "reminder_intent":
        check(identifier == reminder_intent_id(fact["owner_type"], fact["owner_id"]), "SYNC_IDENTITY_MISMATCH")
    if target in {"event", "event_recurrence", "user_preferences"}:
        try:
            ZoneInfo(fact["timezone"])
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("SYNC_TIMEZONE_INVALID") from None
    if target == "event":
        start, end = ("start_date", "end_date") if fact["is_all_day"] else ("start_at", "end_at")
        check(fact[start] < fact[end], "EVENT_TIME_INVALID")
    elif target == "habit":
        span = (date.fromisoformat(fact["end_date"]) - date.fromisoformat(fact["start_date"])).days + 1
        check(1 <= span <= 400, "HABIT_DATE_RANGE_INVALID")
        check(fact["ended_date"] is None or fact["start_date"] <= fact["ended_date"] <= fact["end_date"], "HABIT_DATE_RANGE_INVALID")
    elif target == "habit_check_in" and fact["completed_count_hundredths"] is not None:
        expected = "done" if fact["completed_count_hundredths"] >= fact["target_count_snapshot_hundredths"] else "partial"
        check(fact["status"] == expected, "HABIT_CHECK_IN_STATE_INVALID")
    elif target == "event_occurrence_state":
        original = fact["original_local_start"]
        if fact["occurrence_start_date"] is not None:
            check(original == fact["occurrence_start_date"], "SYNC_IDENTITY_MISMATCH")
        else:
            check(len(original) == 19, "SYNC_IDENTITY_MISMATCH")
            datetime.fromisoformat(original)
        check(identifier == fact["occurrence_key"] == occurrence_key(fact["event_id"], fact["recurrence_revision"], original),
              "SYNC_IDENTITY_MISMATCH")
    elif target == "reminder_intent":
        if fact["owner_type"] == "habit":
            check(not fact["is_enabled"] or fact["template"] is not None, "HABIT_REMINDER_CONFIG_INVALID")
        elif fact["owner_type"] == "anniversary":
            names = [(t["advance_days"], t["local_time"], t["timezone_mode"], t["method"]) for t in fact["templates"]]
            check(len(names) == len(set(names)), "ANNIVERSARY_REMINDER_CONFIG_INVALID")


def validate_patch(target: str, patch: dict, baseline: dict, *, variant: str = "default") -> set[str]:
    _, registry = definitions()
    definition = registry["targets"][target]["variants"][variant]
    check(definition["patch_schema"] is not None, "SYNC_OPERATION_UNSUPPORTED")
    validate_schema(definition["patch_schema"], patch)
    projected = {**baseline, "fact": {**baseline["fact"], **patch}}
    validate_fact(projected)
    if target == "habit" and baseline["fact"]["first_check_in_at"] is not None:
        for field in ("target_count_hundredths", "unit", "start_date"):
            check(projected["fact"][field] == baseline["fact"][field], "HABIT_HISTORY_IMMUTABLE")
    return {definition["fields"][field]["merge_key"] for field in patch}


def validate_graph(records: list[dict], *, deleted_anchors=frozenset()) -> None:
    by_identity = {}
    for record in records:
        validate_fact(record)
        key = record["target_type"], record["target_id"]
        check(key not in by_identity, "IMPORT_DUPLICATE_IDENTITY")
        by_identity[key] = record["fact"]
    check(not set(by_identity) & set(deleted_anchors), "IMPORT_DUPLICATE_IDENTITY")
    exclusive_recurrences = set()
    for (target, _), fact in by_identity.items():
        if target in {"anniversary", "habit"} and fact["recurrence_id"] is not None:
            key = target + "_recurrence", fact["recurrence_id"]
            check((key in by_identity or key in deleted_anchors) and key not in exclusive_recurrences, "IMPORT_REFERENCE_INVALID")
            exclusive_recurrences.add(key)
            if key in deleted_anchors:
                check(fact["deleted_at"] is not None, "IMPORT_REFERENCE_INVALID")
                continue
            child = by_identity[key]
            check(fact["deleted_at"] is not None or child["deleted_at"] is None, "IMPORT_REFERENCE_INVALID")
            if target == "anniversary":
                check((fact["deleted_at"] is None) == (child["deleted_at"] is None), "IMPORT_REFERENCE_INVALID")
        elif target == "event" and fact["has_recurrence"]:
            key = "event_recurrence", fact["recurrence_id"] + "#" + str(integer(fact["recurrence_revision"]))
            check(key in by_identity or key in deleted_anchors, "IMPORT_REFERENCE_INVALID")
            if key in deleted_anchors:
                check(fact["deleted_at"] is not None, "IMPORT_REFERENCE_INVALID")
                continue
            recurrence = by_identity[key]
            check(all(fact[name] == recurrence[name] for name in ("start_at", "start_date", "timezone")), "IMPORT_REFERENCE_INVALID")
        elif target == "habit_check_in":
            habit = by_identity.get(("habit", fact["habit_id"]))
            if habit is None and ("habit", fact["habit_id"]) in deleted_anchors:
                check(fact["deleted_at"] is not None, "IMPORT_REFERENCE_INVALID")
                continue
            check(habit is not None, "IMPORT_REFERENCE_INVALID")
            check(habit["first_check_in_at"] is not None and habit["start_date"] <= fact["check_date"] <= (habit["ended_date"] or habit["end_date"]),
                  "HABIT_HISTORY_IMMUTABLE")
            if fact["status"] != "skipped":
                check(fact["target_count_snapshot_hundredths"] == habit["target_count_hundredths"] and
                      fact["unit_snapshot"] == habit["unit"], "HABIT_HISTORY_IMMUTABLE")
        elif target == "event_occurrence_state":
            event = by_identity.get(("event", fact["event_id"]))
            check(event is not None and event["recurrence_id"] is not None, "IMPORT_REFERENCE_INVALID")
            check(("event_recurrence", event["recurrence_id"] + "#" + str(integer(fact["recurrence_revision"]))) in by_identity,
                  "IMPORT_REFERENCE_INVALID")
        elif target == "reminder_intent":
            owner = by_identity.get((fact["owner_type"], fact["owner_id"]))
            if owner is None and (fact["owner_type"], fact["owner_id"]) in deleted_anchors:
                check(not fact["is_enabled"], "IMPORT_REFERENCE_INVALID")
                continue
            check(owner is not None, "IMPORT_REFERENCE_INVALID")
            check(owner.get("deleted_at") is None or not fact["is_enabled"], "IMPORT_REFERENCE_INVALID")
            if fact["owner_type"] == "event":
                check(not (owner["is_all_day"] and owner["has_recurrence"]) or not fact["templates"], "REMINDER_METHOD_UNSUPPORTED")
                for template in fact["templates"]:
                    check(not (owner["is_all_day"] or owner["has_recurrence"]) or template["method"] == "popup", "REMINDER_METHOD_UNSUPPORTED")
                    check(not owner["has_recurrence"] or template["remind_at"] is None, "REMINDER_METHOD_UNSUPPORTED")
    for (target, identifier), fact in by_identity.items():
        if target in {"habit_recurrence", "anniversary_recurrence"} and fact["deleted_at"] is None:
            owner_type = target.removesuffix("_recurrence")
            owners = [row for (kind, _), row in by_identity.items() if kind == owner_type and
                      row["recurrence_id"] == identifier and row["deleted_at"] is None]
            check(len(owners) == 1, "IMPORT_REFERENCE_INVALID")
    # Category references intentionally do not require a target row and never cascade.


def choose_default_reminder(target_type: str, candidates: list[str], *, is_all_day=False, has_recurrence=False):
    contract = read_yaml(ROOT / "contracts/reminder/default_reminder_method_applicability.yaml")
    check(len(candidates) <= 2 and len(candidates) == len(set(candidates)) and all(x in {"ring", "popup"} for x in candidates),
          "SYNC_PAYLOAD_INVALID")
    row = next((row for row in contract["targets"] if row["target_type"] == target_type and
                (target_type != "event" or row["is_all_day"] == is_all_day and row["has_recurrence"] == has_recurrence)), None)
    check(row is not None, "SYNC_TARGET_UNSUPPORTED")
    return next((candidate for candidate in candidates if candidate in row["allowed"]), None)
