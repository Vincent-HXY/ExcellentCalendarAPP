"""Run fixed shape/decision vectors while preserving their explicitly limited scope."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_protocol_fixtures import derive
from domain_reference import validate_schema
from lifecycle_reference import backend_capability, device_name, sync_phase, retry_delay, retention_due


DECISIONS = {f.__name__: f for f in (backend_capability, device_name, sync_phase, retry_delay, retention_due)}


def run_case(case):
    if case["validation"] == "schema_only":
        try:
            validate_schema(case["schema"], case["input"])
            valid = True
        except ValueError:
            valid = False
        return {"valid": valid}
    if case["validation"] != "reference_decision" or case["operation"] not in DECISIONS:
        raise AssertionError("Unknown fixture consumer")
    try:
        return {"value": DECISIONS[case["operation"]](**case["input"]), "error": None}
    except ValueError as error:
        return {"value": None, "error": str(error)}


class ProtocolFixtureTests(unittest.TestCase):
    def test_fixed_vectors(self):
        value = json.loads((ROOT / "contracts/fixtures/sync/v1/protocol_vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(value, derive())
        self.assertEqual(len({case["id"] for case in value["cases"]}), len(value["cases"]))
        for case in value["cases"]:
            with self.subTest(fixture=case["id"]):
                self.assertEqual(run_case(case), case["expected"])


if __name__ == "__main__":
    unittest.main()
