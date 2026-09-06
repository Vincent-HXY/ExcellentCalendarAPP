"""Actual shared sequence/receipt owner for qualified owned-child merge keys."""
import copy
import base64
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import threading
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1")]
from build_owned_graph_fixtures import derive, make_mutation
from build_target_fixtures import build
from owned_sequence_reference import OwnedSequenceStore
from protocol_reference import mutation_hash, validate_terminal_for_mutation
from domain_reference import validate_schema
from build_owned_sequence_fixtures import derive as sequence_vectors
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import KEY, KEY_ID, NOW, after_image
from notice_projection_reference import NoticeLocalStore

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
CRASH_POINTS = []
OBSERVED = []


def child_edit(record, patch, *, predecessor=None, base=1):
    node = make_mutation(record, 1, patch=patch, base=base)
    node["causal_predecessors"] = [{**row, "client_sequence": predecessor} for row in node["causal_predecessors"]]
    return {name: node[name] for name in ("target_type", "target_id", "operation_type", "base_entity_version", "causal_predecessors", "conflict_recovery_snapshot")} | {"payload": patch}


class OwnedSequenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-owned-sequence-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.server = OwnedSequenceStore(self.path / "owned.db")
        self.server.register(A); self.server.register(B)
        samples = build()["samples"]
        self.root, self.child = samples["event"], samples["reminder_intent_event"]

    def seed(self):
        self.server.seed(self.root); self.server.seed(self.child)

    def child_patch(self, advance):
        patch = {name: copy.deepcopy(self.child["fact"][name]) for name in ("is_enabled", "templates")}
        patch["templates"][0]["advance_minutes"] = advance
        return patch

    def command(self, sequence, title, advance, *, predecessor=None, root_predecessor=None):
        value = make_mutation(self.root, sequence, patch={"title": title},
            dependencies=[child_edit(self.child, self.child_patch(advance), predecessor=predecessor)])
        value["mutation_id"] = str(uuid.uuid4())
        value["causal_predecessors"] = [{**row, "client_sequence": root_predecessor} for row in value["causal_predecessors"]]
        return value

    def send(self, *mutations, device=A, confirmed=0):
        results = self.server.exchange(device, 0, [{"mutation": value, "payload_hash": mutation_hash(value)} for value in mutations], confirmed=confirmed)
        for result, value in zip(results, mutations):
            validate_terminal_for_mutation(result, value)
        return results

    def fact(self, target):
        return json.loads(next(row[3] for row in self.server.snapshot()["facts"] if row[0] == target))

    def test_event_and_habit_owned_create_use_real_sequence_and_complete_typed_group(self):
        for case in derive()["cases"][:2]:
            self.server = OwnedSequenceStore(self.path / (case["id"] + ".db"))
            self.server.register(A)
            command = copy.deepcopy(case["input"]["mutations"][0])
            result = self.send(command)[0]
            self.assertEqual(result["status"], "accepted")
            snapshot = self.server.snapshot()
            self.assertEqual(snapshot["devices"][0][1], 1)
            self.assertEqual(len(snapshot["facts"]), 3)
            group = json.loads(snapshot["typed_groups"][0][2])
            self.assertEqual(len(group["entity_changes"]), 3)
            validate_schema("sync/sync_change_group.schema.json", group)
            before = self.server.snapshot()
            self.assertEqual(self.send(command)[0]["original_result"], result)
            self.assertEqual(self.server.snapshot(), before)

    def test_same_device_child_chain_and_root_chain_accept_frozen_old_bases(self):
        self.seed()
        first = self.command(1, "第一次", 2)
        second = self.command(2, "第二次", 3, predecessor=1, root_predecessor=1)
        results = self.send(first, second)
        self.assertEqual([row["status"] for row in results], ["accepted", "accepted"])
        self.assertEqual(self.fact("event")["title"], "第二次")
        self.assertEqual(self.fact("reminder_intent")["templates"][0]["advance_minutes"], 3)
        child = next(row for row in results[1]["per_key_results"] if row["key"]["target_type"] == "reminder_intent")
        self.assertEqual(child["key"]["owner_type"], "event")
        self.assertEqual((child["causal_disposition"], child["resulting_field_version"], child["effective_prior_sequence"], child["effective_prior_version"]),
            ("applied", 3, 1, 2))

    def test_child_no_effect_predecessor_inherits_verified_baseline(self):
        self.seed()
        first = self.command(1, "第一次", 15)
        second = self.command(2, "第二次", 2, predecessor=1, root_predecessor=1)
        results = self.send(first, second)
        row = next(row for row in results[0]["per_key_results"] if row["key"]["target_type"] == "reminder_intent")
        self.assertEqual((row["causal_disposition"], row["effective_prior_sequence"], row["effective_prior_version"]), ("no_effect", None, 1))
        self.assertEqual(results[1]["status"], "accepted")
        self.assertEqual(self.fact("reminder_intent")["templates"][0]["advance_minutes"], 2)

    def test_other_device_child_edit_conflicts_without_discarding_independent_root_title(self):
        self.seed()
        first = self.command(1, "第一次", 2)
        second = self.command(2, "独立标题", 3, predecessor=1, root_predecessor=1)
        self.send(first)
        remote = make_mutation(self.root, 1, patch={"content": "远端独立备注"}, base=2,
            dependencies=[child_edit(self.child, self.child_patch(4), base=2)])
        remote["mutation_id"] = str(uuid.uuid4())
        self.send(remote, device=B)
        result = self.send(second)[0]
        self.assertEqual(result["status"], "partially_merged")
        self.assertEqual(self.fact("event")["title"], "独立标题")
        self.assertEqual(self.fact("event")["content"], "远端独立备注")
        self.assertEqual(self.fact("reminder_intent")["templates"][0]["advance_minutes"], 4)
        detail = json.loads(self.server.snapshot()["typed_conflicts"][0][3])
        self.assertEqual(detail["conflicting_groups"][0]["key"]["target_type"], "reminder_intent")
        self.assertEqual(detail["auto_merged_groups"][0]["projection"]["value"], {"title": "独立标题"})
        blocked = self.command(3, "受门禁保护", 5)
        blocked["base_entity_version"] = 4
        blocked["payload"]["owned_dependencies"][0]["base_entity_version"] = 3
        result = self.send(blocked)[0]
        self.assertEqual(result["failure_code"], "SYNC_ENTITY_CONFLICT_BLOCKED")
        self.assertTrue(all(row["causal_disposition"] == "no_effect" for row in result["per_key_results"]))

    def test_unpublished_owned_rule_uses_absent_candidate_without_inventing_tombstone(self):
        case = derive()["cases"][2]
        for sample in case["input"]["seed"]:
            self.server.seed(sample)
        first, second = copy.deepcopy(case["input"]["mutations"])
        second["client_sequence"] = 1
        root = second["payload"]["patch"]
        root["recurrence_revision"] = 3
        second["conflict_recovery_snapshot"]["recurrence_revision"] = 3
        rule = second["payload"]["owned_dependencies"][0]
        rule["target_id"] = rule["target_id"].split("#")[0] + "#3"
        rule["payload"]["revision"] = 3
        self.send(first)
        result = self.send(second, device=B)[0]
        self.assertEqual(result["status"], "partially_merged")
        snapshot = self.server.snapshot()
        self.assertFalse(any(row[1] == rule["target_id"] for row in snapshot["facts"]))
        detail = json.loads(snapshot["typed_conflicts"][0][3])
        children = [row for row in detail["conflicting_groups"] if row["key"]["target_type"] == "event_recurrence"]
        self.assertTrue(children)
        self.assertTrue(all(row["server_candidate"] == {"kind": "absent"} for row in children))
        self.assertFalse(snapshot["deletion_sequences"])
        for kind, extra in (("server_candidate", {"kind": "absent", "entity_version": 0}), ("local_candidate", {"kind": "absent"})):
            invalid = copy.deepcopy(detail)
            next(row for row in invalid["conflicting_groups"] if row["key"]["target_type"] == "event_recurrence")[kind] = extra
            with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
                validate_schema("sync/sync_conflict_detail.schema.json", invalid)

    def test_cross_key_future_or_unrelated_child_proof_fails_before_any_write(self):
        self.seed()
        first = make_mutation(self.root, 1, patch={"title": "只有根字段"})
        self.send(first)
        for predecessor in (1, 2):
            second = self.command(2, "不能写", 2, predecessor=predecessor, root_predecessor=1)
            before = self.server.snapshot()
            with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"):
                self.send(second)
            self.assertEqual(self.server.snapshot(), before)

    def test_child_success_anchor_survives_confirmed_receipt_cleanup(self):
        self.seed()
        first = self.command(1, "第一次", 2)
        self.send(first)
        self.server.exchange(A, 0, [], confirmed=1)
        with self.server.connect() as db:
            db.execute("DELETE FROM receipts WHERE device=? AND sequence=1", (A,))
        second = self.command(2, "第二次", 3, predecessor=1, root_predecessor=1)
        self.assertEqual(self.send(second, confirmed=1)[0]["status"], "accepted")

    def test_fenced_generation_rejects_even_exact_old_replay_without_writes(self):
        self.seed()
        command = self.command(1, "原内容", 2)
        original = self.send(command)[0]
        self.server.fence(A, str(uuid.uuid4()), 0)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_TRANSPORT_GENERATION_MISMATCH"):
            self.send(command)
        self.assertEqual(self.server.snapshot(), before)
        duplicate = self.server.exchange(A, 1, [{"mutation": command, "payload_hash": mutation_hash(command)}])[0]
        self.assertEqual(duplicate["original_result"], original)
        self.assertEqual(self.server.snapshot(), before)

    def test_two_real_device_connections_serialize_owned_graph_conflicts(self):
        self.seed()
        commands = [self.command(1, "设备 A", 2), self.command(1, "设备 B", 3)]
        barrier = threading.Barrier(2)
        def upload(index):
            barrier.wait(timeout=10)
            return self.send(commands[index], device=(A, B)[index])[0]["status"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(upload, (0, 1)))
        self.assertEqual(sorted(results), ["accepted", "conflict"])
        self.assertEqual([row[1] for row in self.server.snapshot()["devices"]], [1, 1])
        self.assertEqual(len(self.server.snapshot()["typed_groups"]), 2)

    def kill_at(self, command, points, *, device=A):
        before = self.server.snapshot()
        for point in points:
            fixture = self.path / "crash.json"
            fixture.write_text(json.dumps({"path": str(self.server.path), "device": device, "generation": 0,
                "items": [{"mutation": command, "payload_hash": mutation_hash(command)}], "point": point}), encoding="utf8")
            result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/owned_sequence_crash_probe.py"), str(fixture)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 79, result.stdout + result.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, result.stdout)
            self.server = OwnedSequenceStore(self.server.path)
            self.assertEqual(self.server.snapshot(), before, point)
            CRASH_POINTS.append(point)

    def test_process_death_cannot_publish_partial_owned_graph_receipt_or_sequence(self):
        command = copy.deepcopy(derive()["cases"][0]["input"]["mutations"][0])
        self.kill_at(command, ["owned_fact_and_fields:event", "owned_fact_and_fields:event_recurrence", "owned_fact_and_fields:reminder_intent",
            "owned_typed_change_group", "owned_receipt", "owned_device_sequence"])
        self.assertEqual(self.send(command)[0]["status"], "accepted")
        first = make_mutation({"target_type": "event", "target_id": command["target_id"], "fact": command["payload"]["fact"]},
            2, patch={"title": "A 修改"})
        self.send(first)
        conflicting = make_mutation({"target_type": "event", "target_id": command["target_id"], "fact": command["payload"]["fact"]},
            1, patch={"title": "B 修改"})
        conflicting["mutation_id"] = str(uuid.uuid4())
        self.kill_at(conflicting, ["owned_conflict_lifecycle"], device=B)
        self.assertEqual(self.send(conflicting, device=B)[0]["status"], "conflict")

    def test_fixed_owned_sequence_histories_and_exact_replay(self):
        for case in sequence_vectors()["cases"]:
            self.server = OwnedSequenceStore(self.path / (case["id"] + ".db"))
            self.server.register(A); self.server.register(B)
            for record in case["input"]["seed"]:
                self.server.seed(record)
            statuses = []
            for operation in case["input"]["operations"]:
                result = self.send(operation["mutation"], device=operation["device_id"])[0]
                statuses.append(result["status"])
                before = self.server.snapshot()
                self.assertEqual(self.send(operation["mutation"], device=operation["device_id"])[0]["original_result"], result)
                self.assertEqual(self.server.snapshot(), before)
            snapshot = self.server.snapshot()
            actual = {"statuses": statuses, "facts": len(snapshot["facts"]), "groups": len(snapshot["typed_groups"]),
                "conflicts": len(snapshot["typed_conflicts"]), "has_absent_server_candidate": any(
                    row["server_candidate"]["kind"] == "absent" for raw in snapshot["typed_conflicts"]
                    for row in json.loads(raw[3])["conflicting_groups"])}
            self.assertEqual(actual, case["expected"], case["id"])
            OBSERVED.append({"id": case["id"], "actual": actual})

    def test_local_exact_child_receipts_download_and_bootstrap_preserve_causal_anchors(self):
        self.seed()
        bootstrap = BootstrapServer(self.path / "snapshot.db", account_id=B, device_id=A, keys={KEY_ID: KEY}, key_id=KEY_ID)
        local = NoticeLocalStore(self.path / "local.db", device_id=A)
        def promote(items, highest, upper):
            bootstrap.seed(items, highest=highest, upper_bound=upper)
            page = bootstrap.begin(now=NOW, download_limit=5)
            local.begin(page)
            local.stage(page, request_cursor=None)
            local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        promote([after_image(self.root), after_image(self.child)], 0, 0)
        commands = [self.command(1, "第一次", 2), self.command(2, "第二次", 3, predecessor=1, root_predecessor=1)]
        for command in commands:
            local.enqueue(command)
        prepared = [local.prepare(1), local.prepare(2)]
        results = self.send(*commands)
        for result, request in zip(results, prepared):
            local.acknowledge(result, request_id=request)
        self.assertEqual(json.loads(local.snapshot()["state"][0][0])["local_ack"], 0)
        groups = sorted((json.loads(row[2]) for row in self.server.snapshot()["typed_groups"]), key=lambda row: row["server_sequence"])
        request = local.prepare_download()
        response = {"protocol_version": 1, "device_id": A, "sync_transport_generation": 0, "mode": "normal", "results": [], "changes": groups,
            "account_generation": 0, "snapshot_upper_bound": 2, "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="),
            "has_more": False, "accepted_client_sequence_through": 0, "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
        local.apply_download(response, request_id=request)
        self.assertEqual(json.loads(local.snapshot()["state"][0][0])["local_ack"], 2)
        self.assertFalse(local.snapshot()["pending"])
        self.assertFalse(local.snapshot()["effect_gates"])
        anchors = []
        for device, target, entity, key, sequence, version in self.server.snapshot()["anchors"]:
            identity = {"target_type": target, "target_id": entity, "merge_key": key}
            if target == "reminder_intent":
                identity["owner_type"] = "event"
            anchors.append({"kind": "requesting_device_causal_anchor", "key": identity, "client_sequence": sequence, "resulting_field_version": version})
        promote([*groups[-1]["entity_changes"], *anchors], 2, 2)
        local = NoticeLocalStore(local.path, device_id=A)
        facts = {json.loads(row[1])["target_type"]: json.loads(row[1])["fact"] for row in local.snapshot()["presentation"]}
        self.assertEqual(facts["event"]["title"], "第二次")
        self.assertEqual(facts["reminder_intent"]["templates"][0]["advance_minutes"], 3)
        self.assertEqual(len(local.snapshot()["local_anchors"]), 2)
        self.assertEqual(local.notice_status()["unresolved_conflict_count"], 0)


if __name__ == "__main__":
    unittest.main()
