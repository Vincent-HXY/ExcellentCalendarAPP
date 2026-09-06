"""Isolate v3 business-reader changes without editing any v2 Schema.

The closure is derived from references, not a hand-maintained list of callers.
Unchanged business payloads remain referenced by their original schema IDs.
"""
import argparse
import copy
import hashlib
import json
from urllib.parse import urljoin, urldefrag

from build_sync_domain_contracts import CONTRACTS, BASE, yaml
from build_sync_protocol_contracts import MAX, UUID4, document


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def derive():
    baseline = json.loads((CONTRACTS / "sync/sync_v1_baseline.json").read_text(encoding="utf-8"))
    originals = {path.removeprefix("contracts/"): json.loads((CONTRACTS.parent / path).read_text(encoding="utf-8"))
                 for path in baseline["files"] if path.endswith(".schema.json")}
    anniversary = json.loads((CONTRACTS / "native_v3/anniversary_compatibility.json").read_text(encoding="utf-8"))
    existing = {row["source"]: row["target"] for row in anniversary["schemas"]}
    edited, reasons = {}, {}
    routing_fields = {"workspace_id": UUID4, "workspace_kind": {"enum": ["local", "account"]}}
    for path, original in originals.items():
        data = copy.deepcopy(original)
        changes = []
        for node in walk(data):
            props = node.get("properties", {})
            for key in props:
                if key == "recurrence_revision" or (path == "recurrence/recurrence_response.schema.json" and key == "revision"):
                    props[key]["maximum"] = MAX
                    changes.append("checked_recurrence_revision_int64_safe_range")
        if path == "reminder/reminder_response.schema.json":
            data["properties"]["last_cancellation_reason"]["enum"].append("source_migrated")
            data.setdefault("allOf", []).append({"if": {"properties": {"last_cancellation_reason": {"const": "source_migrated"}}},
                "then": {"properties": {"status": {"const": "cancelled"}, "is_enabled": {"const": False},
                    "scheduled_at": {"type": "null"}, "last_cancelled_at": {"type": "string", "format": "date-time"}}}})
            changes.append("guest_source_migrated_irreversible_cancellation")
        if path == "notification/notification_response.schema.json":
            data["properties"]["abandon_reason"]["enum"].append("source_migrated")
            for condition in data["allOf"]:
                if condition.get("if", {}).get("properties", {}).get("status") == {"const": "abandoned"}:
                    condition["then"]["properties"]["abandon_reason"]["enum"].append("source_migrated")
                    condition["then"]["oneOf"].append({"properties": {
                        "abandon_reason": {"const": "source_migrated"}, "resolved_by_recovery_batch_id": {"type": "null"}}})
            data["allOf"].append({"if": {"properties": {"abandon_reason": {"const": "source_migrated"}}},
                "then": {"properties": {"status": {"const": "abandoned"}}}})
            changes.append("guest_source_migrated_prepared_attempt_abandonment")
        if path in {"notification/notification_tap_payload.schema.json", "notification/prepared_notification_payload.schema.json",
                    "habit/habit_notification_action_payload.schema.json"}:
            data["properties"].update(copy.deepcopy(routing_fields))
            data["dependentRequired"] = {"workspace_id": ["workspace_kind"], "workspace_kind": ["workspace_id"]}
            changes.append("paired_optional_workspace_routing_legacy_reader")
        if path == "ring/active_ring_item.schema.json":
            data["properties"].update(copy.deepcopy(routing_fields))
            data["required"] += list(routing_fields)
            data.pop("examples", None)
            changes.append("required_workspace_routing_each_active_delivery")
        mixed_requests = {"calendar/calendar_range_summary_request.schema.json", "calendar/calendar_list_day_items_request.schema.json",
            "search/search_query_request.schema.json"}
        mixed_responses = {"calendar/calendar_range_summary_response.schema.json", "calendar/calendar_day_item_page.schema.json",
            "search/search_query_response.schema.json"}
        if path in mixed_requests | mixed_responses:
            zone = data["properties"].pop("timezone")
            data["required"].remove("timezone")
            if path in mixed_responses:
                zone["x-format"] = "iana-timezone"
                data["properties"].update(workspace_timezone=copy.deepcopy(zone), device_timezone=copy.deepcopy(zone))
                data["required"] += ["workspace_timezone", "device_timezone"]
            data.pop("examples", None)
            changes.append("mixed_query_separate_workspace_and_device_timezones")
        if changes:
            if path == "calendar/calendar_range_summary_request.schema.json":
                data["description"] = data["description"].replace("in one explicit IANA timezone",
                    "using the persisted workspace timezone for Event and OS device timezone for Habit/Anniversary")
            edited[path], reasons[path] = data, sorted(set(changes))
    changed = set(edited) | set(existing)
    while True:
        parents = {path for path, data in originals.items() if any(
            urldefrag(urljoin(data["$id"], node["$ref"]))[0].removeprefix(BASE) in changed
            for node in walk(data) if "$ref" in node)}
        enlarged = changed | parents
        if enlarged == changed:
            break
        changed = enlarged
    # Anniversary's accepted revision is already generated separately. Other
    # parents can select it without rewriting the accepted 15-schema ledger.
    mapping = {path: existing.get(path, "native_v3/business_compat/" + path) for path in sorted(changed)}
    out, ledger = {}, []
    for source, target in mapping.items():
        if source in existing:
            continue
        data = copy.deepcopy(edited.get(source, originals[source]))
        old_id = data["$id"]
        for node in walk(data):
            if "$ref" in node:
                uri, fragment = urldefrag(urljoin(old_id, node["$ref"]))
                relative = uri.removeprefix(BASE)
                node["$ref"] = BASE + mapping.get(relative, relative) + ("#" + fragment if fragment else "")
        data.update({"$id": BASE + target, "x-contract-domain": "native", "x-contract-version": 3,
            "x-implementation-status": "planned", "x-release-status": "planned", "x-rule-anchor": "cloud-sync-02/5,6.1,8.4"})
        out[CONTRACTS / target] = data
        ledger.append({"source": source, "target": target, "changes": reasons.get(source, ["transitive_ref_only"]),
            "source_semantic_sha256": hashlib.sha256(json.dumps(originals[source], sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()})
    # The persisted Reminder has two private fields deliberately absent from
    # NativeResponse. Preserve those fields instead of storing a boundary DTO.
    reminder_record = copy.deepcopy(out[CONTRACTS / mapping["reminder/reminder_response.schema.json"]])
    reminder_record.update({"$id": BASE + "storage/v6/reminder_record.schema.json", "title": "SQLite v6 complete Reminder record",
        "x-contract-domain": "calendar_core_storage", "x-contract-version": 6})
    reminder_record["properties"].update(recovery_batch_id={"type": ["string", "null"], "format": "uuid"},
        source=copy.deepcopy(originals["reminder/create_reminder_request.schema.json"]["properties"]["source"]))
    reminder_record["required"] += ["recovery_batch_id", "source"]
    reminder_record["allOf"].append({"if": {"properties": {"target_type": {"const": "habit"}}},
        "then": {"properties": {"recovery_batch_id": {"type": "null"}}}})
    out[CONTRACTS / "storage/v6/reminder_record.schema.json"] = reminder_record
    # The migration reader accepts either the old complete identity or the new
    # complete pair; every v6 writer must supply both workspace fields.
    writers = {}
    for directory, source in (("notification", "notification_tap_payload"), ("notification", "prepared_notification_payload"),
                              ("habit", "habit_notification_action_payload")):
        original = directory + "/" + source + ".schema.json"
        target = mapping[original]
        writer_path = "native_v3/" + directory + "/" + source + "_v6_writer.schema.json"
        out[CONTRACTS / writer_path] = document(source + "_v6_writer", {
            "allOf": [{"$ref": BASE + target}, {"required": ["workspace_id", "workspace_kind"]}]
        }, "8.4", "native_v3/" + directory)
        out[CONTRACTS / writer_path].update({"x-contract-domain": "native", "x-contract-version": 3})
        writers[original] = writer_path
    out[CONTRACTS / "native_v3/business_compatibility.yaml"] = {
        "version": 3, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/5,6.1,8.4",
        "schemas": ledger, "schema_mapping": mapping, "writer_schema_mapping": writers,
        "recurrence_revision": {"wire_minimum": 1, "wire_maximum": MAX, "old_cpp_reader_maximum": 2147483647,
            "cpp": "checked std::int64_t", "kotlin": "exact Long", "dart": "exact int", "java": "exact long",
            "storage_codec_revisions": "storage/calendar_core_storage.yaml#/calendar_core_v6/payload_codec_revisions",
            "legacy_v2_schema": "unchanged; its absent maximum does not prove that the int32 production decoder accepts larger values",
            "legacy_v5": "exact historical codecs and rows; v6 explicitly versions recurrence width and source-migrated Reminder/Notification audit deltas",
            "v3_dispatch": "only workspace-bound v6 runtimes; never send a v6 record to the v2/v5 int32 reader"},
        "notification": {"legacy_reader": "workspace pair absent or both present; never one present/null",
            "source_retirement": "pending/scheduled Reminder -> cancelled with last_cancellation_reason=source_migrated; prepared Notification -> abandoned with abandon_reason=source_migrated; terminal audit payloads remain unchanged; late finalize has zero writes",
            "v6_writer": "both workspace fields required for prepared, tap and Habit action payloads; reminder.prepare_delivery uses writer refs recursively",
            "legacy_route": "only a uniquely identified legacy workspace; ambiguity refuses routing; no target-id scan across databases",
            "hidden_account": "unavailable until the same account is authenticated and unlockable; never auto-login",
            "guest_source_label": "本机", "upload": "workspace routing is local-only and excluded from all Sync facts"},
        "mixed_query_timezones": {
            "operations": ["calendar.range_summary", "calendar.list_day_items", "search.query"],
            "public_request": "Flutter supplies dates/filter/pagination only; timezone is absent and forbidden",
            "native_request": "workspace_timezone must be null (resolve in Core); device_timezone is the OS IANA zone injected by Kotlin",
            "workspace_authority": "C++ reads workspace_preferences.timezone inside the same query snapshot; never a Flutter/Kotlin override",
            "response": "workspace_timezone is the resolved persisted value; device_timezone echoes the validated OS value",
            "snapshot_binding": "Calendar/Search snapshot and cursor bind both effective zones; a change on either axis invalidates reuse",
            "projection": "Event uses workspace_timezone; Habit/Anniversary local dates and follow-device use device_timezone",
            "invalidation": "workspace changes invalidate Event projection only; OS changes invalidate Habit/Anniversary and reconcile their open reminders"},
    }
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            assert actual == value, str(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(value, sort_keys=False, allow_unicode=True) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Native v3 business compatibility definitions generated; v2 untouched")
