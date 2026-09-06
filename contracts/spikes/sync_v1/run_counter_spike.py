#!/usr/bin/env python3
"""Execute the counter Contract model and retain source-bound test evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONTRACTS = HERE.parents[1]
ROOT = CONTRACTS.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    cache = Path(tempfile.gettempdir()) / f"excellent-calendar-contract-validation-py{sys.version_info.major}{sys.version_info.minor}"
    sys.path.insert(0, str(cache))
    sys.path.insert(0, str(CONTRACTS))
    import yaml
    registry = yaml.safe_load((CONTRACTS / "sync/sync_counter_registry.yaml").read_text(encoding="utf-8"))
    fixtures = json.loads((CONTRACTS / "fixtures/sync/v1/counter_vectors.json").read_text(encoding="utf-8"))
    suite = unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern="test_sync_counters.py")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    sources = [Path(__file__), HERE / "counter_reference.py", HERE / "sqlite_reference.py", CONTRACTS / "tests/test_sync_counters.py",
               CONTRACTS / "sync/sync_counter_registry.yaml", CONTRACTS / "fixtures/sync/v1/counter_vectors.json"]
    report = {"spike_version": 1, "passed": result.wasSuccessful(), "tests_run": result.testsRun,
              "kind": "real_sqlite_transaction_contract_reference_model", "product_owners_implemented": False,
              "four_language_consumers_verified": False, "counter_kinds": len(registry["counter_kinds"]),
              "boundary_golden_cases": len(fixtures["cases"]), "concurrent_double_write_cases": 2 * len(registry["counter_kinds"]),
              "durable_replay_cases": len(registry["counter_kinds"]), "rollback_cases": len(registry["counter_kinds"]),
              "runtime": {"python": platform.python_version(), "sqlite": sqlite3.sqlite_version},
              "errors": [str(test) + ": " + error for test, error in result.errors + result.failures],
              "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_text(encoding="utf-8").encode()).hexdigest() for p in sources}}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "counter_kinds", "boundary_golden_cases", "concurrent_double_write_cases")}))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
