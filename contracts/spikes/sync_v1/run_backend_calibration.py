"""Build current Backend, execute disposable HTTP audit, validate nested responses independently.

No production source or dependency is changed. This report observes mismatches; it does not
label planned sync behavior implemented. Test tokens are redacted in Java before any file I/O.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from urllib.parse import urldefrag, urljoin

ROOT = Path(__file__).resolve().parents[3]
SPIKE = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT / "contracts"), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from validate_sync_v1 import read_json, read_yaml, validate_schemas, Draft202012Validator, FormatChecker, walk


def source_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def run(args: list[str], log: Path, *, env: dict | None = None, cwd: Path = ROOT) -> None:
    with log.open("wb") as output:
        completed = subprocess.run(args, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=360)
    if completed.returncode:
        # Logs contain only the disposable test application's output, not raw HTTP payloads.
        raise RuntimeError(f"{Path(args[0]).name} failed ({completed.returncode}); inspect {log}")


def summarize_tests(path: Path) -> dict:
    suites = [ET.parse(p).getroot() for p in sorted(path.glob("TEST-*.xml"))]
    result = {key: sum(int(suite.get(key, "0")) for suite in suites)
              for key in ("tests", "failures", "errors", "skipped")}
    result["suites"] = [{"name": s.get("name"), "tests": int(s.get("tests", "0"))} for s in suites]
    if not suites or not result["tests"] or any(result[key] for key in ("failures", "errors", "skipped")):
        raise RuntimeError("Backend verification is incomplete: " + str(result))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=SPIKE / "backend_http_calibration_result.json")
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-contract-http-"))
    report = {"audit_version": 1, "rule_anchor": "cloud-sync-02/3", "passed": False,
              "product_sync_implementation": False, "errors": []}
    try:
        backend = ROOT / "cloud_backend"
        env = dict(os.environ, JAVA_HOME=str(args.jdk))
        run([str(backend / ("mvnw.cmd" if os.name == "nt" else "mvnw")), "--batch-mode", "verify"],
            scratch / "verify.log", env=env, cwd=backend)
        report["unit"] = summarize_tests(backend / "target/surefire-reports")
        report["integration"] = summarize_tests(backend / "target/failsafe-reports")
        xml = ET.parse(next((backend / "target/surefire-reports").glob("TEST-*.xml")))
        classpath = next(p.get("value") for p in xml.findall("./properties/property")
                         if p.get("name") == "java.class.path")
        classes = scratch / "classes"
        classes.mkdir()
        arguments = ["-encoding", "UTF-8", "--release", "21", "-cp", classpath,
                     "-d", str(classes), str(SPIKE / "BackendCalibrationProbe.java")]
        argfile = scratch / "javac.args"
        # Java @argfile quoting, not shell quoting. No shell interpolates any payload.
        argfile.write_text("\n".join('"' + v.replace("\\", "/").replace('"', '\\"') + '"'
                                     for v in arguments), encoding="utf-8")
        run([str(args.jdk / "bin/javac.exe"), "@" + str(argfile)], scratch / "javac.log")
        observed = scratch / "observed.json"
        run([str(args.jdk / "bin/java.exe"), "-Dfile.encoding=UTF-8", "-Djava.awt.headless=true",
             "-Dexcellent-calendar.media.avatar.dir=" + str(scratch / "avatars"),
             "-cp", str(classes) + os.pathsep + classpath,
             "com.excellentcalendar.cloud.BackendCalibrationProbe", str(observed)], scratch / "http.log", cwd=backend)
        raw = read_json(observed)
        if raw["passed"] is not True:
            raise RuntimeError("HTTP probe incomplete")
        schemas, registry = validate_schemas()
        contract = read_yaml(ROOT / "contracts/backend_api.yaml")
        checker = FormatChecker()
        for case in raw["cases"]:
            endpoint = contract["endpoints"][case["operation"]]
            paths = ["common/api_result.schema.json"]
            if case["response"]["ok"]:
                paths.append(endpoint["result"]["data"])
            errors = []
            for path in paths:
                value = case["response"] if path.startswith("common/api_result") else case["response"]["data"]
                schema = read_json(ROOT / "contracts" / path)
                validator = Draft202012Validator(schema, registry=registry, format_checker=checker)
                for error in validator.iter_errors(value):
                    # Error messages may echo data. Persist location/keyword only, never instance.
                    errors.append({"schema": path, "instance_path": list(error.absolute_path),
                                   "schema_path": list(error.absolute_schema_path), "keyword": error.validator})
            case["current_schema_errors"] = errors
        report["http"] = raw
        report["observed_operations"] = sorted({case["operation"] for case in raw["cases"]})
        if set(report["observed_operations"]) != set(contract["endpoints"]):
            raise RuntimeError("HTTP operation coverage differs from the 17 declared endpoints")
        report["source_sha256"] = {
            p.relative_to(ROOT).as_posix(): source_hash(p) for p in sorted(set(
                list((backend / "src").rglob("*.java")) + list((backend / "src").rglob("*.yml")) +
                list((backend / "src").rglob("*.sql")) + [backend / "pom.xml", SPIKE / "BackendCalibrationProbe.java",
                Path(__file__).resolve(), ROOT / "contracts/backend_api.yaml"]))}
        prefix = "https://excellent-calendar.local/contracts/"
        closure = {prefix + path for endpoint in contract["endpoints"].values()
                   for path in (endpoint["request"], endpoint["result"]["data"], endpoint["result"]["envelope"])}
        pending = list(closure)
        while pending:
            schema_id = pending.pop()
            for node in walk(schemas[schema_id]):
                if "$ref" in node:
                    target = urldefrag(urljoin(schema_id, node["$ref"]))[0]
                    if target not in closure:
                        closure.add(target)
                        pending.append(target)
        report["contract_schema_sha256"] = {
            "contracts/" + identifier.removeprefix(prefix): source_hash(ROOT / "contracts" / identifier.removeprefix(prefix))
            for identifier in sorted(closure)}
        report["compiled_probe_sha256"] = hashlib.sha256(
            (classes / "com/excellentcalendar/cloud/BackendCalibrationProbe.class").read_bytes()).hexdigest()
        report["passed"] = True
    except Exception as error:
        report["errors"].append(str(error))
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "scratch": str(scratch), "errors": report["errors"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
