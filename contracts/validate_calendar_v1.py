#!/usr/bin/env python3
"""Validate the frozen, not-yet-integrated Calendar View R1 Contract package."""

from __future__ import annotations

import json
import re
import warnings
from datetime import date, datetime, time, timedelta, timezone
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
        "Verification dependencies are missing. Run run_calendar_v1_validation.py "
        "to install them in an isolated temporary cache."
    ) from error


CONTRACTS = Path(__file__).resolve().parent
CALENDAR = CONTRACTS / "calendar"
FIXTURES = CONTRACTS / "fixtures" / "calendar"
MAX_RANGE_DAYS = 42


def fail(message: str) -> None:
    raise AssertionError(message)


def reject_non_json_constant(value: str) -> None:
    fail(f"Non-JSON numeric constant is forbidden: {value}")


def load_json(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8"), parse_constant=reject_non_json_constant
    )


def load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


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


def validate_ref_closure(
    schemas: dict[str, Any], paths: dict[str, Path]
) -> None:
    for schema_id, schema in schemas.items():
        for ref in walk_refs(schema):
            target, _ = urldefrag(urljoin(schema_id, ref))
            if target.startswith("https://json-schema.org/"):
                continue
            if target not in schemas:
                fail(f"Unclosed $ref {ref} in {paths[schema_id]} -> {target}")


def validate_instance(
    schema_path: Path, instance: Any, schemas: dict[str, Any]
) -> list[str]:
    schema = load_json(schema_path)
    resolver = RefResolver.from_schema(schema, store=schemas)
    validator = Draft202012Validator(
        schema, resolver=resolver, format_checker=FormatChecker()
    )
    return [
        error.message
        for error in sorted(
            validator.iter_errors(instance), key=lambda item: list(item.path)
        )
    ]


def validate_timezone(value: str) -> str | None:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        return "TIMEZONE_ID_INVALID"
    return None


