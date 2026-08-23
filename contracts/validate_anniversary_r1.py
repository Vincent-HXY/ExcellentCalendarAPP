#!/usr/bin/env python3
"""Validate the Anniversary Reminder/Occurrence R1 contract package.

Runtime-only dependencies: jsonschema and PyYAML. They are verification tools,
not application dependencies and are intentionally not added to the product.
"""

from __future__ import annotations

import json
import sys
import uuid
import warnings
from datetime import date
from pathlib import Path
from typing import Any
from urllib.parse import urldefrag, urljoin

try:
    warnings.filterwarnings("ignore", message=r"jsonschema\.RefResolver is deprecated.*", category=DeprecationWarning)
    import yaml
    from jsonschema import Draft202012Validator, FormatChecker, RefResolver
except ModuleNotFoundError as error:  # pragma: no cover - environment gate
    raise SystemExit(
        "Verification dependencies are missing. Install jsonschema and PyYAML "
        "in an isolated environment before running this script."
    ) from error


CONTRACTS = Path(__file__).resolve().parent
FIXTURE_ROOT = CONTRACTS / "fixtures"
ANNIVERSARY_FIXTURES = FIXTURE_ROOT / "anniversary"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


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
    validator = Draft202012Validator(schema, resolver=resolver, format_checker=FormatChecker())
    return [error.message for error in sorted(validator.iter_errors(instance), key=lambda item: list(item.path))]


def semantic_unique_templates(instance: dict[str, Any]) -> str | None:
    templates = instance["reminder_plan"]["templates"]
    keys = [(item["advance_days"], item["local_time"], item["method"]) for item in templates]
    return None if len(keys) == len(set(keys)) else "ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE"


def semantic_occurrence_range(instance: dict[str, Any]) -> str | None:
    start = date.fromisoformat(instance["range_start_date"])
    end = date.fromisoformat(instance["range_end_date"])
    size = (end - start).days
    if size <= 0:
        return "ANNIVERSARY_OCCURRENCE_RANGE_INVALID"
    if size > 400:
        return "ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE"
    return None


def semantic_occurrence_order(instance: dict[str, Any]) -> str | None:
    keys = [(item["occurrence_date"], item["anniversary_id"], item["occurrence_key"]) for item in instance["items"]]
    return None if keys == sorted(keys) and len(keys) == len(set(keys)) else "ANNIVERSARY_OCCURRENCE_CURSOR_INVALID"


def aggregate_delivery_id(instance: dict[str, Any], identity: dict[str, Any]) -> str:
    namespace = uuid.UUID(identity["namespaces"]["anniversary_catch_up_delivery"]["uuid"])
    covered = instance["covered_reminder_ids"]
    canonical = json.dumps(
        ["anniversary_catch_up", instance["target_id"], instance["occurrence_key"], covered, "popup"],
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return str(uuid.uuid5(namespace, canonical))


def semantic_covered_order_and_identity(instance: dict[str, Any], identity: dict[str, Any]) -> str | None:
    covered = instance["covered_reminder_ids"]
    if covered != sorted(covered) or len(covered) != len(set(covered)):
        return "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT"
    if aggregate_delivery_id(instance, identity) != instance["delivery_id"]:
        return "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT"
    return None


def semantic_recovery_membership(instance: dict[str, Any], identity: dict[str, Any]) -> str | None:
    batch = instance["batch"]
    if instance["anniversary_catch_up_groups"] != batch["anniversary_catch_up_groups"]:
        return "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT"
    seen = set(batch["detail_reminder_ids"]) | set(batch["summary_reminder_ids"])
    for group in batch["anniversary_catch_up_groups"]:
        covered = group["covered_reminder_ids"]
        if covered != sorted(covered) or seen.intersection(covered):
            return "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT"
        seen.update(covered)
        notification_shape = {
            "target_id": group["anniversary_id"],
            "occurrence_key": group["occurrence_key"],
            "covered_reminder_ids": covered,
        }
        if aggregate_delivery_id(notification_shape, identity) != group["delivery_id"]:
            return "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT"
    return None


def semantic_mutation_reconciliation(instance: dict[str, Any]) -> str | None:
    settings = instance["detail"]["reminder_settings"]
    capability = instance["capability"]
    expected_count = 0 if not settings["reminders_enabled"] else sum(item["is_enabled"] for item in settings["templates"])
    if settings["active_reminder_count"] != expected_count:
        return "ANNIVERSARY_REMINDER_CONFIG_INVALID"
    if settings["schedule_reconciliation_required"] != capability["schedule_reconciliation_required"]:
        return "SCHEDULER_RECONCILIATION_PENDING"
    return None


def semantic_storage_migration(instance: dict[str, Any]) -> str | None:
    source = instance["source"]["anniversary"]
    expected = instance["expected"]["anniversary"]
    for field in instance["preserve_exact_fields"]:
        if source[field] != expected[field]:
            return "STORAGE_DATA_CORRUPTED"
    if expected["reminders_enabled"] is not False:
        return "STORAGE_DATA_CORRUPTED"
    if instance["expected"]["anniversary_reminder_templates"] != []:
        return "STORAGE_DATA_CORRUPTED"
    if any(value is not None for value in instance["expected"]["reminder_new_fields"].values()):
        return "STORAGE_DATA_CORRUPTED"
    return None


def semantic_vectors(instance: dict[str, Any]) -> str | None:
    required = {"occurrence_vectors", "cursor_vectors", "materialization_vectors", "catch_up_vectors", "finalize_vectors", "tap_vectors", "migration_vectors"}
    if set(instance) != required | {"fixture_version"}:
        return "CONTRACT_VALIDATION_FAILED"
    if not all(instance[name] for name in required):
        return "CONTRACT_VALIDATION_FAILED"
    return None


def validate_identity_vectors(identity: dict[str, Any]) -> None:
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
    }
    vectors = identity["test_vectors"]
    if set(vectors) != set(namespace_for_vector):
        fail(f"Identity vector mapping drift: {set(vectors) ^ set(namespace_for_vector)}")
    for name, namespace_name in namespace_for_vector.items():
        vector = vectors[name]
        namespace = uuid.UUID(identity["namespaces"][namespace_name]["uuid"])
        actual = str(uuid.uuid5(namespace, vector["canonical_name"]))
        if actual != vector["uuid"]:
            fail(f"Identity vector {name}: expected {vector['uuid']}, recalculated {actual}")


