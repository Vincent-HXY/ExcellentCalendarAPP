"""Run the protocol/lifecycle reference checks and bind evidence to exact sources."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTRACTS = ROOT / "contracts"
sys.path[:0] = [str(CONTRACTS), str(HERE), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_protocol_contracts import derive as protocol
from build_sync_import_contracts import derive as imports
from build_sync_lifecycle_contracts import derive as lifecycle
from build_sync_error_contracts import derive as errors
from build_sync_conflict_contracts import derive as conflicts
from build_backend_sync_revision import derive as backend
from build_private_lifecycle_contracts import derive as private_lifecycle


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--report", type=Path, default=HERE / "protocol_spike_result.json")
    args = parser.parse_args()
    patterns = ("test_sync_protocol.py", "test_sync_protocol_fixtures.py", "test_sync_lifecycle.py", "test_sync_errors.py", "test_sync_conflict_contracts.py", "test_sync_backend_revision.py", "test_sync_terminal_binding.py")
    suite = unittest.TestSuite(unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern=p) for p in patterns)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    generated = {**protocol(), **imports(), **lifecycle(), **errors(), **conflicts(), **backend(), **private_lifecycle()}
    sources = list(generated) + [CONTRACTS / "tests" / p for p in patterns]
    sources += [HERE / name for name in ("run_protocol_spike.py", "build_sync_protocol_contracts.py", "build_sync_import_contracts.py",
        "build_sync_lifecycle_contracts.py", "build_sync_error_contracts.py", "build_protocol_fixtures.py", "protocol_reference.py",
        "lifecycle_reference.py", "resolution_contract_reference.py", "domain_reference.py", "schema_validation_reference.py", "counter_reference.py", "identity_reference.py", "sqlite_reference.py", "build_sync_conflict_contracts.py", "build_backend_sync_revision.py", "build_owned_graph_fixtures.py", "build_target_fixtures.py", "build_private_lifecycle_contracts.py")]
    sources += [CONTRACTS / name for name in ("sync/sync_protocol_invariants.yaml", "sync/sync_field_registry.yaml", "sync/sync_counter_registry.yaml",
        "sync/sync_habit_operation_protocol.yaml", "fixtures/sync/v1/protocol_vectors.json", "fixtures/sync/v1/target_vectors.json", "error_codes.yaml", "search/search_history_response.schema.json")]
    # Hash the entire referenced Schema graph, including protected legacy leaves.
    from validate_sync_v1 import validate_schemas
    schema_map, _ = validate_schemas()
    pending = list(generated.values())
    visited = set()
    from urllib.parse import urljoin, urldefrag
    from validate_sync_v1 import walk
    while pending:
        schema = pending.pop()
        if not isinstance(schema, dict) or "$id" not in schema:
            continue
        uri = schema["$id"]
        if uri in visited:
            continue
        visited.add(uri)
        path = CONTRACTS / uri.removeprefix("https://excellent-calendar.local/contracts/")
        sources.append(path)
        for node in walk(schema):
            if isinstance(node, dict) and "$ref" in node:
                target = urldefrag(urljoin(uri, node["$ref"]))[0]
                pending.append(schema_map[target])
    report = {"spike_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
        "generated_schemas": sum(p.suffix == ".json" for p in generated),
        "fixed_cases": len(json.loads((CONTRACTS / "fixtures/sync/v1/protocol_vectors.json").read_text(encoding="utf-8"))["cases"]),
        "scope": "planned schema shapes; real SQLite sequence/causal/ack/notice transactions; pure lifecycle decisions",
        "full_owned_graph_import_bootstrap_engine_verified": False, "android_keystore_verified": False,
        "four_language_consumers_verified": False, "product_owners_implemented": False,
        "errors": [str(test) + ": " + error for test, error in result.errors + result.failures],
        "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for p in sorted(set(sources))}}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "generated_schemas", "fixed_cases")}))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