def semantic_range_request(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    start = date.fromisoformat(instance["range_start_date"])
    end = date.fromisoformat(instance["range_end_date"])
    if end <= start:
        return "CALENDAR_RANGE_INVALID"
    if (end - start).days > MAX_RANGE_DAYS:
        return "CALENDAR_RANGE_TOO_LARGE"
    return validate_timezone(instance["timezone"])


def semantic_range_response(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    error = semantic_range_request(instance, _case)
    if error:
        return error
    start = date.fromisoformat(instance["range_start_date"])
    end = date.fromisoformat(instance["range_end_date"])
    days = instance["days"]
    if len(days) != (end - start).days:
        return "CONTRACT_VALIDATION_FAILED"
    expected = start
    seen: set[str] = set()
    for item in days:
        if item["date"] in seen or date.fromisoformat(item["date"]) != expected:
            return "CONTRACT_VALIDATION_FAILED"
        seen.add(item["date"])
        expected += timedelta(days=1)
    if expected != end:
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_day_request(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    date.fromisoformat(instance["date"])
    return validate_timezone(instance["timezone"])


def event_order(
    item: dict[str, Any], selected_date: str, timezone_id: str
) -> tuple[Any, ...]:
    if item["is_all_day"]:
        effective_start = 0.0
    else:
        requested_zone = ZoneInfo(timezone_id)
        day_start = datetime.combine(
            date.fromisoformat(selected_date), time.min, requested_zone
        ).astimezone(timezone.utc)
        actual_start = datetime.fromisoformat(item["start_at"].replace("Z", "+00:00"))
        effective_start = max(actual_start, day_start).timestamp()
    return (
        0 if item["is_all_day"] else 1,
        1 if item["status"] == "completed" else 0,
        effective_start,
        item["title"],
        item["event_id"],
        item["recurrence_revision"] if item["recurrence_revision"] is not None else -1,
        item["occurrence_key"] or "",
    )


def habit_order(item: dict[str, Any]) -> tuple[Any, ...]:
    buckets = {
        "absent": 0,
        "partial": 0,
        "done": 1,
        "skipped": 2,
        "missed": 3,
        "upcoming": 4,
    }
    # Reminder local time and Habit created_at are intentionally not exposed on
    # CalendarHabitItem. The external fixture oracle can therefore verify only
    # the visible primary bucket; C++ projection tests own the hidden tie-breaks.
    return (buckets[item["status"]],)


def anniversary_order(item: dict[str, Any]) -> tuple[Any, ...]:
    ranks = {
        "important_urgent": 0,
        "important_noturgent": 1,
        "unimportant_urgent": 2,
        "unimportant_noturgent": 3,
        None: 4,
    }
    return (
        ranks[item["importance"]],
        item["title"],
        item["anniversary_id"],
        item["occurrence_key"],
    )


def semantic_day_page(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    if validate_timezone(instance["timezone"]):
        return "TIMEZONE_ID_INVALID"
    items = instance["items"]
    if len(items) > instance["page_size"]:
        return "CONTRACT_VALIDATION_FAILED"
    section = instance["section"]
    if section == "event":
        identities = [
            (item["event_id"], item["occurrence_key"]) for item in items
        ]
        keys = [
            event_order(item, instance["date"], instance["timezone"])
            for item in items
        ]
    elif section == "habit":
        if any(item["date"] != instance["date"] for item in items):
            return "CONTRACT_VALIDATION_FAILED"
        for item in items:
            completed = item["completed_count_hundredths"]
            target = item["target_count_hundredths"]
            if item["status"] == "partial" and not (
                isinstance(completed, int)
                and isinstance(target, int)
                and 0 < completed < target
            ):
                return "CONTRACT_VALIDATION_FAILED"
            if (
                item["status"] == "done"
                and target is not None
                and not (isinstance(completed, int) and completed >= target)
            ):
                return "CONTRACT_VALIDATION_FAILED"
        identities = [(item["habit_id"], item["date"]) for item in items]
        keys = [habit_order(item) for item in items]
    else:
        if any(item["occurrence_date"] != instance["date"] for item in items):
            return "CONTRACT_VALIDATION_FAILED"
        identities = [item["occurrence_key"] for item in items]
        keys = [anniversary_order(item) for item in items]
    if len(set(identities)) != len(identities) or keys != sorted(keys):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_summary_conservation(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    for day in instance.get("days", []):
        expected = {
            "has_open_event": any(
                status != "completed" for status in day["event_statuses"]
            ),
            "has_pending_habit": any(
                status != "done" for status in day["habit_statuses"]
            ),
            "has_anniversary": day["anniversary_count"] > 0,
        }
        if day["summary"] != expected:
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_pagination_boundaries(
    instance: dict[str, Any], _case: dict[str, Any]
) -> str | None:
    page_size = instance.get("page_size")
    if page_size != 20:
        return "CONTRACT_VALIDATION_FAILED"
    for vector in instance.get("vectors", []):
        counts = vector["page_item_counts"]
        flags = vector["has_more"]
        if len(counts) != len(flags) or sum(counts) != vector["total_items"]:
            return "CONTRACT_VALIDATION_FAILED"
        if not counts or flags[-1] or any(count < 0 or count > page_size for count in counts):
            return "CONTRACT_VALIDATION_FAILED"
        if any(flag != (index < len(counts) - 1) for index, flag in enumerate(flags)):
            return "CONTRACT_VALIDATION_FAILED"
        if any(count == 0 and flag for count, flag in zip(counts, flags)):
            return "CONTRACT_VALIDATION_FAILED"
    return None


def semantic_cursor_binding(
    instance: dict[str, Any], _case: dict[str, Any], invariants: dict[str, Any]
) -> str | None:
    pagination = invariants["pagination"]
    if instance.get("sort_revision") != pagination["cursor_sort_revision"]:
        return "CONTRACT_VALIDATION_FAILED"
    if instance.get("required_bindings") != pagination["cursor_binds"]:
        return "CONTRACT_VALIDATION_FAILED"
    expected_errors = {
        "mismatch_error": "CALENDAR_CURSOR_QUERY_MISMATCH",
        "changed_generation_error": "CALENDAR_SNAPSHOT_EXPIRED",
        "malformed_cursor_error": "CALENDAR_CURSOR_INVALID",
        "malformed_snapshot_error": "CALENDAR_SNAPSHOT_INVALID",
    }
    if any(instance.get(key) != value for key, value in expected_errors.items()):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def validate_manifest(
    schemas: dict[str, Any], invariants: dict[str, Any]
) -> int:
    handlers = {
        "range_request": semantic_range_request,
        "range_response": semantic_range_response,
        "day_request": semantic_day_request,
        "day_page": semantic_day_page,
        "summary_conservation": semantic_summary_conservation,
        "pagination_boundaries": semantic_pagination_boundaries,
        "cursor_binding": lambda value, case: semantic_cursor_binding(
            value, case, invariants
        ),
    }
    manifest = load_json(FIXTURES / "manifest.json")
    if manifest.get("fixture_version") != 1 or not manifest.get("cases"):
        fail("Calendar fixture manifest version/cases are invalid")
    count = 0
    for case in manifest["cases"]:
        count += 1
        instance = load_json(FIXTURES / case["instance"])
        if "schema" in case:
            errors = validate_instance(
                (FIXTURES / case["schema"]).resolve(), instance, schemas
            )
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


def validate_capabilities(documents: dict[str, Any]) -> None:
    expected = {
        "calendar.range_summary": (
            "calendar/calendar_range_summary_request.schema.json",
            "calendar/calendar_range_summary_response.schema.json",
        ),
        "calendar.list_day_items": (
            "calendar/calendar_list_day_items_request.schema.json",
            "calendar/calendar_day_item_page.schema.json",
        ),
    }
    methods = documents["method_channels.yaml"]["methods"]
    calls = documents["native_calls.yaml"]["calls"]
    actual_methods = {
        name for name, entry in methods.items() if entry.get("module") == "calendar"
    }
    actual_calls = {
        name for name, entry in calls.items() if entry.get("module") == "calendar"
    }
    if actual_methods != set(expected) or actual_calls != set(expected):
        fail("Calendar public/internal capability map drift")
    for mapping, public in ((methods, True), (calls, False)):
        for name, schemas in expected.items():
            entry = mapping[name]
            actual = (entry.get("request"), entry.get("result", {}).get("data"))
            if actual != schemas:
                fail(f"Calendar capability schema drift: {name}")
            if entry.get("result", {}).get("envelope") != "common/native_result.schema.json":
                fail(f"Calendar NativeResult envelope drift: {name}")
            if entry.get("implementation_status") != "integrated" or entry.get(
                "release_status"
            ) != "active":
                fail(
                    "Calendar capability must remain integrated + active after the "
                    f"2026-09-02 product release decision: {name}"
                )
            if public:
                if entry.get("event_stream") is not False:
                    fail(f"Calendar query must not be an EventChannel: {name}")
            elif entry.get("visibility") != "internal" or entry.get("caller") != "kotlin":
                fail(f"Calendar native visibility/caller drift: {name}")


def validate_errors_and_enums(
    documents: dict[str, Any], schemas: dict[str, Any]
) -> None:
    required_errors = {
        "CALENDAR_RANGE_INVALID",
        "CALENDAR_RANGE_TOO_LARGE",
        "CALENDAR_SNAPSHOT_INVALID",
        "CALENDAR_SNAPSHOT_EXPIRED",
        "CALENDAR_CURSOR_INVALID",
        "CALENDAR_CURSOR_QUERY_MISMATCH",
    }
    errors = documents["error_codes.yaml"]["errors"]
    if missing := required_errors - set(errors):
        fail(f"Missing Calendar errors: {sorted(missing)}")
    for code in required_errors:
        if not {
            "module",
            "message",
            "retryable",
            "boundaries",
            "data_saved_allowed",
        } <= set(errors[code]):
            fail(f"Calendar error metadata incomplete: {code}")
        if errors[code]["module"] != "calendar":
            fail(f"Calendar error module drift: {code}")
    native_codes = set(
        schemas[
            "https://excellent-calendar.local/contracts/common/native_error.schema.json"
        ]["properties"]["code"]["enum"]
    )
    if missing := required_errors - native_codes:
        fail(f"NativeError enum is missing Calendar codes: {sorted(missing)}")
    expected_enums = {
        "CalendarSection": ["event", "habit", "anniversary"],
        "CalendarEventItemStatus": [
            "pending",
            "in_progress",
            "overdue",
            "completed",
            "skipped",
        ],
        "CalendarEventDayDisplay": [
            "all_day",
            "starts_at",
            "continues",
            "ends_at",
        ],
    }
    enums = documents["enums.yaml"]
    for name, values in expected_enums.items():
        if enums.get(name, {}).get("values") != values:
            fail(f"Calendar enum drift: {name}")


def validate_invariants(invariants: dict[str, Any]) -> None:
    if invariants.get("version") != 1 or invariants.get("contract_version") != 2:
        fail("Calendar query invariant version drift")
    if invariants.get("implementation_status") != "integrated" or invariants.get(
        "release_status"
    ) != "active":
        fail(
            "Calendar query invariants must remain integrated + active"
        )
    if invariants["range_summary"]["maximum_natural_days"] != MAX_RANGE_DAYS:
        fail("Calendar range maximum drift")
    if invariants["pagination"]["default_page_size"] != 20 or invariants[
        "pagination"
    ]["maximum_page_size"] != 100:
        fail("Calendar pagination limits drift")
    if invariants["sections"]["order"] != ["event", "habit", "anniversary"]:
        fail("Calendar section order drift")
    snapshot = invariants["snapshot"]
    if snapshot.get("contributing_stores") != [
        "events",
        "recurrence_versions",
        "event_occurrence_states",
        "habits",
        "habit_recurrences",
        "habit_check_ins",
        "anniversaries",
        "anniversary_recurrences",
        "reminders",
    ]:
        fail("Calendar snapshot contributing-store order drift")
    if snapshot.get("token_payload") != [
        "contributing_store_generations",
        "evaluation_clock_utc",
    ]:
        fail("Calendar snapshot payload must freeze generations and evaluation Clock")
    required_snapshot_rules = {
        "range_summary_captures_one_clock_and_returns_current_token",
        "every_list_page_uses_token_evaluation_clock",
        "wall_clock_advance_alone_does_not_expire_token",
        "flutter_invalidates_at_requested_timezone_local_day_change",
    }
    if not required_snapshot_rules <= set(snapshot.get("protocol", [])):
        fail("Calendar snapshot Clock protocol drift")
    if (
        invariants["sections"]["event"]["status_projection"].get("clock")
        != "snapshot_token_evaluation_clock_utc"
    ):
        fail("Calendar Event status Clock drift")
    completed_series = invariants["sections"]["event"].get(
        "completed_recurring_series_cutoff", {}
    )
    if completed_series != {
        "cutoff": "occurrence_anchor_strictly_before_event_completed_at",
        "timed_occurrence_anchor": "occurrence_start_at",
        "all_day_occurrence_anchor": (
            "occurrence_start_date_start_of_day_resolved_in_recurrence_timezone"
        ),
        "occurrence_starting_exactly_at_cutoff_is_excluded": True,
        "occurrence_starting_before_cutoff_retains_full_original_interval": True,
        "retained_occurrence_projects_as": "completed",
    }:
        fail("Calendar completed recurring-series cutoff drift")
    timed_projection = invariants["sections"]["event"].get(
        "timed_day_projection", {}
    )
    if timed_projection.get("effective_sort_start") != (
        "max_actual_start_at_and_selected_day_start_instant"
    ) or timed_projection.get("ends_at") != (
        "actual_start_at_is_before_day_start_and_actual_end_at_is_at_or_before_day_end"
    ):
        fail("Calendar cross-day display/sort projection drift")
    if invariants["sections"]["event"].get("all_day_effective_sort_start") != (
        "selected_day_start_in_requested_timezone"
    ):
        fail("Calendar all-day effective sort start drift")
    quantity_projection = invariants["sections"]["habit"].get(
        "quantity_status_projection", {}
    )
    if quantity_projection.get("partial") != (
        "0_lt_completed_count_hundredths_lt_target_count_hundredths"
    ) or quantity_projection.get("done") != (
        "completed_count_hundredths_gte_target_count_hundredths"
    ):
        fail("Calendar Habit quantity status projection drift")
    snapshot_pattern = snapshot["token_pattern"]
    cursor_pattern = invariants["pagination"]["cursor_pattern"]
    if not re.fullmatch(snapshot_pattern, "calsnap1.ABCDEFGHIJKLMNOPQRST"):
        fail("Calendar snapshot pattern rejects the frozen fixture")
    if not re.fullmatch(cursor_pattern, "calcur1.ABCDEFGHIJKLMNOPQRST"):
        fail("Calendar cursor pattern rejects the frozen fixture")


def validate_calendar_schema_metadata(paths: dict[str, Path]) -> None:
    calendar_paths = sorted(CALENDAR.glob("*.schema.json"))
    if len(calendar_paths) != 8:
        fail(f"Expected 8 Calendar schemas, found {len(calendar_paths)}")
    known_paths = set(paths.values())
    for path in calendar_paths:
        if path not in known_paths:
            fail(f"Calendar schema was not collected: {path}")
        schema = load_json(path)
        if schema.get("x-contract-version") != 2:
            fail(f"Calendar schema contract version drift: {path.name}")
        if schema.get("x-calendar-view-revision") != 1:
            fail(f"Calendar schema revision drift: {path.name}")
        if schema.get("x-implementation-status") != "integrated":
            fail(
                "Calendar schema status must remain integrated: "
                f"{path.name}"
            )


def main() -> int:
    schemas, paths = collect_schemas()
    validate_ref_closure(schemas, paths)
    documents = {
        name: load_yaml(CONTRACTS / name)
        for name in (
            "method_channels.yaml",
            "native_calls.yaml",
            "error_codes.yaml",
            "enums.yaml",
        )
    }
    invariants = load_yaml(CALENDAR / "calendar_query_invariants.yaml")
    validate_calendar_schema_metadata(paths)
    validate_invariants(invariants)
    validate_capabilities(documents)
    validate_errors_and_enums(documents, schemas)
    fixture_count = validate_manifest(schemas, invariants)
    print(
        "Calendar View R1 contract validation passed: "
        f"schemas={len(schemas)} fixtures={fixture_count} public_methods=2 "
        "native_calls=2 status=integrated+active"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
