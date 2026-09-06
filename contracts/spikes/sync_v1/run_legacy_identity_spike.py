"""Build before executing the actual Core v1 reader/migration on isolated fixtures."""
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

from build_legacy_identity_fixtures import derive, FIXTURE
from legacy_identity_reference import project_legacy_graph, legacy_source_id, OPTIONAL

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-legacy-identity-"))
    executable = scratch / "legacy.exe"
    libraries = [ROOT / "cpp_core/build-ninja" / name for name in
        ("libexcellent_calendar_core.a", "libexcellent_calendar_date_tz.a", "libexcellent_calendar_sqlite.a")]
    report = {"spike_version": 1, "passed": False, "production_converter_implemented": False,
        "scope": "current Core v1-to-v5 migration, exact legacy field preservation, read-only typed import eligibility",
        "cases": [], "errors": []}
    try:
        fixed = derive()
        if json.loads(FIXTURE.read_text(encoding="utf-8")) != fixed: raise ValueError("legacy fixture drift")
        command = ["D:/mingw/mingw64/bin/g++.exe", "-std=c++17", "-O2", "-finput-charset=UTF-8",
            "-I", str(ROOT / "cpp_core/include"), "-I", str(ROOT / "cpp_core/third_party"), str(HERE / "legacy_identity_probe.cpp"),
            *map(str, libraries), "-lbcrypt", "-lole32", "-pthread", "-o", str(executable)]
        build = subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace", timeout=180)
        if build.returncode: raise ValueError(build.stderr[-3000:])
        for index, case in enumerate(fixed["cases"]):
            directory = scratch / str(index); directory.mkdir()
            source = case["input"]
            for name in ("events", "reminders", "notifications"):
                (directory / (name + ".json")).write_text(json.dumps({"storage_version": 1, name: source.get(name, [])}, ensure_ascii=False), encoding="utf-8")
            run = subprocess.run([str(executable), str(directory)], capture_output=True, encoding="utf-8", timeout=30, check=True)
            output = run.stdout.strip()
            actual = {"core_error": output.split("\t")[1] if output.startswith("ERROR\t") else None,
                "projection_error": None, "portable_events": 0, "portable_intents": 0}
            if actual["core_error"]:
                actual["projection_error"] = actual["core_error"]
                if (directory / "calendar_core.sqlite3").exists(): raise ValueError("Invalid v1 source published SQLite")
            else:
                decoded = json.loads(output)
                expected_events = [{**{name: None for name in OPTIONAL}, **row} for row in source["events"]]
                if decoded["events"]["events"] != expected_events or decoded["reminders"]["reminders"] != source["reminders"]:
                    raise ValueError("Core v1 migration changed preserved source values: " + case["id"])
                if any(row["recurrence_revision_present"] or row["civil_date_range_present"] for row in decoded["availability"]):
                    raise ValueError("V1 unexpectedly reconstructed absent fields")
                with sqlite3.connect(directory / "calendar_core.sqlite3") as db:
                    history = [row[0] for row in db.execute("SELECT migration_id FROM migration_history ORDER BY source_version")]
                    if history != case["expected"]["v1_to_v5_migration_ids"] or db.execute("PRAGMA user_version").fetchone()[0] != 5:
                        raise ValueError("Legacy migration history differs")
                actual["v1_fields_preserved"] = True
                actual["missing_fields_not_invented"] = True
                actual["migration_ids"] = history
                try:
                    mapping = {legacy_source_id(row["id"]): source["target_uuid"] for row in source["events"] if row.get("deleted_at") is None}
                    projected = project_legacy_graph(decoded["events"]["events"], decoded["reminders"]["reminders"], mapping)
                    actual["portable_events"] = sum(row["target_type"] == "event" for row in projected)
                    actual["portable_intents"] = sum(row["target_type"] == "reminder_intent" for row in projected)
                    actual["typed_projection_sha256"] = hashlib.sha256(json.dumps(projected, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
                except ValueError as error:
                    actual["projection_error"] = str(error)
                # Read-only projection cannot modify or retire any original guest row.
                replay = subprocess.run([str(executable), str(directory)], capture_output=True, encoding="utf-8", timeout=30, check=True)
                if replay.stdout != run.stdout: raise ValueError("Eligibility projection changed guest source")
                actual["source_unchanged_after_projection"] = True
            passed = all(actual[key] == case["expected"][key] for key in ("core_error", "projection_error", "portable_events", "portable_intents"))
            report["cases"].append({"id": case["id"], "passed": passed, "actual": actual})
            if not passed: report["errors"].append(case["id"] + ": " + json.dumps(actual))
        report["core_library_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in libraries}
        report["binary_sha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
        report["passed"] = not report["errors"]
    except Exception as error:
        report["errors"].append(str(error))
    sources = [Path(__file__), HERE / "legacy_identity_probe.cpp", HERE / "legacy_identity_reference.py", HERE / "build_legacy_identity_fixtures.py",
        HERE / "identity_reference.py", HERE / "domain_reference.py", HERE / "schema_validation_reference.py", FIXTURE,
        ROOT / "contracts/sync/sync_identity_registry.yaml", ROOT / "contracts/sync/sync_field_registry.yaml",
        ROOT / "cpp_core/src/storage/sqlite/sqlite_calendar_database.cpp",
        ROOT / "cpp_core/include/excellent_calendar/storage/json/legacy_json_codec.hpp",
        *[ROOT / "cpp_core/src/storage/json" / ("json_" + kind + "_repository.cpp") for kind in ("event", "reminder", "notification")]]
    # Bind the exact draft schemas consumed by the read-only projector as well.
    sources += list((ROOT / "contracts/sync/v1").glob("*_fact.schema.json"))
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "legacy_identity_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "errors")})); print("cases=" + str(len(report["cases"])))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
