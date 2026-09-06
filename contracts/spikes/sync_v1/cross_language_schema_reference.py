"""Compile the existing schemas to a small lossless assertion graph for probes.

The graph is derived at run time, not a replacement Contract. Each consumer
independently evaluates the assertions and reparses its serialized output.
"""
import copy
import json
from pathlib import Path
import subprocess
from urllib.parse import urldefrag, urljoin

from domain_reference import validate_schema

ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = ROOT / "contracts"
PREFIX = "https://excellent-calendar.local/contracts/"
ANNOTATIONS = {"$schema", "$id", "$defs", "definitions", "$comment", "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly"}
SCALARS = {"type", "const", "enum", "required", "dependentRequired", "minimum", "maximum", "minLength", "maxLength", "pattern", "format",
    "minItems", "maxItems", "uniqueItems", "minProperties", "maxProperties"}


class AssertionGraph:
    def __init__(self):
        self.documents, self.memo, self.nodes, self.paths = {}, {}, [], set()

    def document(self, uri):
        if not uri.startswith(PREFIX):
            raise ValueError("Remote schema resolution is not permitted")
        if uri not in self.documents:
            path = CONTRACTS / uri.removeprefix(PREFIX)
            self.documents[uri] = json.loads(path.read_text(encoding="utf8"))
            self.paths.add(path)
        return self.documents[uri]

    def reference(self, uri):
        base, pointer = urldefrag(uri)
        schema = self.document(base)
        for key in pointer.lstrip("/").split("/") if pointer else []:
            key = key.replace("~1", "/").replace("~0", "~")
            schema = schema[int(key)] if isinstance(schema, list) else schema[key]
        return self.node(schema, base)

    def node(self, schema, base):
        identity = id(schema), base
        if identity in self.memo:
            return self.memo[identity]
        index = len(self.nodes)
        self.memo[identity] = index
        self.nodes.append({})
        if isinstance(schema, bool):
            self.nodes[index] = {"boolean": schema}
            return index
        out = {}
        for key in sorted(schema):
            value = schema[key]
            if key in ANNOTATIONS or key.startswith("x-"):
                continue
            if key == "$ref":
                out["ref"] = self.reference(urljoin(base, value))
            elif key in SCALARS:
                out[key] = value
            elif key in {"properties", "patternProperties"}:
                out[key] = {name: self.node(shape, base) for name, shape in sorted(value.items())}
            elif key in {"oneOf", "anyOf", "allOf"}:
                out[key] = [self.node(shape, base) for shape in value]
            elif key in {"not", "if", "then", "else", "items", "additionalProperties", "propertyNames"}:
                out[key] = self.node(value, base)
            else:
                raise ValueError("Assertion graph must explicitly support keyword: " + key)
        self.nodes[index] = out
        return index


