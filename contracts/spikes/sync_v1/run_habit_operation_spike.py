"""Source-bound operation semantics, SQLite persistence, and abrupt process death."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import urljoin, urldefrag

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_habit_operation_fixtures import derive, FIXTURE
import test_sync_habit_operations as checks
from validate_sync_v1 import validate_schemas, walk


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "isolated Habit additive/nonadditive semantics combined with SQLite device ordering, receipts and restart",
        "production_owners_implemented": False, "combined_bootstrap_pending_rebase_verified": False,
        "four_language_consumers_verified": False}
    suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_habit_operations.py")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    report["tests_run"] = result.testsRun
    report["cases"] = [{**row, "passed": row["actual"] == derive()["cases"][i]["expected"]} for i, row in enumerate(checks.OBSERVED)]
    report["errors"] = [error for _, error in result.errors + result.failures]
    if len(report["cases"]) != len(derive()["cases"]):
        report["errors"].append("Habit operation fixed cases incomplete")
    report["passed"] = result.wasSuccessful() and not report["errors"] and all(row["passed"] for row in report["cases"])
    report["actual_process_death_points"] = checks.CRASH_POINTS if report["passed"] else []
    sources = [Path(__file__), FIXTURE, ROOT / "contracts/tests/test_sync_habit_operations.py",
        *[HERE / name for name in ("habit_operation_reference.py", "habit_operation_crash_probe.py", "build_habit_operation_fixtures.py",
            "protocol_reference.py", "domain_reference.py", "schema_validation_reference.py", "identity_reference.py", "counter_reference.py", "sqlite_reference.py", "build_sync_storage_contract.py")],
        *[ROOT / "contracts" / name for name in ("sync/sync_habit_operation_protocol.yaml", "sync/sync_field_registry.yaml",
            "sync/sync_protocol_invariants.yaml", "sync/sync_error_registry.yaml", "storage/calendar_core_storage.yaml", "fixtures/sync/v1/target_vectors.json")]]
    schemas, _ = validate_schemas()
    prefix = "https://excellent-calendar.local/contracts/"
    pending = [schemas[prefix + name] for name in ("sync/sync_mutation.schema.json", "sync/sync_upload_result.schema.json", "sync/v1/sync_fact.schema.json")]
    seen = set()
    while pending:
        schema = pending.pop()
        uri = schema["$id"]
        if uri in seen:
            continue
        seen.add(uri)
        sources.append(ROOT / "contracts" / uri.removeprefix(prefix))
        for node in walk(schema):
            if "$ref" in node:
                pending.append(schemas[urldefrag(urljoin(uri, node["$ref"]))[0]])
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "habit_operation_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({name: report[name] for name in ("passed", "tests_run", "actual_process_death_points", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
