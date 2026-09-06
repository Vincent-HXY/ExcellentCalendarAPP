"""Execute capability boundary regressions and hash their complete Schema closure."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import urljoin, urldefrag

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTRACTS = ROOT / "contracts"
sys.path[:0] = [str(CONTRACTS), str(HERE), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_capability_graph import derive as graph
from build_sync_native_contracts import derive as native
from build_native_v3_business_contracts import derive as business
from build_sync_registry_revisions import derive as registries, REVISION_PATHS
from build_capability_fixtures import derive as fixtures
from validate_sync_v1 import validate_schemas, walk


def main():
    suite = unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern="test_sync_capabilities.py")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    outputs = {**business(), **native(), **graph(), **registries()}
    sources = set(outputs) | {CONTRACTS / name for name in REVISION_PATHS}
    sources.update(HERE / name for name in ("run_capability_spike.py", "build_native_v3_business_contracts.py", "build_sync_native_contracts.py",
        "build_sync_capability_graph.py", "build_sync_registry_revisions.py", "build_capability_fixtures.py", "capability_reference.py", "domain_reference.py", "schema_validation_reference.py"))
    sources.update(CONTRACTS / path for path in ("tests/test_sync_capabilities.py", "native_v3/anniversary_compatibility.json",
        "backend_sync_v1/backend_api.yaml", "backend_sync_v1/session_capabilities.yaml", "sync/sync_v1_baseline.json", "sync/sync_field_registry.yaml",
        "fixtures/sync/v1/capability_vectors.json", "fixtures/habit/prepare_habit_delivery.valid.json"))
    sources.update(ROOT / "cpp_core/include/excellent_calendar/domain" / name for name in ("event.hpp", "recurrence.hpp", "event_occurrence_state.hpp", "reminder.hpp"))
    schemas, _ = validate_schemas()
    pending = [value for value in outputs.values() if "$id" in value]
    visited = set()
    while pending:
        value = pending.pop()
        uri = value["$id"]
        if uri in visited:
            continue
        visited.add(uri)
        sources.add(CONTRACTS / uri.removeprefix("https://excellent-calendar.local/contracts/"))
        for node in walk(value):
            if "$ref" in node:
                pending.append(schemas[urldefrag(urljoin(uri, node["$ref"]))[0]])
    report = {"spike_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
        "fixed_cases": len(fixtures()["cases"]), "generated_schemas": sum(path.suffix == ".json" for path in outputs),
        "public_methods": len(outputs[CONTRACTS / "native_v3/method_channels.yaml"]["methods"]),
        "native_calls": len(outputs[CONTRACTS / "native_v3/native_calls.yaml"]["calls"]),
        "scope": "strict Schema, declared graph reachability, pure boundary/route rejection and protected legacy projection",
        "production_handlers_verified": False, "four_language_consumers_verified": False,
        "signature_authentication_verified": False, "cipher_open_authorized_by_shape_checks": False,
        "errors": [str(test) + ": " + error for test, error in result.errors + result.failures],
        "source_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(sources)}}
    (HERE / "capability_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "fixed_cases", "generated_schemas", "public_methods", "native_calls")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
