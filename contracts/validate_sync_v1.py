#!/usr/bin/env python3
"""CT0 compatibility/audit checks. Full Sync V1 freeze validation is not delivered.

Default invocation fails closed: passing --stage ct0 explicitly requests only
the evidence available before ADR acceptance. Never treat that as CONTRACT FROZEN.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
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
from build_anniversary_v3_revision import derive as derive_anniversary_v3

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
        data = read_data(path)
        from build_sync_registry_revisions import REVISION_PATHS, extension
        registry_name = relative.removeprefix("contracts/")
        if registry_name in REVISION_PATHS and "planned_revisions" in data:
            require(data["planned_revisions"] == extension(registry_name), "Unreviewed planned registry link")
            data = dict(data)
            data.pop("planned_revisions")
        # cloud-sync-02/9.3 explicitly authorizes an additive planned v6 node.
        # Compare the complete historical projection against the original hash;
        # never replace the protected baseline with a newly generated digest.
        if relative == "contracts/storage/calendar_core_storage.yaml" and "calendar_core_v6" in data:
            from build_sync_storage_contract import derive
            require(data["calendar_core_v6"] == derive(), "Unreviewed v6 storage definition")
            require(data["latest_declared_format_version"] == 6 and data["planned_format_contract"] == "calendar_core_v6", "Planned v6 declaration differs")
            data = dict(data)
            data.pop("calendar_core_v6")
            data.pop("planned_format_contract")
            data["latest_declared_format_version"] = 5
        current_hash = digest(data)
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
    frozen = gates["contract_status"] == "CONTRACT FROZEN"
    require(frozen or gates["contract_status"] == "DECISION REQUIRED", "Unknown Contract gate state")
    if frozen:
        require(gates.get("revision_lock") == "contracts/sync/sync_v1_revision_lock.json", "Cannot mark Contract frozen without a revision lock")
        require(gates["implementation_allowed"] is True and not gates["open_gates"], "Frozen design still has unresolved gates")
        require(gates["stages"] == {"CT" + str(n): "passed" for n in range(5)}, "All Contract stages must pass before freeze")
        from freeze_contract_revision import validate_lock
        validate_lock(read_json(ROOT / gates["revision_lock"]))
    else:
        require(gates["implementation_allowed"] is False, "Unfrozen Contract cannot authorize downstream implementation")
    require(len(gates["adrs"]) == 7, "Seven CT0 decisions must be represented")
    for entry in gates["adrs"]:
        path = ROOT / entry["path"]
        expected = "Status: Accepted" if entry["status"] == "accepted_direction" else "Status: Proposed"
        require(path.is_file() and expected in path.read_text(encoding="utf-8"), "ADR state differs from recorded decision")
        if entry["status"] == "accepted_direction":
            require(bool(entry.get("acceptance")), "Accepted direction needs an authorization record")
    require(frozen or gates["stages"]["CT1"] == "typed_fact_registry_and_identity_partial" and gates["stages"]["CT4"] == "reference_golden_partial",
            "Full mutation/lifecycle and four-language freeze evidence is not delivered")
    require(frozen or gates["stages"]["CT2"] == "versioned_capability_graph_and_http_revision_partial" and gates["stages"]["CT3"] == "typed_protocol_errors_and_storage_partial",
            "Planned protocol/storage evidence cannot imply full capability/consumer delivery")
    for relative, expected in gates["evidence"].items():
        path = (ROOT / relative).resolve()
        require(path.is_relative_to(CONTRACTS.resolve()), "Gate evidence path escapes contracts")
        require(hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest() == expected, "Gate result digest stale: " + relative)


def validate_fixture_manifest(manifest: dict, vectors: dict) -> None:
    from build_fixture_manifest import derive
    require(manifest["contract_status_ref"] == "contracts/sync/ct0_gate_status.json" and "contract_status" not in manifest,
        "Fixture manifest must reference the single freeze authority")
    families = {f["id"]: f for f in manifest["families"]}
    require(len(families) == len(manifest["families"]) == 20, "Fixture family inventory incomplete or duplicated")
    expected_families = {"FX-TARGET", "FX-MERGE", "FX-CONFLICT", "FX-SEQUENCE", "FX-CANONICAL", "FX-COUNTER",
                         "FX-RUN", "FX-FAILED-LOCAL", "FX-CURSOR", "FX-BOOTSTRAP", "FX-WORKSPACE",
                         "FX-IMPORT-STAGE", "FX-IMPORT-PUBLISH", "FX-IMPORT-RANGE", "FX-IMPORT-CLEANUP",
                         "FX-PREFERENCE", "FX-SESSION-DEVICE", "FX-RETENTION-NOTIFY", "FX-MAINTENANCE", "FX-CROSS-LAYER"}
    require(set(families) == expected_families, "Fixture family identity drift")
    require(all(family["coverage_status"] == "contract_reference_delivered" for family in families.values()), "Fixture family has no delivered Contract evidence")
    require(manifest == derive(), "Manifest/vector coverage or identity differs")
    canonical = read_json(CONTRACTS / "fixtures/sync/v1/jcs_boundary_vectors.json")
    require(canonical["cases"][:len(vectors["cases"])] == vectors["cases"], "Expanded JCS vectors drift from the original cases")


def validate_spike_sources(report: dict, root: Path = ROOT) -> None:
    require(bool(report["source_sha256"]), "Spike must identify the exact audited sources")
    for relative, expected in report["source_sha256"].items():
        path = (root / relative).resolve()
        require(path.is_relative_to(root.resolve()), "Spike source path escapes repository")
        actual = hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest()
        require(actual == expected, f"Spike result stale: {relative}")


def validate_jcs_spike(report: dict, fixtures: dict) -> None:
    validate_spike_sources(report)
    require(report["jcs_spike_passed"] is True, "JCS implementation has not passed the recorded matrix")
    require(not report["errors"] and not report["cleanup_pending"], "JCS execution or cleanup failed")
    require(report["product_dependency_changed"] is False, "JCS spike cannot introduce a production dependency")
    expected_consumers = {"windows_cpp", "java", "ndk_bionic_arm64-v8a", "ndk_bionic_armeabi-v7a", "ndk_bionic_x86_64"}
    require(expected_consumers <= set(report["consumers"]), "JCS evidence omits a required compiler/ABI consumer")
    require(any(key.startswith("android_device_") for key in report["consumers"]), "JCS evidence needs actual Android device execution too")
    require(report["android_three_os_device_matrix_verified"] is False, "QEMU-user portability must not be relabeled as three Android OS devices")
    require(report["extracted_sha256_kat"]["passed"] is True, "Independent extracted SHA-256 KAT missing")
    require(report["extracted_sha256_kat"]["counter_width"] == 64, "SHA byte count can wrap on a 32-bit ABI")
    raw = (CONTRACTS / "fixtures/sync/v1/jcs_boundary_vectors.json").read_text(encoding="utf-8").encode()
    require(hashlib.sha256(raw).hexdigest() == report["fixture_sha256"], "JCS result uses stale fixtures")
    validate_vectors(fixtures)
    for key, consumer in report["consumers"].items():
        require(consumer["passed"] and not consumer["mismatches"], f"JCS consumer failed: {key}")
        require(consumer["boundary_cases"] == len(fixtures["cases"]), f"JCS boundary coverage missing: {key}")
        require(consumer["numeric_cases"] == 20000 and consumer["malformed_utf8_cases"] == 6, f"JCS numeric/UTF-8 coverage missing: {key}")
        require(consumer["systematic_numeric_cases"] == fixtures["systematic_numeric_oracle"]["case_count"] == 31487,
                f"JCS exponent/midpoint coverage missing: {key}")
        require(consumer["actual_output_sha256"] == report["expected_output_sha256"], f"JCS bytes/hash differ: {key}")
        if key.startswith(("ndk_bionic_", "android_device_")):
            require(consumer["sha256_kat_passed"], f"JCS ABI KAT missing: {key}")


def validate_cipher_step(step: dict) -> dict | None:
    require(hashlib.sha256(step["stdout"].encode()).hexdigest() == step["stdout_sha256"], "Cipher stdout hash differs")
    require(hashlib.sha256(step["stderr"].encode()).hexdigest() == step["stderr_sha256"], "Cipher stderr hash differs")
    if "KILL_POINT_REACHED" in step["stdout"]:
        require(step["exit_code"] in (86, -9, 9, 137), "Probe kill lacks a child failure status")
        return None
    require(step["exit_code"] == 0, "Cipher probe command failed")
    return json.loads(step["stdout"])


def validate_cipher_source_spike(report: dict, audit: dict) -> None:
    base = CONTRACTS / "spikes/sync_v1"
    require(report["passed"] is True and not report["errors"] and not report["cleanup_errors"], "Native cipher source/recovery evidence failed")
    require(report["product_dependency_changed"] is False, "Cipher spike cannot change the product provider")
    require(report["android_three_os_device_matrix_verified"] is False, "QEMU ABI execution is not three Android OS devices")
    for item in (report, audit):
        for name, expected in item["source_hashes"].items():
            path = (base / name).resolve()
            require(path.is_relative_to(base.resolve()), "Cipher source path escapes spike")
            require(hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest() == expected, f"Cipher source evidence stale: {name}")
    required = {"windows", "arm64-v8a", "armeabi-v7a", "x86_64", "android_device_arm64"}
    if "armeabi-v7a" in report.get("device", {}).get("abi", "").split(","):
        required.add("android_device_arm32")
    require(set(report["consumers"]) == required, "Cipher runtime evidence omits a required environment")
    for env, row in report["consumers"].items():
        require(row["passed"] is True and len(row["steps"]) == 24, "Cipher recovery matrix incomplete: " + env)
        expected_execution = "windows_native" if env == "windows" else "android_os_device_bionic_static" if env.startswith("android_device_") else "bionic_static_qemu_user"
        require(row["execution"] == expected_execution, "Cipher execution kind mislabeled: " + env)
        modes = []
        killed = 0
        for step in row["steps"]:
            value = validate_cipher_step(step)
            if value is None:
                killed += 1
            else:
                if "mode" in value:
                    require(value["passed"] is True, "Cipher recovery mode failed")
                    modes.append(value["mode"])
                elif "os_rng_failure_returns_zero" in value:
                    require(value == {"os_rng_failure_returns_zero": True, "clock_rng_fallback": False}, "Entropy fallback is not fail closed")
                else:
                    require(value["rows"] == 20000 and value["sqlite"] == "3.53.4" and value["cipher"] == "4.18.0", "Cipher baseline/capacity differs")
                    require(all(value[key] is True for key in ("wal", "full", "defensive", "wrong_key_rejected", "db_and_wal_sentinel_absent")), "Cipher policy failed")
        require(killed == 4 and modes.count("init") == modes.count("verify") == 7, "Cipher crash/reopen coverage missing")
        require(all(modes.count(mode) == 1 for mode in ("keys", "full", "temp", "binary-key")), "Cipher binary-key/binding/full/temp coverage missing")
        require(set(row["binary_sha256"]) == {"cipher_probe", "cipher_recovery_probe", "rng_failure_probe"}, "Cipher executable hashes missing")
    require(report["consumers"]["android_device_arm64"]["binary_sha256"] == report["consumers"]["arm64-v8a"]["binary_sha256"],
            "Android device did not run the audited arm64 source binaries")
    if "android_device_arm32" in required:
        require(report["consumers"]["android_device_arm32"]["binary_sha256"] == report["consumers"]["armeabi-v7a"]["binary_sha256"],
                "Android device did not run the audited arm32 source binaries")
    require(audit["runtime_source_license_inventory_complete"] is True and audit["reviewed_file_count"] == 427, "Cipher runtime source license inventory incomplete")
    for name, notice in audit["notices"].items():
        require(hashlib.sha256((base / "licenses" / name).read_bytes()).hexdigest() == notice["sha256"], "Preserved cipher notice differs")
    for name, expected in report["amalgamation_hashes"].items():
        require(audit["files"]["sqlcipher/" + name]["sha256"] == expected, "License inventory and executed source differ")


def validate_backend_http_audit(report: dict, registry: Registry) -> None:
    validate_spike_sources(report)
    validate_spike_sources({"source_sha256": report["contract_schema_sha256"]})
    require(report["passed"] is True and not report["errors"], "Backend HTTP calibration failed")
    require(report["product_sync_implementation"] is False, "HTTP calibration cannot implement Sync")
    for name in ("unit", "integration"):
        result = report[name]
        require(result["tests"] > 0 and all(result[key] == 0 for key in ("failures", "errors", "skipped")),
                "Backend test suite skipped or failed: " + name)
    contract = read_yaml(CONTRACTS / "backend_api.yaml")
    cases = report["http"]["cases"]
    require(set(report["observed_operations"]) == set(contract["endpoints"]), "Backend operation coverage incomplete")
    require(len({case["id"] for case in cases}) == len(cases) == 39, "Backend HTTP case coverage differs")
    success = {case["operation"] for case in cases if case["response"]["ok"]}
    require(success == set(contract["endpoints"]) - {"auth.registration.email.update"}, "Implemented HTTP success responses not covered")
    for case in cases:
        require(not case["current_schema_errors"], "Backend current response differs from Schema")
        envelope = Draft202012Validator(read_json(CONTRACTS / "common/api_result.schema.json"), registry=registry, format_checker=FormatChecker())
        require(envelope.is_valid(case["response"]), "Recorded Backend envelope invalid")
        if case["response"]["ok"]:
            path = contract["endpoints"][case["operation"]]["result"]["data"]
            require(Draft202012Validator(read_json(CONTRACTS / path), registry=registry, format_checker=FormatChecker()).is_valid(case["response"]["data"]),
                    "Recorded Backend nested response invalid")
        hint = case["retry_after_header"]
        if hint is not None:
            require(str(case["response"]["error"]["retry_after_seconds"]) == hint, "Backend retry hint/header differ")


def validate_backend_shape_audit(report: dict) -> None:
    from urllib.parse import urljoin, urldefrag
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["production_corrections_implemented"] is False and
            report["all_business_error_paths_executed"] is False, "Backend nested shape audit failed or overclaims runtime paths")
    inventory = read_json(CONTRACTS / "sync/backend_calibration_audit.json")
    target = read_yaml(CONTRACTS / "backend_sync_v1/backend_api.yaml")
    require([row["operation"] for row in report["endpoints"]] == [row["operation"] for row in inventory["endpoints"]],
            "Backend nested shape endpoint coverage incomplete")
    observed = report["compiled_dtos"]
    require(len(observed["records"]) == 24 and set(report["compiled_dto_sha256"]) == set(observed["records"]) and
            not observed["request_instances_created"] and not observed["application_context_started"], "Compiled DTO metadata coverage differs")
    roots = set()
    for row, source in zip(report["endpoints"], inventory["endpoints"]):
        require(row["current_controller_present"] == (source["source_status"] == "controller_present") and
                row["current_declared_error_http_status"] == source["error_statuses_from_backend_enum"] and
                row["declaration_only_errors_requiring_04_enum_producer"] == source["declared_errors_missing_backend_enum"] and
                row["observed_http_case_ids"] and row["target_implementation_status"] == "planned", "Backend disposition/error mapping differs")
        for direction in ("request", "response"):
            entry = row[direction]
            require(entry["current_schema"] == source[direction + "_schema"], "Backend current schema binding differs")
            expected_target = target["endpoints"][row["operation"]]["request"] if direction == "request" else target["endpoints"][row["operation"]]["result"]["data"]
            require(entry["target_schema"] == expected_target and bool(entry["schema_closure"]), "Backend target/closure incomplete")
            prefix = "https://excellent-calendar.local/contracts/"
            pending, closure = [prefix + entry["current_schema"]], {}
            while pending:
                uri = pending.pop()
                require(uri.startswith(prefix), "Backend schema reference leaves repository")
                relative = uri.removeprefix(prefix)
                if relative in closure:
                    continue
                path = CONTRACTS / relative
                closure[relative] = hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest()
                for node in walk(read_json(path)):
                    if "$ref" in node:
                        pending.append(urldefrag(urljoin(uri, node["$ref"]))[0])
            require(entry["schema_closure"] == closure, "Backend nested schema closure differs")
            if entry["current_jvm_dto"]:
                roots.add(entry["current_jvm_dto"])
                require(sorted(observed["records"][entry["current_jvm_dto"]]["fields"]) == source[direction + "_schema_fields"] and
                        entry["top_level_field_match"], "Backend reflected field coverage differs")
    require(roots == set(observed["roots"]), "Backend reflected roots incomplete")
    require(set(report["dispositions"]) == {"java_string_size", "nullable_and_union", "idempotency", "unknown_and_coercion", "profile_preferences", "http_errors"},
            "Backend calibration disposition missing")


def validate_domain_drafts(report: dict) -> None:
    from build_sync_domain_contracts import derive
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 22, "Typed domain/identity checks failed")
    require(report["targets"] == 12 and report["field_entries"] == 125 and report["golden_cases"] == 61, "Typed domain coverage incomplete")
    require(not report["product_owners_implemented"] and not report["four_language_consumers_verified"], "Draft oracle cannot certify product consumers")
    for path, expected in derive().items():
        require(read_data(path) == expected, "Typed domain registry/schema drift: " + str(path))


def validate_protocol_drafts(report: dict) -> None:
    from build_sync_protocol_contracts import derive as protocol
    from build_sync_import_contracts import derive as imports
    from build_sync_lifecycle_contracts import derive as lifecycle
    from build_sync_error_contracts import derive as errors
    from build_sync_conflict_contracts import derive as conflicts
    from build_backend_sync_revision import derive as backend
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 53,
            "Protocol/lifecycle reference tests failed")
    require(report["generated_schemas"] == 216 and report["fixed_cases"] == 96, "Protocol draft coverage differs")
    for field in ("full_owned_graph_import_bootstrap_engine_verified", "android_keystore_verified",
                  "four_language_consumers_verified", "product_owners_implemented"):
        require(report[field] is False, "Limited reference evidence cannot certify " + field)
    for path, expected in {**protocol(), **imports(), **lifecycle(), **errors(), **conflicts(), **backend()}.items():
        require(read_data(path) == expected, "Protocol/lifecycle/error definition drift: " + str(path))


def validate_storage_drafts(report: dict) -> None:
    from build_sync_storage_contract import derive as sqlite
    from build_sync_postgres_contract import derive as postgres
    from build_storage_fixtures import derive as fixtures
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"], "SQLite/PostgreSQL logical model experiment failed")
    require(report["sqlite"]["tests_run"] == 11 and report["sqlite"]["transaction_rollback_boundaries"] == 134,
            "Frozen checker/migration boundary evidence incomplete")
    require(report["postgres"]["passed"] and report["postgres"]["new_tables"] == 40 and report["postgres"]["mapped_fields_checked"] == 125,
            "PostgreSQL live typed field mapping incomplete")
    require(len(report["postgres"]["cases"]) == 70 and all(row["passed"] for row in report["postgres"]["cases"]), "PostgreSQL constraints failed")
    require(report["postgres"]["concurrent_last_allocation_winners"] == 1, "PostgreSQL concurrent safe-integer allocation failed")
    require(read_yaml(CONTRACTS / "storage/calendar_core_storage.yaml")["calendar_core_v6"] == sqlite(), "Planned v6 differs")
    require(read_yaml(CONTRACTS / "storage/cloud_sync_postgresql_v1.yaml") == postgres(), "PostgreSQL model differs")
    require(read_json(CONTRACTS / "fixtures/sync/v1/postgres_vectors.json") == fixtures(), "PostgreSQL fixtures differ")
    for field in ("production_migration_activated", "account_encrypted_full_graph_verified", "android_migration_verified"):
        require(report[field] is False, "Logical DDL evidence cannot certify " + field)


def validate_capability_drafts(report: dict) -> None:
    from build_native_v3_business_contracts import derive as business
    from build_sync_native_contracts import derive as native
    from build_sync_capability_graph import derive as graph
    from build_sync_registry_revisions import derive as registries, REVISION_PATHS, extension
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 22 and report["fixed_cases"] == 62,
            "Capability boundary regression evidence incomplete")
    require(report["generated_schemas"] == 487 and report["public_methods"] == 107 and report["native_calls"] == 90,
            "Capability graph coverage differs")
    for path, expected in {**business(), **native(), **graph(), **registries()}.items():
        require(read_data(path) == expected, "Capability/compatibility definition differs: " + str(path))
    for path in REVISION_PATHS:
        require(read_yaml(CONTRACTS / path)["planned_revisions"] == extension(path), "Planned registry link missing: " + path)
    for field in ("production_handlers_verified", "four_language_consumers_verified", "signature_authentication_verified", "cipher_open_authorized_by_shape_checks"):
        require(report[field] is False, "Schema checks cannot certify " + field)


def validate_proof_evidence(primitive: dict, capsule: dict) -> None:
    from build_sync_proof_contracts import derive as proofs
    from build_proof_capsule_fixtures import derive as fixtures
    for report in (primitive, capsule):
        validate_spike_sources(report)
        require(report["passed"] and not report["errors"] and not report["cleanup_errors"], "Proof experiment or cleanup failed")
        require(not report["android_x86_os_executed"], "Compiled x86 library cannot certify an Android OS execution")
        require({"windows_cng_cpp", "arm64-v8a", "armeabi-v7a", "x86_64"} <= set(report["builds"]), "Proof build matrix incomplete")
    signature_fixture = read_json(CONTRACTS / "fixtures/sync/v1/proof_signature_vectors.json")
    signature_output = "\n".join([case["id"] + "\tPASS" for case in signature_fixture["cases"]] + ["PASS\t14"])
    expected_primitive = {"java21", "windows_cng_cpp", "android_jca_arm64-v8a", "android_jni_arm64-v8a"}
    if "armeabi-v7a" in primitive["device"]["abi"].split(","):
        expected_primitive |= {"android_jca_armeabi-v7a", "android_jni_armeabi-v7a"}
    require(set(primitive["consumers"]) == expected_primitive, "Proof primitive consumer coverage differs")
    require(not primitive["capsule_claim_authentication_verified"] and not primitive["key_rotation_verified"] and not primitive["product_dependency_changed"],
            "Primitive evidence cannot certify claim binding or product changes")
    for value in primitive["consumers"].values():
        require(value["passed"] and value["cases"] == 14 and value["actual_output_sha256"] == hashlib.sha256(signature_output.encode()).hexdigest(),
                "Proof primitive output bytes/hash differ")
    fixed = fixtures()
    require(read_json(CONTRACTS / "fixtures/sync/v1/proof_capsule_vectors.json") == fixed, "Proof fixture drift")
    expected_capsule = {"java21", "windows_cng_cpp", "android_cpp_jni_arm64-v8a"}
    if "armeabi-v7a" in capsule["device"]["abi"].split(","):
        expected_capsule.add("android_cpp_jni_armeabi-v7a")
    require(set(capsule["consumers"]) == expected_capsule, "Proof capsule consumer coverage differs")
    expected = "\n".join("VALID" if case["expected"]["authenticated"] else "REJECT" for case in fixed["cases"])
    for value in capsule["consumers"].values():
        require(value["passed"] and value["cases"] == len(fixed["cases"]) == 49 and value["actual_output_sha256"] == hashlib.sha256(expected.encode()).hexdigest(),
                "Proof capsule output bytes/hash differ")
    require(capsule["typed_atomic_acceptance"]["passed"] and capsule["typed_atomic_acceptance"]["tests"] == 12,
            "Typed proof binding/atomic receipt evidence incomplete")
    for name in ("production_activated", "all_import_saga_crash_points_verified", "android_persistent_revocation_store_verified", "account_deletion_backend_producer_implemented"):
        require(capsule[name] is False, "Isolated capsule proof cannot certify " + name)
    for path, expected in proofs().items():
        require(read_data(path) == expected, "Proof machine definition drift: " + str(path))


def validate_occurrence_identity_evidence(report: dict) -> None:
    from build_occurrence_identity_fixtures import derive
    validate_spike_sources(report)
    fixed = derive()
    require(read_json(CONTRACTS / "fixtures/sync/v1/occurrence_identity_vectors.json") == fixed, "Original-civil fixture drift")
    require(report["passed"] and not report["errors"] and len(report["cases"]) == len(fixed["cases"]) == 15, "Core original-civil probe incomplete")
    output = []
    for actual, case in zip(report["cases"], fixed["cases"]):
        require(actual["id"] == case["id"] and actual["passed"] and actual["actual"] == case["expected"]["result"], "Core original-civil output differs")
        output.append("REJECT" if actual["actual"] is None else json.dumps(actual["actual"], ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    require(hashlib.sha256(("\n".join(output) + "\n").encode()).hexdigest() == report["actual_output_sha256"], "Core original-civil output bytes/hash differ")
    for name in ("production_v6_writer_implemented", "legacy_v1_conversion_verified", "native_v3_wide_revision_runtime_verified"):
        require(report[name] is False, "Current Core identity lookup cannot certify " + name)


def validate_android_key_evidence(report: dict, build: dict) -> None:
    from build_android_key_contract import derive as definitions
    from build_android_key_fixtures import PHASES, derive as fixtures
    for value in (report, build):
        validate_spike_sources(value)
        require(value["passed"] and not value["errors"] and not value["cleanup_errors"], "Android key evidence failed")
        for field in ("product_package_touched", "production_manifest_activated", "full_v6_account_migration_verified",
                      "actual_cloud_backup_or_restore_executed", "actual_device_to_device_transfer_executed",
                      "api23_os_executed", "api24_os_executed", "android_x86_os_executed"):
            require(value[field] is False, "Isolated APK cannot certify " + field)
        require(value["backup_resource_matrix"] == {"api23_domains": 5, "api24_domains": 9, "api31_cloud_domains": 9, "api31_transfer_domains": 9},
                "Backup exclusion matrix incomplete")
    require(build["build_only"] and not build["consumers"] and not report["build_only"], "Build-only evidence cannot replace device execution")
    require(report["current_build_evidence_sha256"] == hashlib.sha256(
        (CONTRACTS / "spikes/sync_v1/android_key_build_result.json").read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
        "Executed APK evidence refers to a different rebuild")
    require(report["test_package_absent_after_run"], "Isolated package cleanup unverified")
    expected = {"arm64-v8a"} | ({"armeabi-v7a"} if "armeabi-v7a" in report["device"]["abi"].split(",") else set())
    require(set(report["consumers"]) == expected, "Android key consumer coverage differs")
    for abi, consumer in report["consumers"].items():
        require(consumer["binary_wrapper_bytes"] == 136 and consumer["cleanup_confirmed"] and consumer["uninstalled_before_reinstall"], "Key wrapper/cleanup evidence missing")
        initial = consumer["initial"]
        for phase, names in PHASES.items():
            result = consumer.get(phase, {})
            require(result.get("passed") and result.get("cases") == names, "Android key phase coverage differs: " + phase)
            require(result["is_64_bit"] == (abi == "arm64-v8a"), "Android actual process ABI differs")
            if phase in {"process_restart", "apk_upgrade", "crypto_destroy"}:
                require(result["installation_id"] == initial["installation_id"], "Same-install identity changed")
        require(consumer["process_restart"]["process_id"] != initial["process_id"], "Restart did not create a new process")
        require(consumer["reinstall"]["installation_id"] != initial["installation_id"] and
                consumer["restored_ciphertext"]["installation_id"] == consumer["reinstall"]["installation_id"], "Reinstall identity continuity failed")
    for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
        require(report["builds"][abi] == build["builds"][abi], "Rebuilt native APK payload differs from executed binary")
    for abi in ("arm64-v8a", "armeabi-v7a"):
        for version in (1, 2):
            artifact = build["builds"][f"apk_{version}_{abi}"]
            require(artifact["packaged_abis"] == [abi] and artifact["packaged_license_contents_verified"] and
                    artifact["no_internet_permission"] and artifact["allow_backup"] is False, "Single-ABI APK package evidence incomplete")
    require(read_json(CONTRACTS / "fixtures/sync/v1/android_key_vectors.json") == fixtures(), "Android key fixture drift")
    for path, expected in definitions().items():
        actual = read_yaml(path) if path.suffix == ".yaml" else path.read_text(encoding="utf-8")
        require(actual == expected, "Key/backup definition drift: " + str(path))


def validate_legacy_identity_evidence(report: dict) -> None:
    from build_legacy_identity_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["production_converter_implemented"] is False,
            "Legacy reader/projection evidence failed or overstates product activation")
    fixed = derive()
    require(read_json(FIXTURE) == fixed, "Legacy identity fixture drift")
    require([row["id"] for row in report["cases"]] == [row["id"] for row in fixed["cases"]], "Legacy identity coverage incomplete")
    for row, case in zip(report["cases"], fixed["cases"]):
        require(row["passed"], "Legacy identity case failed")
        actual = row["actual"]
        require(all(actual[key] == case["expected"][key] for key in ("core_error", "projection_error", "portable_events", "portable_intents")),
                "Legacy identity outcome differs from fixed expectation")
        if actual["core_error"] is None:
            require(actual["v1_fields_preserved"] and actual["missing_fields_not_invented"] and actual["source_unchanged_after_projection"] and
                    actual["migration_ids"] == case["expected"]["v1_to_v5_migration_ids"], "Legacy projection lost preservation/migration evidence")


def validate_owned_graph_evidence(report: dict) -> None:
    from build_owned_graph_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 4 and report["rollback_boundaries"] == 4,
            "Owned graph publication/rollback evidence failed")
    require(report["production_owner_implemented"] is False and report["combined_transport_and_child_causal_evidence_verified"] is False,
            "Owned coherence oracle cannot certify combined transport/product implementation")
    fixed = derive()
    require(read_json(FIXTURE) == fixed and report["fixed_case_ids"] == [row["id"] for row in fixed["cases"]],
            "Owned graph golden coverage differs")


def validate_cursor_evidence(report: dict) -> None:
    from build_cursor_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 4, "Cursor authentication evidence failed")
    for field in ("production_producer_implemented", "durable_key_retirement_ledger_verified", "materialized_bootstrap_and_page_apply_verified"):
        require(report[field] is False, "Cursor codec cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed, "Cursor fixture drift")
    require(set(report["consumers"]) == {"java21", "python_contract_oracle"}, "Cursor evidence omits independent consumer")
    expected_hash = hashlib.sha256(("\n".join(row["expected"]["output"] for row in fixed["cases"]) + "\n").encode()).hexdigest()
    for row in report["consumers"].values():
        require(row["passed"] and not row["mismatched"] and row["cases"] == len(fixed["cases"]) == 33 and
                row["actual_output_sha256"] == expected_hash, "Cursor bytes or rejection outcomes differ")


def validate_bootstrap_evidence(report: dict) -> None:
    from build_bootstrap_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 7, "Bootstrap evidence failed")
    for field in ("production_implementation_verified", "combined_pending_failed_effect_rebase_verified", "postgresql_service_materialization_verified"):
        require(report[field] is False, "Isolated fresh bootstrap cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 10, "Bootstrap fixture drift")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]],
            "Bootstrap fixed outcomes differ")
    require(report["actual_process_death_points"] == ["server_supersede", "server_session", "server_pages", "local_page_receipt",
        "local_clear_baseline", "local_entities", "local_conflicts_anchors", "local_import_markers", "local_confirmation_cursor", "local_finalize_receipt"],
        "Bootstrap process death coverage incomplete")


def validate_backup_policy_evidence(report: dict) -> None:
    from build_backup_policy_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 4, "Backup policy evidence failed")
    for field in ("actual_cloud_transport_executed", "actual_device_transfer_executed", "api23_or_api24_os_executed", "production_restore_owner_implemented"):
        require(report[field] is False, "Backup policy model cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["categories"]) == 25 and len(fixed["cases"]) == 11, "Backup policy fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Backup policy outcomes differ")


def validate_habit_operation_evidence(report: dict) -> None:
    from build_habit_operation_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 11, "Habit operation evidence failed")
    for field in ("production_owners_implemented", "combined_bootstrap_pending_rebase_verified", "four_language_consumers_verified"):
        require(report[field] is False, "Habit oracle cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 29, "Habit operation fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Habit operation outcomes differ")
    require(report["actual_process_death_points"] == ["operation_binding", "check_in_fact", "parent_history_guard", "change_group", "operation_effect"],
            "Habit operation process death coverage incomplete")
    policy = read_yaml(CONTRACTS / "sync/sync_habit_operation_protocol.yaml")
    require({name: row["merge_keys"] for name, row in policy["operations"].items()} == {
        "increment": ["completion", "deleted_at", "snapshot"], "decrement": ["completion", "deleted_at", "snapshot"],
        "replace_total": ["completion", "deleted_at", "note", "snapshot"], "clear": ["completion", "deleted_at"]},
        "Habit operation causal write set differs")


def validate_local_intent_evidence(report: dict) -> None:
    from build_local_intent_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 29, "Local intent recovery evidence failed")
    for field in ("production_owners_implemented", "import_publication_and_resolution_writers_verified", "four_language_consumers_verified"):
        require(report[field] is False, "Local journal oracle cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 8, "Local intent fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]],
            "Local intent fixed outcomes differ")
    require(report["actual_process_death_points"] == ["local_clear_baseline", "local_entities", "local_conflicts_anchors", "local_import_markers",
        "local_intent_effect_coverage", "local_intent_projection", "local_confirmation_cursor", "local_finalize_receipt",
        "local_intent_enqueue", "local_intent_ack", "local_intent_discard", "download_entities", "download_conflicts",
        "download_group_receipt", "download_effect_coverage", "download_projection", "download_cursor", "download_page_receipt"],
        "Local intent actual process-death coverage incomplete")


def validate_conflict_resolution_evidence(report: dict) -> None:
    from build_conflict_resolution_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 19, "Conflict resolution component evidence failed")
    for field in ("production_owners_implemented", "owned_recurrence_and_import_conflicts_verified", "durable_conflict_notice_projection_verified", "four_language_consumers_verified"):
        require(report[field] is False, "Root conflict component cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 8, "Conflict resolution fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Conflict resolution outcomes differ")
    require(report["actual_process_death_points"] == ["resolution_fact_and_fields", "resolution_conflict_lifecycle", "resolution_change_group",
        "resolution_receipt", "resolution_device_sequence"], "Conflict resolution actual process-death coverage incomplete")


def validate_owned_sequence_evidence(report: dict) -> None:
    from build_owned_sequence_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 12, "Owned sequence component evidence failed")
    for field in ("production_owners_implemented", "owned_resolution_and_import_verified", "deletion_cascades_verified", "four_language_consumers_verified"):
        require(report[field] is False, "Owned sequence component cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 7, "Owned sequence fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Owned sequence outcomes differ")
    require(report["actual_process_death_points"] == ["owned_fact_and_fields:event", "owned_fact_and_fields:event_recurrence",
        "owned_fact_and_fields:reminder_intent", "owned_typed_change_group", "owned_receipt", "owned_device_sequence",
        "owned_conflict_lifecycle"], "Owned sequence process-death coverage incomplete")


def validate_owned_resolution_evidence(report: dict) -> None:
    from build_owned_resolution_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 11, "Owned resolution component evidence failed")
    for field in ("production_owners_implemented", "all_owned_lifecycles_and_import_verified", "deletion_cascades_verified", "four_language_consumers_verified"):
        require(report[field] is False, "Owned resolution component cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 6, "Owned resolution fixture coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Owned resolution outcomes differ")
    require(report["actual_process_death_points"] == ["owned_resolution_fact:event", "owned_resolution_fact:event_recurrence",
        "owned_resolution_conflict_lifecycle", "owned_resolution_change_group", "resolution_receipt", "resolution_device_sequence"],
        "Owned resolution process-death coverage incomplete")


def validate_notice_evidence(report: dict) -> None:
    from build_notice_fixtures import derive, FIXTURE
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["tests_run"] == 9, "Notice component evidence failed")
    for field in ("production_native_or_ui_implemented", "four_language_consumers_verified", "million_individual_fsync_commits_claimed"):
        require(report[field] is False, "Notice component cannot certify " + field)
    fixed = derive()
    require(read_json(FIXTURE) == fixed and len(fixed["cases"]) == 6, "Notice fixed coverage differs")
    require(report["cases"] == [{"id": row["id"], "actual": row["expected"], "passed": True} for row in fixed["cases"]], "Notice fixed outcomes differ")
    expected = ["finalize:" + point for point in ("notice_queue_members", "notice_sequence_state", "notice_terminal_journal_cleanup", "local_confirmation_cursor", "local_finalize_receipt")]
    expected += ["apply_download:" + point for point in ("notice_download_window", "notice_queue_members", "notice_sequence_state", "notice_terminal_journal_cleanup", "download_cursor", "download_page_receipt")]
    expected += ["claim_notice:" + point for point in ("notice_claim_watermark", "notice_claim_head_cleanup", "notice_claim_revision")]
    require(report["actual_process_death_points"] == expected, "Notice actual process-death coverage incomplete")
    capacity = report["capacity"]
    require(capacity["passed"] and capacity["windows"] == 1000000 and capacity["windows_per_commit"] == 1000 and capacity["committed_batches"] == 1000,
        "Notice million-window capacity coverage incomplete")
    require(capacity["maximum_rows_at_terminal"] == {"queue": 1, "members": 1, "discovery": 0} and
        capacity["retained_rows"] == {name: 0 for name in ("notice_queue", "notice_members", "notice_window", "notice_discovery")} and
        capacity["final_next_sequence"] == 1000001 and capacity["last_claimed"] == 1000000 and capacity["database_bytes_after_checkpoint"] <= 1024 * 1024,
        "Notice cleanup growth or final watermark differs")


def validate_import_saga_evidence(report: dict) -> None:
    import ast
    from run_import_capacity_spike import sources
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"], "Import component evidence failed")
    for field in ("production_implemented", "complete_import_lifecycle_verified", "all_language_consumers_verified"):
        require(report[field] is False, "Import component cannot certify " + field)
    files = sorted((CONTRACTS / "tests").glob("test_sync_import_*.py"))
    expected_ids = []
    for path in files:
        tree = ast.parse(path.read_text(encoding="utf8"))
        for cls in tree.body:
            if isinstance(cls, ast.ClassDef):
                expected_ids += [path.stem + "." + cls.name + "." + method.name for method in cls.body
                    if isinstance(method, ast.FunctionDef) and method.name.startswith("test_")]
    require(sorted(report["test_case_ids"]) == sorted(expected_ids) and
            report["tests_run"] == len(expected_ids) == 54, "Import test identity/count coverage differs")
    expected_points = {
        "contract": [], "status": [],
        "staging": ["import_canonical_fact:event", "import_canonical_fact:event_recurrence", "import_canonical_fact:reminder_intent",
            "import_publication_and_marker", "import_receipt", "import_device_sequence"],
        "download": ["import_download_staged_line", "import_download_staging_cursor", "import_download_page_receipt",
            "import_download_fact:event", "import_download_fact:event_recurrence", "import_download_fact:reminder_intent",
            "import_download_marker", "import_download_effect_coverage", "import_download_projection", "import_download_visible_cursor", "import_download_page_receipt"],
        "leases": ["import_guest_reserved", "import_guest_reserved_committed", "import_account_outbox", "import_account_operation_receipt",
            "import_account_allocator", "import_account_receipt_committed", "import_guest_active"],
        "ranges": ["import_range_highest", "import_range_proof_and_stage", "import_absent_identity_fence",
            "import_fence_generation", "import_range_highest", "import_range_proof_and_stage", "import_fence_receipt"],
        "cleanup": ["import_guest_execution_retired", "import_guest_facts_retired", "import_guest_retirement_receipt_epoch",
            "import_account_retirement_observed", "import_server_cleanup_stage", "import_server_cleanup_receipt", "import_native_cleanup_completed",
            "import_guest_completed_release", "import_ack_only_accepted"],
        "successor": ["import_graph_mapping", "import_graph_frozen_batch", "import_successor_canonical:category",
            "import_successor_publication_head", "import_receipt", "import_device_sequence"],
    }
    expected_components = {"test_sync_import_" + name: {"test_count": sum(case.startswith("test_sync_import_" + name + ".") for case in expected_ids),
        "actual_process_exit_points": points} for name, points in expected_points.items()}
    require(report["components"] == expected_components, "Import component/process-death coverage differs")
    paths = sources([CONTRACTS / "spikes/sync_v1/run_import_saga_spike.py", *files])
    require(set(report["source_sha256"]) == {path.relative_to(ROOT).as_posix() for path in paths}, "Import transitive source closure differs")


def validate_client_recovery_evidence(report: dict) -> None:
    import ast
    from run_import_capacity_spike import sources
    from run_client_recovery_spike import PATTERNS
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"], "Client recovery evidence failed")
    for name in ("production_implemented", "android_lifecycle_owner_implemented", "all_language_consumers_verified"):
        require(report[name] is False, "Client recovery component cannot certify " + name)
    expected_ids = []
    files = [CONTRACTS / "tests" / name for name in PATTERNS]
    for path in files:
        for cls in ast.parse(path.read_text(encoding="utf8")).body:
            if isinstance(cls, ast.ClassDef):
                expected_ids.extend(path.stem + "." + cls.name + "." + method.name for method in cls.body
                    if isinstance(method, ast.FunctionDef) and method.name.startswith("test_"))
    require(sorted(report["test_case_ids"]) == sorted(expected_ids) and report["tests_run"] == len(expected_ids) == 27,
            "Client recovery test identity/count coverage differs")
    points = {
        "test_sync_full_import": ["import_guest_reserved", "import_guest_reserved_committed", "import_client_mapping", "import_account_outbox",
            "import_account_operation_receipt", "import_account_allocator", "import_account_receipt_committed", "import_guest_active"],
        "test_sync_fresh_import": ["import_fresh_mapping_and_control", "import_fresh_seed_and_receipt", "import_fresh_account_committed",
            "import_fresh_restore_previous_lease", "import_fresh_ready"],
        "test_sync_policy_maintenance": ["policy_state_and_pull_gate", "policy_latest_receipt", "policy_terminal_pull_gate", "maintenance_bounded_deletes"],
        "test_sync_private_lifecycle": [],
    }
    require(report["components"] == {name: {"test_count": sum(case.startswith(name + ".") for case in expected_ids),
        "actual_process_exit_points": value} for name, value in points.items()}, "Client recovery process-death coverage differs")
    paths = sources([CONTRACTS / "spikes/sync_v1/run_client_recovery_spike.py", *files])
    require(set(report["source_sha256"]) == {path.relative_to(ROOT).as_posix() for path in paths}, "Client recovery source closure differs")


def validate_import_capacity_evidence(report: dict) -> None:
    from run_import_capacity_spike import sources
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["production_implemented"] is False, "Import capacity evidence failed or overstates scope")
    require([row["input_business_facts"] for row in report["counts"]] == [20000, 50000], "Import capacity workload coverage differs")
    for row in report["counts"]:
        count = row["input_business_facts"]
        require(row["passed"] and row["expanded_import_items"] == row["published_facts"] == row["mapping_count"] == count and
            row["actual_receipts"] == count + 2 and sum(row["target_counts"].values()) == count,
            "Import capacity truncated facts, mapping or actual receipts")
        require(set(row["target_counts"]) == {"event", "event_recurrence", "event_occurrence_state", "anniversary", "anniversary_recurrence",
            "habit", "habit_recurrence", "habit_check_in", "category", "reminder_intent"} and all(value > 0 for value in row["target_counts"].values()),
            "Import capacity omits a required mixed target")
        require(0 < row["canonical_bytes"] <= 128 * 1024 * 1024 and row["publish_chunks"] == (count + 499) // 500 and
            0 < row["maximum_chunk_canonical_bytes"] <= 1024 * 1024, "Import capacity byte/item hard cap differs")
        require(bool(re.fullmatch(r"[0-9a-f]{64}", row["publication_digest"])) and row["seconds"] > 0, "Import capacity observed digest/time missing")
    require(set(report["source_sha256"]) == {path.relative_to(ROOT).as_posix() for path in sources()}, "Capacity transitive source closure differs")


def validate_cross_language_schema_evidence(report: dict) -> None:
    from cross_language_schema_reference import bundle
    validate_spike_sources(report)
    require(report["passed"] and not report["errors"] and report["production_implemented"] is False and
        report["all_fixture_families_verified"] is False, "Schema consumers failed or overstate full fixture scope")
    value, paths = bundle()
    require(report["case_ids"] == [case["id"] for case in value["cases"]] and report["case_count"] == len(value["cases"]) == 1376,
        "Four-language schema case identity/count differs")
    manifest = read_json(CONTRACTS / "fixtures/sync/v1/manifest.json")
    require(report["all_fixed_fixture_transport_verified"] is True and report["fixture_transport_ids"] == [case["id"] for case in manifest["cases"]],
        "Every fixed fixture must round trip through all four parsers")
    require(report["fixture_transport_families"] == sorted({case["family"] for case in manifest["cases"]}), "Fixture transport family coverage differs")
    require(report["schema_documents"] == len(paths) and report["assertion_nodes"] == len(value["nodes"]), "Schema assertion coverage differs")
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    require(report["derived_assertion_graph_sha256"] == hashlib.sha256(encoded).hexdigest(), "Derived assertion graph differs")
    lines = ["VALID\t" + case["canonical_utf8_hex"] if case["valid"] else "REJECT" for case in value["cases"]]
    expected = hashlib.sha256(("\n".join(lines) + "\n").encode()).hexdigest()
    require(set(report["consumers"]) == {"cpp_windows", "java21", "kotlin_jvm_2_2_20", "dart"}, "Four-language consumer missing")
    require(all(row["passed"] and row["cases"] == len(lines) and row["output_sha256"] == expected for row in report["consumers"].values()),
        "Four-language schema/round-trip bytes differ")


def validate_audit(*, drafts_only: bool = False) -> dict:
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
    jcs_path = CONTRACTS / "spikes/sync_v1/jcs_spike_result.json"
    if jcs_path.is_file():
        validate_jcs_spike(read_json(jcs_path), read_json(CONTRACTS / "fixtures/sync/v1/jcs_boundary_vectors.json"))
    cipher_path = CONTRACTS / "spikes/sync_v1/cipher_source_spike_result.json"
    if cipher_path.is_file() and not drafts_only:
        validate_cipher_source_spike(read_json(cipher_path), read_json(CONTRACTS / "spikes/sync_v1/cipher_runtime_source_audit.json"))
    validate_backend_http_audit(read_json(CONTRACTS / "spikes/sync_v1/backend_http_calibration_result.json"), registry)
    validate_backend_shape_audit(read_json(CONTRACTS / "spikes/sync_v1/backend_shape_audit_result.json"))
    validate_domain_drafts(read_json(CONTRACTS / "spikes/sync_v1/domain_spike_result.json"))
    validate_protocol_drafts(read_json(CONTRACTS / "spikes/sync_v1/protocol_spike_result.json"))
    validate_storage_drafts(read_json(CONTRACTS / "spikes/sync_v1/storage_spike_result.json"))
    validate_capability_drafts(read_json(CONTRACTS / "spikes/sync_v1/capability_spike_result.json"))
    validate_proof_evidence(read_json(CONTRACTS / "spikes/sync_v1/proof_signature_spike_result.json"),
                            read_json(CONTRACTS / "spikes/sync_v1/proof_capsule_spike_result.json"))
    validate_occurrence_identity_evidence(read_json(CONTRACTS / "spikes/sync_v1/occurrence_identity_spike_result.json"))
    validate_legacy_identity_evidence(read_json(CONTRACTS / "spikes/sync_v1/legacy_identity_spike_result.json"))
    validate_owned_graph_evidence(read_json(CONTRACTS / "spikes/sync_v1/owned_graph_spike_result.json"))
    validate_cursor_evidence(read_json(CONTRACTS / "spikes/sync_v1/cursor_spike_result.json"))
    validate_bootstrap_evidence(read_json(CONTRACTS / "spikes/sync_v1/bootstrap_spike_result.json"))
    validate_android_key_evidence(read_json(CONTRACTS / "spikes/sync_v1/android_key_spike_result.json"),
                                  read_json(CONTRACTS / "spikes/sync_v1/android_key_build_result.json"))
    validate_backup_policy_evidence(read_json(CONTRACTS / "spikes/sync_v1/backup_policy_spike_result.json"))
    validate_habit_operation_evidence(read_json(CONTRACTS / "spikes/sync_v1/habit_operation_spike_result.json"))
    validate_local_intent_evidence(read_json(CONTRACTS / "spikes/sync_v1/local_intent_spike_result.json"))
    validate_conflict_resolution_evidence(read_json(CONTRACTS / "spikes/sync_v1/conflict_resolution_spike_result.json"))
    validate_notice_evidence(read_json(CONTRACTS / "spikes/sync_v1/notice_spike_result.json"))
    validate_owned_sequence_evidence(read_json(CONTRACTS / "spikes/sync_v1/owned_sequence_spike_result.json"))
    validate_owned_resolution_evidence(read_json(CONTRACTS / "spikes/sync_v1/owned_resolution_spike_result.json"))
    validate_import_saga_evidence(read_json(CONTRACTS / "spikes/sync_v1/import_saga_spike_result.json"))
    validate_client_recovery_evidence(read_json(CONTRACTS / "spikes/sync_v1/client_recovery_spike_result.json"))
    validate_import_capacity_evidence(read_json(CONTRACTS / "spikes/sync_v1/import_capacity_spike_result.json"))
    validate_cross_language_schema_evidence(read_json(CONTRACTS / "spikes/sync_v1/cross_language_schema_spike_result.json"))
    counters = read_json(CONTRACTS / "spikes/sync_v1/counter_spike_result.json")
    validate_spike_sources(counters)
    require(counters["passed"] and not counters["errors"] and counters["tests_run"] == 6, "Counter model tests failed")
    require(counters["counter_kinds"] == 27 and counters["boundary_golden_cases"] == 81 and counters["concurrent_double_write_cases"] == 54,
            "Counter matrix incomplete")
    require(counters["product_owners_implemented"] is False and counters["four_language_consumers_verified"] is False,
            "Reference counter model cannot certify product/four-language behavior")
    for path, expected in derive_anniversary_v3().items():
        require(read_json(path) == expected, "Anniversary v3 differs from the approved compatibility delta: " + str(path))
    gate_record = read_json(CONTRACTS / "sync/ct0_gate_status.json")
    validate_gate_record(gate_record)
    return dict(status=gate_record["contract_status"] if gate_record["contract_status"] == "CONTRACT FROZEN" else "DRAFT_CONTRACTS_ONLY_NOT_FROZEN" if drafts_only else "CT0_AUDIT_ONLY_NOT_FROZEN", protected_contracts=count, schemas=len(schemas),
                runtime_fixtures=fixtures, backend_endpoints=17, backend_controllers=16, canonical_vector_integrity=vector_count)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("drafts", "ct0", "frozen"), default="frozen")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    print(json.dumps(validate_audit(drafts_only=args.stage == "drafts")))
    if args.self_test:
        suite = unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern="test_sync_*.py")
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        if not result.wasSuccessful():
            return 1
    if args.stage == "frozen" and read_json(CONTRACTS / "sync/ct0_gate_status.json")["contract_status"] != "CONTRACT FROZEN":
        print("DECISION REQUIRED: final Contract revision acceptance has not been recorded. No downstream production activation is authorized.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ValueError, KeyError, OSError, yaml.YAMLError) as error:
        print(f"Sync CT0 validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
