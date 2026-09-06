"""Run full typed import, fresh recovery, policy and maintenance composition."""
import json
from pathlib import Path
import sys
import time
import unittest

from run_import_capacity_spike import hashes, sources
from run_import_saga_spike import test_ids

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PATTERNS = ("test_sync_full_import.py", "test_sync_fresh_import.py", "test_sync_policy_maintenance.py", "test_sync_private_lifecycle.py")


def main():
    paths = sources([Path(__file__), *[ROOT / "contracts/tests" / name for name in PATTERNS]])
    before = hashes(paths)
    suite = unittest.TestSuite(unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern=name) for name in PATTERNS)
    cases = list(test_ids(suite))
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    after = hashes(paths)
    errors = [str(test) + ": " + error for test, error in result.errors + result.failures]
    if before != after:
        errors.append("Source changed during workload; rerun required")
    report = {"spike_version": 1, "passed": result.wasSuccessful() and before == after, "tests_run": result.testsRun,
        "test_case_ids": cases, "seconds": round(time.monotonic() - started, 3), "errors": errors, "source_sha256": after,
        "components": {Path(name).stem: {"test_count": sum(case.startswith(Path(name).stem + ".") for case in cases),
            "actual_process_exit_points": getattr(sys.modules[Path(name).stem], "CRASH_POINTS", [])} for name in PATTERNS},
        "production_implemented": False, "android_lifecycle_owner_implemented": False, "all_language_consumers_verified": False,
        "scope": "Actual isolated dual SQLite freeze/publish/cleanup, successor and fresh fence/bootstrap recovery; persisted latest policy receipt and bounded maintenance"}
    (HERE / "client_recovery_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({name: report[name] for name in ("passed", "tests_run", "seconds", "errors")}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
