"""Read-only CT0 source inventory. Does not certify HTTP behavior or release state."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

PREFIX = "cloud_backend/src/main/java/com/excellentcalendar/cloud/"


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_text(encoding="utf-8").replace("\r\n", "\n").encode()).hexdigest()


def wire_name(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def record_fields(path: Path) -> list[str]:
    source = path.read_text(encoding="utf-8")
    header = re.search(r"public record \w+(?:<[^>]+>)?\((.*?)\)\s*\{", source, re.S)
    if not header:
        raise AssertionError(f"No Java record header in {path.name}")
    types = r"(?:String|UUID|Instant|boolean|Boolean|Integer|T|\w+Dto|\w+Response|List<[^>]+>|Map<[^>]+>)"
    return sorted(wire_name(name) for name in re.findall(r"\b" + types + r"\s+(\w+)\s*[,)]", header[1] + ")"))


def collect(contract: dict, root: Path) -> dict:
    sources: dict[str, str] = {}
    def read(path: Path) -> str:
        sources[path.relative_to(root).as_posix()] = file_hash(path)
        return path.read_text(encoding="utf-8")

    packages = [root / PREFIX / p for p in ("identity/api", "userdevice/api")]
    dtos = {p.stem: p for package in packages for p in package.glob("*Dto.java")}
    routes = {}
    pattern = re.compile(r"@(Get|Post|Patch|Delete)Mapping(\([^\n]*\))?\s+public\s+ApiResultResponse<(\w+)>\s+(\w+)\(([^{};]*?)\)\s*(?:throws\s+[\w.,\s]+)?\{", re.S)
    for package in packages:
        for path in sorted(package.glob("*Controller.java")):
            source = read(path)
            base = re.search(r'@RequestMapping\("([^"\n]+)"\)', source)
            if not base:
                raise AssertionError(f"Missing base path in {path.name}")
            for verb, annotation, response, handler, parameters in pattern.findall(source):
                suffix = re.search(r'"(/[^"\n]*)"', annotation or "")
                route = (verb.upper(), base[1] + (suffix[1] if suffix else ""))
                if route in routes:
                    raise AssertionError(f"Duplicate Controller route: {route}")
                request_match = re.search(r"\b(\w+RequestDto)\s+request", parameters)
                request = request_match[1] if request_match else None
                if handler == "updateCurrent":
                    request = "UpdateCurrentUserRequestDto"
                routes[route] = dict(controller=path.relative_to(root).as_posix(), handler=handler,
                                     request_dto=request, response_dto=response)
    enum_source = read(root / PREFIX / "platform/api/ApiErrorCode.java")
    http_codes = {name: int(status) for name, status in re.findall(r'\b([A-Z][A-Z_]+)\("[A-Z_]+",\s*"[^"\n]*",\s*(?:true|false),\s*(\d{3})\)', enum_source)}
    if not http_codes:
        raise AssertionError("Backend error enum was not parsed")
    for path in sorted((root / PREFIX / "platform/idempotency").glob("*.java")):
        read(path)
    rows = []
    for operation, endpoint in contract["endpoints"].items():
        request_schema = json.loads((root / "contracts" / endpoint["request"]).read_text(encoding="utf-8"))
        response_schema = json.loads((root / "contracts" / endpoint["result"]["data"]).read_text(encoding="utf-8"))
        route = (endpoint["method"], contract["base_path"] + endpoint["path"])
        controller = routes.pop(route, None)
        row = {"operation": operation, "method": route[0], "path": route[1],
               "declared_implementation_status": endpoint.get("implementation_status", contract["implementation_status"]),
               "source_status": "controller_present" if controller else "controller_absent",
               "request_schema": endpoint["request"], "response_schema": endpoint["result"]["data"],
               "request_schema_fields": sorted(request_schema.get("properties", {})),
               "response_schema_fields": sorted(response_schema.get("properties", {})),
               "declared_business_http_status": contract["http_conventions"]["business_error_status"],
               "error_statuses_from_backend_enum": {code: http_codes.get(code) for code in endpoint["errors"]},
               "declared_errors_missing_backend_enum": sorted(set(endpoint["errors"]) - set(http_codes)),
               "idempotency": endpoint["idempotency"], "runtime_verification": "not_run_in_ct0"}
        if controller:
            row.update(controller)
            for direction in ("request", "response"):
                dto = controller[direction + "_dto"]
                if dto:
                    read(dtos[dto])
                    fields = record_fields(dtos[dto])
                    row[direction + "_dto_fields"] = fields
                    row[direction + "_top_level_fields_match"] = fields == row[direction + "_schema_fields"]
                else:
                    row[direction + "_dto_fields"] = None
                    row[direction + "_top_level_fields_match"] = None
        rows.append(row)
    if routes:
        raise AssertionError(f"Controller routes not accounted for: {sorted(routes)}")
    return {"audit_version": 1, "rule_anchor": "cloud-sync-02/3", "scope": "Static route, top-level DTO field, error enum and idempotency source inventory; nested constraints and actual HTTP results remain unverified",
            "endpoints": rows, "source_sha256": dict(sorted(sources.items()))}
