"""Source-bound combined journal, ordinary apply and bootstrap recovery evidence."""
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
from build_local_intent_fixtures import derive, FIXTURE
import test_sync_local_intent_fixtures as fixed_checks
import test_sync_local_download as crash_checks
from validate_sync_v1 import validate_schemas, walk


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "real isolated SQLite pending/failed journals, ordinary typed apply, complete bootstrap rebase, Habit lost receipts and process death",
        "production_owners_implemented": False, "import_publication_and_resolution_writers_verified": False,
        "four_language_consumers_verified": False}
    fixed_checks.OBSERVED.clear()
    crash_checks.CRASH_POINTS.clear()
    suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_local_*.py")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    report["tests_run"] = result.testsRun
    report["cases"] = [{**row, "passed": row["actual"] == derive()["cases"][index]["expected"]}
        for index, row in enumerate(fixed_checks.OBSERVED)]
    report["errors"] = [error for _, error in result.errors + result.failures]
    if len(report["cases"]) != len(derive()["cases"]):
        report["errors"].append("Local intent fixed cases incomplete")
    report["actual_process_death_points"] = crash_checks.CRASH_POINTS[:]
    report["passed"] = result.wasSuccessful() and not report["errors"] and all(row["passed"] for row in report["cases"])
    sources = [Path(__file__), FIXTURE,
        *[ROOT / "contracts/tests" / name for name in ("test_sync_local_projection.py", "test_sync_local_intents.py",
            "test_sync_local_download.py", "test_sync_local_intent_fixtures.py", "test_sync_protocol.py")],
        *[HERE / name for name in ("build_local_intent_fixtures.py", "local_projection_reference.py", "local_intent_reference.py",
            "local_download_reference.py", "local_intent_crash_probe.py", "bootstrap_reference.py", "build_bootstrap_fixtures.py",
            "build_target_fixtures.py", "build_habit_operation_fixtures.py", "habit_operation_reference.py", "owned_graph_reference.py",
            "cursor_reference.py", "protocol_reference.py", "resolution_contract_reference.py", "owned_resolution_reference.py", "owned_sequence_reference.py", "domain_reference.py", "schema_validation_reference.py", "counter_reference.py", "identity_reference.py", "sqlite_reference.py")],
        *[ROOT / "contracts" / name for name in ("sync/sync_local_intent_protocol.yaml", "sync/sync_habit_operation_protocol.yaml",
            "sync/sync_field_registry.yaml", "sync/sync_protocol_invariants.yaml", "sync/sync_bootstrap_protocol.yaml",
            "sync/sync_cursor_protocol.yaml", "fixtures/sync/v1/target_vectors.json")]]
    schemas, _ = validate_schemas()
    prefix = "https://excellent-calendar.local/contracts/"
    pending = [schemas[prefix + name] for name in ("sync/sync_bootstrap_page_response.schema.json", "sync/sync_mutation.schema.json",
        "sync/sync_upload_result.schema.json", "sync/sync_exchange_response.schema.json", "sync/v1/sync_fact.schema.json")]
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
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        for path in sorted(set(sources))}
    (HERE / "local_intent_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "actual_process_death_points", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
