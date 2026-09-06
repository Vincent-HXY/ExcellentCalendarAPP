"""Source-bound owned-graph/SQLite evidence, separate from transport and product code."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts"), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_owned_graph_fixtures import derive, FIXTURE


def main():
    suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_owned_graph.py")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    sources = [Path(__file__), FIXTURE, ROOT / "contracts/tests/test_sync_owned_graph.py",
        *[HERE / name for name in ("owned_graph_reference.py", "build_owned_graph_fixtures.py", "build_target_fixtures.py",
            "domain_reference.py", "schema_validation_reference.py", "identity_reference.py", "protocol_reference.py", "counter_reference.py", "sqlite_reference.py",
            "build_sync_protocol_contracts.py", "build_sync_domain_contracts.py")],
        ROOT / "contracts/sync/sync_field_registry.yaml", ROOT / "contracts/sync/sync_protocol_invariants.yaml",
        ROOT / "contracts/sync/sync_mutation.schema.json", ROOT / "contracts/sync/sync_owned_dependency.schema.json",
        *sorted((ROOT / "contracts/sync/v1").glob("*.schema.json"))]
    report = {"spike_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
        "fixed_case_ids": [row["id"] for row in derive()["cases"]], "rollback_boundaries": 4,
        "scope": "owned candidate closure, recurrence collision components, independent root fields, real SQLite atomicity and response-loss replay",
        "production_owner_implemented": False, "combined_transport_and_child_causal_evidence_verified": False,
        "errors": [str(test) + ": " + error for test, error in result.errors + result.failures],
        "source_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}}
    (HERE / "owned_graph_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "rollback_boundaries", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
