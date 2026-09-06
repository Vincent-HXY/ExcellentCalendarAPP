"""Run typed-domain/identity Contract examples with source-bound, fail-closed evidence."""
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
from build_sync_domain_contracts import derive
from validate_sync_v1 import read_json, read_yaml


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--report", type=Path, default=HERE / "domain_spike_result.json")
    args = parser.parse_args()
    suite = unittest.TestSuite(unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern=pattern)
                               for pattern in ("test_sync_identity.py", "test_sync_domains.py", "test_sync_legacy_identity.py"))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    generated = derive()
    registry = read_yaml(CONTRACTS / "sync/sync_field_registry.yaml")
    sources = list(generated) + [CONTRACTS / path for path in registry["source_projections_sha256"]]
    sources += [HERE / name for name in ("run_domain_spike.py", "build_sync_domain_contracts.py", "build_target_fixtures.py",
                                        "domain_reference.py", "schema_validation_reference.py", "identity_reference.py", "counter_reference.py", "sqlite_reference.py",
                                        "legacy_identity_reference.py", "build_legacy_identity_fixtures.py")]
    sources += [CONTRACTS / name for name in ("sync/sync_identity_registry.yaml", "fixtures/sync/v1/target_vectors.json",
                                            "tests/test_sync_identity.py", "tests/test_sync_domains.py", "tests/test_sync_legacy_identity.py")]
    report = {"spike_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
        "scope": "CT1 typed facts, patch groups, reference graph and persistent mapping oracle; full mutation/lifecycle protocol not yet delivered",
        "targets": len(registry["targets"]), "field_entries": sum(len(v["fields"]) for r in registry["targets"].values() for v in r["variants"].values()),
        "golden_cases": len(read_json(CONTRACTS / "fixtures/sync/v1/target_vectors.json")["cases"]),
        "product_owners_implemented": False, "four_language_consumers_verified": False,
        "errors": [str(test) + ": " + error for test, error in result.errors + result.failures],
        "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for p in sorted(set(sources))}}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "targets", "field_entries", "golden_cases")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
