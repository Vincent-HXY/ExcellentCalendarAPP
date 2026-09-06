"""Run materialization/page integrity and actual process-death Contract checks."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_bootstrap_fixtures import derive, FIXTURE
import test_sync_bootstrap as checks


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "immutable snapshots, authenticated cursor pagination and fresh atomic local promotion in isolated SQLite",
        "production_implementation_verified": False, "combined_pending_failed_effect_rebase_verified": False,
        "postgresql_service_materialization_verified": False}
    try:
        if json.loads(FIXTURE.read_text(encoding="utf-8")) != derive(): raise ValueError("Bootstrap fixture drift")
        checks.OBSERVED.clear()
        suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_bootstrap.py")
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        report["tests_run"] = result.testsRun
        report["cases"] = checks.OBSERVED
        if not result.wasSuccessful(): report["errors"].extend(error for _, error in result.errors + result.failures)
        if len(report["cases"]) != len(derive()["cases"]): report["errors"].append("Bootstrap cases incomplete")
        report["actual_process_death_points"] = [*checks.SERVER_POINTS, "local_page_receipt", *checks.LOCAL_POINTS] if not report["errors"] else []
        report["passed"] = not report["errors"]
    except Exception as error: report["errors"].append(str(error))
    sources = [Path(__file__), FIXTURE, ROOT / "contracts/tests/test_sync_bootstrap.py",
        *[HERE / name for name in ("bootstrap_reference.py", "bootstrap_crash_probe.py", "build_bootstrap_fixtures.py", "build_target_fixtures.py",
            "cursor_reference.py", "protocol_reference.py", "counter_reference.py", "identity_reference.py", "domain_reference.py", "schema_validation_reference.py", "sqlite_reference.py")],
        *[ROOT / "contracts/sync" / name for name in ("sync_protocol_invariants.yaml", "sync_bootstrap_protocol.yaml", "sync_cursor_protocol.yaml", "sync_field_registry.yaml")]]
    from validate_sync_v1 import validate_schemas, walk
    from urllib.parse import urljoin, urldefrag
    schema_map, _ = validate_schemas()
    pending = [schema_map["https://excellent-calendar.local/contracts/sync/sync_bootstrap_page_response.schema.json"]]
    seen = set()
    while pending:
        schema = pending.pop(); uri = schema["$id"]
        if uri in seen: continue
        seen.add(uri); sources.append(ROOT / "contracts" / uri.removeprefix("https://excellent-calendar.local/contracts/"))
        for node in walk(schema):
            if "$ref" in node: pending.append(schema_map[urldefrag(urljoin(uri, node["$ref"]))[0]])
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "bootstrap_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report.get(key) for key in ("passed", "tests_run", "actual_process_death_points", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
