#!/usr/bin/env python3
"""CT0 compatibility/audit checks. Full Sync V1 freeze validation is not delivered.

Default invocation fails closed: passing --stage ct0 explicitly requests only
the evidence available before ADR acceptance. Never treat that as CONTRACT FROZEN.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import unittest
from pathlib import Path
from urllib.parse import unquote, urldefrag, urljoin

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

CONTRACTS = Path(__file__).resolve().parent
ROOT = CONTRACTS.parent
sys.path.insert(0, str(CONTRACTS / "spikes/sync_v1"))
from audit_backend import collect as collect_backend_audit

FROZEN_STORAGE_HASHES = {
    "calendar_core_v4": "b6093231573d6b31eb245e227ff42ac92b34f7dc100903223968c1e8f2539837",
    "calendar_core_v5": "dcd92464591cae3f74b2454d4b80021298acab1874ac6f946b45c89d8fe5db79",
}
AMENDMENTS = {
    "contracts/method_channels.yaml", "contracts/runtime/initialize_runtime_response.schema.json",
    "contracts/sync/sync_operation.schema.json", "contracts/sync/sync_result.schema.json",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def unique_object(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate object key: {key}")
        result[key] = value
    return result


def invalid_constant(value: str) -> None:
    raise AssertionError(f"Non-JSON constant: {value}")


def read_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)


class UniqueYamlLoader(yaml.SafeLoader):
    pass


def yaml_mapping(loader: UniqueYamlLoader, node: yaml.MappingNode) -> dict:
    loader.flatten_mapping(node)
    return unique_object([(loader.construct_object(k), loader.construct_object(v)) for k, v in node.value])


UniqueYamlLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, yaml_mapping)


def read_yaml(path: Path) -> dict:
    return yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueYamlLoader)


def digest(value: object) -> str:
    # This is the pre-existing storage audit representation, deliberately not JCS.
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def read_data(path: Path) -> object:
    return read_json(path) if path.suffix == ".json" else read_yaml(path)


def validate_baseline(baseline: dict, root: Path = ROOT) -> int:
    require(baseline["hash_algorithm"] == "sha256_sorted_compact_utf8_json_not_jcs", "Baseline hash domain changed")
    require(set(baseline["approved_amendments"]) == AMENDMENTS, "Unreviewed CT0 baseline amendment")
    require(baseline["frozen_storage_nodes"] == FROZEN_STORAGE_HASHES, "Frozen storage digest baseline changed")
    for relative, old_hash in baseline["files"].items():
        path = (root / relative).resolve()
        require(path.is_relative_to((root / "contracts").resolve()), "Baseline path escapes contracts")
        require(path.is_file(), f"Protected Contract removed: {relative}")
        current_hash = digest(read_data(path))
        amendment = baseline["approved_amendments"].get(relative)
        expected = amendment["current_sha256"] if amendment else old_hash
        require(current_hash == expected, f"Protected Contract drift: {relative}; add a reviewed compatibility revision, not a regenerated baseline")
    return len(baseline["files"])


def validate_storage(storage: dict, response: dict) -> None:
    for node, expected in FROZEN_STORAGE_HASHES.items():
        require(digest(storage[node]) == expected, f"Frozen {node} changed")
    require(storage["active_format_contract"] == "calendar_core_v5", "CT0 must not activate v6")
    require(storage["storage_format_version"] == 5, "Storage v5 baseline drift")
    require(response["properties"]["storage_format_version"].get("const") == 5, "Runtime Schema is not calibrated to v5")
    require(response["x-contract-version"] == 2, "Native version domain changed")


def walk(value: object):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def validate_refs(schemas: dict[str, dict]) -> None:
    for schema_id, schema in schemas.items():
        for node in walk(schema):
            if "$ref" not in node:
                continue
            target, fragment = urldefrag(urljoin(schema_id, node["$ref"]))
            require(target in schemas, f"Unclosed $ref: {node['$ref']} in {schema_id}")
            value = schemas[target]
            fragment = unquote(fragment)
            if fragment and not fragment.startswith("/"):
                require(any(n.get("$anchor") == fragment for n in walk(value)), f"Missing $anchor: {fragment}")
            elif fragment:
                for part in fragment[1:].split("/"):
                    part = part.replace("~1", "/").replace("~0", "~")
                    try:
                        value = value[int(part)] if isinstance(value, list) else value[part]
                    except (KeyError, IndexError, ValueError, TypeError) as error:
                        raise AssertionError(f"Unclosed JSON pointer: {node['$ref']}") from error


def validate_schemas() -> tuple[dict, Registry]:
    schemas = {}
    for path in sorted(CONTRACTS.rglob("*.schema.json")):
        schema = read_json(path)
        require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"Unexpected dialect: {path.name}")
        schema_id = schema.get("$id")
        require(isinstance(schema_id, str) and schema_id not in schemas, f"Missing/duplicate schema ID: {path.name}")
        Draft202012Validator.check_schema(schema)
        schemas[schema_id] = schema
    validate_refs(schemas)
    registry = Registry().with_resources((key, Resource.from_contents(value)) for key, value in schemas.items())
    return schemas, registry


def validate_runtime_fixtures(registry: Registry) -> int:
    parent = CONTRACTS / "fixtures/runtime"
    cases = read_json(parent / "manifest.json")["cases"]
    for case in cases:
        schema = read_json((parent / case["schema"]).resolve())
        instance = read_json(parent / case["instance"])
        validator = Draft202012Validator(schema, registry=registry, format_checker=FormatChecker())
        require(validator.is_valid(instance) == case["expected_valid"], f"Runtime fixture failed: {case['name']}")
    return len(cases)


def validate_legacy_tombstone(methods: dict, native: dict) -> None:
    require(methods["version"] == native["version"] == 2, "Native v2 must remain unchanged")
    method = methods["methods"]["sync.apply"]
    require(method["implementation_status"] == "deprecated" and method["release_status"] == "blocked", "Legacy sync.apply must remain blocked")
    require(method["implementation"] == "not_implemented", "Legacy sync.apply cannot gain a runtime implementation")
    require("sync.apply" not in native["calls"], "Legacy sync.apply must not gain JNI")
    for name in ("sync_operation", "sync_result"):
        schema = read_json(CONTRACTS / "sync" / (name + ".schema.json"))
        require(schema.get("deprecated") is True and schema.get("x-release-status") == "blocked", "Legacy Sync Schema cannot advertise production")


def validate_vectors(vectors: dict) -> int:
    ids = set()
    for case in vectors["cases"]:
        require(case["id"] not in ids, "Duplicate canonical vector ID")
        ids.add(case["id"])
        require(case["rule_anchor"] == "cloud-sync-02/4.2", "Canonical vector anchor drift")
        require(isinstance(case["input_json"], str), "Canonical vector needs raw input JSON")
        if case["expected_error"]:
            require("canonical_utf8_hex" not in case and "sha256" not in case, "Rejected input must not have a fabricated canonical hash")
        else:
            raw = bytes.fromhex(case["canonical_utf8_hex"])
            raw.decode("utf-8", errors="strict")
            require(hashlib.sha256(raw).hexdigest() == case["sha256"], "Canonical vector byte/hash drift")
    return len(ids)


def validate_gate_record(gates: dict) -> None:
    require(gates["contract_status"] == "DECISION REQUIRED", "CT0 audit cannot mark the Contract frozen")
    require(gates["implementation_allowed"] is False, "CT0 cannot authorize downstream implementation")
    require(len(gates["adrs"]) == 7, "Seven CT0 decisions must be represented")
    for entry in gates["adrs"]:
        path = ROOT / entry["path"]
        require(path.is_file() and "Status: Proposed" in path.read_text(encoding="utf-8"), "ADR state differs from unsigned CT0 audit")
    require(all(gates["stages"][stage] == "not_started" for stage in ("CT1", "CT2", "CT3", "CT4")), "CT1-CT4 require their own evidence and validator")


def validate_fixture_manifest(manifest: dict, vectors: dict) -> None:
    require(manifest["contract_status"] == "DECISION REQUIRED", "Fixture manifest cannot imply freeze")
    families = {f["id"]: f for f in manifest["families"]}
    require(len(families) == len(manifest["families"]) == 20, "Fixture family inventory incomplete or duplicated")
    expected_families = {"FX-TARGET", "FX-MERGE", "FX-CONFLICT", "FX-SEQUENCE", "FX-CANONICAL", "FX-COUNTER",
                         "FX-RUN", "FX-FAILED-LOCAL", "FX-CURSOR", "FX-BOOTSTRAP", "FX-WORKSPACE",
                         "FX-IMPORT-STAGE", "FX-IMPORT-PUBLISH", "FX-IMPORT-RANGE", "FX-IMPORT-CLEANUP",
                         "FX-PREFERENCE", "FX-SESSION-DEVICE", "FX-RETENTION-NOTIFY", "FX-MAINTENANCE", "FX-CROSS-LAYER"}
    require(set(families) == expected_families, "Fixture family identity drift")
    for family in families.values():
        expected = "partial_ct0_probe_only" if family["id"] == "FX-CANONICAL" else "not_delivered"
        require(family["coverage_status"] == expected, "CT0 does not deliver full fixture families")
    require(len(manifest["cases"]) == len(vectors["cases"]), "Manifest/vector coverage differs")
    for index, (case, vector) in enumerate(zip(manifest["cases"], vectors["cases"])):
        require(case["id"] == vector["id"] and case["rule_anchor"] == vector["rule_anchor"], "Manifest case identity drift")
        require(case["input_file"] == "canonical_vectors.json" and case["case_pointer"] == f"/cases/{index}", "Manifest vector pointer drift")


def validate_spike_sources(report: dict, root: Path = ROOT) -> None:
    require(bool(report["source_sha256"]), "Spike must identify the exact audited sources")
    for relative, expected in report["source_sha256"].items():
        path = (root / relative).resolve()
        require(path.is_relative_to(root.resolve()), "Spike source path escapes repository")
        actual = hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest()
        require(actual == expected, f"Spike result stale: {relative}")


def validate_audit() -> dict:
    baseline = read_json(CONTRACTS / "sync/sync_v1_baseline.json")
    count = validate_baseline(baseline)
    schemas, registry = validate_schemas()
    validate_storage(read_yaml(CONTRACTS / "storage/calendar_core_storage.yaml"), read_json(CONTRACTS / "runtime/initialize_runtime_response.schema.json"))
    validate_legacy_tombstone(read_yaml(CONTRACTS / "method_channels.yaml"), read_yaml(CONTRACTS / "native_calls.yaml"))
    fixtures = validate_runtime_fixtures(registry)
    recorded = read_json(CONTRACTS / "sync/backend_calibration_audit.json")
    actual = collect_backend_audit(read_yaml(CONTRACTS / "backend_api.yaml"), ROOT)
    require(recorded == actual, "Backend audit stale; review actual Controller/DTO/error changes")
    require(len(actual["endpoints"]) == 17, "CT0 endpoint inventory is incomplete")
    require(sum(row["source_status"] == "controller_present" for row in actual["endpoints"]) == 16, "CT0 Controller inventory drift")
    vectors = read_json(CONTRACTS / "fixtures/sync/v1/canonical_vectors.json")
    vector_count = validate_vectors(vectors)
    validate_fixture_manifest(read_json(CONTRACTS / "fixtures/sync/v1/manifest.json"), vectors)
    serializer = read_json(CONTRACTS / "spikes/sync_v1/serializer_audit_result.json")
    validate_spike_sources(serializer)
    vector_bytes = (CONTRACTS / "fixtures/sync/v1/canonical_vectors.json").read_text(encoding="utf-8").encode()
    require(serializer["fixture_sha256"] == hashlib.sha256(vector_bytes).hexdigest(), "Serializer result uses a different vector revision")
    require(serializer["jcs_spike_passed"] is False, "Encoder reuse audit must not certify a JCS implementation")
    for consumer in serializer["consumers"].values():
        require([case["id"] for case in consumer["cases"]] == [v["id"] for v in vectors["cases"]], "Serializer result omits vectors")
        for actual_case, vector in zip(consumer["cases"], vectors["cases"]):
            expected = "ERROR" if vector["expected_error"] else "OK\t" + vector["canonical_utf8_hex"]
            require(actual_case["matches_jcs"] == (actual_case["actual"] == expected), "Serializer evidence classification differs from bytes")
    encryption = read_json(CONTRACTS / "spikes/sync_v1/encryption_package_audit.json")
    validate_spike_sources(encryption)
    require(encryption["encryption_spike_passed"] is False and encryption["source_build_verified"] is False,
            "AAR symbol/link audit is not an encryption feasibility pass")
    gate_record = read_json(CONTRACTS / "sync/ct0_gate_status.json")
    validate_gate_record(gate_record)
    return dict(status="CT0_AUDIT_ONLY_NOT_FROZEN", protected_contracts=count, schemas=len(schemas),
                runtime_fixtures=fixtures, backend_endpoints=17, backend_controllers=16, canonical_vector_integrity=vector_count)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("ct0", "frozen"), default="frozen")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    print(json.dumps(validate_audit()))
    if args.self_test:
        suite = unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern="test_sync_ct0_validation.py")
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        if not result.wasSuccessful():
            return 1
    if args.stage == "frozen":
        print("DECISION REQUIRED: seven proposed ADRs; encryption/JCS/counter/identity gates open. CT1-CT4 and full Sync V1 validator are not delivered. No downstream implementation or activation is authorized.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ValueError, KeyError, OSError, yaml.YAMLError) as error:
        print(f"Sync CT0 validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
