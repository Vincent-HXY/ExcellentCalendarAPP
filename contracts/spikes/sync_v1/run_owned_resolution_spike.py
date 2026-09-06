"""Run the owned resolution component and record reproducible evidence."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import urldefrag, urljoin

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
    str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_owned_resolution_fixtures import derive, FIXTURE
import test_sync_owned_resolution as checks
from validate_sync_v1 import validate_schemas, walk


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "Event immutable revision and mutable reminder resolution with shared sequence/receipt, actual local apply/bootstrap and retained manual drafts",
        "production_owners_implemented": False, "all_owned_lifecycles_and_import_verified": False,
        "deletion_cascades_verified": False, "four_language_consumers_verified": False}
    checks.OBSERVED.clear()
    checks.CRASH_POINTS.clear()
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromModule(checks))
    report["tests_run"] = result.testsRun
    fixed = derive()
    report["cases"] = [{**row, "passed": row["actual"] == fixed["cases"][index]["expected"]} for index, row in enumerate(checks.OBSERVED)]
    report["errors"] = [error for _, error in result.errors + result.failures]
    if len(report["cases"]) != len(fixed["cases"]):
        report["errors"].append("Owned resolution fixed cases incomplete")
    report["actual_process_death_points"] = checks.CRASH_POINTS[:]
    report["passed"] = result.wasSuccessful() and not report["errors"] and all(row["passed"] for row in report["cases"])
    sources = [Path(__file__), FIXTURE,
        *[ROOT / "contracts/tests" / name for name in ("test_sync_owned_resolution.py", "test_sync_owned_sequence.py")],
        *[HERE / name for name in ("build_owned_resolution_fixtures.py", "owned_resolution_reference.py", "owned_resolution_crash_probe.py",
            "owned_sequence_reference.py", "build_owned_sequence_fixtures.py", "conflict_resolution_reference.py", "resolution_contract_reference.py",
            "notice_projection_reference.py", "local_intent_reference.py", "local_download_reference.py", "local_projection_reference.py",
            "bootstrap_reference.py", "build_bootstrap_fixtures.py", "build_target_fixtures.py", "build_owned_graph_fixtures.py",
            "habit_operation_reference.py", "owned_graph_reference.py", "protocol_reference.py", "domain_reference.py", "schema_validation_reference.py", "identity_reference.py",
            "counter_reference.py", "cursor_reference.py", "sqlite_reference.py")],
        *[ROOT / "contracts" / name for name in ("sync/sync_owned_resolution_protocol.yaml", "sync/sync_owned_protocol.yaml", "sync/sync_conflict_protocol.yaml",
            "sync/sync_local_intent_protocol.yaml", "sync/sync_habit_operation_protocol.yaml", "sync/sync_notice_protocol.yaml", "sync/sync_field_registry.yaml",
            "sync/sync_protocol_invariants.yaml", "sync/sync_bootstrap_protocol.yaml", "sync/sync_cursor_protocol.yaml", "sync/sync_error_registry.yaml",
            "fixtures/sync/v1/target_vectors.json", "fixtures/sync/v1/owned_graph_vectors.json")]]
    schemas, _ = validate_schemas()
    prefix = "https://excellent-calendar.local/contracts/"
    pending = [schemas[prefix + name] for name in ("sync/sync_conflict_resolution_mutation.schema.json", "sync/backend_sync_conflict_resolution_response.schema.json",
        "sync/sync_bootstrap_page_response.schema.json", "sync/sync_mutation.schema.json", "sync/sync_upload_result.schema.json", "sync/sync_exchange_response.schema.json")]
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
    (HERE / "owned_resolution_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "actual_process_death_points", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
