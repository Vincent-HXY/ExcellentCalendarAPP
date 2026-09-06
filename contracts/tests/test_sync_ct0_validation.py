"""Negative regressions for the compatibility and freeze gates."""
from __future__ import annotations

import copy
import json
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path

import validate_sync_v1 as validation


class SyncCt0ValidationTests(unittest.TestCase):
    def test_client_recovery_requires_exact_cases_process_deaths_and_scope(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/client_recovery_spike_result.json")
        validation.validate_client_recovery_evidence(report)
        for mutate in (
            lambda value: value["test_case_ids"].pop(),
            lambda value: value["components"]["test_sync_fresh_import"]["actual_process_exit_points"].pop(),
            lambda value: value["source_sha256"].popitem(),
            lambda value: value.update(android_lifecycle_owner_implemented=True),
        ):
            changed = copy.deepcopy(report)
            mutate(changed)
            with self.assertRaises(AssertionError):
                validation.validate_client_recovery_evidence(changed)

    def test_import_report_requires_actual_case_crash_and_source_closure(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/import_saga_spike_result.json")
        validation.validate_import_saga_evidence(report)
        for field in ("test_case_ids", "source_sha256"):
            changed = copy.deepcopy(report)
            changed[field].pop() if isinstance(changed[field], list) else changed[field].popitem()
            with self.assertRaisesRegex(AssertionError, "coverage|closure"):
                validation.validate_import_saga_evidence(changed)
        changed = copy.deepcopy(report)
        changed["components"]["test_sync_import_successor"]["actual_process_exit_points"].pop()
        with self.assertRaisesRegex(AssertionError, "process-death coverage"):
            validation.validate_import_saga_evidence(changed)
        report["complete_import_lifecycle_verified"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_import_saga_evidence(report)

    def test_capacity_report_rejects_missing_workload_truncation_and_scope_expansion(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/import_capacity_spike_result.json")
        validation.validate_import_capacity_evidence(report)
        changed = copy.deepcopy(report)
        changed["counts"].pop()
        with self.assertRaisesRegex(AssertionError, "workload coverage"):
            validation.validate_import_capacity_evidence(changed)
        for field in ("published_facts", "mapping_count", "actual_receipts"):
            changed = copy.deepcopy(report)
            changed["counts"][0][field] -= 1
            with self.assertRaisesRegex(AssertionError, "truncated"):
                validation.validate_import_capacity_evidence(changed)
        report["production_implemented"] = True
        with self.assertRaisesRegex(AssertionError, "overstates scope"):
            validation.validate_import_capacity_evidence(report)

    def test_four_language_report_rejects_missing_consumer_case_and_round_trip_drift(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/cross_language_schema_spike_result.json")
        validation.validate_cross_language_schema_evidence(report)
        changed = copy.deepcopy(report)
        changed["consumers"].pop("dart")
        with self.assertRaisesRegex(AssertionError, "consumer missing"):
            validation.validate_cross_language_schema_evidence(changed)
        changed = copy.deepcopy(report)
        changed["case_ids"].pop()
        with self.assertRaisesRegex(AssertionError, "case identity"):
            validation.validate_cross_language_schema_evidence(changed)
        changed = copy.deepcopy(report)
        changed["consumers"]["kotlin_jvm_2_2_20"]["output_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "bytes differ"):
            validation.validate_cross_language_schema_evidence(changed)
        report["all_fixture_families_verified"] = True
        with self.assertRaisesRegex(AssertionError, "overstate"):
            validation.validate_cross_language_schema_evidence(report)

    def test_owned_resolution_evidence_rejects_missing_cases_crashes_and_scope_expansion(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/owned_resolution_spike_result.json")
        for field in ("cases", "actual_process_death_points"):
            modified = copy.deepcopy(report)
            modified[field].pop()
            with self.assertRaises(AssertionError):
                validation.validate_owned_resolution_evidence(modified)
        modified = copy.deepcopy(report)
        modified["all_owned_lifecycles_and_import_verified"] = True
        with self.assertRaises(AssertionError):
            validation.validate_owned_resolution_evidence(modified)

    def test_owned_sequence_evidence_rejects_missing_cases_crashes_and_scope_expansion(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/owned_sequence_spike_result.json")
        for field in ("cases", "actual_process_death_points"):
            modified = copy.deepcopy(report)
            modified[field].pop()
            with self.assertRaises(AssertionError):
                validation.validate_owned_sequence_evidence(modified)
        modified = copy.deepcopy(report)
        modified["owned_resolution_and_import_verified"] = True
        with self.assertRaises(AssertionError):
            validation.validate_owned_sequence_evidence(modified)

    def test_conflict_resolution_evidence_cannot_drop_cases_crashes_or_claim_owned_closure(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/conflict_resolution_spike_result.json")
        for field in ("cases", "actual_process_death_points"):
            modified = copy.deepcopy(report)
            modified[field].pop()
            with self.assertRaises(AssertionError):
                validation.validate_conflict_resolution_evidence(modified)
        modified = copy.deepcopy(report)
        modified["owned_recurrence_and_import_conflicts_verified"] = True
        with self.assertRaises(AssertionError):
            validation.validate_conflict_resolution_evidence(modified)

    def test_local_intent_evidence_rejects_lost_cases_crash_points_and_scope_expansion(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/local_intent_spike_result.json")
        for field in ("cases", "actual_process_death_points"):
            modified = copy.deepcopy(report)
            modified[field].pop()
            with self.assertRaises(AssertionError):
                validation.validate_local_intent_evidence(modified)
        modified = copy.deepcopy(report)
        modified["import_publication_and_resolution_writers_verified"] = True
        with self.assertRaises(AssertionError):
            validation.validate_local_intent_evidence(modified)

    def test_habit_evidence_rejects_missing_cases_crash_points_or_product_claim(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/habit_operation_spike_result.json")
        for field in ("cases", "actual_process_death_points"):
            modified = copy.deepcopy(report)
            modified[field].pop()
            with self.assertRaises(AssertionError):
                validation.validate_habit_operation_evidence(modified)
        modified = copy.deepcopy(report)
        modified["production_owners_implemented"] = True
        with self.assertRaises(AssertionError):
            validation.validate_habit_operation_evidence(modified)

    def test_duplicate_json_keys_are_not_silently_collapsed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "duplicate.json"
            path.write_text('{"revision":1,"revision":2}', encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Duplicate"):
                validation.read_json(path)

    def test_non_json_numeric_constant_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "nan.json"
            path.write_text('{"value":NaN}', encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Non-JSON"):
                validation.read_json(path)

    def test_duplicate_yaml_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "duplicate.yaml"
            path.write_text('version: 2\nversion: 3\n', encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "Duplicate"):
                validation.read_yaml(path)

    def test_ref_document_and_fragment_closure(self):
        schema_id = "https://test.invalid/root.schema.json"
        for ref in ("missing.schema.json", "#/$defs/missing"):
            with self.subTest(ref=ref), self.assertRaises(AssertionError):
                validation.validate_refs({schema_id: {"$ref": ref}})

    def test_valid_ref_with_escaped_pointer(self):
        schema_id = "https://test.invalid/root.schema.json"
        validation.validate_refs({schema_id: {"$defs": {"a/b": {"type": "string"}}, "$ref": "#/$defs/a~1b"}})

    def test_v5_definition_drift_is_rejected(self):
        storage = validation.read_yaml(validation.CONTRACTS / "storage/calendar_core_storage.yaml")
        response = validation.read_json(validation.CONTRACTS / "runtime/initialize_runtime_response.schema.json")
        storage["calendar_core_v5"]["sqlite"]["synchronous"] = "NORMAL"
        with self.assertRaisesRegex(AssertionError, "Frozen calendar_core_v5"):
            validation.validate_storage(storage, response)

    def test_stale_and_future_runtime_versions_are_rejected(self):
        storage = validation.read_yaml(validation.CONTRACTS / "storage/calendar_core_storage.yaml")
        response = validation.read_json(validation.CONTRACTS / "runtime/initialize_runtime_response.schema.json")
        for version in (4, 6):
            response["properties"]["storage_format_version"]["const"] = version
            with self.subTest(version=version), self.assertRaisesRegex(AssertionError, "calibrated"):
                validation.validate_storage(storage, response)

    def test_legacy_sync_activation_is_rejected(self):
        methods = validation.read_yaml(validation.CONTRACTS / "method_channels.yaml")
        native = validation.read_yaml(validation.CONTRACTS / "native_calls.yaml")
        methods["methods"]["sync.apply"]["release_status"] = "active"
        with self.assertRaisesRegex(AssertionError, "blocked"):
            validation.validate_legacy_tombstone(methods, native)

    def test_jcs_expected_byte_hash_tamper_is_rejected(self):
        vectors = validation.read_json(validation.CONTRACTS / "fixtures/sync/v1/canonical_vectors.json")
        vectors["cases"][0]["sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "byte/hash"):
            validation.validate_vectors(vectors)

    def test_unsigned_gate_cannot_be_marked_frozen(self):
        gates = validation.read_json(validation.CONTRACTS / "sync/ct0_gate_status.json")
        gates["contract_status"] = "CONTRACT FROZEN"
        gates.pop("revision_lock", None)
        with self.assertRaisesRegex(AssertionError, "Cannot mark"):
            validation.validate_gate_record(gates)

    def test_existing_schema_drift_is_detected(self):
        baseline = validation.read_json(validation.CONTRACTS / "sync/sync_v1_baseline.json")
        original = validation.read_json(validation.CONTRACTS / "event/event_response.schema.json")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "contracts/event/event_response.schema.json"
            path.parent.mkdir(parents=True)
            mutant = copy.deepcopy(original)
            mutant["properties"]["title"]["type"] = "number"
            path.write_text(json.dumps(mutant), encoding="utf-8")
            baseline["files"] = {"contracts/event/event_response.schema.json": validation.digest(original)}
            with self.assertRaisesRegex(AssertionError, "Protected Contract drift"):
                validation.validate_baseline(baseline, root)

    def test_upload_throws_declaration_does_not_hide_avatar_delete(self):
        audit = validation.collect_backend_audit(validation.read_yaml(validation.CONTRACTS / "backend_api.yaml"), validation.ROOT)
        endpoints = {row["operation"]: row for row in audit["endpoints"]}
        self.assertEqual(endpoints["user.avatar.upload"]["handler"], "upload")
        self.assertEqual(endpoints["user.avatar.delete"]["handler"], "delete")
        self.assertEqual(endpoints["auth.registration.email.update"]["source_status"], "controller_absent")

    def test_missing_fixture_case_is_rejected(self):
        manifest = validation.read_json(validation.CONTRACTS / "fixtures/sync/v1/manifest.json")
        vectors = validation.read_json(validation.CONTRACTS / "fixtures/sync/v1/canonical_vectors.json")
        manifest["cases"].pop()
        with self.assertRaisesRegex(AssertionError, "coverage"):
            validation.validate_fixture_manifest(manifest, vectors)

    def test_stale_spike_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "probe.cpp").write_text("changed probe", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "stale"):
                validation.validate_spike_sources({"source_sha256": {"probe.cpp": "0" * 64}}, root)

    def test_capsule_cannot_relabel_compilation_or_skip_android_consumer(self):
        primitive = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/proof_signature_spike_result.json")
        capsule = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/proof_capsule_spike_result.json")
        missing = copy.deepcopy(capsule)
        del missing["consumers"]["android_cpp_jni_arm64-v8a"]
        with self.assertRaisesRegex(AssertionError, "consumer coverage"):
            validation.validate_proof_evidence(primitive, missing)
        capsule["android_x86_os_executed"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_proof_evidence(primitive, capsule)

    def test_capsule_changed_output_or_product_claim_is_rejected(self):
        primitive = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/proof_signature_spike_result.json")
        capsule = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/proof_capsule_spike_result.json")
        changed = copy.deepcopy(capsule); changed["consumers"]["java21"]["actual_output_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "bytes/hash differ"):
            validation.validate_proof_evidence(primitive, changed)
        capsule["production_activated"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_proof_evidence(primitive, capsule)

    def test_jcs_missing_abi_or_relabelled_qemu_is_rejected(self):
        original = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/jcs_spike_result.json")
        fixtures = validation.read_json(validation.CONTRACTS / "fixtures/sync/v1/jcs_boundary_vectors.json")
        missing = copy.deepcopy(original)
        del missing["consumers"]["ndk_bionic_armeabi-v7a"]
        with self.assertRaisesRegex(AssertionError, "omits"):
            validation.validate_jcs_spike(missing, fixtures)
        wrong_label = copy.deepcopy(original)
        wrong_label["android_three_os_device_matrix_verified"] = True
        with self.assertRaisesRegex(AssertionError, "relabeled"):
            validation.validate_jcs_spike(wrong_label, fixtures)

    def test_original_civil_lookup_cannot_omit_case_or_claim_full_migration(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/occurrence_identity_spike_result.json")
        missing = copy.deepcopy(report)
        missing["cases"].pop()
        with self.assertRaisesRegex(AssertionError, "incomplete"):
            validation.validate_occurrence_identity_evidence(missing)
        report["legacy_v1_conversion_verified"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_occurrence_identity_evidence(report)

    def test_original_civil_identity_does_not_merge_same_instant_occurrences(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/occurrence_identity_spike_result.json")
        matches = [row for row in report["cases"] if row["actual"] and row["actual"]["same_instant_candidates"] == 2]
        self.assertEqual(len(matches), 2)
        matches[1]["actual"]["target_occurrence_key"] = matches[0]["actual"]["target_occurrence_key"]
        with self.assertRaisesRegex(AssertionError, "output differs"):
            validation.validate_occurrence_identity_evidence(report)

    def test_android_key_evidence_cannot_substitute_compilation_or_wrong_process_abi(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/android_key_spike_result.json")
        build = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/android_key_build_result.json")
        wrong = copy.deepcopy(report)
        wrong["consumers"]["armeabi-v7a"]["initial"]["is_64_bit"] = True
        with self.assertRaisesRegex(AssertionError, "process ABI"):
            validation.validate_android_key_evidence(wrong, build)
        report["build_only"] = True
        with self.assertRaisesRegex(AssertionError, "Build-only"):
            validation.validate_android_key_evidence(report, build)

    def test_android_key_evidence_requires_all_phases_and_does_not_claim_cloud_restore(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/android_key_spike_result.json")
        build = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/android_key_build_result.json")
        missing = copy.deepcopy(report)
        del missing["consumers"]["arm64-v8a"]["restored_ciphertext"]
        with self.assertRaisesRegex(AssertionError, "phase coverage"):
            validation.validate_android_key_evidence(missing, build)
        report["actual_cloud_backup_or_restore_executed"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_android_key_evidence(report, build)

    def test_jcs_changed_output_digest_is_rejected(self):
        result = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/jcs_spike_result.json")
        fixtures = validation.read_json(validation.CONTRACTS / "fixtures/sync/v1/jcs_boundary_vectors.json")
        result["consumers"]["java"]["actual_output_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "bytes/hash differ"):
            validation.validate_jcs_spike(result, fixtures)

    def test_legacy_identity_missing_preservation_or_case_is_rejected(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/legacy_identity_spike_result.json")
        altered = copy.deepcopy(report)
        altered["cases"][0]["actual"]["source_unchanged_after_projection"] = False
        with self.assertRaisesRegex(AssertionError, "preservation"):
            validation.validate_legacy_identity_evidence(altered)
        report["cases"].pop()
        with self.assertRaisesRegex(AssertionError, "coverage"):
            validation.validate_legacy_identity_evidence(report)

    def test_owned_graph_oracle_cannot_certify_missing_transport_component(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/owned_graph_spike_result.json")
        report["combined_transport_and_child_causal_evidence_verified"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_owned_graph_evidence(report)

    def test_cursor_missing_consumer_or_changed_authenticated_bytes_is_rejected(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/cursor_spike_result.json")
        missing = copy.deepcopy(report)
        missing["consumers"].pop("java21")
        with self.assertRaisesRegex(AssertionError, "omits"):
            validation.validate_cursor_evidence(missing)
        report["consumers"]["java21"]["actual_output_sha256"] = "0" * 64
        with self.assertRaisesRegex(AssertionError, "bytes or rejection"):
            validation.validate_cursor_evidence(report)

    def test_bootstrap_missing_crash_point_or_unverified_rebase_claim_is_rejected(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/bootstrap_spike_result.json")
        missing = copy.deepcopy(report); missing["actual_process_death_points"].pop()
        with self.assertRaisesRegex(AssertionError, "process death"):
            validation.validate_bootstrap_evidence(missing)
        report["combined_pending_failed_effect_rebase_verified"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_bootstrap_evidence(report)

    def test_backend_nested_audit_requires_all_endpoints_fields_and_dispositions(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/backend_shape_audit_result.json")
        missing = copy.deepcopy(report); missing["endpoints"].pop()
        with self.assertRaisesRegex(AssertionError, "endpoint coverage"):
            validation.validate_backend_shape_audit(missing)
        missing = copy.deepcopy(report); missing["dispositions"].pop("java_string_size")
        with self.assertRaisesRegex(AssertionError, "disposition missing"):
            validation.validate_backend_shape_audit(missing)
        missing = copy.deepcopy(report)
        nested = next(row[direction] for row in missing["endpoints"] for direction in ("request", "response") if len(row[direction]["schema_closure"]) > 1)
        nested["schema_closure"].popitem()
        with self.assertRaisesRegex(AssertionError, "nested schema closure"):
            validation.validate_backend_shape_audit(missing)
        record = next(iter(report["compiled_dtos"]["roots"]))
        report["compiled_dtos"]["records"][record]["fields"].popitem()
        with self.assertRaisesRegex(AssertionError, "reflected field coverage"):
            validation.validate_backend_shape_audit(report)

    def test_backup_policy_cannot_omit_two_destination_case_or_claim_real_cloud_transport(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/backup_policy_spike_result.json")
        missing = copy.deepcopy(report); missing["cases"].pop()
        with self.assertRaisesRegex(AssertionError, "outcomes differ"):
            validation.validate_backup_policy_evidence(missing)
        report["actual_cloud_transport_executed"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_backup_policy_evidence(report)

    def test_cipher_kill_requires_real_child_exit_status(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/cipher_source_spike_result.json")
        step = next(row for row in report["consumers"]["windows"]["steps"] if "KILL_POINT_REACHED" in row["stdout"])
        validation.validate_cipher_step(step)
        step["exit_code"] = 0
        with self.assertRaisesRegex(AssertionError, "child failure status"):
            validation.validate_cipher_step(step)

    def test_cipher_missing_environment_is_rejected(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/cipher_source_spike_result.json")
        audit = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/cipher_runtime_source_audit.json")
        del report["consumers"]["x86_64"]
        with self.assertRaisesRegex(AssertionError, "omits|evidence failed"):
            validation.validate_cipher_source_spike(report, audit)

    def test_default_command_requires_current_freeze_and_matching_evidence(self):
        result = subprocess.run([sys.executable, str(validation.CONTRACTS / "run_sync_v1_validation.py")],
                                capture_output=True, text=True, timeout=90)
        frozen = validation.read_json(validation.CONTRACTS / "sync/ct0_gate_status.json")["contract_status"] == "CONTRACT FROZEN"
        if frozen:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("CONTRACT FROZEN", result.stdout)
        else:
            self.assertIn(result.returncode, (1, 2), result.stdout + result.stderr)
            self.assertTrue("DECISION REQUIRED" in result.stderr or "validation failed" in result.stderr,
                            result.stdout + result.stderr)

    def test_notice_missing_crash_or_capacity_and_fsync_overclaim_are_rejected(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/notice_spike_result.json")
        changed = copy.deepcopy(report)
        changed["actual_process_death_points"].pop()
        with self.assertRaisesRegex(AssertionError, "process-death coverage"):
            validation.validate_notice_evidence(changed)
        changed = copy.deepcopy(report)
        changed["capacity"]["retained_rows"]["notice_discovery"] = 1
        with self.assertRaisesRegex(AssertionError, "cleanup growth"):
            validation.validate_notice_evidence(changed)
        report["million_individual_fsync_commits_claimed"] = True
        with self.assertRaisesRegex(AssertionError, "cannot certify"):
            validation.validate_notice_evidence(report)

    def test_backend_skipped_integration_is_not_a_pass(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/backend_http_calibration_result.json")
        report["integration"]["skipped"] = 1
        _, registry = validation.validate_schemas()
        with self.assertRaisesRegex(AssertionError, "skipped or failed"):
            validation.validate_backend_http_audit(report, registry)

    def test_backend_nested_response_drift_is_not_hidden_by_a_green_build(self):
        report = validation.read_json(validation.CONTRACTS / "spikes/sync_v1/backend_http_calibration_result.json")
        case = next(case for case in report["http"]["cases"] if case["id"] == "get_current.valid")
        case["response"]["data"]["profile"]["password_hash"] = "forbidden"
        _, registry = validation.validate_schemas()
        with self.assertRaisesRegex(AssertionError, "nested response invalid"):
            validation.validate_backend_http_audit(report, registry)


if __name__ == "__main__":
    unittest.main()
