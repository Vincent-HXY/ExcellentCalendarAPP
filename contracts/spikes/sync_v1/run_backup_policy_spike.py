"""Check explicit backup resources and restore policy without invoking cloud or D2D."""
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
from build_backup_policy_fixtures import derive, FIXTURE
from validate_sync_v1 import read_json, validate_android_key_evidence
import test_sync_backup_policy as checks


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "25 synthetic data categories, API23/24/30/31/33 XML policy selection and two-destination restore decisions",
        "actual_cloud_transport_executed": False, "actual_device_transfer_executed": False,
        "api23_or_api24_os_executed": False, "production_restore_owner_implemented": False}
    try:
        validate_android_key_evidence(read_json(HERE / "android_key_spike_result.json"), read_json(HERE / "android_key_build_result.json"))
        if read_json(FIXTURE) != derive(): raise ValueError("Backup policy fixture drift")
        checks.OBSERVED.clear()
        result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_backup_policy.py"))
        report["tests_run"] = result.testsRun
        report["cases"] = checks.OBSERVED
        if not result.wasSuccessful(): report["errors"].extend(error for _, error in result.errors + result.failures)
        if len(report["cases"]) != len(derive()["cases"]): report["errors"].append("Backup policy cases incomplete")
        report["passed"] = not report["errors"]
    except Exception as error: report["errors"].append(str(error))
    sources = [Path(__file__), FIXTURE, ROOT / "contracts/tests/test_sync_backup_policy.py",
        *[HERE / name for name in ("backup_policy_reference.py", "build_backup_policy_fixtures.py", "build_android_key_contract.py", "identity_reference.py", "domain_reference.py", "schema_validation_reference.py",
                                  "android_key_spike_result.json", "android_key_build_result.json")],
        ROOT / "contracts/workspace/android_backup_policy_v1.yaml", *list((HERE / "android_key_probe/res").rglob("*.xml"))]
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "backup_policy_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report.get(key) for key in ("passed", "tests_run", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
