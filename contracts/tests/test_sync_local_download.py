"""Independent local recovery and atomicity checks with typed wire fixtures."""
import copy
import base64
import json
from pathlib import Path
import subprocess
import sys
import uuid

from test_sync_local_intents import LocalIntentTests, terminal, ROOT
from build_bootstrap_fixtures import A, D, NOW, after_image, all_kinds
from bootstrap_reference import page_set_digest
from local_download_reference import group_hash
from local_intent_reference import LocalIntentStore
from protocol_reference import ProtocolStore, digest, mutation_hash
from test_sync_protocol import mutation
from sqlite_reference import connect
from counter_reference import MAXIMUM
from build_habit_operation_fixtures import derive, operation
from habit_operation_reference import HabitOperationStore

CRASH_POINTS = []


def group(*items, sequence=1, deltas=None, identifier=None):
    value = {"kind": "change_group", "change_group_id": identifier or str(uuid.uuid4()), "server_sequence": sequence,
        "entity_changes": list(items), "conflict_deltas": deltas or []}
    value["payload_hash"] = group_hash(value)
    return value


def revised(record, **fields):
    value = after_image(record)
    value["entity_version"] = 2
    value["fact"].update(fields)
    for field in value["field_versions"]:
        field["field_version"] = 2
    return value


