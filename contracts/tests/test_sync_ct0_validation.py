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
        with self.assertRaisesRegex(AssertionError, "cannot mark"):
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

    def test_default_command_fails_closed_with_decision_required(self):
        result = subprocess.run([sys.executable, str(validation.CONTRACTS / "validate_sync_v1.py")],
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("DECISION REQUIRED", result.stderr)


if __name__ == "__main__":
    unittest.main()
