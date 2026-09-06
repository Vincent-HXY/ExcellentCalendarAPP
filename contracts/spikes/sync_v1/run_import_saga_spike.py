"""Run the delivered import components and bind their actual evidence to source.

Passing this component report does not certify the remaining full lifecycle,
all-language consumers or product implementation.
"""
import json
from pathlib import Path
import sys
import time
import unittest

from run_import_capacity_spike import hashes, sources

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def test_ids(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from test_ids(test)
        else:
            yield test.id()


def main():
    files = sorted((ROOT / "contracts/tests").glob("test_sync_import_*.py"))
    paths = sources([Path(__file__), *files])
    before = hashes(paths)
    suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_import_*.py")
    cases = list(test_ids(suite))
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    after = hashes(paths)
    errors = [str(test) + ": " + message for test, message in result.errors + result.failures]
    if before != after:
        errors.append("Source changed during workload; rerun required")
    modules = sorted({name.split(".")[0] for name in cases})
    report = {"spike_version": 1, "passed": result.wasSuccessful() and before == after,
        "tests_run": result.testsRun, "test_case_ids": cases, "seconds": round(time.monotonic() - started, 3),
        "components": {name: {"test_count": sum(value.startswith(name + ".") for value in cases),
            "actual_process_exit_points": getattr(sys.modules[name], "CRASH_POINTS", [])} for name in modules},
        "errors": errors, "source_sha256": after, "production_implemented": False,
        "complete_import_lifecycle_verified": False, "all_language_consumers_verified": False,
        "scope": "Actual isolated SQLite staging, publication, download/bootstrap, source lease, cleanup, status, range proofs and server successor components",
        "remaining": ["full client successor lease journal and fresh lifecycle recovery composition",
            "trusted crypto-destroy release composition", "complete owned conflict graph resolution in import",
            "all applicable fixture consumers and revision acceptance"]}
    (HERE / "import_saga_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({name: report[name] for name in ("passed", "tests_run", "seconds", "errors")}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
