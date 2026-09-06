"""Notice ordering, real typed apply composition, durable crash and cleanup."""
import base64
from concurrent.futures import ThreadPoolExecutor
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
from bootstrap_reference import page_set_digest
from build_bootstrap_fixtures import A, D, NOW, identifier
from build_notice_fixtures import derive
from counter_reference import MAXIMUM
from notice_projection_reference import NoticeJournal, NoticeLocalStore
from local_download_reference import group_hash
from protocol_reference import mutation_hash
from sqlite_reference import connect
import test_sync_conflict_local_recovery as recovery_checks
from test_sync_protocol import mutation

OBSERVED = []
CRASH_POINTS = []


class NoticeJournalTests(unittest.TestCase):
    def test_fixed_histories_survive_every_transaction_reopen(self):
        for case in derive()["cases"]:
            with tempfile.TemporaryDirectory(prefix="excellent-calendar-notice-fixed-") as temporary:
                path = Path(temporary) / "notice.db"
                with connect(path) as db:
                    NoticeJournal.initialize(db)
                unresolved, notices, upper, claim = set(), [], 0, None
                for step in case["input"]["steps"]:
                    with connect(path) as db:
                        db.execute("BEGIN IMMEDIATE")
                        if step == "maximum":
                            db.execute("UPDATE notice_state SET next_sequence=?", (MAXIMUM,))
                        elif step == "known_a":
                            unresolved.add(A)
                        elif step in {"begin", "bootstrap"}:
                            upper += 1
                            NoticeJournal.begin(db, kind="bootstrap" if step == "bootstrap" else "download", generation=0,
                                upper_bound=upper, identity=str(upper), unresolved=unresolved)
                        elif step.startswith("create_"):
                            conflict = A if step.endswith("a") else D
                            unresolved.add(conflict)
                            NoticeJournal.observe(db, conflict, resolved=False)
                        elif step == "resolve_a":
                            unresolved.discard(A)
                            NoticeJournal.observe(db, A, resolved=True)
                        elif step == "terminal":
                            value = NoticeJournal.terminal(db, unresolved)
                            if value:
                                notices.append(value)
                        elif step == "claim_a":
                            claim = NoticeJournal.claim(db, *notices[0], unresolved)["disposition"]
                        else:
                            self.fail("Unknown fixed history instruction")
                with connect(path) as db:
                    next_sequence, watermark, exhausted = db.execute("SELECT next_sequence,last_claimed,exhausted FROM notice_state").fetchone()
                    actual = {"unresolved": len(unresolved), "queue": db.execute("SELECT count(*) FROM notice_queue").fetchone()[0],
                        "next_sequence": next_sequence, "last_claimed": watermark, "exhausted": bool(exhausted), "claim_disposition": claim}
                    self.assertEqual(actual, case["expected"], case["id"])
                    self.assertEqual(db.execute("SELECT count(*) FROM notice_discovery").fetchone()[0], 0)
                OBSERVED.append({"id": case["id"], "actual": actual})

    def test_maintenance_uses_watermark_and_preserves_active_window_and_unclaimed_head(self):
        with tempfile.TemporaryDirectory(prefix="excellent-calendar-notice-maintenance-") as temporary:
            path = Path(temporary) / "notice.db"
            with connect(path) as db:
                NoticeJournal.initialize(db)
                db.executemany("INSERT INTO notice_queue VALUES(?,?,0,1)", ((n, identifier(n)) for n in range(1, 602)))
                db.executemany("INSERT INTO notice_members VALUES(?,?)", ((n, identifier(n)) for n in range(1, 602)))
                db.execute("UPDATE notice_state SET last_claimed=600,next_sequence=602")
                NoticeJournal.begin(db, kind="download", generation=0, upper_bound=10, identity="10", unresolved=[])
                NoticeJournal.observe(db, A, resolved=False)
                self.assertEqual(NoticeJournal.maintenance(db, limit=256), 256)
                self.assertEqual(db.execute("SELECT count(*) FROM notice_queue").fetchone()[0], 345)
                self.assertEqual(NoticeJournal.maintenance(db, limit=256), 256)
                self.assertEqual(NoticeJournal.maintenance(db, limit=256), 88)
                self.assertEqual(NoticeJournal.maintenance(db), 0)
                self.assertEqual(db.execute("SELECT sequence FROM notice_queue").fetchall(), [(601,)])
                self.assertEqual(db.execute("SELECT id FROM notice_discovery").fetchall(), [(A,)])
                self.assertEqual(db.execute("SELECT count(*) FROM notice_window").fetchone()[0], 1)

    def test_concurrent_claims_only_commit_once_and_preserve_successor(self):
        with tempfile.TemporaryDirectory(prefix="excellent-calendar-notice-race-") as temporary:
            path = Path(temporary) / "notice.db"
            with connect(path) as db:
                NoticeJournal.initialize(db)
                for upper, conflict in enumerate((A, D), start=1):
                    NoticeJournal.begin(db, kind="download", generation=0, upper_bound=upper, identity=str(upper), unresolved=[])
                    NoticeJournal.observe(db, conflict, resolved=False)
                    NoticeJournal.terminal(db, [conflict])
                head, successor = db.execute("SELECT sequence,id FROM notice_queue ORDER BY sequence").fetchall()
                revision = db.execute("SELECT revision FROM notice_state").fetchone()[0]
            barrier = threading.Barrier(2)
            def claim():
                barrier.wait(timeout=10)
                with connect(path) as db:
                    db.execute("BEGIN IMMEDIATE")
                    return NoticeJournal.claim(db, *head, [A, D])["disposition"]
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: claim(), range(2)))
            self.assertEqual(sorted(results), ["claimed", "no_longer_actionable"])
            with connect(path) as db:
                self.assertEqual(db.execute("SELECT sequence,id FROM notice_queue").fetchall(), [successor])
                self.assertEqual(db.execute("SELECT last_claimed,revision FROM notice_state").fetchone(), (head[0], revision + 1))


