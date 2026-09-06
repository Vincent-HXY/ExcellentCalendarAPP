"""Real v5 checker + SQLite rollback and disposable PostgreSQL 17 model checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTRACTS = ROOT / "contracts"
sys.path[:0] = [str(CONTRACTS), str(HERE), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_storage_contract import derive as sqlite_model
from build_sync_postgres_contract import derive as postgres_model
from build_storage_fixtures import derive as fixtures


def sha(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def run(command, log):
    with log.open("wb") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed; inspect {log}")


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--jdk", type=Path, default=Path("A:/Android/AndroidStudio/jbr"))
    parser.add_argument("--report", type=Path, default=HERE / "storage_spike_result.json")
    args = parser.parse_args()
    report = {"spike_version": 1, "passed": False, "production_migration_activated": False,
        "account_encrypted_full_graph_verified": False, "android_migration_verified": False, "errors": []}
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-storage-contract-"))
    try:
        suite = unittest.defaultTestLoader.discover(str(CONTRACTS / "tests"), pattern="test_sync_storage.py")
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        report["sqlite"] = {"passed": result.wasSuccessful(), "tests_run": result.testsRun, "frozen_checker": "unchanged_production_cpp_v5",
            "new_tables": len(sqlite_model()["new_tables"]), "new_indexes": len(sqlite_model()["new_indexes"]),
            "transaction_rollback_boundaries": sum(len(sqlite_model()[k]) for k in ("new_tables", "new_indexes", "new_triggers")) + 2}
        if not result.wasSuccessful():
            raise RuntimeError("SQLite storage reference failed")
        xml = ET.parse(next((ROOT / "cloud_backend/target/surefire-reports").glob("TEST-*.xml")))
        classpath = next(p.get("value") for p in xml.findall("./properties/property") if p.get("name") == "java.class.path")
        classes = scratch / "classes"
        classes.mkdir()
        arguments = ["-encoding", "UTF-8", "--release", "21", "-cp", classpath, "-d", str(classes), str(HERE / "PostgresModelProbe.java")]
        argfile = scratch / "javac.args"
        argfile.write_text("\n".join('"' + value.replace("\\", "/").replace('"', '\\"') + '"' for value in arguments), encoding="utf-8")
        run([str(args.jdk / "bin/javac.exe"), "@" + str(argfile)], scratch / "javac.log")
        observed = scratch / "observed.json"
        try:
            run([str(args.jdk / "bin/java.exe"), "-Dfile.encoding=UTF-8", "-cp", str(classes) + os.pathsep + classpath,
                "PostgresModelProbe", str(ROOT), str(CONTRACTS / "fixtures/sync/v1/postgres_vectors.json"), str(observed)], scratch / "postgres.log")
        finally:
            if observed.exists():
                report["postgres"] = json.loads(observed.read_text(encoding="utf-8"))
        pg = report["postgres"]
        if not pg["passed"]:
            raise RuntimeError("PostgreSQL model reference failed")
        # Independently check every mapping against the actual database catalog.
        columns = {(column["table"], column["column"]) for column in pg["columns"]}
        mapped = 0
        for target, fields in postgres_model()["field_mappings"].items():
            for name, mapping in fields.items():
                if mapping["column"] == "typed_child_rows":
                    assert any(t == mapping["table"] for t, c in columns), (target, name)
                else:
                    assert (mapping["table"], mapping["column"]) in columns, (target, name)
                mapped += 1
        pg["mapped_fields_checked"] = mapped
        report["passed"] = True
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    sources = [HERE / name for name in ("run_storage_spike.py", "build_sync_storage_contract.py", "build_sync_postgres_contract.py", "build_storage_fixtures.py", "storage_reference.py", "sqlite_reference.py", "storage_v5_probe.cpp", "PostgresModelProbe.java", "domain_reference.py", "schema_validation_reference.py", "protocol_reference.py", "counter_reference.py", "identity_reference.py")]
    sources += [CONTRACTS / name for name in ("tests/test_sync_storage.py", "storage/calendar_core_storage.yaml", "storage/cloud_sync_postgresql_v1.yaml", "storage/cloud_sync_postgresql_v1.sql", "fixtures/sync/v1/postgres_vectors.json", "fixtures/sync/v1/target_vectors.json", "sync/sync_field_registry.yaml")]
    sources += list((ROOT / "cloud_backend/src/main/resources/db/migration").glob("*.sql"))
    sources += list((ROOT / "cpp_core/src/storage").rglob("*.cpp")) + list((ROOT / "cpp_core/include/excellent_calendar/storage").rglob("*.hpp"))
    sources.append(CONTRACTS / "sync/sync_error_registry.yaml")
    from validate_sync_v1 import validate_schemas, walk
    from urllib.parse import urljoin, urldefrag
    schema_map, _ = validate_schemas()
    pending = [schema_map["https://excellent-calendar.local/contracts/sync/v1/sync_fact.schema.json"]]
    for codec in sqlite_model()["payload_codecs"].values():
        for relative in codec.get("columns", {}).values():
            if ".schema.json" in relative:
                pending.append(schema_map["https://excellent-calendar.local/contracts/" + relative.partition("#")[0]])
    seen = set()
    while pending:
        schema = pending.pop()
        uri = schema["$id"]
        if uri in seen:
            continue
        seen.add(uri)
        sources.append(CONTRACTS / uri.removeprefix("https://excellent-calendar.local/contracts/"))
        for node in walk(schema):
            if "$ref" in node:
                pending.append(schema_map[urldefrag(urljoin(uri, node["$ref"]))[0]])
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(set(sources))}
    report["frozen_checker_libraries_sha256"] = {name: hashlib.sha256((ROOT / "cpp_core/build-ninja" / name).read_bytes()).hexdigest() for name in (
        "libexcellent_calendar_core.a", "libexcellent_calendar_date_tz.a", "libexcellent_calendar_sqlite.a")}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "sqlite": report.get("sqlite"), "postgres_cases": len(report.get("postgres", {}).get("cases", [])), "errors": report["errors"]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
