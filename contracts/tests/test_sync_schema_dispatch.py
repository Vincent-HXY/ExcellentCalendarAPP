"""Prove dispatch cannot relax unions or any remaining Schema assertion."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from domain_reference import definitions, read_json, FormatChecker
from cross_language_schema_reference import boundary_cases
from schema_validation_reference import compiled, DispatchedValidator
from jsonschema import Draft202012Validator


class SchemaDispatchTests(unittest.TestCase):
    def test_reviewed_schema_boundaries_match_original_validator(self):
        cases = boundary_cases()
        checked = 0
        registry, _ = definitions()
        for case in cases:
            if case.get("malformed_json"):
                continue
            value = json.loads(case["input_json"])
            expected = Draft202012Validator(read_json(ROOT / "contracts" / case["schema"]), registry=registry,
                                           format_checker=FormatChecker()).is_valid(value)
            self.assertEqual(expected, case["valid"], case["id"])
            self.assertEqual(compiled(case["schema"]).is_valid(value), expected, case["id"])
            checked += 1
        self.assertGreaterEqual(checked, 385)

    def test_overlap_optional_discriminant_bool_numeric_and_nested_assertions_remain_exact(self):
        schemas = [
            {"oneOf": [{"properties": {"kind": {"const": "a"}}}, {"properties": {"kind": {"const": "b"}}}]},
            {"oneOf": [{"properties": {"kind": {"const": 1}}}, {"properties": {"kind": {"const": True}}}]},
            {"oneOf": [{"properties": {"kind": {"const": "a"}}}, {"properties": {"kind": {"const": "a"}}}]},
            {"oneOf": [True, False]}, {"oneOf": [True, True]},
            {"oneOf": [{"type": "object", "required": ["kind", "count"], "additionalProperties": False,
                "properties": {"kind": {"const": "a"}, "count": {"type": "integer", "minimum": 0, "maximum": 2}}},
                {"type": "array", "items": {"type": "string"}}]},
        ]
        values = [{}, {"kind": "a"}, {"kind": "b"}, {"kind": 1}, {"kind": True}, {"kind": 1.0}, {"kind": None},
                  {"kind": "a", "count": -1}, {"kind": "a", "count": 2}, {"kind": "a", "count": True},
                  {"kind": "a", "count": 2, "extra": None}, [], [1], ["x"], None, 0]
        for schema in schemas:
            for value in values:
                self.assertEqual(DispatchedValidator(schema).is_valid(value), Draft202012Validator(schema).is_valid(value), (schema, value))


if __name__ == "__main__":
    unittest.main()
