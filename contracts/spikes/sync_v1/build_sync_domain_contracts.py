"""Derive planned Sync v1 fact/patch schemas and a field registry from reviewed v2 inputs.

This generator never edits a legacy Schema. Generated changes are restricted to the declared
Sync projection: device-local aliases disappear, hidden domain guards are included, and Sync
lifecycle/metadata is distinct from active Native projections.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from urllib.parse import urljoin

ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "contracts"
sys.path.insert(0, str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310"))
import yaml

BASE = "https://excellent-calendar.local/contracts/"
MAX = 9007199254740991
READ_FILES = set()
DATE_TIME = {"type": "string", "format": "date-time", "pattern": r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"}
UUID = {"type": "string", "format": "uuid",
        "pattern": r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"}
LOCAL_TIME = {"type": "string", "pattern": "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"}
SOURCES = {
    "category": "category/category_response.schema.json",
    "event": "event/event_response.schema.json",
    "event_recurrence": "recurrence/recurrence_response.schema.json",
    "event_occurrence_state": "event/event_occurrence_state_response.schema.json",
    "anniversary": "anniversary/anniversary_response.schema.json",
    "anniversary_recurrence": "anniversary/anniversary_recurrence_response.schema.json",
    "habit": "habit/habit_response.schema.json",
    "habit_recurrence": "habit/habit_recurrence_response.schema.json",
    "habit_check_in": "habit/habit_check_in_response.schema.json",
}
GROUPS = {
    "category": {"ordering": ["sort_order", "reorder_revision"], "lifecycle": ["deleted_at"]},
    "event": {"timing": ["is_all_day", "start_at", "end_at", "start_date", "end_date", "timezone"],
              "lifecycle": ["status", "completed_at", "deleted_at"],
              "recurrence_link": ["has_recurrence", "recurrence_id", "recurrence_revision"]},
    "event_occurrence_state": {"occurrence_state": ["status", "state_changed_at", "reopened_at"]},
    "anniversary": {"date_rule": ["date", "calendar_type", "recurrence_id"], "lifecycle": ["deleted_at"]},
    "habit": {"target": ["target_count_hundredths", "unit"],
              "lifecycle": ["start_date", "end_date", "ended_date", "is_active", "deleted_at"],
              "history_guard": ["first_check_in_at"]},
    "habit_check_in": {"completion": ["status", "completed_count_hundredths", "completed_at"],
                       "snapshot": ["target_count_snapshot_hundredths", "unit_snapshot"]},
}
IDENTITY = {
    "category": ["id"], "event": ["id"], "event_recurrence": ["recurrence_id", "revision"],
    "event_occurrence_state": ["event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at", "occurrence_start_date", "original_local_start"],
    "anniversary": ["id"], "anniversary_recurrence": ["recurrence_id"], "habit": ["id", "recurrence_id"],
    "habit_recurrence": ["id"], "habit_check_in": ["habit_id", "check_date"],
    "reminder_intent": ["owner_type", "owner_id"], "user_preferences": [], "account_profile": [],
}
IMMUTABLE_TARGETS = {"event_recurrence", "anniversary_recurrence", "habit_recurrence"}


def nullable(schema):
    schema = copy.deepcopy(schema)
    if "type" in schema:
        schema["type"] = list(dict.fromkeys(([schema["type"]] if isinstance(schema["type"], str) else schema["type"]) + ["null"]))
    else:
        schema = {"oneOf": [schema, {"type": "null"}]}
    return schema


def object_of(properties, **extra):
    return {"type": "object", "additionalProperties": False, "required": list(properties), "properties": properties, **extra}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def read(relative):
    READ_FILES.add(relative)
    value = json.loads((CONTRACTS / relative).read_text(encoding="utf-8"))
    for node in walk(value):
        if "$ref" in node:
            node["$ref"] = urljoin(value["$id"], node["$ref"])
    return value


def schema_document(target, suffix, content):
    value = copy.deepcopy(content)
    for key in list(value):
        if key.startswith("x-") or key in {"$id", "title", "description", "examples"}:
            value.pop(key)
    value.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                  "$id": BASE + f"sync/v1/{target}_{suffix}.schema.json",
                  "title": "SyncV1 " + target + " " + suffix,
                  "x-contract-domain": "sync_protocol", "x-contract-version": 1,
                  "x-implementation-status": "planned", "x-release-status": "planned",
                  "x-rule-anchor": "cloud-sync-02/7.2,7.7"})
    return value


def reminder_schemas():
    sources = read("reminder/reminder_draft_request.schema.json")["properties"]["source"]
    entry = object_of({"remind_at": nullable(DATE_TIME), "advance_minutes": nullable({"type": "integer", "minimum": 0, "maximum": 2147483647}),
                       "method": {"enum": ["ring", "popup"]}, "message": {"type": ["string", "null"]},
                       "is_enabled": {"type": "boolean"}, "source": sources}, oneOf=[
                           {"properties": {"remind_at": DATE_TIME, "advance_minutes": {"type": "null"}}},
                           {"properties": {"remind_at": {"type": "null"}, "advance_minutes": {"type": "integer"}}}])
    result = {}
    for owner in ("event", "anniversary", "habit"):
        properties = {"owner_type": {"const": owner}, "owner_id": UUID, "is_enabled": {"type": "boolean"}}
        if owner == "event":
            properties["templates"] = {"type": "array", "items": entry, "uniqueItems": True}
        elif owner == "anniversary":
            properties["templates"] = {"type": "array", "maxItems": 5, "uniqueItems": True, "items": object_of({
                "advance_days": {"type": "integer", "minimum": 0, "maximum": 365}, "local_time": LOCAL_TIME,
                "timezone_mode": {"const": "follow_device"}, "method": {"const": "popup"},
                "is_enabled": {"type": "boolean"}})}
        else:
            properties["template"] = nullable(object_of({"local_time": LOCAL_TIME,
                "timezone_mode": {"const": "follow_device"}, "method": {"const": "popup"}}))
        result[owner] = object_of(properties)
    return result


def derive():
    READ_FILES.clear()
    facts = {name: read(path) for name, path in SOURCES.items()}
    facts["category"]["properties"]["reorder_revision"] = {"type": "integer", "minimum": 0, "maximum": MAX}
    facts["category"]["required"].append("reorder_revision")
    facts["anniversary"]["properties"]["category_id"] = {"type": ["string", "null"]}
    # Active persistent domain rejects lunar; v2 request acceptance was a typed rejection entry.
    facts["anniversary"]["properties"]["calendar_type"] = {"const": "solar"}
    facts["anniversary_recurrence"]["properties"].update(created_at=DATE_TIME, deleted_at=nullable(DATE_TIME))
    facts["anniversary_recurrence"]["required"] += ["created_at", "deleted_at"]
    facts["habit"]["properties"]["first_check_in_at"] = nullable(DATE_TIME)
    facts["habit"]["required"].append("first_check_in_at")
    facts["habit_check_in"]["properties"].pop("id")
    facts["habit_check_in"]["required"].remove("id")
    for target in ("habit_check_in", "habit_recurrence"):
        facts[target]["properties"]["deleted_at"] = nullable(DATE_TIME)
    facts["event_occurrence_state"]["properties"]["original_local_start"] = {
        "type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2})?$"}
    facts["event_occurrence_state"]["required"].append("original_local_start")
    facts["user_preferences"] = object_of({
        "timezone": {"type": "string", "minLength": 1, "x-format": "iana-timezone"},
        "habit_progress_color": read("appearance/local_appearance_response.schema.json")["properties"]["habit_progress_color"],
        "default_reminder_methods": {"type": "array", "maxItems": 2, "uniqueItems": True,
                                     "items": {"enum": ["ring", "popup"]}},
        "auto_enable_reminders_on_other_devices": {"type": "boolean"},
    })
    account, profile = read("user/user_account_response.schema.json"), read("user/user_profile_response.schema.json")
    facts["account_profile"] = object_of({"email": account["properties"]["email"],
        **{key: profile["properties"][key] for key in ("username", "display_name", "avatar")}})
    reminder_variants = reminder_schemas()
    # Properties can reference shared primitive dictionaries. Tightening a fact
    # must not change primitives used by later protocol/capability generators.
    facts = copy.deepcopy(facts)
    fact_datetime_pattern = r"^(?!0000)\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
    for target, value in facts.items():
        # Only Sync schemas gain safe-integer ceilings; protected v2 definitions remain byte/semantic stable.
        for node in walk(value):
            if node.get("format") == "date-time":
                node["pattern"] = fact_datetime_pattern
            if node.get("format") == "uuid":
                node["pattern"] = UUID["pattern"]
            types = node.get("type", [])
            if types == "integer" or "integer" in types:
                node.setdefault("maximum", MAX)
            if "timezone" in node.get("properties", {}):
                node["properties"]["timezone"]["x-format"] = "iana-timezone"

    outputs, registry = {}, {"version": 1, "protocol": "sync_protocol/v1", "implementation_status": "planned",
        "release_status": "planned", "rule_anchor": "cloud-sync-02/7.2,7.7", "targets": {},
        "excluded_targets": ["notification", "reminder", "alarm", "work", "ring_settings", "search_history",
                             "permission", "attachment", "ai", "wechat", "widget", "guest"],
        "source_projections_sha256": {path: hashlib.sha256((CONTRACTS / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
                                      for path in sorted(READ_FILES)}}
    all_facts = {**facts, **{"reminder_intent_" + name: value for name, value in reminder_variants.items()}}
    for name, fact in all_facts.items():
        target = "reminder_intent" if name.startswith("reminder_intent_") else name
        variants = registry["targets"].setdefault(target, {"direction": "download" if target == "account_profile" else "both",
            "owner": "BackendIdentityService" if target == "account_profile" else "UserPreferencesService" if target == "user_preferences" else "CoreDomainWriter",
            "conflict_center": target not in {"account_profile", "user_preferences"},
            "identity_registry": "sync_identity_registry.yaml#/targets/" + target,
            "variants": {}})["variants"]
        variant = name.removeprefix("reminder_intent_") if target == "reminder_intent" else "default"
        identity = IDENTITY[target]
        groups = copy.deepcopy(GROUPS.get(target, {}))
        fields = {}
        for field, constraint in fact["properties"].items():
            if field in identity:
                group = None
            elif target == "reminder_intent":
                group = "schedule"
            else:
                group = next((key for key, members in groups.items() if field in members), field)
            if field in {"created_at", "updated_at", "source"}:
                group = None
            readonly = field in {"reorder_revision", "first_check_in_at"} or target == "account_profile"
            update = (group is not None and not readonly and field != "deleted_at"
                      and target not in IMMUTABLE_TARGETS | {"habit_check_in"})
            accepts_null = (constraint.get("type") == "null" or "null" in constraint.get("type", [])
                            or any(n.get("type") == "null" for n in constraint.get("oneOf", [])))
            server_generated = field == "reorder_revision" or target == "account_profile"
            fields[field] = {"direction": "download" if server_generated else "both", "schema": constraint,
                "nullable": accepts_null, "merge_key": group, "server_generated": server_generated,
                "create": not readonly, "update": update, "clear": update and accepts_null,
                "import": target != "account_profile" and (target != "user_preferences" or field == "habit_progress_color"),
                "sensitive": False, "conflict_center": registry["targets"][target]["conflict_center"] and group is not None,
                "role": "identity" if field in identity else "fact" if group else "audit"}
            if group is not None:
                groups.setdefault(group, [])
                if field not in groups[group]:
                    groups[group].append(field)
        fact_path = f"sync/v1/{name}_fact.schema.json"
        outputs[CONTRACTS / fact_path] = schema_document(name, "fact", fact)
        patch_properties = {field: value["schema"] for field, value in fields.items() if value["update"]}
        patch_path = None
        if patch_properties:
            patch_path = f"sync/v1/{name}_patch.schema.json"
            patch = object_of(patch_properties, minProperties=1)
            patch["required"] = []
            dependencies = {}
            for members in groups.values():
                writable = [member for member in members if member in patch_properties]
                if len(writable) > 1:
                    for member in writable:
                        dependencies[member] = [other for other in writable if other != member]
            if dependencies:
                patch["dependentRequired"] = dependencies
            outputs[CONTRACTS / patch_path] = schema_document(name, "patch", patch)
        variants[variant] = {"fact_schema": fact_path, "patch_schema": patch_path, "fields": fields,
                             "merge_groups": groups, "immutable_fact": target in IMMUTABLE_TARGETS}
    outputs[CONTRACTS / "sync/v1/reminder_intent_fact.schema.json"] = schema_document("reminder_intent", "fact", {
        "oneOf": [{"$ref": BASE + f"sync/v1/reminder_intent_{owner}_fact.schema.json"} for owner in reminder_variants]})
    outputs[CONTRACTS / "sync/v1/sync_fact.schema.json"] = schema_document("sync", "fact", {"oneOf": [
        object_of({"target_type": {"const": target}, "target_id": {
            "type": "string", "pattern": r"^[0-9a-f-]{36}#[1-9][0-9]{0,15}$"} if target == "event_recurrence" else UUID,
            "fact": {"$ref": BASE + f"sync/v1/{target}_fact.schema.json"}})
        for target in registry["targets"]]})
    outputs[CONTRACTS / "sync/sync_field_registry.yaml"] = registry
    outputs[CONTRACTS / "reminder/default_reminder_method_applicability.yaml"] = {
        "version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/7.7",
        "selection": "first_candidate_in_original_order_that_is_legal_for_target",
        "no_intersection": "no_automatic_selection", "preference_changes_existing_reminders": False,
        "preference": {"min_items": 0, "max_items": 2, "unique": True, "enum": ["ring", "popup"], "order_significant": True},
        "targets": [{"target_type": "event", "is_all_day": all_day, "has_recurrence": recurring,
                     "allowed": [] if all_day and recurring else ["popup"] if all_day or recurring else ["ring", "popup"]}
                    for all_day in (False, True) for recurring in (False, True)] +
                   [{"target_type": "habit", "allowed": ["popup"]}, {"target_type": "anniversary", "allowed": ["popup"]}]}
    return outputs


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = derive()
    for path, value in outputs.items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            if actual != value:
                raise ValueError("Sync domain schema/registry drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            text = yaml.safe_dump(value, allow_unicode=True, sort_keys=False) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n"
            path.write_text(text, encoding="utf-8")
    print(json.dumps({"outputs": len(outputs), "targets": len(outputs[CONTRACTS / "sync/sync_field_registry.yaml"]["targets"]), "stage": "CT1_PARTIAL_NOT_FROZEN"}))


if __name__ == "__main__":
    main()