class LocalDownloadTests(LocalIntentTests):
    # Reuse setup/helpers, not the parent's test cases.
    test_rejected_intent_survives_bootstrap_restart_and_exact_discard = None
    test_existing_pending_is_not_deleted_or_confirmed_from_snapshot_highest = None
    test_effect_gate_clears_only_when_full_bootstrap_covers_it = None
    test_replacement_failure_preserves_both_drafts_and_success_waits_for_apply = None

    def response(self, *groups, upper=None, more=False):
        return {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
            "changes": list(groups), "account_generation": 0, "snapshot_upper_bound": upper if upper is not None else groups[-1]["server_sequence"],
            "next_cursor": base64.urlsafe_b64encode(b"synthetic opaque boundary " + uuid.uuid4().bytes).decode().rstrip("="), "has_more": more,
            "accepted_client_sequence_through": self.state()["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}

    def pull(self, response, **arguments):
        request = self.local.prepare_download()
        self.local.apply_download(response, request_id=request, **arguments)
        return request

    def assert_zero_write(self, error, action):
        before = self.local.snapshot()
        with self.assertRaisesRegex(ValueError, error):
            action()
        self.assertEqual(self.local.snapshot(), before)

    def promote(self, items, *, highest, upper, now):
        self.server.seed(items, highest=highest, upper_bound=upper)
        page = self.server.begin(now=now, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        self.local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])

    @staticmethod
    def actual_habit_images(server):
        state = server.snapshot()
        images = []
        for target, identifier, version, raw, deleted, delete_version, last_group in state["facts"]:
            record = {"target_type": target, "target_id": identifier, "fact": json.loads(raw)}
            item = after_image(record)
            item["entity_version"] = version
            versions = {key: v for t, i, key, v in state["fields"] if (t, i) == (target, identifier)}
            for row in item["field_versions"]:
                row["field_version"] = versions[row["key"]["merge_key"]]
            images.append(item)
        return images

    def accepted_habit_without_local_ack(self):
        vectors = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]
        backend = HabitOperationStore(self.directory / "habit-backend.sqlite")
        backend.register(D)
        for name in ("habit", "habit_recurrence", "habit_check_in"):
            backend.seed(vectors[name])
        self.promote(self.actual_habit_images(backend), highest=0, upper=0, now=NOW + 86400)
        m = operation(vectors["habit_check_in"], "increment", number=100)
        self.queue(m)
        self.assertEqual(self.total(), 600)
        result = backend.exchange(D, 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])[0]
        self.assertEqual(result["status"], "accepted")
        return backend, m, result

    def total(self):
        facts = [json.loads(row[1]) for row in self.local.snapshot()["presentation"]]
        return next(row["fact"]["completed_count_hundredths"] for row in facts if row["target_type"] == "habit_check_in")

    def kill_at(self, method, arguments, points):
        for point in points:
            before = self.local.snapshot()
            file = self.directory / "crash.json"
            file.write_text(json.dumps({"path": str(self.local.path), "device_id": D, "method": method,
                "arguments": arguments, "point": point}), encoding="utf8")
            result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/local_intent_crash_probe.py"), str(file)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 79, result.stdout + result.stderr)
            self.local = LocalIntentStore(self.local.path, device_id=D)
            self.assertEqual(self.local.snapshot(), before, point)
            CRASH_POINTS.append(point)

    def test_failed_overlay_rebases_over_normal_download_and_exact_replay(self):
        m = mutation(self.category, patch={"name": "保留输入"})
        self.queue(m)
        self.ack(terminal(m))
        response = self.response(group(revised(self.category, description="远端更改")))
        request = self.pull(response)
        self.assertEqual(self.fact()["name"], "保留输入")
        self.assertEqual(self.fact()["description"], "远端更改")
        self.assertEqual(self.state()["local_ack"], 1)
        before = self.local.snapshot()
        self.local.apply_download(response, request_id=request)
        self.assertEqual(self.local.snapshot(), before)
        self.assertEqual(len(before["pending"]), 0)

    def test_group_effect_apply_unlocks_writer_and_contiguous_ack(self):
        m = mutation(self.category, patch={"name": "新名字"})
        self.queue(m)
        g = group(revised(self.category, name="新名字"))
        self.ack(terminal(m, status="accepted", effect={"effect_change_group_id": g["change_group_id"], "effect_group_last_server_sequence": 1}))
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 1)
        self.pull(self.response(g))
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 0)
        self.assertEqual(self.state()["local_ack"], 1)
        self.assertEqual(self.fact()["name"], "新名字")

    def test_receipt_binding_rejects_wrong_request_hash_device_and_changed_replay(self):
        m = mutation(self.category, patch={"name": "输入"})
        self.queue(m)
        good = terminal(m)
        self.assert_zero_write("SYNC_SEQUENCE_ROUTE_MISMATCH", lambda: self.local.acknowledge(good, request_id=str(uuid.uuid4())))
        bad = copy.deepcopy(good)
        bad["receipt"]["device_id"] = A
        self.assert_zero_write("SYNC_SEQUENCE_ROUTE_MISMATCH", lambda: self.ack(bad))
        bad = copy.deepcopy(good)
        bad["receipt"]["payload_hash"] = "f" * 64
        self.assert_zero_write("SYNC_SEQUENCE_ROUTE_MISMATCH", lambda: self.ack(bad))
        self.ack(good)
        before = self.local.snapshot()
        self.ack(good)
        self.assertEqual(self.local.snapshot(), before)
        bad = copy.deepcopy(good)
        bad["receipt"]["receipt_id"] = str(uuid.uuid4())
        self.assert_zero_write("SYNC_SEQUENCE_REPLAY_MISMATCH", lambda: self.ack(bad))

    def test_stale_page_wrong_hash_generation_and_same_sequence_are_atomic(self):
        g = group(revised(self.category, description="first"))
        response = self.response(g)
        request = self.local.prepare_download()
        stale = self.local.prepare_download()
        bad = copy.deepcopy(response)
        bad["changes"][0]["payload_hash"] = "0" * 64
        self.assert_zero_write("SYNC_PAYLOAD_HASH_MISMATCH", lambda: self.local.apply_download(bad, request_id=request))
        bad = copy.deepcopy(response)
        bad["account_generation"] = 1
        self.assert_zero_write("SYNC_CURSOR_GENERATION_MISMATCH", lambda: self.local.apply_download(bad, request_id=request))
        self.local.apply_download(response, request_id=request)
        self.assert_zero_write("SYNC_APPLY_FAILED", lambda: self.local.apply_download(response, request_id=stale))
        request = self.local.prepare_download()
        self.assert_zero_write("SYNC_APPLY_FAILED", lambda: self.local.apply_download(response, request_id=request))

    def test_download_fixed_upper_and_opaque_next_cursor(self):
        response = self.response(group(revised(self.category, description="第一页")), upper=2, more=True)
        self.pull(response)
        self.assertEqual(self.state()["download_upper"], 2)
        self.assertEqual(self.state()["upper_bound"], 1)
        request = self.local.prepare_download()
        wrong = self.response(upper=3)
        self.assert_zero_write("SYNC_APPLY_FAILED", lambda: self.local.apply_download(wrong, request_id=request))
        final = self.response(upper=2)
        self.local.apply_download(final, request_id=request)
        self.assertIsNone(self.state()["download_upper"])
        self.assertEqual(self.state()["cursor"], final["next_cursor"])

    def test_sent_pending_with_unknown_receipt_is_retained_after_download(self):
        m = mutation(self.category, patch={"name": "可能已在云端"})
        self.queue(m)
        self.pull(self.response(group(revised(self.category, name="可能已在云端"))))
        self.assertEqual(len(self.local.snapshot()["pending"]), 1)
        self.assertEqual(self.state()["local_ack"], 0)
        self.assertEqual(json.loads(self.local.snapshot()["retained_drafts"][0][1])["reason"], "awaiting_exact_receipt")
        self.assert_zero_write("SYNC_ENTITY_SYNC_EFFECT_PENDING", lambda: self.local.enqueue(mutation(self.category, 2, patch={"description": "later"})))

    def test_actual_habit_lost_receipt_bootstrap_restart_never_doubles_increment(self):
        backend, m, result = self.accepted_habit_without_local_ack()
        self.promote(self.actual_habit_images(backend), highest=1, upper=1, now=NOW + 2 * 86400)
        self.local = LocalIntentStore(self.local.path, device_id=D)
        self.assertEqual(self.total(), 600)
        self.assertEqual(self.state()["local_ack"], 0)
        self.assertEqual(len(self.local.snapshot()["pending"]), 1)
        duplicate = backend.exchange(D, 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])[0]
        self.assertEqual(duplicate["status"], "duplicate")
        self.local.acknowledge(duplicate, request_id=self.prepared[1])
        self.assertEqual(self.total(), 600)
        self.assertEqual(self.state()["local_ack"], 1)
        self.assertEqual(len(self.local.snapshot()["pending"]), 0)

    def test_actual_habit_lost_receipt_normal_download_never_doubles_increment(self):
        backend, m, result = self.accepted_habit_without_local_ack()
        effect = result["effect"]
        self.pull(self.response(group(*self.actual_habit_images(backend), identifier=effect["effect_change_group_id"],
            sequence=effect["effect_group_last_server_sequence"])))
        self.assertEqual(self.total(), 600)
        self.assertEqual(len(self.local.snapshot()["uncertain_pending"]), 1)
        self.ack(result)
        self.assertEqual(self.total(), 600)
        self.assertEqual(self.state()["local_ack"], 1)

    def test_conflict_created_resolved_and_late_created_preserve_entity_gate(self):
        detail = next(item["conflict"] for item in all_kinds() if item["kind"] == "unresolved_conflict")
        key = {"target_type": "category", "target_id": self.category["target_id"], "merge_key": "name"}
        detail.update(target_id=self.category["target_id"], recovery_snapshot=copy.deepcopy(self.category))
        detail["conflicting_groups"][0]["key"] = key
        for choice in ("server_candidate", "local_candidate"):
            detail["conflicting_groups"][0][choice]["projection"].update(key)
        detail["conflicting_groups"][0]["server_candidate"]["projection"]["value"]["name"] = self.category["fact"]["name"]
        created = {"kind": "created", "conflict": detail}
        self.pull(self.response(group(sequence=1, deltas=[created])))
        self.assert_zero_write("SYNC_ENTITY_CONFLICT_BLOCKED", lambda: self.local.enqueue(mutation(self.category, patch={"name": "普通编辑"})))
        resolution = {"kind": "resolved", "conflict_id": detail["conflict_id"], "conflict_version": 2,
            "resolved_at": "2026-09-05T02:00:00Z", "resolution_mode": "keep_remote", "resulting_entity_version": 2,
            "resolution_receipt": terminal(mutation(self.category, patch={"name": "resolve"}))["receipt"]}
        self.pull(self.response(group(revised(self.category), sequence=2, deltas=[resolution])))
        self.pull(self.response(group(sequence=3, deltas=[created])))
        unresolved = [json.loads(raw) for _, raw in self.local.snapshot()["live"] if json.loads(raw)["kind"] == "unresolved_conflict"]
        self.assertEqual(unresolved, [])
        self.local.enqueue(mutation(self.category, patch={"name": "解决后编辑"}))

    def test_corrupted_frozen_journal_is_rejected_on_reopen(self):
        m = mutation(self.category, patch={"name": "不得静默变化"})
        self.queue(m)
        with connect(self.local.path) as db:
            db.execute("UPDATE frozen_intents SET hash=?", ("0" * 64,))
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_HASH_MISMATCH"):
            LocalIntentStore(self.local.path, device_id=D)

    def test_real_successor_chain_pins_ack_until_pending_and_effects_are_terminal(self):
        server = ProtocolStore(self.directory / "causal-server.db")
        server.register(D)
        server.seed(self.category)
        first = mutation(self.category, patch={"name": "第一条"})
        second = mutation(self.category, 2, patch={"name": "后继"}, predecessor=1)
        self.queue(first)
        self.queue(second)
        def publish(m):
            result = server.exchange(D, 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])[0]
            image = self.actual_habit_images(server)[0]
            self.ack(result)
            self.pull(self.response(group(image, identifier=result["effect"]["effect_change_group_id"],
                sequence=result["effect"]["effect_group_last_server_sequence"])))
        publish(first)
        self.assertEqual(self.state()["local_ack"], 0)
        self.assertEqual(len(self.local.snapshot()["pending"]), 1)
        publish(second)
        self.assertEqual(self.state()["local_ack"], 2)
        self.assertEqual(self.fact()["name"], "后继")
        self.assertEqual(len(self.local.snapshot()["failed"]), 0)

    def test_remote_field_version_regression_cannot_reset_local_baseline(self):
        self.pull(self.response(group(revised(self.category, description="first"))))
        regressed = revised(self.category, description="regressed")
        regressed["entity_version"] = 3
        regressed["field_versions"][0]["field_version"] = 1
        request = self.local.prepare_download()
        response = self.response(group(regressed, sequence=2))
        self.assert_zero_write("SYNC_APPLY_FAILED", lambda: self.local.apply_download(response, request_id=request))

    def test_rebuilding_and_duplicate_mutation_identity_refuse_new_writer(self):
        m = mutation(self.category, patch={"name": "first"})
        self.queue(m)
        self.ack(terminal(m))
        reused = mutation(self.category, 2, patch={"name": "second"})
        reused["mutation_id"] = m["mutation_id"]
        self.assert_zero_write("SYNC_SEQUENCE_REPLAY_MISMATCH", lambda: self.local.enqueue(reused))
        self.server.seed([after_image(self.category)], highest=1, upper_bound=2)
        page = self.server.begin(now=NOW, download_limit=5)
        self.local.begin(page)
        self.assert_zero_write("SYNC_BOOTSTRAP_INCOMPLETE", lambda: self.local.enqueue(mutation(self.category, 2, patch={"name": "second"})))
        self.assert_zero_write("SYNC_BOOTSTRAP_INCOMPLETE", self.local.prepare_download)

    def test_failed_revision_max_preserves_draft_and_allows_exact_discard(self):
        m = mutation(self.category, patch={"name": "保留"})
        self.queue(m)
        self.ack(terminal(m))
        with connect(self.local.path) as db:
            entry = json.loads(db.execute("SELECT payload FROM failed").fetchone()[0])
            entry["revision"] = MAXIMUM
            db.execute("UPDATE failed SET payload=?", (json.dumps(entry),))
        self.assert_zero_write("SYNC_COUNTER_EXHAUSTED", lambda: self.local.enqueue(mutation(self.category, 2, patch={"name": "另存"}),
            replaces=1, expected_failed_revision=MAXIMUM))
        self.local.discard(1, expected_revision=MAXIMUM)
        self.assertEqual(len(self.local.snapshot()["failed"]), 0)

    def test_bootstrap_cannot_skip_existing_missing_receipts_by_server_ack(self):
        m = mutation(self.category, patch={"name": "lost ack"})
        self.queue(m)
        self.server.seed([after_image(self.category)], highest=1, confirmed=1, upper_bound=2)
        page = self.server.begin(now=NOW, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        self.assert_zero_write("SYNC_BOOTSTRAP_INCOMPLETE", lambda: self.local.finalize(
            expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"]))

    def test_real_process_death_during_journal_and_download_transactions(self):
        m = mutation(self.category, patch={"name": "耐久输入"})
        self.kill_at("enqueue", {"mutation": m}, ["local_intent_enqueue"])
        self.queue(m)
        result = terminal(m)
        self.kill_at("acknowledge", {"result": result, "request_id": self.prepared[1]}, ["local_intent_ack"])
        self.ack(result)
        self.kill_at("discard", {"sequence": 1, "expected_revision": 1}, ["local_intent_discard"])
        response = self.response(group(revised(self.category, description="远端修改")))
        request = self.local.prepare_download()
        self.kill_at("apply_download", {"response": response, "request_id": request}, ["download_entities", "download_conflicts",
            "download_group_receipt", "download_effect_coverage", "download_projection", "download_cursor", "download_page_receipt"])
        self.local.apply_download(response, request_id=request)
        self.assertEqual(self.fact()["name"], "耐久输入")
        self.assertEqual(self.fact()["description"], "远端修改")

    def test_real_process_death_during_combined_bootstrap_finalization(self):
        m = mutation(self.category, patch={"name": "重建保留"})
        self.queue(m)
        self.ack(terminal(m))
        self.server.seed([revised(self.category, description="重建远端")], highest=1, upper_bound=2)
        page = self.server.begin(now=NOW, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        arguments = {"expected_page_set_digest": page_set_digest([page]), "final_cursor": page["terminal_sync_cursor"]}
        self.kill_at("finalize", arguments, ["local_clear_baseline", "local_entities", "local_conflicts_anchors", "local_import_markers",
            "local_intent_effect_coverage", "local_intent_projection", "local_confirmation_cursor", "local_finalize_receipt"])
        self.local.finalize(**arguments)
        self.assertEqual(self.fact()["name"], "重建保留")
        self.assertEqual(self.fact()["description"], "重建远端")


del LocalIntentTests
