"""Typed apply/notice evidence and a million bounded SQLite queue windows."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from urllib.parse import urljoin, urldefrag

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
    str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
import test_sync_notices as checks
from build_notice_fixtures import derive, FIXTURE
from build_bootstrap_fixtures import identifier
from notice_projection_reference import NoticeJournal
from sqlite_reference import connect
from validate_sync_v1 import validate_schemas, walk


def capacity():
    expected = derive()["capacity"]
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="excellent-calendar-notice-million-") as temporary:
        path = Path(temporary) / "capacity.db"
        with connect(path) as db:
            db.execute("PRAGMA journal_mode=WAL")
            NoticeJournal.initialize(db)
            maxima = dict(queue=0, members=0, discovery=0)
            for begin in range(0, expected["windows"], expected["windows_per_commit"]):
                db.execute("BEGIN IMMEDIATE")
                for number in range(begin, begin + expected["windows_per_commit"]):
                    conflict = identifier(number + 1)
                    NoticeJournal.begin(db, kind="download", generation=0, upper_bound=number + 1, identity=str(number + 1), unresolved=[])
                    NoticeJournal.observe(db, conflict, resolved=False)
                    notice = NoticeJournal.terminal(db, [conflict])
                    counts = db.execute("SELECT (SELECT count(*) FROM notice_queue),(SELECT count(*) FROM notice_members),(SELECT count(*) FROM notice_discovery)").fetchone()
                    maxima = {key: max(maxima[key], value) for key, value in zip(maxima, counts)}
                    assert notice[0] == number + 1
                    assert NoticeJournal.claim(db, *notice, [conflict]) == {"disposition": "claimed", "count": 1}
                db.commit()
                if (begin + expected["windows_per_commit"]) % 100000 == 0:
                    print(json.dumps({"notice_windows_completed": begin + expected["windows_per_commit"]}), flush=True)
            state = db.execute("SELECT next_sequence,last_claimed,revision FROM notice_state").fetchone()
            remaining = {name: db.execute("SELECT count(*) FROM " + name).fetchone()[0] for name in
                ("notice_queue", "notice_members", "notice_window", "notice_discovery")}
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            pages = db.execute("PRAGMA page_count").fetchone()[0]
            size = pages * db.execute("PRAGMA page_size").fetchone()[0]
            assert state == (expected["windows"] + 1, expected["windows"], expected["windows"] * 2)
            assert not any(remaining.values()) and maxima == {"queue": 1, "members": 1, "discovery": 0}
            assert size <= 1024 * 1024, "Claimed history must not cause persistent database growth"
        with connect(path) as db:
            assert db.execute("SELECT next_sequence,last_claimed,revision FROM notice_state").fetchone() == state
        return {"passed": True, "windows": expected["windows"], "windows_per_commit": expected["windows_per_commit"],
            "committed_batches": expected["windows"] // expected["windows_per_commit"], "maximum_rows_at_terminal": maxima,
            "retained_rows": remaining, "final_next_sequence": state[0], "last_claimed": state[1],
            "database_bytes_after_checkpoint": size, "elapsed_seconds": round(time.monotonic() - started, 3),
            "scope": "Actual million queue/discovery/claim transitions in bounded capacity batches; independent real process-death tests cover transaction atomicity."}


def main():
    report = {"spike_version": 1, "passed": False, "errors": [], "cases": [],
        "scope": "isolated SQLite notices composed with authoritative typed ordinary download and bootstrap",
        "production_native_or_ui_implemented": False, "four_language_consumers_verified": False,
        "million_individual_fsync_commits_claimed": False}
    checks.OBSERVED.clear(); checks.CRASH_POINTS.clear()
    suite = unittest.defaultTestLoader.loadTestsFromModule(checks)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    report["tests_run"] = result.testsRun
    report["cases"] = [{**row, "passed": row["actual"] == derive()["cases"][index]["expected"]} for index, row in enumerate(checks.OBSERVED)]
    report["errors"] = [error for _, error in result.errors + result.failures]
    report["actual_process_death_points"] = checks.CRASH_POINTS[:]
    try:
        if not result.wasSuccessful() or len(report["cases"]) != len(derive()["cases"]):
            raise RuntimeError("Notice apply/journal evidence failed")
        report["capacity"] = capacity()
        report["passed"] = all(row["passed"] for row in report["cases"])
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    sources = [Path(__file__), FIXTURE,
        *[ROOT / "contracts/tests" / name for name in ("test_sync_notices.py", "test_sync_conflict_local_recovery.py", "test_sync_protocol.py")],
        *[HERE / name for name in ("build_notice_fixtures.py", "notice_projection_reference.py", "notice_crash_probe.py",
            "conflict_resolution_reference.py", "resolution_contract_reference.py", "owned_resolution_reference.py", "owned_sequence_reference.py", "local_intent_reference.py", "local_download_reference.py",
            "local_projection_reference.py", "bootstrap_reference.py", "build_bootstrap_fixtures.py", "build_target_fixtures.py",
            "habit_operation_reference.py", "owned_graph_reference.py", "protocol_reference.py", "domain_reference.py", "schema_validation_reference.py", "identity_reference.py",
            "counter_reference.py", "cursor_reference.py", "sqlite_reference.py")],
        *[ROOT / "contracts" / name for name in ("sync/sync_notice_protocol.yaml", "sync/sync_field_registry.yaml",
            "sync/sync_protocol_invariants.yaml", "sync/sync_bootstrap_protocol.yaml", "sync/sync_cursor_protocol.yaml", "fixtures/sync/v1/target_vectors.json")]]
    schemas, _ = validate_schemas()
    prefix = "https://excellent-calendar.local/contracts/"
    pending = [schemas[prefix + name] for name in ("sync/sync_bootstrap_page_response.schema.json", "sync/sync_mutation.schema.json",
        "sync/sync_upload_result.schema.json", "sync/sync_exchange_response.schema.json", "sync/backend_sync_conflict_resolution_response.schema.json")]
    seen = set()
    while pending:
        schema = pending.pop()
        uri = schema["$id"]
        if uri in seen:
            continue
        seen.add(uri)
        sources.append(ROOT / "contracts" / uri.removeprefix(prefix))
        for node in walk(schema):
            if "$ref" in node:
                pending.append(schemas[urldefrag(urljoin(uri, node["$ref"]))[0]])
    report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sorted(set(sources))}
    (HERE / "notice_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: report[key] for key in ("passed", "tests_run", "actual_process_death_points", "errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