def boundary_cases():
    cases = []
    for filename, field in (("protocol_vectors.json", "valid"), ("capability_vectors.json", "schema_valid"), ("private_lifecycle_vectors.json", "schema_valid")):
        fixture = json.loads((CONTRACTS / "fixtures/sync/v1" / filename).read_text(encoding="utf8"))
        for case in fixture["cases"]:
            if "schema" in case and field in case["expected"]:
                cases.append({"id": case["id"], "rule_anchor": case["rule_anchor"], "schema": case["schema"],
                    "input_json": json.dumps(case["input"], ensure_ascii=False, separators=(",", ":")), "valid": case["expected"][field]})
    samples = json.loads((CONTRACTS / "fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]
    for name, sample in samples.items():
        examples = [("valid", sample, True), ("unknown_field", {**sample, "unexpected": 1}, False), ("null_fact", {**sample, "fact": None}, False)]
        for field in sample["fact"]:
            missing = copy.deepcopy(sample)
            del missing["fact"][field]
            examples.append(("missing_" + field, missing, False))
            wrong = copy.deepcopy(sample)
            wrong["fact"][field] = {"unexpected_type": True}
            examples.append(("type_" + field, wrong, False))
        for variant, value, valid in examples:
            cases.append({"id": "FX-CROSS-SCHEMA-target-" + name + "-" + variant, "rule_anchor": "cloud-sync-02/7.7,9,13.2",
                "schema": "sync/v1/sync_fact.schema.json", "input_json": json.dumps(value, ensure_ascii=False, separators=(",", ":")), "valid": valid})
    base = {"workspace_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "expected_active_route_revision": 0}
    for identity, raw in (("duplicate", '{"workspace_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","expected_active_route_revision":0,"expected_active_route_revision":0}'),
        ("lone_surrogate", '{"workspace_id":"\\ud800","expected_active_route_revision":0}'),
        ("trailing_data", json.dumps(base) + " false"), ("non_finite", '{"workspace_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","expected_active_route_revision":1e999}')):
        cases.append({"id": "FX-CROSS-SCHEMA-json-" + identity, "rule_anchor": "cloud-sync-02/4.2,9,13.2", "schema": "sync/run_sync_now_request.schema.json",
            "input_json": raw, "valid": False, "malformed_json": True})
    return cases


def manifest_cases():
    """Every fixed fixture is transported losslessly by every parser.

    Fixture control records are not public business payloads. Schema assertions
    below cover typed payloads separately; stateful/OS expectations remain with
    the manifest's actual owner runners rather than being claimed by JSON echo.
    """
    manifest = json.loads((CONTRACTS / "fixtures/sync/v1/manifest.json").read_text(encoding="utf8"))
    files, cases = {}, []
    for entry in manifest["cases"]:
        path = CONTRACTS / "fixtures/sync/v1" / entry["input_file"]
        if path not in files:
            files[path] = json.loads(path.read_text(encoding="utf8"))
        fixture = files[path]
        for key in entry["case_pointer"].lstrip("/").split("/"):
            fixture = fixture[int(key)] if isinstance(fixture, list) else fixture[key]
        cases.append({"id": "transport/" + entry["id"], "fixture_id": entry["id"], "family": entry["family"],
            "rule_anchor": entry["rule_anchor"], "input_json": json.dumps(fixture, ensure_ascii=False, separators=(",", ":")),
            "valid": True, "role": "fixture_transport_only"})
        if entry["input_file"] == "jcs_boundary_vectors.json":
            cases.append({"id": "canonical/" + entry["id"], "fixture_id": entry["id"], "rule_anchor": entry["rule_anchor"],
                "input_json": fixture["input_json"], "valid": not fixture["expected_error"], "role": "jcs_boundary",
                "canonical_utf8_hex": fixture.get("canonical_utf8_hex"), "malformed_json": fixture["expected_error"]})
        elif "v2_schema" in fixture:
            for version in ("v2", "v3"):
                cases.append({"id": version + "/" + entry["id"], "fixture_id": entry["id"], "rule_anchor": entry["rule_anchor"],
                    "schema": fixture[version + "_schema"], "input_json": json.dumps(fixture["value"], ensure_ascii=False, separators=(",", ":")),
                    "valid": fixture[version + "_valid"], "role": "native_compatibility"})
        elif entry["input_file"] == "target_vectors.json":
            # Domain-specific equality/reference errors can pass shape validation.
            # The existing domain runner remains responsible for those errors.
            try:
                validate_schema("sync/v1/sync_fact.schema.json", fixture["input"])
                valid = True
            except ValueError:
                valid = False
            cases.append({"id": "shape/" + entry["id"], "fixture_id": entry["id"], "rule_anchor": entry["rule_anchor"],
                "schema": "sync/v1/sync_fact.schema.json", "input_json": json.dumps(fixture["input"], ensure_ascii=False, separators=(",", ":")),
                "valid": valid, "role": "typed_fact_schema"})
    return cases, set(files)


def bundle():
    graph, cases = AssertionGraph(), boundary_cases()
    corpus, fixture_paths = manifest_cases()
    cases.extend(corpus)
    generic = graph.node(True, PREFIX)
    for case in cases:
        case["root"] = graph.reference(PREFIX + case["schema"]) if "schema" in case else generic
        if not case.get("malformed_json"):
            value = json.loads(case["input_json"])
            try:
                if "schema" in case:
                    validate_schema(case["schema"], value)
                actual = True
            except ValueError:
                actual = False
            if actual != case["valid"]:
                raise ValueError("Existing reviewed schema expectation drift: " + case["id"])
    accepted = [case for case in cases if case["valid"]]
    process = subprocess.run(["C:/Program Files/nodejs/node.exe", Path(__file__).with_name("fixture_roundtrip_oracle.cjs")],
        input=json.dumps([case["input_json"] for case in accepted], ensure_ascii=False),
        encoding="utf8", capture_output=True, check=True, timeout=30)
    for case, encoded in zip(accepted, json.loads(process.stdout), strict=True):
        if case.get("canonical_utf8_hex") is not None and case["canonical_utf8_hex"] != encoded:
            raise ValueError("Independent ECMAScript oracle disagrees with fixed JCS bytes: " + case["id"])
        case["canonical_utf8_hex"] = encoded
    return {"nodes": graph.nodes, "cases": cases}, graph.paths | fixture_paths
