"""Pair all 17 old HTTP declarations with compiled nested DTO constraints and target disposition."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(ROOT / "contracts"), str(HERE), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from validate_sync_v1 import read_json, read_yaml, validate_spike_sources, validate_schemas, walk
from urllib.parse import urljoin, urldefrag


def sha(path): return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def main():
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-backend-shape-"))
    report = {"audit_version": 1, "passed": False, "errors": [], "endpoints": [],
        "scope": "compiled DTO nested Bean Validation metadata, complete request/response Schema closure, declared errors and existing HTTP dispositions",
        "production_corrections_implemented": False, "all_business_error_paths_executed": False}
    try:
        old = read_yaml(ROOT / "contracts/backend_api.yaml")
        target = read_yaml(ROOT / "contracts/backend_sync_v1/backend_api.yaml")
        inventory = read_json(ROOT / "contracts/sync/backend_calibration_audit.json")
        http = read_json(HERE / "backend_http_calibration_result.json")
        validate_spike_sources(http)
        dto_paths = {path.stem: path for area in ("identity/api", "userdevice/api")
            for path in (ROOT / "cloud_backend/src/main/java/com/excellentcalendar/cloud" / area).glob("*Dto.java")}
        roots = sorted({name for row in inventory["endpoints"] for name in (row.get("request_dto"), row.get("response_dto")) if name})
        classes = {name: path.read_text(encoding="utf-8").split("package ", 1)[1].split(";", 1)[0].strip() + "." + name for name, path in dto_paths.items()}
        request = scratch / "roots.json"; request.write_text(json.dumps([classes[name] for name in roots]), encoding="utf-8")
        compiled = scratch / "classes"; compiled.mkdir()
        xml = ET.parse(next((ROOT / "cloud_backend/target/surefire-reports").glob("TEST-*.xml")))
        classpath = next(row.get("value") for row in xml.findall("./properties/property") if row.get("name") == "java.class.path")
        args = ["-encoding", "UTF-8", "--release", "21", "-cp", classpath, "-d", str(compiled), str(HERE / "BackendShapeProbe.java")]
        argfile = scratch / "javac.args"
        argfile.write_text("\n".join('"' + value.replace("\\", "/").replace('"', '\\"') + '"' for value in args), encoding="utf-8")
        for command, log in ((["A:/Android/AndroidStudio/jbr/bin/javac.exe", "@" + str(argfile)], "javac.log"),
            (["A:/Android/AndroidStudio/jbr/bin/java.exe", "-Dfile.encoding=UTF-8", "-cp", str(compiled) + os.pathsep + classpath,
                "BackendShapeProbe", str(request), str(scratch / "observed.json")], "java.log")):
            with (scratch / log).open("wb") as output:
                result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=60)
            if result.returncode: raise ValueError(str(scratch / log) + ": " + (scratch / log).read_text(encoding="utf-8")[-2000:])
        observed = read_json(scratch / "observed.json")
        report["compiled_dtos"] = observed
        schemas, _ = validate_schemas()
        base = "https://excellent-calendar.local/contracts/"
        for row in inventory["endpoints"]:
            operation = row["operation"]
            entry = {"operation": operation, "method": row["method"], "path": row["path"], "current_controller_present": row["source_status"] == "controller_present",
                "current_idempotency": row["idempotency"], "current_declared_error_http_status": row["error_statuses_from_backend_enum"],
                "declaration_only_errors_requiring_04_enum_producer": row["declared_errors_missing_backend_enum"],
                "target_implementation_status": target["endpoints"][operation]["implementation_status"],
                "observed_http_case_ids": [case["id"] for case in http["http"]["cases"] if case["operation"] == operation],
                "current_declared_error_status": row["declared_business_http_status"],
                "target_error_status_policy": "sync_error_registry semantic HTTP status plus ApiResult; old 200-only rule retained only in frozen legacy revision"}
            for direction in ("request", "response"):
                path = row[direction + "_schema"]
                dto = row.get(direction + "_dto")
                closure, pending = {}, [base + path]
                while pending:
                    uri = pending.pop()
                    if uri in closure: continue
                    closure[uri] = schemas[uri]
                    for node in walk(schemas[uri]):
                        if "$ref" in node: pending.append(urldefrag(urljoin(uri, node["$ref"]))[0])
                entry[direction] = {"current_schema": path,
                    "target_schema": target["endpoints"][operation]["request"] if direction == "request" else target["endpoints"][operation]["result"]["data"],
                    "current_jvm_dto": classes[dto] if dto else None,
                    "schema_closure": {uri.removeprefix(base): sha(ROOT / "contracts" / uri.removeprefix(base)) for uri in sorted(closure)},
                    "shape_rule": "strict exact keys/types/null/union in target Schema; reject scalar coercion and unknown fields before DTO binding"}
                if dto:
                    fields = observed["records"][classes[dto]]["fields"]
                    if sorted(fields) != row[direction + "_schema_fields"]: raise ValueError(operation + " reflected wire fields differ")
                    entry[direction]["top_level_field_match"] = True
                else:
                    entry[direction]["non_dto_reason"] = "controller_absent" if not entry["current_controller_present"] else "no_json_body_or_multipart_binary_schema"
            report["endpoints"].append(entry)
        report["dispositions"] = {
            "java_string_size": "Bean Validation Size(String) counts UTF-16 code units; Contract lengths count Unicode code points. 04 must validate target Schema/code points before DTO binding and remove narrower duplicate constraints in the same compatibility release.",
            "nullable_and_union": "Bean constraints, required JSON members, exact nested unions and service-domain checks are separate gates; @Valid metadata is recorded recursively and never substitutes for the target Schema.",
            "idempotency": "Existing register JSON and avatar multipart replay old success on changed content; accepted ADR-Sync-06 requires typed request digest and HTTP 409 API_IDEMPOTENCY_KEY_REUSED.",
            "unknown_and_coercion": "Existing 39 HTTP cases expose ignored unknown fields and numeric password coercion; target rejects both for every request, including nested credential.",
            "profile_preferences": "Target registration locale zh-CN, profile writer username/display_name only, four portable preferences with separate revisions; old locale/settings preserved only by the documented migration/read compatibility.",
            "http_errors": "Semantic status/retry mirror is observed; each old declared error is mapped above, missing producers remain explicit 04 work. The absent registration-email PATCH remains unavailable.",
        }
        report["compiled_probe_sha256"] = hashlib.sha256((compiled / "BackendShapeProbe.class").read_bytes()).hexdigest()
        report["compiled_dto_sha256"] = {name: hashlib.sha256((ROOT / "cloud_backend/target/classes" / (name.replace(".", "/") + ".class")).read_bytes()).hexdigest()
            for name in observed["records"]}
        report["passed"] = len(report["endpoints"]) == 17 and sum(row["current_controller_present"] for row in report["endpoints"]) == 16
    except Exception as error: report["errors"].append(str(error))
    sources = [Path(__file__), HERE / "BackendShapeProbe.java", HERE / "backend_http_calibration_result.json",
        ROOT / "contracts/sync/backend_calibration_audit.json", ROOT / "contracts/backend_api.yaml", ROOT / "contracts/backend_sync_v1/backend_api.yaml"]
    sources += list((ROOT / "cloud_backend/src/main/java").rglob("*.java"))
    sources += list((ROOT / "cloud_backend/src/main/resources").glob("*.yml"))
    for row in report["endpoints"]:
        for direction in ("request", "response"):
            sources += [ROOT / "contracts" / name for name in row[direction]["schema_closure"]]
            sources.append(ROOT / "contracts" / row[direction]["target_schema"])
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(set(sources))}
    (HERE / "backend_shape_audit_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "endpoints": len(report["endpoints"]), "compiled_dtos": len(report.get("compiled_dtos", {}).get("records", {})), "errors": report["errors"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
