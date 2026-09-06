"""Immutable materialization, complete snapshot checks and real process-death rollback."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from bootstrap_reference import BootstrapLocal, BootstrapServer, item_key, page_hash, page_set_digest, validate_snapshot
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, all_kinds, category_items, derive
from protocol_reference import digest, encode
from sqlite_reference import connect

HERE = Path(__file__).resolve().parents[1] / "spikes/sync_v1"
SERVER_POINTS = ("server_supersede", "server_session", "server_pages")
LOCAL_POINTS = ("local_clear_baseline", "local_entities", "local_conflicts_anchors", "local_import_markers", "local_confirmation_cursor", "local_finalize_receipt")
OBSERVED = []


def server_at(directory, items, **state):
    server = BootstrapServer(directory / "server.sqlite", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
    server.seed(items, **state)
    return server


def download(server, first):
    pages = [first]
    while pages[-1]["has_more"]:
        pages.append(server.download(pages[-1]["next_bootstrap_cursor"], now=NOW, download_limit=first["page_item_limit"]))
    return pages


def stage(local, pages):
    local.begin(pages[0])
    for index, page in enumerate(pages):
        local.stage(page, request_cursor=pages[index - 1]["next_bootstrap_cursor"] if index else None)


def finalize(local, pages, **options):
    local.finalize(expected_page_set_digest=page_set_digest(pages), final_cursor=pages[-1]["terminal_sync_cursor"], **options)


def execute_case(case):
    with tempfile.TemporaryDirectory(prefix="excellent-calendar-bootstrap-fixed-") as raw:
        directory = Path(raw)
        scenario = case["input"]["scenario"]
        items = [] if scenario == "empty" else all_kinds() if scenario == "six_kinds" else category_items(500 if scenario == "five_hundred" else 2)
        high = 9007199254740991 if scenario == "exhausted" else 4
        server = server_at(directory, items, highest=high, confirmed=2)
        limit = 128 if scenario == "five_hundred" else 2 if scenario == "six_kinds" else 1
        first = server.begin(now=NOW, download_limit=limit)
        if scenario == "first_loss":
            replay = server.begin(now=NOW + 1, download_limit=limit)
            return {"same_bootstrap_id": first["bootstrap_id"] == replay["bootstrap_id"], "same_page_bytes": encode(first) == encode(replay)}
        if scenario in {"generation", "expired"}:
            if scenario == "generation": server.seed(items, generation=1, highest=high, confirmed=2)
            try: server.download(first["next_bootstrap_cursor"], now=NOW + (86400 if scenario == "expired" else 0), download_limit=limit)
            except ValueError as error: return {"error": str(error)}
            raise AssertionError("invalid bootstrap cursor was accepted")
        if scenario == "fixed_snapshot":
            server.seed(category_items(3), upper_bound=101, highest=high, confirmed=2)
            reused = server.begin(now=NOW + 1, download_limit=limit)
            pages = download(server, reused)
            with connect(server.path) as db: live_count = db.execute("SELECT count(*) FROM live").fetchone()[0]
            return {"old_upper_bound": reused["snapshot_upper_bound"], "new_live_items": live_count, "snapshot_items": sum(len(page["items"]) for page in pages)}
        if scenario == "supersede":
            server.seed(items, highest=high + 1, confirmed=2)
            replacement = server.begin(now=NOW + 1, download_limit=limit)
            try: server.download(first["next_bootstrap_cursor"], now=NOW + 1, download_limit=limit)
            except ValueError as error:
                return {"new_bootstrap_id": replacement["bootstrap_id"] != first["bootstrap_id"], "old_cursor_error": str(error)}
            raise AssertionError("superseded session was accepted")
        pages = download(server, first)
        local = BootstrapLocal(directory / "local.sqlite", device_id=D)
        stage(local, pages)
        visible_before = len(local.snapshot()["live"])
        finalize(local, pages)
        state = json.loads(local.snapshot()["state"][0][0])
        if scenario == "recovery": return {name: state[name] for name in ("local_ack", "server_ack", "next_sequence")}
        if scenario == "exhausted": return {name: state[name] for name in ("local_ack", "next_sequence", "exhausted")}
        return {"pages": len(pages), "items": len(local.snapshot()["live"]), "visible_before_finalize": visible_before}


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="excellent-calendar-bootstrap-test-")
        self.directory = Path(self.temp.name)

    def tearDown(self): self.temp.cleanup()

    def prepared(self):
        server = server_at(self.directory, all_kinds(), highest=4, confirmed=2)
        pages = download(server, server.begin(now=NOW, download_limit=2))
        local = BootstrapLocal(self.directory / "local.sqlite", device_id=D)
        return server, local, pages

    def test_fixed_materialized_snapshot_and_confirmation_cases(self):
        for case in derive()["cases"]:
            with self.subTest(case=case["id"]):
                actual = execute_case(case)
                OBSERVED.append({"id": case["id"], "actual": actual, "passed": actual == case["expected"]})
                self.assertEqual(actual, case["expected"])

    def test_replay_missing_out_of_order_cross_device_and_cursor_do_not_publish(self):
        server, local, pages = self.prepared()
        local.begin(pages[0]); initial = local.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            local.stage(pages[1], request_cursor=pages[0]["next_bootstrap_cursor"])
        self.assertEqual(local.snapshot(), initial)
        local.stage(pages[0], request_cursor=None); first_saved = local.snapshot()
        local.stage(pages[0], request_cursor=None)
        self.assertEqual(local.snapshot(), first_saved)
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
            local.stage(pages[1], request_cursor="A" * 16)
        with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"): finalize(local, pages)
        foreign = copy.deepcopy(pages[1]); foreign["device_id"] = A; foreign["page_hash"] = page_hash(foreign)
        with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"):
            local.stage(foreign, request_cursor=pages[0]["next_bootstrap_cursor"])
        self.assertEqual(local.snapshot(), first_saved)
        reopened = BootstrapLocal(local.path, device_id=D)
        stage(reopened, pages); finalize(reopened, pages)
        committed = reopened.snapshot()
        finalize(reopened, pages)
        self.assertEqual(reopened.snapshot(), committed)
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            server.download(pages[0]["next_bootstrap_cursor"], now=NOW, download_limit=1)

    def test_tampered_page_item_count_hash_and_causal_anchor_are_rejected(self):
        _, local, pages = self.prepared()
        for field, value in (("snapshot_item_count", 5), ("snapshot_items_hash", "0" * 64), ("device_next_client_sequence_at_snapshot", 7)):
            local = BootstrapLocal(self.directory / (field + ".sqlite"), device_id=D)
            altered = copy.deepcopy(pages)
            for page in altered: page[field] = value; page["page_hash"] = page_hash(page)
            with self.subTest(field=field), self.assertRaises(ValueError):
                stage(local, altered); finalize(local, altered)
            self.assertFalse(local.snapshot()["live"])
        items = sorted(all_kinds(), key=item_key)
        for mutate in (
            lambda rows: next(row for row in rows if row["kind"] == "requesting_device_causal_anchor").update(client_sequence=5),
            lambda rows: next(row for row in rows if row["kind"] == "import_publish_marker").update(snapshot_provenance_digest="0" * 64),
            lambda rows: next(row for row in rows if row["kind"] == "fact_after_image")["field_versions"].pop(),
        ):
            altered = copy.deepcopy(items); mutate(altered)
            with self.assertRaisesRegex(ValueError, "SYNC_BOOTSTRAP_INCOMPLETE"):
                validate_snapshot(altered, upper_bound=100, highest=4)

    def test_later_business_edit_keeps_import_provenance_valid(self):
        items = all_kinds()
        next(item for item in items if item["kind"] == "fact_after_image")["fact"]["name"] = "发布后的正常编辑"
        validate_snapshot(sorted(items, key=item_key), upper_bound=100, highest=4)

    def test_partial_experiment_refuses_to_skip_pending_failed_or_effect_rebase(self):
        _, local, pages = self.prepared()
        stage(local, pages)
        for table in ("pending", "failed", "effect_gates"):
            with connect(local.path) as db:
                if table == "effect_gates": db.execute("INSERT INTO effect_gates VALUES(5)")
                else: db.execute("INSERT INTO " + table + " VALUES(5,'{}')")
            before = local.snapshot()
            with self.assertRaisesRegex(ValueError, "REFERENCE_BOOTSTRAP_REBASE_REQUIRED"): finalize(local, pages)
            self.assertEqual(local.snapshot(), before)
            with connect(local.path) as db: db.execute("DELETE FROM " + table)

    def crash(self, request):
        path = self.directory / "crash-request.json"
        path.write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
        process = subprocess.run([sys.executable, "-X", "utf8", str(HERE / "bootstrap_crash_probe.py"), str(path)],
            capture_output=True, encoding="utf-8", timeout=60)
        self.assertEqual(process.returncode, 79, process.stdout + process.stderr)

    def test_actual_process_death_at_every_server_write_preserves_old_state(self):
        server = server_at(self.directory, all_kinds(), highest=4, confirmed=2)
        for point in SERVER_POINTS:
            self.crash({"mode": "server_begin", "path": str(server.path), "checkpoint": point})
            with connect(server.path) as db:
                self.assertEqual(db.execute("SELECT count(*) FROM sessions").fetchone()[0], 0)
                self.assertEqual(db.execute("SELECT count(*) FROM pages").fetchone()[0], 0)
                self.assertEqual(db.execute("SELECT count(*) FROM live").fetchone()[0], 6)
        self.assertEqual(server.begin(now=NOW, download_limit=2)["snapshot_item_count"], 6)

    def test_actual_process_death_at_page_and_all_finalize_writes_keeps_visibility_atomic(self):
        _, local, pages = self.prepared()
        local.begin(pages[0]); before = local.snapshot()
        self.crash({"mode": "stage", "path": str(local.path), "checkpoint": "local_page_receipt", "page": pages[0]})
        self.assertEqual(local.snapshot(), before)
        stage(local, pages); before = local.snapshot()
        for point in LOCAL_POINTS:
            self.crash({"mode": "finalize", "path": str(local.path), "checkpoint": point,
                "digest": page_set_digest(pages), "cursor": pages[-1]["terminal_sync_cursor"]})
            self.assertEqual(BootstrapLocal(local.path, device_id=D).snapshot(), before)
        finalize(local, pages)
        self.assertEqual(len(local.snapshot()["live"]), 6)


if __name__ == "__main__": unittest.main()
