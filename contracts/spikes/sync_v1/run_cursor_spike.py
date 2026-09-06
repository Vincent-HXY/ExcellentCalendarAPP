"""Independent Java/Python HMAC cursor bytes and rejection classification."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_cursor_fixtures import derive, FIXTURE
from test_sync_cursors import run_case


def main():
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-cursor-contract-"))
    java_sources = [HERE / name for name in ("JcsProbe.java", "ProofSignatureProbe.java", "ProofCapsuleProbe.java", "CursorProbe.java")]
    report = {"spike_version": 1, "passed": False, "consumers": {}, "errors": [],
        "scope": "private binary HMAC cursor encoder/authenticator and pure key-retirement eligibility",
        "production_producer_implemented": False, "durable_key_retirement_ledger_verified": False,
        "materialized_bootstrap_and_page_apply_verified": False}
    try:
        fixtures = derive()
        if json.loads(FIXTURE.read_text(encoding="utf-8")) != fixtures: raise ValueError("cursor fixture drift")
        build = subprocess.run(["A:/Android/AndroidStudio/jbr/bin/javac.exe", "-encoding", "UTF-8", "-d", str(scratch), *map(str, java_sources)],
                               capture_output=True, encoding="utf-8", timeout=90)
        if build.returncode: raise ValueError(build.stderr[-3000:])
        run = subprocess.run(["A:/Android/AndroidStudio/jbr/bin/java.exe", "-cp", str(scratch), "CursorProbe"],
            input="\n".join(json.dumps(case["input"], ensure_ascii=False, separators=(",", ":")) for case in fixtures["cases"]) + "\n",
            capture_output=True, encoding="utf-8", timeout=45, check=True)
        expected = [row["expected"]["output"] for row in fixtures["cases"]]
        for name, outputs in (("java21", run.stdout.splitlines()), ("python_contract_oracle", [run_case(row["input"]) for row in fixtures["cases"]])):
            if len(outputs) != len(expected): raise ValueError(name + " omitted cursor cases")
            mismatched = [case["id"] for case, actual, wanted in zip(fixtures["cases"], outputs, expected) if actual != wanted]
            report["consumers"][name] = {"passed": not mismatched, "cases": len(outputs),
                "actual_output_sha256": hashlib.sha256(("\n".join(outputs) + "\n").encode()).hexdigest(), "mismatched": mismatched}
            if mismatched: report["errors"].append(name + ": " + ",".join(mismatched))
        suite = unittest.defaultTestLoader.discover(str(ROOT / "contracts/tests"), pattern="test_sync_cursors.py")
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        report["tests_run"] = result.testsRun
        if not result.wasSuccessful(): report["errors"].extend(error for _, error in result.errors + result.failures)
        report["passed"] = not report["errors"]
    except Exception as error: report["errors"].append(str(error))
    sources = [Path(__file__), FIXTURE, *java_sources, ROOT / "contracts/tests/test_sync_cursors.py",
        ROOT / "contracts/sync/sync_cursor_protocol.yaml",
        *[HERE / name for name in ("cursor_reference.py", "build_cursor_fixtures.py", "counter_reference.py", "identity_reference.py", "domain_reference.py", "schema_validation_reference.py")]]
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "cursor_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "consumers", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
