"""The accepted Anniversary change is additive in v3; v2 remains a strict oracle."""
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
import validate_sync_v1 as validation
from build_anniversary_v3_revision import derive

CONTRACTS = Path(__file__).resolve().parents[1]


class NativeV3Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _, cls.registry = validation.validate_schemas()

    def valid(self, path, value):
        schema = validation.read_json(CONTRACTS / path)
        return Draft202012Validator(schema, registry=self.registry, format_checker=FormatChecker()).is_valid(value)

    def test_exact_approved_delta_and_transitive_ref_closure(self):
        for path, expected in derive().items():
            with self.subTest(path=path):
                self.assertEqual(validation.read_json(path), expected)
        ledger = validation.read_json(CONTRACTS / "native_v3/anniversary_compatibility.json")
        self.assertEqual(len(ledger["schemas"]), 15)
        self.assertFalse(ledger["dispatch"]["automatic_fallback"])
        self.assertFalse(ledger["dispatch"]["v2_schema_changes"])

    def test_opaque_reference_fixtures_and_old_reader_rejection(self):
        fixture = validation.read_json(CONTRACTS / "fixtures/sync/v1/native_v3_anniversary_vectors.json")
        for case in fixture["cases"]:
            with self.subTest(case=case["id"]):
                self.assertEqual(self.valid(case["v3_schema"], case["value"]), case["v3_valid"])
                self.assertEqual(self.valid(case["v2_schema"], case["value"]), case["v2_valid"])

    def test_legacy_anniversary_examples_keep_their_validation_result(self):
        original = validation.read_json(CONTRACTS / "fixtures/anniversary/manifest.json")
        exercised = 0
        for case in original["cases"]:
            if "schema" not in case:
                continue
            path = (CONTRACTS / "fixtures/anniversary" / case["schema"]).resolve()
            relative = path.relative_to(CONTRACTS)
            v3 = CONTRACTS / "native_v3" / relative
            if not v3.is_file():
                continue
            value = validation.read_json(CONTRACTS / "fixtures/anniversary" / case["instance"])
            self.assertEqual(self.valid(relative, value), self.valid(v3.relative_to(CONTRACTS), value), case["name"])
            exercised += 1
        self.assertGreaterEqual(exercised, 15)

    def test_entity_identity_and_date_only_shape_are_not_weakened(self):
        fixtures = validation.read_json(CONTRACTS / "fixtures/sync/v1/native_v3_anniversary_vectors.json")
        case = next(item for item in fixtures["cases"] if item["id"] == "V3-entity-opaque")
        for field, value in (("id", "not-a-uuid"), ("date", "2026-02-30"), ("timezone", "Asia/Shanghai")):
            mutant = copy.deepcopy(case["value"]); mutant[field] = value
            self.assertFalse(self.valid(case["v3_schema"], mutant), field)


if __name__ == "__main__":
    unittest.main()
