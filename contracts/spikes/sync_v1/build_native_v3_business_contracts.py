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
        if changes:
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
            "legacy_v5": "exact historical codecs and rows; four v6 metadata codec bumps authorize only the recurrence counter width change",
            "v3_dispatch": "only workspace-bound v6 runtimes; never send a v6 record to the v2/v5 int32 reader"},
        "notification": {"legacy_reader": "workspace pair absent or both present; never one present/null",
            "v6_writer": "both workspace fields required for prepared, tap and Habit action payloads; reminder.prepare_delivery uses writer refs recursively",
            "legacy_route": "only a uniquely identified legacy workspace; ambiguity refuses routing; no target-id scan across databases",
            "hidden_account": "unavailable until the same account is authenticated and unlockable; never auto-login",
            "guest_source_label": "本机", "upload": "workspace routing is local-only and excluded from all Sync facts"},
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