def validate_yaml_and_capabilities() -> dict[str, Any]:
    yaml_documents = {}
    for path in CONTRACTS.rglob("*.yaml"):
        yaml_documents[path.relative_to(CONTRACTS).as_posix()] = yaml.safe_load(path.read_text(encoding="utf-8"))
    identity = yaml_documents["identity.yaml"]
    validate_identity_vectors(identity)

    methods = yaml_documents["method_channels.yaml"]["methods"]
    calls = yaml_documents["native_calls.yaml"]["calls"]
    for capability in [
        "anniversary.create", "anniversary.update", "anniversary.delete", "anniversary.detail",
        "anniversary.set_reminders_enabled", "anniversary.list_occurrences",
    ]:
        if capability not in methods or capability not in calls:
            fail(f"Public/native capability path is incomplete: {capability}")
        if methods[capability].get("release_status") != "blocked":
            fail(f"Capability must remain blocked before integration: {capability}")
        if calls[capability].get("release_status") != "blocked":
            fail(f"Native capability must remain blocked before integration: {capability}")
        for side in (methods[capability], calls[capability]):
            for key in ("request",):
                if not (CONTRACTS / side[key]).is_file():
                    fail(f"Missing {capability} {key}: {side[key]}")
            data = side["result"]["data"]
            if not (CONTRACTS / data).is_file():
                fail(f"Missing {capability} response: {data}")

    errors = yaml_documents["error_codes.yaml"]["errors"]
    required_errors = {
        "ANNIVERSARY_REMINDER_CONFIG_INVALID", "ANNIVERSARY_REMINDER_TEMPLATE_DUPLICATE",
        "ANNIVERSARY_REMINDER_TEMPLATE_LIMIT_EXCEEDED", "ANNIVERSARY_OCCURRENCE_RANGE_INVALID",
        "ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE", "ANNIVERSARY_OCCURRENCE_FILTER_INVALID",
        "ANNIVERSARY_OCCURRENCE_CURSOR_INVALID", "ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED",
        "ANNIVERSARY_TARGET_DELETED", "ANNIVERSARY_OCCURRENCE_STALE",
        "ANNIVERSARY_REMINDER_OCCURRENCE_EXPIRED", "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT",
        "CALENDAR_WORKFLOW_COMMIT_FAILED", "CALENDAR_WORKFLOW_RECOVERY_FAILED",
        "SCHEDULER_RECONCILIATION_PENDING",
    }
    if missing := required_errors - set(errors):
        fail(f"Missing stable Anniversary errors: {sorted(missing)}")
    for code in required_errors:
        entry = errors[code]
        if "retryable" not in entry or "boundaries" not in entry or "data_saved_allowed" not in entry:
            fail(f"Error metadata incomplete: {code}")
    return identity


def validate_manifests(schemas: dict[str, Any], identity: dict[str, Any]) -> int:
    semantic_handlers = {
        "unique_templates": lambda value: semantic_unique_templates(value),
        "occurrence_range": lambda value: semantic_occurrence_range(value),
        "occurrence_order": lambda value: semantic_occurrence_order(value),
        "covered_order_and_identity": lambda value: semantic_covered_order_and_identity(value, identity),
        "recovery_membership": lambda value: semantic_recovery_membership(value, identity),
        "mutation_reconciliation": lambda value: semantic_mutation_reconciliation(value),
        "storage_migration": lambda value: semantic_storage_migration(value),
        "semantic_vectors": lambda value: semantic_vectors(value),
    }
    count = 0
    for manifest_path in [FIXTURE_ROOT / "ring" / "manifest.json", ANNIVERSARY_FIXTURES / "manifest.json"]:
        manifest = load_json(manifest_path)
        for case in manifest["cases"]:
            count += 1
            instance = load_json(manifest_path.parent / case["instance"])
            if "schema" in case:
                errors = validate_instance((manifest_path.parent / case["schema"]).resolve(), instance, schemas)
                actual_valid = not errors
                if actual_valid != case["expected_valid"]:
                    fail(f"Fixture {case['name']} expected_valid={case['expected_valid']} errors={errors}")
            check = case.get("semantic_check")
            if check:
                actual_error = semantic_handlers[check](instance)
                expected_error = case.get("expected_error")
                if actual_error != expected_error:
                    fail(f"Fixture {case['name']} semantic error expected {expected_error}, got {actual_error}")
    return count


def main() -> int:
    schemas, paths = collect_schemas()
    validate_ref_closure(schemas, paths)
    identity = validate_yaml_and_capabilities()
    fixture_count = validate_manifests(schemas, identity)
    print(f"validated schemas={len(schemas)} fixtures={fixture_count} identity_vectors={len(identity['test_vectors'])}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
