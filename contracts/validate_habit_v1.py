#!/usr/bin/env python3
"""Validate the released Habit/Appearance V1 Contract package.

Runtime-only dependencies are isolated verification tools. This validator proves
that the integrated schemas, maps, identities, errors, fixtures, storage format,
and compatibility gates remain aligned with the active production capability.
"""

from __future__ import annotations

import json
import hashlib
import sys
import uuid
import warnings
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any
from urllib.parse import urldefrag, urljoin
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

try:
    warnings.filterwarnings(
        "ignore",
        message=r"jsonschema\.RefResolver is deprecated.*",
        category=DeprecationWarning,
    )
    import yaml
    from jsonschema import Draft202012Validator, FormatChecker, RefResolver
except ModuleNotFoundError as error:  # pragma: no cover - environment gate
    raise SystemExit(
        "Verification dependencies are missing. Run run_habit_v1_validation.py "
        "to install them in an isolated temporary cache."
    ) from error


CONTRACTS = Path(__file__).resolve().parent
FIXTURES = CONTRACTS / "fixtures" / "habit"
SAFE_HUNDREDTHS_MAX = 9_007_199_254_740_991
DISPLAY_DECIMAL_MAX = Decimal("90071992547409.91")
MAX_CHALLENGE_DAYS = 400


def fail(message: str) -> None:
    raise AssertionError(message)


def reject_non_json_constant(value: str) -> None:
    fail(f"Non-JSON numeric constant is forbidden: {value}")


def load_json(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8"),
        parse_constant=reject_non_json_constant,
    )


def collect_schemas() -> tuple[dict[str, Any], dict[str, Path]]:
    schemas: dict[str, Any] = {}
    paths: dict[str, Path] = {}
    for path in CONTRACTS.rglob("*.schema.json"):
        schema = load_json(path)
        schema_id = schema.get("$id")
        if not schema_id:
            fail(f"Schema has no $id: {path}")
        if schema_id in schemas:
            fail(f"Duplicate $id {schema_id}: {paths[schema_id]} and {path}")
        Draft202012Validator.check_schema(schema)
        schemas[schema_id] = schema
        paths[schema_id] = path
    return schemas, paths


