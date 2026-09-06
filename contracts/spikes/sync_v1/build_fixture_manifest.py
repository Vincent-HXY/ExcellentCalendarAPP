"""Index Contract evidence; the single freeze decision lives in ct0_gate_status."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "contracts/fixtures/sync/v1"
ANCHORS = {
    "FX-TARGET": "7.1-7.3,7.7", "FX-MERGE": "6.2,7.2-7.5", "FX-CONFLICT": "7.5,8,12",
    "FX-SEQUENCE": "6.1-6.2,12", "FX-CANONICAL": "4.2,6.2", "FX-COUNTER": "6.1",
    "FX-RUN": "6.2-6.3,8", "FX-FAILED-LOCAL": "6.2,7.5,8", "FX-CURSOR": "6.3,12",
    "FX-BOOTSTRAP": "6.3,8,10-11", "FX-WORKSPACE": "5,8.3-8.4,10",
    "FX-IMPORT-STAGE": "7.6/IMP-01-IMP-06", "FX-IMPORT-PUBLISH": "7.6/IMP-03-IMP-05",
    "FX-IMPORT-RANGE": "7.6/IMP-07,IMP-08,IMP-12", "FX-IMPORT-CLEANUP": "7.6/IMP-09-IMP-10",
    "FX-PREFERENCE": "7.7,8,10", "FX-SESSION-DEVICE": "8,12",
    "FX-RETENTION-NOTIFY": "7.6/IMP-08-IMP-10,8,12", "FX-MAINTENANCE": "6.2-6.3,7.5,8,10,12",
    "FX-CROSS-LAYER": "9,13.2",
}


def derive():
    result = {"fixture_version": 1, "contract_status_ref": "contracts/sync/ct0_gate_status.json",
              "scope": "Contract fixtures and isolated owner evidence, plus four-language fixture transport and typed boundary assertions; no production owner or multi-device integration claim",
              "families": [{"id": name, "rule_anchor": "cloud-sync-02/" + anchor, "coverage_status": "not_delivered"}
                           for name, anchor in ANCHORS.items()], "cases": [], "generated_suites": []}
    used = set()
    for filename, default_family in (("jcs_boundary_vectors.json", "FX-CANONICAL"), ("counter_vectors.json", "FX-COUNTER"),
                                     ("target_vectors.json", "FX-TARGET"), ("native_v3_anniversary_vectors.json", "FX-WORKSPACE"),
                                     ("protocol_vectors.json", "FX-CROSS-LAYER"), ("capability_vectors.json", "FX-CROSS-LAYER"), ("postgres_vectors.json", "FX-WORKSPACE"),
                                     ("proof_signature_vectors.json", "FX-CROSS-LAYER"), ("proof_capsule_vectors.json", "FX-IMPORT-RANGE"),
                                     ("occurrence_identity_vectors.json", "FX-TARGET"), ("android_key_vectors.json", "FX-RETENTION-NOTIFY"),
                                     ("legacy_identity_vectors.json", "FX-TARGET"), ("owned_graph_vectors.json", "FX-MERGE"),
                                     ("cursor_vectors.json", "FX-CURSOR"), ("bootstrap_vectors.json", "FX-BOOTSTRAP"),
                                     ("backup_policy_vectors.json", "FX-RETENTION-NOTIFY"), ("habit_operation_vectors.json", "FX-TARGET"),
                                     ("local_intent_vectors.json", "FX-FAILED-LOCAL"), ("conflict_resolution_vectors.json", "FX-CONFLICT"),
                                     ("notice_vectors.json", "FX-CONFLICT"), ("owned_sequence_vectors.json", "FX-MERGE"), ("owned_resolution_vectors.json", "FX-CONFLICT"),
                                     ("private_lifecycle_vectors.json", "FX-MAINTENANCE")):
        content = json.loads((FIXTURES / filename).read_text(encoding="utf-8"))
        for index, case in enumerate(content["cases"]):
            family = case["family"] if filename in {"protocol_vectors.json", "capability_vectors.json", "occurrence_identity_vectors.json", "legacy_identity_vectors.json", "owned_graph_vectors.json", "habit_operation_vectors.json", "private_lifecycle_vectors.json"} else "FX-PREFERENCE" if default_family == "FX-TARGET" and case["input"]["target_type"] == "user_preferences" else default_family
            byte_exact = family == "FX-CANONICAL" and not case["expected_error"]
            expected = ({"sqlstate": case["sqlstate"], **({"scalar": case["scalar"]} if "scalar" in case else {})} if filename == "postgres_vectors.json" else
                        {"v2_valid": case["v2_valid"], "v3_valid": case["v3_valid"]} if filename.startswith("native_v3") else
                        case["expected"] if family == "FX-COUNTER" or filename in {"protocol_vectors.json", "capability_vectors.json", "proof_signature_vectors.json", "proof_capsule_vectors.json", "occurrence_identity_vectors.json", "android_key_vectors.json", "legacy_identity_vectors.json", "owned_graph_vectors.json", "cursor_vectors.json", "bootstrap_vectors.json", "backup_policy_vectors.json", "habit_operation_vectors.json", "local_intent_vectors.json", "conflict_resolution_vectors.json", "notice_vectors.json", "owned_sequence_vectors.json", "owned_resolution_vectors.json", "private_lifecycle_vectors.json"} else
                        {"error": case["expected_error"]} if family != "FX-CANONICAL" else
                        {"reject": True} if case["expected_error"] else
                        {"canonical_utf8_hex": case["canonical_utf8_hex"], "sha256": case["sha256"]})
            if case["id"] in used:
                raise ValueError("Duplicate fixture identity")
            used.add(case["id"])
            result["cases"].append({"id": case["id"], "family": family, "rule_anchor": case["rule_anchor"],
                "input_file": filename, "case_pointer": f"/cases/{index}", "expected": expected,
                "required_consumers": ["java_postgresql"] if filename == "postgres_vectors.json" else
                    ["java21", "python_contract_oracle"] if filename == "cursor_vectors.json" else
                    ["python_contract_oracle"] if filename in {"bootstrap_vectors.json", "backup_policy_vectors.json", "habit_operation_vectors.json", "local_intent_vectors.json", "conflict_resolution_vectors.json", "notice_vectors.json", "owned_sequence_vectors.json", "owned_resolution_vectors.json", "private_lifecycle_vectors.json"} else
                    ["cpp_windows_current_core_v5", "python_contract_oracle"] if filename == "legacy_identity_vectors.json" else
                    ["android_apk_arm64", "android_apk_armv7"] if filename == "android_key_vectors.json" else
                    ["cpp_windows_current_core_tzdb"] if filename == "occurrence_identity_vectors.json" else
                    ["cpp_windows", "cpp_android_arm64_jni", "cpp_android_armv7_jni", "java"] if filename.startswith("proof_") else
                    ["cpp_windows", "cpp_android_arm64", "cpp_android_armv7", "cpp_android_x86_64", "java", "kotlin", "dart"],
                "parser_consumers": ["cpp_windows", "java21", "kotlin_jvm_2_2_20", "dart"],
                "byte_for_byte_required": byte_exact})
        if default_family == "FX-CANONICAL":
            for suite_name in ("random_numeric_oracle", "systematic_numeric_oracle"):
                result["generated_suites"].append({"id": "FX-CANONICAL-" + suite_name, "rule_anchor": "cloud-sync-02/4.2",
                    "input_file": filename, "case_pointer": "/" + suite_name,
                    "runner": "contracts/spikes/sync_v1/run_jcs_spike.py", "byte_for_byte_required": True})
            result["generated_suites"].append({"id": "FX-CANONICAL-malformed-utf8", "rule_anchor": "cloud-sync-02/4.2",
                "input_file": filename, "case_pointer": "/malformed_utf8", "runner": "contracts/spikes/sync_v1/run_jcs_spike.py",
                "expected": "reject_malformed_utf8_before_canonicalization", "byte_for_byte_required": False})
    result["generated_suites"].append({"id": "FX-WORKSPACE-sqlite-v6-migration", "rule_anchor": "cloud-sync-02/10",
        "input_file": "../../../storage/calendar_core_storage.yaml", "case_pointer": "/calendar_core_v6/migration",
        "runner": "contracts/spikes/sync_v1/run_storage_spike.py", "required_consumers": ["cpp_windows_v5_checker", "python_sqlite"],
        "expected": "preserve all inherited v5 rows/objects; every added DDL/history/commit boundary rolls back; old v5 runtime rejects v6",
        "byte_for_byte_required": True})
    result["generated_suites"].append({"id": "FX-MAINTENANCE-million-notice-windows", "rule_anchor": "cloud-sync-02/8.2,10,13",
        "input_file": "notice_vectors.json", "case_pointer": "/capacity", "runner": "contracts/spikes/sync_v1/run_notice_spike.py",
        "required_consumers": ["python_sqlite_notice_journal"], "byte_for_byte_required": False,
        "expected": "one million actual notice/discovery/claim transitions in bounded capacity batches; no retained claimed queue or terminal journal"})
    result["generated_suites"].append({"id": "FX-IMPORT-PUBLISH-mixed-20000-50000", "rule_anchor": "cloud-sync-02/7.6/IMP-11;cloud-sync-01/6.3",
        "input_file": "../../../spikes/sync_v1/import_capacity_reference.py", "case_pointer": "combined_graph",
        "runner": "contracts/spikes/sync_v1/run_import_capacity_spike.py", "required_consumers": ["python_sqlite_import_staging"],
        "input_fact_counts": [20000, 50000], "byte_for_byte_required": False,
        "expected": "ten target types; every fact and mapping published; count+2 actual receipts; 500-item/1-MiB chunks; no truncation"})
    result["generated_suites"].append({"id": "FX-CROSS-LAYER-schema-boundaries", "rule_anchor": "cloud-sync-02/9,13.2",
        "input_file": "../../../spikes/sync_v1/cross_language_schema_reference.py", "case_pointer": "boundary_cases",
        "runner": "contracts/spikes/sync_v1/run_cross_language_schema_spike.py", "required_consumers": ["cpp_windows", "java21", "kotlin_jvm_2_2_20", "dart"],
        "byte_for_byte_required": True, "expected": "every fixed fixture transports losslessly; typed schema/Native v2-v3 and JCS boundaries agree. Stateful/OS outcomes use their explicit owner runners"})
    result["generated_suites"].append({"id": "FX-IMPORT-components", "rule_anchor": "cloud-sync-02/7.6/IMP-01-IMP-12",
        "input_file": "../../../tests", "case_pointer": "test_sync_import_*.py", "runner": "contracts/spikes/sync_v1/run_import_saga_spike.py",
        "required_consumers": ["python_sqlite_import_components"], "byte_for_byte_required": False,
        "expected": "all delivered import component tests and actual process-death points pass; combined client recovery uses its separate suite"})
    result["generated_suites"].append({"id": "FX-IMPORT-client-recovery", "rule_anchor": "cloud-sync-02/7.6/IMP-01-IMP-12,8,10",
        "input_file": "../../../tests", "case_pointer": ["test_sync_full_import.py", "test_sync_fresh_import.py", "test_sync_policy_maintenance.py", "test_sync_private_lifecycle.py"],
        "runner": "contracts/spikes/sync_v1/run_client_recovery_spike.py", "required_consumers": ["python_sqlite_client_recovery"],
        "byte_for_byte_required": False, "expected": "27 combined tests; 8 dual-store, 5 fresh-recovery and 4 policy/maintenance process-death boundaries; durable cleanup cutoff, authenticated private receipts/AEAD and safe-export TTL"})
    present = {case["family"] for case in result["cases"]}
    for family in result["families"]:
        if family["id"] in present:
            family["coverage_status"] = "contract_reference_delivered"
    owner_reports = {
        "jcs_boundary": "jcs", "counter": "counter", "target": "domain", "native_v3_anniversary": "cross_language_schema",
        "protocol": "protocol", "capability": "capability", "postgres": "storage", "proof_signature": "proof_signature",
        "proof_capsule": "proof_capsule", "occurrence_identity": "occurrence_identity", "android_key": "android_key",
        "legacy_identity": "legacy_identity", "owned_graph": "owned_graph", "cursor": "cursor", "bootstrap": "bootstrap",
        "backup_policy": "backup_policy", "habit_operation": "habit_operation", "local_intent": "local_intent",
        "conflict_resolution": "conflict_resolution", "notice": "notice", "owned_sequence": "owned_sequence",
        "owned_resolution": "owned_resolution", "private_lifecycle": "client_recovery",
    }
    for case in result["cases"]:
        stem = case["input_file"].removesuffix("_vectors.json")
        report = owner_reports[stem]
        case["owner_evidence_file"] = "contracts/spikes/sync_v1/" + report + "_spike_result.json"
        # ABI-specific canonical and crypto evidence keeps its stronger matrix.
        # Other fixtures have host-language parser consumers plus their actual
        # stateful owner runner, not invented Android implementations.
        if stem in {"counter", "target", "protocol", "capability", "owned_graph"}:
            case["required_consumers"] = ["python_contract_oracle"]
        elif stem == "native_v3_anniversary":
            case["required_consumers"] = case["parser_consumers"][:]
    for suite in result["generated_suites"]:
        if suite["id"].startswith("FX-IMPORT"):
            suite["families"] = ["FX-IMPORT-STAGE", "FX-IMPORT-PUBLISH", "FX-IMPORT-RANGE", "FX-IMPORT-CLEANUP"]
    delivered = present | {family for suite in result["generated_suites"] for family in suite.get("families", [])}
    for family in result["families"]:
        if family["id"] in delivered:
            family["coverage_status"] = "contract_reference_delivered"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    value = derive()
    path = FIXTURES / "manifest.json"
    if args.check:
        if json.loads(path.read_text(encoding="utf-8")) != value:
            raise ValueError("Fixture manifest coverage/identity differs")
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"families": len(value["families"]), "fixed_cases": len(value["cases"]), "generated_suites": len(value["generated_suites"])}))
