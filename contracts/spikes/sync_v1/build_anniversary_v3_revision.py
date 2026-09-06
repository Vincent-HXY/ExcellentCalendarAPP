#!/usr/bin/env python3
"""Derive the approved Anniversary v3 compatibility revision without editing v2.

Copies only changed schemas and their transitive schema consumers. A check run
re-derives the change from the protected v2 definitions and rejects extra drift.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from urllib.parse import urldefrag, urljoin

ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "contracts"
PREFIX = "https://excellent-calendar.local/contracts/"


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def derive():
    schemas = {}
    for path in CONTRACTS.rglob("*.schema.json"):
        if "native_v3" in path.relative_to(CONTRACTS).parts or "sync/v1" in path.relative_to(CONTRACTS).as_posix():
            continue
        value = json.loads(path.read_text(encoding="utf-8"))
        schemas[value["$id"]] = (path, value)
    direct, transformed = set(), {}
    for identifier, (path, original) in schemas.items():
        if path.parent != CONTRACTS / "anniversary":
            continue
        value = copy.deepcopy(original)
        changed = False
        for node in walk(value):
            for field in ("category_id", "category_ids"):
                field_schema = node.get("properties", {}).get(field)
                if not field_schema:
                    continue
                target = field_schema.get("items", field_schema)
                if target.get("format") == "uuid":
                    del target["format"]
                    target["description"] = "Opaque weak Category reference; preserve exact Unicode, including historical non-UUID values. Null remains distinct from a string."
                    changed = True
        if changed:
            direct.add(identifier); transformed[identifier] = value
    affected = set(direct)
    while True:
        parents = {identifier for identifier, (_, value) in schemas.items()
                   if any(urldefrag(urljoin(identifier, n["$ref"]))[0] in affected for n in walk(value) if "$ref" in n)}
        if parents <= affected:
            break
        affected |= parents
    outputs, rows = {}, []
    for identifier in sorted(affected):
        path, original = schemas[identifier]
        relative = path.relative_to(CONTRACTS).as_posix()
        value = copy.deepcopy(transformed.get(identifier, original))
        value["$id"] = PREFIX + "native_v3/" + relative
        value["x-contract-version"] = 3
        value["x-implementation-status"] = "planned"
        value["x-release-status"] = "planned"
        value["x-native-compatibility-revision"] = "anniversary_opaque_category_v1"
        for node in walk(value):
            if "$ref" not in node:
                continue
            target, fragment = urldefrag(urljoin(identifier, node["$ref"]))
            node["$ref"] = (PREFIX + "native_v3/" + target[len(PREFIX):] if target in affected else target) + ("#" + fragment if fragment else "")
        outputs[CONTRACTS / "native_v3" / relative] = value
        rows.append({"source": relative, "source_semantic_sha256": digest(original),
                     "target": "native_v3/" + relative, "change": "opaque_reference" if identifier in direct else "transitive_ref_only"})
    ledger = {"revision": "anniversary_opaque_category_v1", "native_version": 3,
              "release_status": "planned", "implementation_status": "planned",
              "rule_anchor": "ADR-Sync-05/Accepted Compatibility Direction", "schemas": rows,
              "dispatch": {"v2_channel": "excellent_calendar/native", "v3_channel": "excellent_calendar/native_v3",
                           "automatic_fallback": False, "v2_schema_changes": False,
                           "v6_workspace_v2_access": "reject_with_CONTRACT_VERSION_UNSUPPORTED_before_business_read_or_write",
                           "same_apk_required": ["Dart", "Kotlin", "JNI", "C++"]},
              "cache_policy": {"identity": ["workspace_id", "active_route_revision", "native_contract_version", "cache_schema_version"],
                               "legacy_payload_to_v3_reader": "invalidate_and_reread_after_verified_workspace_open",
                               "v3_payload_to_v2_reader": "forbidden", "cross_account_reuse": "forbidden"},
              "storage": {"v5_checker": "unchanged_and_mandatory_before_migration",
                          "v5_invalid_opaque_anniversary_input": "reject_migration_without_repair_or_deletion",
                          "v6_domain_and_codec": "opaque_reference_required_in_downstream_03",
                          "missing_or_deleted_category": "preserve_reference_return_null_category_projection"}}
    outputs[CONTRACTS / "native_v3/anniversary_compatibility.json"] = ledger
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = derive()
    for path, value in outputs.items():
        if args.check:
            if not path.is_file() or json.loads(path.read_text(encoding="utf-8")) != value:
                raise ValueError("Native v3 compatibility drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"compatibility_schemas": len(outputs) - 1, "v2_changed": False, "mode": "check" if args.check else "write"}))


if __name__ == "__main__":
    main()