def walk_refs(value: Any):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "$ref" and isinstance(child, str):
                yield child
            else:
                yield from walk_refs(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_refs(child)


def validate_ref_closure(schemas: dict[str, Any], paths: dict[str, Path]) -> None:
    for schema_id, schema in schemas.items():
        for ref in walk_refs(schema):
            target, _ = urldefrag(urljoin(schema_id, ref))
            if target.startswith("https://json-schema.org/"):
                continue
            if target not in schemas:
                fail(f"Unclosed $ref {ref} in {paths[schema_id]} -> {target}")


def validate_instance(schema_path: Path, instance: Any, schemas: dict[str, Any]) -> list[str]:
    schema = load_json(schema_path)
    resolver = RefResolver.from_schema(schema, store=schemas)
    validator = Draft202012Validator(
        schema,
        resolver=resolver,
        format_checker=FormatChecker(),
    )
    return [
        error.message
        for error in sorted(validator.iter_errors(instance), key=lambda item: list(item.path))
    ]


def compact_name(values: list[Any]) -> str:
    return json.dumps(values, ensure_ascii=False, separators=(",", ":"))


def derived_uuid(identity: dict[str, Any], namespace_name: str, values: list[Any]) -> str:
    namespace = uuid.UUID(identity["namespaces"][namespace_name]["uuid"])
    return str(uuid.uuid5(namespace, compact_name(values)))


def semantic_create_dates_and_timezone(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    start = date.fromisoformat(instance["start_date"])
    end = date.fromisoformat(instance["end_date"])
    if end < start:
        return "HABIT_DATE_RANGE_INVALID"
    if (end - start).days + 1 > MAX_CHALLENGE_DAYS:
        return "HABIT_CHALLENGE_TOO_LONG"
    try:
        ZoneInfo(instance["timezone"])
    except (ZoneInfoNotFoundError, ValueError):
        return "TIMEZONE_ID_INVALID"
    return None


def semantic_check_in_action_identity(
    instance: dict[str, Any], case: dict[str, Any], identity: dict[str, Any]
) -> str | None:
    if instance["source"] != "notification_action":
        return "CONTRACT_VALIDATION_FAILED"
    if instance["check_date"] != case["semantic_today"]:
        return "HABIT_NOTIFICATION_ACTION_EXPIRED"
    expected = derived_uuid(
        identity,
        "habit_notification_action",
        ["habit_complete", instance["habit_id"], instance["check_date"], instance["occurrence_key"]],
    )
    if instance["action_id"] != expected:
        return "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH"
    return None


def semantic_habit_reminder_identity(
    instance: dict[str, Any], _case: dict[str, Any], identity: dict[str, Any]
) -> str | None:
    expected_occurrence = derived_uuid(
        identity,
        "habit_occurrence",
        [instance["target_id"], instance["template_key"], instance["occurrence_date"]],
    )
    expected_reminder = derived_uuid(
        identity,
        "habit_reminder",
        ["habit", instance["target_id"], instance["template_key"], instance["occurrence_date"]],
    )
    if instance["occurrence_key"] != expected_occurrence or instance["reminder_id"] != expected_reminder:
        return "REMINDER_IDEMPOTENCY_CONFLICT"
    return None


def semantic_prepared_habit_identity(
    instance: dict[str, Any], _case: dict[str, Any], identity: dict[str, Any]
) -> str | None:
    notification = instance["notification"]
    tap = instance["tap_payload"]
    action = instance["habit_action_payload"]
    shared = ("notification_id", "delivery_id", "delivery_attempt_id", "reminder_id", "target_id", "occurrence_key")
    for field in shared:
        action_field = "habit_id" if field == "target_id" else field
        if notification[field] != tap[field]:
            return "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH"
        if action_field in action and notification[field] != action[action_field]:
            return "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH"
    expected_delivery = derived_uuid(
        identity,
        "delivery",
        [notification["reminder_id"], notification["method"]],
    )
    expected_action = derived_uuid(
        identity,
        "habit_notification_action",
        ["habit_complete", action["habit_id"], action["check_date"], action["occurrence_key"]],
    )
    if notification["delivery_id"] != expected_delivery or action["action_id"] != expected_action:
        return "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH"
    if tap["route"] != "habit.detail" or action["delivery_id"] != notification["delivery_id"]:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_reconcile_counts(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    outcome_sum = (
        instance["materialized_count"]
        + instance["expired_count"]
        + instance["cancelled_count"]
        + instance["unchanged_count"]
    )
    if outcome_sum != instance["processed_count"]:
        return "HABIT_RECONCILIATION_CONFLICT"
    if instance["processed_count"] > instance["request_limit"]:
        return "HABIT_RECONCILIATION_CONFLICT"
    return None


def semantic_today_progress_counts(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    eligible = instance["done_count"] + instance["partial_count"] + instance["absent_count"]
    active = eligible + instance["skipped_count"]
    if eligible != instance["eligible_count"] or active != instance["active_count"]:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_fixed_point_vectors(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    if instance.get("scale") != 2 or instance.get("wire_representation") != "json_integer_hundredths":
        return "CONTRACT_VALIDATION_FAILED"
    vectors = instance.get("vectors", [])
    if not vectors:
        return "CONTRACT_VALIDATION_FAILED"
    for vector in vectors:
        hundredths = vector.get("hundredths")
        if type(hundredths) is not int or not 1 <= hundredths <= SAFE_HUNDREDTHS_MAX:
            return "CONTRACT_VALIDATION_FAILED"
        expected_decimal = f"{Decimal(hundredths) / Decimal(100):.2f}"
        if vector.get("canonical_decimal") != expected_decimal:
            return "CONTRACT_VALIDATION_FAILED"
        round_trip = json.loads(json.dumps({"value": hundredths}, separators=(",", ":")))["value"]
        if type(round_trip) is not int or round_trip != hundredths:
            return "CONTRACT_VALIDATION_FAILED"
    adjacent = instance.get("adjacent_maximum_hundredths")
    if adjacent != [SAFE_HUNDREDTHS_MAX - 1, SAFE_HUNDREDTHS_MAX]:
        return "CONTRACT_VALIDATION_FAILED"
    decimals = [vectors[-2]["canonical_decimal"], vectors[-1]["canonical_decimal"]]
    if decimals != ["90071992547409.90", "90071992547409.91"]:
        return "CONTRACT_VALIDATION_FAILED"
    if float(decimals[0]) != float(decimals[1]):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_daily_display_transitions(instance: dict[str, Any], _case: dict[str, Any]) -> str | None:
    if instance.get("daily_display_key") != ["habit_id", "occurrence_date"]:
        return "CONTRACT_VALIDATION_FAILED"
    if instance.get("prepared_reserves_display_slot") is not True:
        return "CONTRACT_VALIDATION_FAILED"
    cases = {case["name"]: case for case in instance.get("cases", [])}
    expected_same_day = {
        "pending_then_time_change": "replace_with_new_template_reminder",
        "prepared_then_time_change": "no_new_display",
        "sent_then_time_change": "no_new_display",
        "disabled_then_reenabled_before_attempt": "replace_with_new_template_reminder",
        "disabled_then_reenabled_after_sent": "no_new_display",
    }
    if set(cases) != set(expected_same_day):
        return "CONTRACT_VALIDATION_FAILED"
    for name, result in expected_same_day.items():
        if cases[name].get("same_day_result") != result:
            return "CONTRACT_VALIDATION_FAILED"
    if cases["prepared_then_time_change"].get("old_attempt_terminal_reason") != "habit_reminder_cancelled":
        return "CONTRACT_VALIDATION_FAILED"
    for name in ["prepared_then_time_change", "sent_then_time_change", "disabled_then_reenabled_after_sent"]:
        if cases[name].get("new_template_first_date") != "2026-09-02":
            return "CONTRACT_VALIDATION_FAILED"
    return None


def validate_manifest(schemas: dict[str, Any], identity: dict[str, Any]) -> int:
    handlers = {
        "create_dates_and_timezone": semantic_create_dates_and_timezone,
        "check_in_action_identity": lambda value, case: semantic_check_in_action_identity(value, case, identity),
        "habit_reminder_identity": lambda value, case: semantic_habit_reminder_identity(value, case, identity),
        "prepared_habit_identity": lambda value, case: semantic_prepared_habit_identity(value, case, identity),
        "reconcile_counts": semantic_reconcile_counts,
        "today_progress_counts": semantic_today_progress_counts,
        "fixed_point_vectors": semantic_fixed_point_vectors,
        "daily_display_transitions": semantic_daily_display_transitions,
    }
    manifest = load_json(FIXTURES / "manifest.json")
    if manifest.get("fixture_version") != 1 or not manifest.get("cases"):
        fail("Habit fixture manifest version/cases are invalid")
    count = 0
    for case in manifest["cases"]:
        count += 1
        instance = load_json(FIXTURES / case["instance"])
        if "schema" in case:
            errors = validate_instance((FIXTURES / case["schema"]).resolve(), instance, schemas)
            actual_valid = not errors
            if actual_valid != case["expected_valid"]:
                fail(
                    f"Fixture {case['name']} expected_valid={case['expected_valid']} "
                    f"errors={errors}"
                )
        semantic_check = case.get("semantic_check")
        if semantic_check:
            actual_error = handlers[semantic_check](instance, case)
            if actual_error != case.get("expected_error"):
                fail(
                    f"Fixture {case['name']} semantic error expected "
                    f"{case.get('expected_error')}, got {actual_error}"
                )
    return count


def validate_identity(identity: dict[str, Any]) -> None:
    namespace_for_vector = {
        "timed_occurrence": "occurrence",
        "all_day_occurrence": "occurrence",
        "recurring_reminder": "reminder",
        "ring_reminder_delivery": "delivery",
        "snoozed_reminder": "reminder",
        "reminder_delivery": "delivery",
        "recovery_summary_delivery": "delivery",
        "anniversary_occurrence": "anniversary_occurrence",
        "anniversary_occurrence_changed_date": "anniversary_occurrence",
        "anniversary_occurrence_restored_date": "anniversary_occurrence",
        "anniversary_reminder_template": "anniversary_reminder_template",
        "anniversary_reminder_template_changed": "anniversary_reminder_template",
        "anniversary_reminder": "anniversary_reminder",
        "anniversary_reminder_second_template": "anniversary_reminder",
        "anniversary_catch_up_single": "anniversary_catch_up_delivery",
        "anniversary_catch_up_multi_sorted": "anniversary_catch_up_delivery",
        "habit_occurrence": "habit_occurrence",
        "habit_occurrence_next_date": "habit_occurrence",
        "habit_reminder": "habit_reminder",
        "habit_notification_action": "habit_notification_action",
    }
    if set(identity["test_vectors"]) != set(namespace_for_vector):
        fail(f"Identity vector mapping drift: {set(identity['test_vectors']) ^ set(namespace_for_vector)}")
    for name, namespace_name in namespace_for_vector.items():
        vector = identity["test_vectors"][name]
        namespace = uuid.UUID(identity["namespaces"][namespace_name]["uuid"])
        actual = str(uuid.uuid5(namespace, vector["canonical_name"]))
        if actual != vector["uuid"]:
            fail(f"Identity vector {name}: expected {vector['uuid']}, recalculated {actual}")
    expected_names = {
        "habit_occurrence": "[habit_id, template_key, occurrence_date]",
        "habit_reminder": '["habit", habit_id, template_key, occurrence_date]',
        "habit_notification_action": '["habit_complete", habit_id, check_date, occurrence_key]',
    }
    for name, expected in expected_names.items():
        if identity["identities"][name]["name"] != expected:
            fail(f"Habit identity canonical name drift: {name}")
    if identity["capability_status"].get("habit_v1") != {
        "implementation_status": "integrated",
        "release_status": "active",
    }:
        fail("Habit identity capability must remain integrated + active")


def validate_capabilities(yaml_documents: dict[str, Any]) -> None:
    methods = yaml_documents["method_channels.yaml"]["methods"]
    calls = yaml_documents["native_calls.yaml"]["calls"]
    public = {
        "habit.create": ("habit/create_habit_request.schema.json", "habit/habit_mutation_response.schema.json"),
        "habit.update": ("habit/update_habit_request.schema.json", "habit/habit_mutation_response.schema.json"),
        "habit.list": ("habit/list_habits_request.schema.json", "habit/habit_list_response.schema.json"),
        "habit.detail": ("habit/get_habit_detail_request.schema.json", "habit/habit_detail_response.schema.json"),
        "habit.end": ("habit/end_habit_request.schema.json", "habit/habit_mutation_response.schema.json"),
        "habit.delete": ("habit/delete_habit_request.schema.json", "habit/habit_delete_operation_response.schema.json"),
        "habit.check_in": ("habit/habit_check_in_request.schema.json", "habit/habit_check_in_mutation_response.schema.json"),
        "habit.clear_check_in": ("habit/clear_habit_check_in_request.schema.json", "habit/habit_check_in_mutation_response.schema.json"),
        "habit.list_daily_statuses": ("habit/list_habit_daily_statuses_request.schema.json", "habit/habit_daily_status_list_response.schema.json"),
        "habit.set_reminder": ("habit/set_habit_reminder_request.schema.json", "habit/habit_mutation_response.schema.json"),
    }
    appearance = {
        "appearance.get_local": ("common/native_empty_request.schema.json", "appearance/local_appearance_response.schema.json"),
        "appearance.update_local": ("appearance/update_local_appearance_request.schema.json", "appearance/local_appearance_response.schema.json"),
    }
    native = {
        "habit.create": ("habit/create_habit_request.schema.json", "habit/habit_mutation_commit_response.schema.json"),
        "habit.update": ("habit/update_habit_request.schema.json", "habit/habit_mutation_commit_response.schema.json"),
        "habit.list": public["habit.list"],
        "habit.detail": public["habit.detail"],
        "habit.end": ("habit/end_habit_request.schema.json", "habit/habit_mutation_commit_response.schema.json"),
        "habit.delete": ("habit/delete_habit_request.schema.json", "habit/habit_delete_commit_response.schema.json"),
        "habit.check_in": ("habit/habit_check_in_command_request.schema.json", "habit/habit_check_in_commit_response.schema.json"),
        "habit.clear_check_in": ("habit/clear_habit_check_in_request.schema.json", "habit/habit_check_in_commit_response.schema.json"),
        "habit.list_daily_statuses": public["habit.list_daily_statuses"],
        "habit.set_reminder": ("habit/set_habit_reminder_request.schema.json", "habit/habit_mutation_commit_response.schema.json"),
        "habit.reconcile_reminders": ("habit/reconcile_habit_reminders_request.schema.json", "habit/reconcile_habit_reminders_response.schema.json"),
    }
    actual_public = {name for name, entry in methods.items() if entry.get("module") == "habit"}
    actual_appearance = {name for name, entry in methods.items() if entry.get("module") == "appearance"}
    actual_native = {name for name, entry in calls.items() if entry.get("module") == "habit"}
    if actual_public != set(public):
        fail(f"Habit public capability drift: {actual_public ^ set(public)}")
    if actual_appearance != set(appearance):
        fail(f"Appearance public capability drift: {actual_appearance ^ set(appearance)}")
    if actual_native != set(native):
        fail(f"Habit native capability drift: {actual_native ^ set(native)}")
    if any(name.startswith("appearance.") for name in calls):
        fail("Appearance is Kotlin-local and must not have JNI/native calls")

    for name, expected in {**public, **appearance}.items():
        entry = methods[name]
        if (entry.get("request"), entry.get("result", {}).get("data")) != expected:
            fail(f"Public capability schema drift: {name}")
        if entry.get("implementation_status") != "integrated" or entry.get("release_status") != "active":
            fail(f"Released public capability must remain integrated + active: {name}")
        if entry.get("result", {}).get("envelope") != "common/native_result.schema.json":
            fail(f"Public NativeResult envelope drift: {name}")

    for name, expected in native.items():
        entry = calls[name]
        if (entry.get("request"), entry.get("result", {}).get("data")) != expected:
            fail(f"Native capability schema drift: {name}")
        if entry.get("implementation_status") != "integrated" or entry.get("release_status") != "active":
            fail(f"Released native capability must remain integrated + active: {name}")
        if entry.get("visibility") != "internal" or entry.get("caller") != "kotlin":
            fail(f"Habit native visibility/caller drift: {name}")

    for request, response in set(public.values()) | set(appearance.values()) | set(native.values()):
        if not (CONTRACTS / request).is_file() or not (CONTRACTS / response).is_file():
            fail(f"Capability references missing schema: {request} -> {response}")


def validate_errors_and_enums(yaml_documents: dict[str, Any], schemas: dict[str, Any]) -> None:
    errors = yaml_documents["error_codes.yaml"]["errors"]
    required_errors = {
        "HABIT_TITLE_EMPTY", "HABIT_NOT_FOUND", "HABIT_TARGET_DELETED", "HABIT_UPDATE_CONFLICT",
        "HABIT_DATE_RANGE_INVALID", "HABIT_CHALLENGE_TOO_LONG", "HABIT_TARGET_INVALID", "HABIT_TARGET_LOCKED",
        "HABIT_START_DATE_LOCKED", "HABIT_ALREADY_ENDED", "HABIT_CHECK_IN_DATE_OUT_OF_RANGE",
        "HABIT_NOT_STARTED", "HABIT_END_NOT_EARLY",
        "HABIT_CHECK_IN_FUTURE_DATE", "HABIT_CHECK_IN_NOT_FOUND", "HABIT_DAILY_STATUS_RANGE_INVALID",
        "HABIT_DAILY_STATUS_RANGE_TOO_LARGE", "HABIT_REMINDER_CONFIG_INVALID",
        "HABIT_NOTIFICATION_ACTION_EXPIRED", "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH",
        "HABIT_RECONCILIATION_CURSOR_INVALID", "HABIT_RECONCILIATION_CONFLICT",
        "HABIT_STATISTICS_OVERFLOW", "APPEARANCE_COLOR_TOKEN_INVALID", "APPEARANCE_STORAGE_FAILED",
    }
    if missing := required_errors - set(errors):
        fail(f"Missing Habit/Appearance errors: {sorted(missing)}")
    if "HABIT_CHECK_IN_DUPLICATED" in errors:
        fail("Habit check-in is idempotent set/upsert; duplicated error must not exist")
    if "APPEARANCE_STORAGE_CORRUPTED" in errors:
        fail("Recovered appearance corruption is diagnostic-only, not a NativeResult error")
    for code in required_errors:
        if not {"module", "message", "retryable", "boundaries", "data_saved_allowed"} <= set(errors[code]):
            fail(f"Habit/Appearance error metadata incomplete: {code}")
    native_codes = set(
        schemas["https://excellent-calendar.local/contracts/common/native_error.schema.json"]
        ["properties"]["code"]["enum"]
    )
    if missing := required_errors - native_codes:
        fail(f"NativeError enum is missing Habit/Appearance codes: {sorted(missing)}")

    enums = yaml_documents["enums.yaml"]
    expected_enums = {
        "HabitCheckInStatus": ["done", "partial", "skipped"],
        "HabitDailyStatus": ["upcoming", "absent", "partial", "done", "skipped", "missed"],
        "HabitLifecycleStatus": ["upcoming", "active", "completed", "ended_early"],
        "HabitCheckInSource": ["manual", "notification_action"],
        "HabitNotificationActionType": ["complete"],
        "HabitProgressColor": ["teal", "blue", "indigo", "green", "orange", "rose", "purple"],
        "HabitScheduleStatus": ["not_required", "scheduled_exact", "scheduled_approximate", "pending_permission", "pending_reconciliation"],
        "HabitReminderReconciliationTriggerSource": ["app_start", "device_boot", "app_update", "date_changed", "time_changed", "timezone_changed", "permission_restored", "manual_retry"],
    }
    for name, values in expected_enums.items():
        if enums.get(name, {}).get("values") != values:
            fail(f"Habit enum drift: {name}")
    abandon = set(enums["DeliveryAbandonReason"]["values"])
    if not {"habit_occurrence_elapsed", "habit_reminder_cancelled"} <= abandon:
        fail("Habit prepared-attempt terminal reasons are missing")


def validate_fixed_point_shapes(schemas: dict[str, Any]) -> None:
    fields = [
        ("habit/create_habit_request.schema.json", "target_count_hundredths", 1),
        ("habit/update_habit_request.schema.json", "target_count_hundredths", 1),
        ("habit/habit_response.schema.json", "target_count_hundredths", 1),
        ("habit/habit_check_in_request.schema.json", "completed_count_hundredths", 1),
        ("habit/habit_check_in_command_request.schema.json", "completed_count_hundredths", 1),
        ("habit/habit_check_in_response.schema.json", "completed_count_hundredths", 1),
        ("habit/habit_check_in_response.schema.json", "target_count_snapshot_hundredths", 1),
        ("habit/habit_statistics_response.schema.json", "total_completed_count_hundredths", 0),
        ("habit/habit_statistics_response.schema.json", "average_completed_count_per_eligible_day_hundredths", 0),
    ]
    for relative, field, minimum in fields:
        schema = load_json(CONTRACTS / relative)
        shape = schema["properties"][field]
        types = shape.get("type")
        if types not in ("integer", ["integer", "null"]):
            fail(f"Fixed-point wire must be integer hundredths: {relative}#{field}")
        if shape.get("minimum") != minimum or shape.get("maximum") != SAFE_HUNDREDTHS_MAX:
            fail(f"Fixed-point integer range drift: {relative}#{field}")
        if "multipleOf" in shape:
            fail(f"Decimal multipleOf is forbidden for Habit quantities: {relative}#{field}")
    legacy_names = {
        "target_count", "completed_count", "target_count_snapshot",
        "total_completed_count", "average_completed_count_per_eligible_day",
    }
    for path in (CONTRACTS / "habit").glob("*.schema.json"):
        properties = load_json(path).get("properties", {})
        if legacy_names & set(properties):
            fail(f"Legacy decimal quantity field remains in {path.name}")
    if DISPLAY_DECIMAL_MAX * 100 != SAFE_HUNDREDTHS_MAX:
        fail("Display decimal and safe-integer maximum drift")


def validate_habit_limits_and_aggregates(schemas: dict[str, Any]) -> None:
    base = "https://excellent-calendar.local/contracts/habit/"
    for relative in ["create_habit_request.schema.json", "update_habit_request.schema.json", "habit_response.schema.json"]:
        if schemas[base + relative].get("x-inclusive-max-days") != MAX_CHALLENGE_DAYS:
            fail(f"Habit challenge cap drift: {relative}")
    text_shapes = [
        ("create_habit_request.schema.json", "title", 80),
        ("create_habit_request.schema.json", "description", 2000),
        ("create_habit_request.schema.json", "unit", 32),
        ("update_habit_request.schema.json", "title", 80),
        ("update_habit_request.schema.json", "description", 2000),
        ("update_habit_request.schema.json", "unit", 32),
        ("habit_check_in_request.schema.json", "note", 500),
        ("habit_check_in_command_request.schema.json", "note", 500),
    ]
    for relative, field, maximum in text_shapes:
        if schemas[base + relative]["properties"][field].get("maxLength") != maximum:
            fail(f"Habit text limit drift: {relative}#{field}")
    list_request = schemas[base + "list_habits_request.schema.json"]
    overlay = list_request["properties"]["pagination"]["allOf"][1]["properties"]
    if overlay["page_size"].get("maximum") != 100 or overlay["cursor"].get("maxLength") != 512:
        fail("Habit list pagination cap drift")
    reconcile_request = schemas[base + "reconcile_habit_reminders_request.schema.json"]
    if reconcile_request["properties"]["cursor"].get("maxLength") != 512:
        fail("Habit reconciliation cursor cap drift")
    list_response = schemas[base + "habit_list_response.schema.json"]
    if "today_progress" not in list_response.get("required", []):
        fail("Habit list response lacks page-independent today progress")
    progress = schemas[base + "habit_today_progress_response.schema.json"]
    expected_progress = {
        "as_of_date", "active_count", "done_count", "eligible_count",
        "skipped_count", "partial_count", "absent_count",
    }
    if set(progress.get("required", [])) != expected_progress:
        fail("Habit today-progress shape drift")


def validate_habit_boundary_separation(schemas: dict[str, Any]) -> None:
    base = "https://excellent-calendar.local/contracts/habit/"
    date_sensitive_requests = [
        "create_habit_request.schema.json", "update_habit_request.schema.json",
        "list_habits_request.schema.json", "get_habit_detail_request.schema.json",
        "end_habit_request.schema.json", "delete_habit_request.schema.json",
        "habit_check_in_request.schema.json", "habit_check_in_command_request.schema.json",
        "clear_habit_check_in_request.schema.json", "list_habit_daily_statuses_request.schema.json",
        "set_habit_reminder_request.schema.json", "reconcile_habit_reminders_request.schema.json",
    ]
    for relative in date_sensitive_requests:
        timezone = schemas[base + relative].get("properties", {}).get("timezone", {})
        if timezone.get("x-format") != "iana-timezone":
            fail(f"Date-sensitive Habit request lacks IANA timezone marker: {relative}")

    public = schemas[base + "habit_check_in_request.schema.json"]
    command = schemas[base + "habit_check_in_command_request.schema.json"]
    forbidden_public = {"source", "occurrence_key", "action_id"}
    if forbidden_public & set(public["properties"]):
        fail("Flutter-visible habit.check_in must not accept notification-action identity")
    if set(command["required"]) != {
        "habit_id", "check_date", "status", "completed_count_hundredths", "note", "source",
        "occurrence_key", "action_id", "timezone",
    }:
        fail("Internal HabitCheckIn command shape drift")

    detail = schemas[base + "habit_detail_response.schema.json"]
    for field in ["has_ever_checked_in", "latest_check_in_date"]:
        if field not in detail["required"]:
            fail(f"Habit detail edit-lock projection missing: {field}")
    for relative in ["habit_summary_response.schema.json", "habit_detail_response.schema.json"]:
        today = schemas[base + relative]["properties"]["today"]
        if not any(option.get("type") == "null" for option in today.get("oneOf", [])):
            fail(f"Out-of-range lifecycle must permit today=null: {relative}")

    settings = schemas[base + "habit_reminder_settings_response.schema.json"]
    enabled_branch = settings["oneOf"][0]
    active_count = enabled_branch.get("properties", {}).get("active_reminder_count", {})
    if active_count.get("const") == 1:
        fail("Enabled Habit template may legitimately have zero open Reminders")

    detail = schemas[base + "habit_detail_response.schema.json"]
    if detail["properties"]["history_start_date"].get("type") != ["string", "null"]:
        fail("Empty Habit history must permit null bounds")
    daily = schemas[base + "habit_daily_status_response.schema.json"]
    for branch_name in ["skipped", "partial", "done"]:
        branch = next(
            item for item in daily["oneOf"]
            if item["properties"]["status"].get("const") == branch_name
        )
        deleted = branch["properties"]["check_in"].get("properties", {}).get("deleted_at", {})
        if deleted.get("type") != "null":
            fail(f"DailyStatus {branch_name} must reject tombstone CheckIn")


def validate_lifecycle_matrix(yaml_documents: dict[str, Any]) -> None:
    matrix_contract = yaml_documents["habit/habit_lifecycle_operation_matrix.yaml"]
    expected_operations = {
        "habit.update", "habit.end", "habit.delete", "habit.check_in",
        "habit.clear_check_in", "habit.set_reminder",
    }
    if set(matrix_contract.get("operations", [])) != expected_operations:
        fail("Habit lifecycle operation set drift")
    matrix = matrix_contract.get("matrix", {})
    if set(matrix) != {"upcoming", "active", "completed", "ended_early", "deleted"}:
        fail("Habit lifecycle row set drift")
    for lifecycle, row in matrix.items():
        if set(row) != expected_operations:
            fail(f"Habit lifecycle operation columns drift: {lifecycle}")
    if matrix["upcoming"]["habit.end"] != {"decision": "rejected", "error": "HABIT_NOT_STARTED"}:
        fail("Upcoming Habit end policy drift")
    active_end = matrix["active"]["habit.end"]
    if active_end.get("rejected_when") != "today_equals_end_date" or active_end.get("error") != "HABIT_END_NOT_EARLY":
        fail("Final-day Habit end policy drift")
    for lifecycle in ["completed", "ended_early"]:
        for operation in expected_operations - {"habit.delete"}:
            if matrix[lifecycle][operation] != {"decision": "rejected", "error": "HABIT_ALREADY_ENDED"}:
                fail(f"Ended Habit read-only policy drift: {lifecycle}/{operation}")
        if matrix[lifecycle]["habit.delete"].get("decision") != "allowed":
            fail(f"Ended Habit delete policy drift: {lifecycle}")


def validate_recovery_separation(schemas: dict[str, Any]) -> None:
    for relative in [
        "reminder/plan_recovery_request.schema.json",
        "reminder/plan_recovery_response.schema.json",
        "reminder/reminder_recovery_batch_response.schema.json",
    ]:
        schema = schemas[f"https://excellent-calendar.local/contracts/{relative}"]
        if schema.get("x-excluded-target-types") != ["habit"]:
            fail(f"Ordinary recovery must machine-declare Habit exclusion: {relative}")
    recovery_response = schemas[
        "https://excellent-calendar.local/contracts/reminder/plan_recovery_response.schema.json"
    ]
    detail_item = recovery_response["properties"]["detail_reminders"]["items"]
    if '"const": "habit"' not in json.dumps(detail_item, sort_keys=True):
        fail("Ordinary recovery detail schema must structurally reject Habit Reminders")


def normalize_sql(value: str) -> str:
    return "".join(character.lower() for character in value if not character.isspace() and character != ";")


def validate_storage_v5(yaml_documents: dict[str, Any]) -> None:
    storage = yaml_documents["storage/calendar_core_storage.yaml"]
    if storage.get("active_format_contract") != "calendar_core_v5" or storage.get("storage_format_version") != 5:
        fail("Storage v5 must remain the active runtime format")
    if storage.get("planned_format_contract") is not None or storage.get("latest_declared_format_version") != 5:
        fail("Storage v5 active declaration is inconsistent")
    v4 = storage["calendar_core_v4"]
    v5 = storage["calendar_core_v5"]
    digest = hashlib.sha256(
        json.dumps(v4, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()
    expected_hash = "b6093231573d6b31eb245e227ff42ac92b34f7dc100903223968c1e8f2539837"
    if digest != expected_hash or v5.get("source_v4_contract_sha256") != expected_hash:
        fail(f"Frozen calendar_core_v4 Contract drift: {digest}")
    if v5.get("storage_format_version") != 5 or v5.get("implementation_status") != "integrated" or v5.get("release_status") != "active":
        fail("Storage v5 must remain integrated + active")
    if v5.get("sqlite", {}).get("user_version") != 5 or v5.get("sqlite", {}).get("bundled_version") != "3.53.4":
        fail("Storage v5 user_version or no-upgrade SQLite dependency drift")

    table_names = {"habit_recurrences", "habits", "habit_check_ins", "habit_reminder_templates"}
    tables = v5.get("new_store_tables", {})
    if set(tables) != table_names or v5["required_tables"] != {
        "inherited_count": 16,
        "new": ["habit_recurrences", "habits", "habit_check_ins", "habit_reminder_templates"],
        "total_count": 20,
    }:
        fail("Storage v5 required Habit table set/count drift")
    for name, sql in tables.items():
        normalized = normalize_sql(sql)
        expected = normalize_sql(
            f"CREATE TABLE {name}(record_key TEXT PRIMARY KEY,position INTEGER NOT NULL UNIQUE "
            "CHECK(position >= 0),payload_json TEXT NOT NULL CHECK(json_valid(payload_json))) WITHOUT ROWID"
        )
        if normalized != expected:
            fail(f"Storage v5 canonical table SQL drift: {name}")

    expected_indexes = {
        "ux_habit_recurrence_owner", "ux_habit_check_in_identity", "ux_habit_active_template",
        "ux_habit_reminder_identity", "ux_habit_sent_display_per_day", "ix_habits_lifecycle", "ix_habit_check_ins_range",
        "ix_habit_templates_by_habit",
    }
    indexes = v5.get("new_indexes", {})
    if set(indexes) != expected_indexes or v5["required_indexes"].get("total_count") != 24:
        fail("Storage v5 required Habit index set/count drift")
    if len({normalize_sql(sql) for sql in indexes.values()}) != len(expected_indexes):
        fail("Storage v5 canonical indexes must have unique definitions")
    for name, sql in indexes.items():
        if name not in normalize_sql(sql):
            fail(f"Storage v5 index SQL/name mismatch: {name}")
    expected_daily_display_sql = (
        "CREATE UNIQUE INDEX ux_habit_sent_display_per_day ON reminders("
        "json_extract(payload_json,'$.target_id'),json_extract(payload_json,'$.occurrence_date')) "
        "WHERE json_extract(payload_json,'$.target_type')='habit' "
        "AND json_extract(payload_json,'$.status')='sent'"
    )
    if normalize_sql(indexes["ux_habit_sent_display_per_day"]) != normalize_sql(expected_daily_display_sql):
        fail("Storage v5 daily Habit sent-display unique index drift")

    expected_codecs = {
        "events": 3, "recurrence_versions": 3, "event_occurrence_states": 3,
        "anniversaries": 3, "anniversary_recurrences": 3,
        "anniversary_reminder_templates": 3, "reminders": 4, "notifications": 4,
        "reminder_recovery_batches": 3, "categories": 3, "legacy_events": 1,
        "legacy_reminders": 1, "legacy_notifications": 1, "habit_recurrences": 1,
        "habits": 1, "habit_check_ins": 1, "habit_reminder_templates": 1,
    }
    if v5.get("per_store_payload_codec_versions") != expected_codecs:
        fail("Storage v5 per-store payload codec map drift")
    if v5["schema_metadata"]["required_exact"] != {
        "format_name": "excellent_calendar_core_sqlite",
        "storage_format_version": "5",
        "record_payload_version": "3",
    }:
        fail("Storage v5 exact schema metadata drift")
    fixed = v5.get("fixed_point", {})
    if fixed.get("scale") != 2 or fixed.get("max_hundredths") != SAFE_HUNDREDTHS_MAX:
        fail("Storage v5 fixed-point representation drift")
    if fixed.get("wire_representation") != "json_integer_hundredths" or fixed.get("wire_field_suffix") != "_hundredths":
        fail("Storage v5 fixed-point wire representation drift")
    if fixed.get("display_max_decimal") != str(DISPLAY_DECIMAL_MAX) or fixed.get("json_decimal_number_wire") != "forbidden":
        fail("Storage v5 must forbid JSON decimal quantity wire values")
    if fixed.get("overflow_error") != "HABIT_STATISTICS_OVERFLOW" or fixed.get("accumulation") != "checked":
        fail("Storage v5 fixed-point overflow policy drift")
    habit_invariants = v5["payload_codecs"]["habit_v1"]["invariants"]
    if not any("at most 400 natural days" in value for value in habit_invariants):
        fail("Storage v5 Habit challenge cap drift")
    if not any("at most 80 Unicode code points" in value for value in habit_invariants):
        fail("Storage v5 Habit text cap drift")

    migration = v5.get("migration", {})
    if migration.get("migration_id_v4") != "calendar_core_sqlite_v4_to_v5_habit_v1" or migration.get("transaction") != "single_BEGIN_IMMEDIATE_transaction":
        fail("Storage v4-to-v5 migration identity/atomicity drift")
    if migration.get("legal_history_suffix") != ["calendar_core_sqlite_v4_to_v5_habit_v1"]:
        fail("Storage v5 migration history suffix drift")
    if "run the complete frozen v4 checker before opening a write transaction" not in migration.get("ordered_steps", []):
        fail("Storage v5 migration must validate v4 before any write")
    if "create the four exact new tables and eight exact new indexes without IF NOT EXISTS" not in migration.get("ordered_steps", []):
        fail("Storage v5 migration DDL count drift")


def validate_yaml_and_contract_shapes(schemas: dict[str, Any]) -> dict[str, Any]:
    yaml_documents: dict[str, Any] = {}
    for path in CONTRACTS.rglob("*.yaml"):
        yaml_documents[path.relative_to(CONTRACTS).as_posix()] = yaml.safe_load(
            path.read_text(encoding="utf-8")
        )
    identity = yaml_documents["identity.yaml"]
    validate_identity(identity)
    validate_capabilities(yaml_documents)
    validate_errors_and_enums(yaml_documents, schemas)
    validate_fixed_point_shapes(schemas)
    validate_habit_limits_and_aggregates(schemas)
    validate_habit_boundary_separation(schemas)
    validate_lifecycle_matrix(yaml_documents)
    validate_recovery_separation(schemas)
    validate_storage_v5(yaml_documents)
    for path in (CONTRACTS / "habit").glob("*.schema.json"):
        schema = load_json(path)
        if schema.get("x-habit-revision") != 1 or schema.get("x-implementation-status") != "integrated":
            fail(f"Habit schema revision/status drift: {path.name}")
    for path in (CONTRACTS / "appearance").glob("*.schema.json"):
        if load_json(path).get("x-implementation-status") != "integrated":
            fail(f"Appearance schema status drift: {path.name}")
    return identity


def main() -> int:
    schemas, paths = collect_schemas()
    validate_ref_closure(schemas, paths)
    identity = validate_yaml_and_contract_shapes(schemas)
    fixture_count = validate_manifest(schemas, identity)
    print(
        f"validated schemas={len(schemas)} habit_fixtures={fixture_count} "
        f"habit_identity_vectors=4 public_methods=12 native_calls=11 status=integrated+active"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