class NoticeApplyTests(recovery_checks.ConflictLocalRecoveryTests):
    test_success_is_visible_only_after_typed_group_applies_and_replay_is_exact = None
    test_losing_resolution_retains_manual_draft_after_download_restart_and_new_edit = None
    test_losing_resolution_survives_full_bootstrap_and_explicit_discard = None

    def setUp(self):
        super().setUp()
        self.local = NoticeLocalStore(self.local.path, device_id=D)

    def stage_conflict(self):
        m = mutation(self.sample, patch={"name": "保留候选"})
        self.local.enqueue(m)
        prepared = self.local.prepare(1)
        self.upload(mutation(self.sample, patch={"name": "远端候选"}), A)
        result = self.upload(m, D)
        self.local.acknowledge(result, request_id=prepared)
        return result["conflict_ids"][0]

    def response(self, groups, *, upper, more=False):
        state = json.loads(self.local.snapshot()["state"][0][0])
        return {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
            "changes": groups, "account_generation": 0, "snapshot_upper_bound": upper,
            "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="), "has_more": more,
            "accepted_client_sequence_through": state["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}

    def groups(self):
        return sorted((json.loads(row[2]) for row in self.server.snapshot()["typed_groups"]), key=lambda group: group["server_sequence"])

    def apply(self, response):
        request = self.local.prepare_download()
        self.local.apply_download(response, request_id=request)
        return request

    def test_ack_and_partial_pages_do_not_notify_resolved_in_same_window_net_is_empty(self):
        conflict = self.stage_conflict()
        self.assertEqual(self.local.notice_status()["unresolved_conflict_count"], 0)
        self.assertEqual(self.local.notice_status()["unclaimed_conflict_notice_count"], 0)
        resolver = self.resolution(conflict, manual=False)
        self.server.resolve(A, 0, resolver, mutation_hash(resolver))
        groups = self.groups()
        first = self.response(groups[:2], upper=3, more=True)
        request = self.apply(first)
        partial = self.local.snapshot()
        self.assertEqual(self.local.notice_status()["unresolved_conflict_count"], 1)
        self.assertEqual(self.local.notice_status()["unclaimed_conflict_notice_count"], 0)
        self.local = NoticeLocalStore(self.local.path, device_id=D)
        self.local.apply_download(first, request_id=request)
        self.assertEqual(self.local.snapshot(), partial)
        last = self.response(groups[2:], upper=3)
        self.apply(last)
        self.assertEqual(self.local.notice_status()["unresolved_conflict_count"], 0)
        self.assertEqual(self.local.notice_status()["unclaimed_conflict_notice_count"], 0)
        self.assertFalse(self.local.snapshot()["notice_discovery"])

    def test_claim_response_loss_keeps_red_dot_and_cannot_requeue_exact_page(self):
        self.stage_conflict()
        response = self.response(self.groups(), upper=2)
        request = self.apply(response)
        status = self.local.notice_status()
        self.assertEqual(status["unresolved_conflict_count"], 1)
        self.assertEqual(status["next_conflict_notice_count"], 1)
        self.assertEqual(self.local.claim_notice(status["next_conflict_notice_sequence"], status["next_conflict_notice_id"]),
            {"disposition": "claimed", "count": 1})
        self.local = NoticeLocalStore(self.local.path, device_id=D)
        self.assertEqual(self.local.claim_notice(status["next_conflict_notice_sequence"], status["next_conflict_notice_id"]),
            {"disposition": "no_longer_actionable", "count": 0})
        self.local.apply_download(response, request_id=request)
        status = self.local.notice_status()
        self.assertEqual(status["unresolved_conflict_count"], 1)
        self.assertEqual(status["unclaimed_conflict_notice_count"], 0)

    def test_late_created_delta_cannot_reopen_or_notify_resolved_conflict(self):
        conflict = self.stage_conflict()
        self.apply(self.response(self.groups(), upper=2))
        original_created = copy.deepcopy(self.groups()[1]["conflict_deltas"][0])
        resolver = self.resolution(conflict, manual=False)
        self.server.resolve(A, 0, resolver, mutation_hash(resolver))
        self.apply(self.response(self.groups()[2:], upper=3))
        status = self.local.notice_status()
        self.assertEqual(status["next_conflict_notice_count"], 1)
        self.assertEqual(self.local.claim_notice(status["next_conflict_notice_sequence"], status["next_conflict_notice_id"])["disposition"], "no_longer_actionable")
        late = {"kind": "change_group", "change_group_id": str(uuid.uuid4()), "server_sequence": 4,
            "entity_changes": [], "conflict_deltas": [original_created]}
        late["payload_hash"] = group_hash(late)
        self.apply(self.response([late], upper=4))
        self.assertEqual(self.local.notice_status()["unresolved_conflict_count"], 0)
        self.assertEqual(self.local.notice_status()["unclaimed_conflict_notice_count"], 0)

    def test_bootstrap_carries_partial_discovery_and_complete_rebootstrap_does_not_repeat(self):
        self.stage_conflict()
        self.apply(self.response(self.groups(), upper=3, more=True))
        current = [json.loads(row[1]) for row in self.local.snapshot()["live"]]
        self.bootstrap(current, highest=1, upper=3)
        status = self.local.notice_status()
        self.assertEqual(status["unclaimed_conflict_notice_count"], 1)
        before = self.local.snapshot()
        self.bootstrap(current, highest=1, upper=3)
        self.assertEqual(self.local.snapshot(), before)

    def kill_at(self, method, arguments, points):
        for point in points:
            before = self.local.snapshot()
            fixture = self.root / "notice-crash.json"
            fixture.write_text(json.dumps({"path": str(self.local.path), "device_id": D, "method": method, "arguments": arguments, "point": point}), encoding="utf8")
            completed = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/notice_crash_probe.py"), str(fixture)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(completed.returncode, 79, completed.stdout + completed.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, completed.stdout)
            self.local = NoticeLocalStore(self.local.path, device_id=D)
            self.assertEqual(self.local.snapshot(), before, point)
            CRASH_POINTS.append(method + ":" + point)

    def test_download_notice_and_claim_actual_process_death_are_atomic(self):
        self.stage_conflict()
        response = self.response(self.groups(), upper=2)
        request = self.local.prepare_download()
        self.kill_at("apply_download", {"response": response, "request_id": request},
            ["notice_download_window", "notice_queue_members", "notice_sequence_state", "notice_terminal_journal_cleanup", "download_cursor", "download_page_receipt"])
        self.local.apply_download(response, request_id=request)
        status = self.local.notice_status()
        arguments = {"sequence": status["next_conflict_notice_sequence"], "identifier": status["next_conflict_notice_id"]}
        self.kill_at("claim_notice", arguments, ["notice_claim_watermark", "notice_claim_head_cleanup", "notice_claim_revision"])
        self.assertEqual(self.local.claim_notice(**arguments)["disposition"], "claimed")

    def test_bootstrap_notice_and_cursor_actual_process_death_are_atomic(self):
        self.stage_conflict()
        items = []
        with self.server.connect() as db:
            items.append(self.server.image(db, self.sample["target_type"], self.sample["target_id"]))
            items += [{"kind": "unresolved_conflict", "conflict": json.loads(row[0])} for row in db.execute("SELECT detail FROM typed_conflicts WHERE status='unresolved'")]
        self.bootstrap_server.seed(items, highest=1, upper_bound=2)
        page = self.bootstrap_server.begin(now=NOW, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        arguments = {"expected_page_set_digest": page_set_digest([page]), "final_cursor": page["terminal_sync_cursor"]}
        self.kill_at("finalize", arguments, ["notice_queue_members", "notice_sequence_state", "notice_terminal_journal_cleanup", "local_confirmation_cursor", "local_finalize_receipt"])
        self.local.finalize(**arguments)
        self.assertEqual(self.local.notice_status()["unclaimed_conflict_notice_count"], 1)


if __name__ == "__main__":
    unittest.main()
