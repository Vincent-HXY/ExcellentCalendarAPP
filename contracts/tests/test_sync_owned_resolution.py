"""Reviewable owned conflict choices, immutable revisions and durable receipts."""
import copy
import base64
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from threading import Barrier
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
from build_owned_graph_fixtures import derive, make_mutation
from build_target_fixtures import build
from domain_reference import validate_schema
from owned_resolution_reference import OwnedResolutionStore, prepare_resolution, identity
from protocol_reference import mutation_hash, validate_terminal_for_mutation
from test_sync_owned_sequence import child_edit
from build_owned_resolution_fixtures import derive as fixed_vectors, FIXTURE
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import KEY, KEY_ID, NOW as BOOTSTRAP_NOW
from notice_projection_reference import NoticeLocalStore

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
NOW = "2026-09-06T04:00:00Z"
CRASH_POINTS = []
OBSERVED = []


class OwnedResolutionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-owned-resolution-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.initialize("initial")

    def initialize(self, name, *, reminder=False, unpublished=False, frozen_input=None):
        self.server = OwnedResolutionStore(self.path / (name + ".db"))
        self.server.register(A)
        self.server.register(B)
        if frozen_input is not None:
            seed, mutations = copy.deepcopy(frozen_input["seed"]), copy.deepcopy(frozen_input["mutations"])
        elif reminder:
            samples = build()["samples"]
            seed = [samples["event"], samples["reminder_intent_event"]]
            mutations = []
            for sequence, (title, advance) in enumerate((("远端标题", 2), ("本机标题", 3)), start=1):
                patch = {name: copy.deepcopy(seed[1]["fact"][name]) for name in ("is_enabled", "templates")}
                patch["templates"][0]["advance_minutes"] = advance
                mutations.append(make_mutation(seed[0], sequence, patch={"title": title}, dependencies=[child_edit(seed[1], patch)]))
        else:
            case = copy.deepcopy(derive()["cases"][2]["input"])
            seed, mutations = case["seed"], case["mutations"]
        for row in seed:
            self.server.seed(row)
        mutations[1]["client_sequence"] = 1
        if unpublished:
            mutations[1]["payload"]["patch"]["recurrence_revision"] = 3
            mutations[1]["conflict_recovery_snapshot"]["recurrence_revision"] = 3
            child = mutations[1]["payload"]["owned_dependencies"][0]
            child["target_id"] = child["target_id"].split("#")[0] + "#3"
            child["payload"]["revision"] = 3
        for device, mutation in zip((A, B), mutations):
            result = self.server.exchange(device, 0, [{"mutation": mutation, "payload_hash": mutation_hash(mutation)}])[0]
        self.conflict_id = result["conflict_ids"][0]
        return seed, mutations

    def state(self):
        snapshot = self.server.snapshot()
        graph = {(row[0], row[1]): {"target_type": row[0], "target_id": row[1], "fact": json.loads(row[3])} for row in snapshot["facts"]}
        versions = {(row[0], row[1]): row[2] for row in snapshot["facts"]}
        detail = json.loads(next(row[3] for row in snapshot["typed_conflicts"] if row[0] == self.conflict_id))
        return graph, versions, detail

    def prepare(self, mode="keep_local", *, sequence=2):
        graph, versions, detail = self.state()
        manual = copy.deepcopy(graph[identity(detail)]) if mode == "manual_edit" else None
        if manual:
            manual["fact"]["title"] = "手动根对象"
        choice = {"mode": mode, "group_choices": [{"key": row["key"], "source": "local"} for row in detail["conflicting_groups"]] if mode == "per_field" else [],
            "manual_candidate": manual}
        return prepare_resolution(detail, graph, versions, choice, sequence, created_at=NOW)

    def resolve(self, mutation, *, device=B, **kwargs):
        result = self.server.resolve(device, 0, mutation, mutation_hash(mutation), **kwargs)
        validate_schema("sync/backend_sync_conflict_resolution_response.schema.json", result)
        validate_terminal_for_mutation(result["result"], mutation)
        return result

    def test_all_choices_preserve_existing_revisions_and_publish_one_coherent_group(self):
        for mode in ("keep_local", "keep_remote", "per_field", "manual_edit"):
            with self.subTest(mode=mode):
                self.initialize(mode)
                before = self.server.snapshot()
                mutation = self.prepare(mode)
                result = self.resolve(mutation)
                self.assertEqual(result["result"]["status"], "accepted")
                graph, _, _ = self.state()
                event = next(row["fact"] for key, row in graph.items() if key[0] == "event")
                self.assertEqual(event["recurrence_revision"], 2 if mode == "keep_remote" else 3)
                if mode == "manual_edit":
                    self.assertEqual(event["title"], "手动根对象")
                for row in before["facts"]:
                    if row[0] == "event_recurrence":
                        self.assertIn(row, self.server.snapshot()["facts"])
                if mode != "keep_remote":
                    new = graph[("event_recurrence", event["recurrence_id"] + "#3")]["fact"]
                    self.assertEqual((new["frequency"], new["start_at"]), ("monthly", event["start_at"]))
                group = next(json.loads(row[2]) for row in self.server.snapshot()["typed_groups"] if row[0] == result["result"]["effect"]["effect_change_group_id"])
                self.assertEqual(len(group["entity_changes"]), 1 if mode == "keep_remote" else 2)
                self.assertEqual(group["conflict_deltas"][0]["kind"], "resolved")
                after = self.server.snapshot()
                self.assertEqual(self.resolve(mutation)["result"]["original_result"], result["result"])
                self.assertEqual(self.server.snapshot(), after)

    def test_mutable_reminder_child_uses_qualified_anchor_and_retains_remote_root_choice(self):
        self.initialize("reminder", reminder=True)
        graph, versions, detail = self.state()
        choice = {"mode": "per_field", "group_choices": [{"key": row["key"], "source": "remote" if row["key"]["target_type"] == "event" else "local"}
            for row in detail["conflicting_groups"]], "manual_candidate": None}
        mutation = prepare_resolution(detail, graph, versions, choice, 2, created_at=NOW)
        result = self.resolve(mutation)
        self.assertEqual(result["result"]["status"], "accepted")
        graph, _, _ = self.state()
        self.assertEqual(next(row["fact"]["title"] for key, row in graph.items() if key[0] == "event"), "远端标题")
        child = next(row for row in result["result"]["per_key_results"] if row["key"]["target_type"] == "reminder_intent")
        self.assertEqual((child["key"]["owner_type"], child["causal_disposition"]), ("event", "applied"))
        self.assertEqual(next(row["fact"]["templates"][0]["advance_minutes"] for key, row in graph.items() if key[0] == "reminder_intent"), 3)

    def test_unpublished_child_can_stay_absent_or_publish_a_new_complete_revision(self):
        for mode in ("keep_remote", "keep_local"):
            self.initialize("absent-" + mode, unpublished=True)
            result = self.resolve(self.prepare(mode))
            self.assertEqual(result["result"]["status"], "accepted")
            graph, _, _ = self.state()
            event = next(row["fact"] for key, row in graph.items() if key[0] == "event")
            self.assertEqual(event["recurrence_revision"], 2 if mode == "keep_remote" else 3)
            self.assertFalse(self.server.snapshot()["deletion_sequences"])

    def test_prepared_child_cannot_smuggle_unselected_values_or_overwrite_existing_revision(self):
        good = self.prepare()
        for index, kind in enumerate(("rule", "identity"), start=2):
            mutation = copy.deepcopy(good)
            mutation["client_sequence"] = index
            mutation["mutation_id"] = str(uuid.uuid4())
            child = mutation["payload"]["prepared_owned_dependencies"][0]
            if kind == "rule":
                child["payload"]["day_of_month"] = 6
            else:
                child["payload"]["revision"] = 2
                child["target_id"] = child["target_id"].split("#")[0] + "#2"
            before = self.server.snapshot()
            result = self.resolve(mutation)
            self.assertEqual(result["result"]["failure_code"], "SYNC_RESOLUTION_CANDIDATE_INVALID")
            self.assertEqual(self.server.snapshot()["facts"], before["facts"])
            self.assertEqual(self.server.snapshot()["typed_conflicts"], before["typed_conflicts"])
            self.assertEqual(self.resolve(mutation)["result"]["original_result"], result["result"])

    def test_invalid_causal_proof_and_old_generation_are_zero_write(self):
        good = self.prepare()
        mutation = copy.deepcopy(good)
        mutation["payload"]["prepared_owned_dependencies"][0]["causal_predecessors"][0]["client_sequence"] = 2
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_CAUSAL_PREDECESSOR_INVALID"):
            self.resolve(mutation)
        self.assertEqual(self.server.snapshot(), before)
        self.server.fence(B, str(uuid.uuid4()), 0)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_TRANSPORT_GENERATION_MISMATCH"):
            self.resolve(good)
        self.assertEqual(self.server.snapshot(), before)

    def test_stale_and_missing_conflicts_consume_sequence_without_publishing_children(self):
        good = self.prepare()
        for sequence, (field, value, code) in enumerate((("expected_conflict_version", 2, "SYNC_CONFLICT_VERSION_MISMATCH"),
                ("conflict_id", str(uuid.uuid4()), "SYNC_CONFLICT_NOT_FOUND")), start=2):
            mutation = copy.deepcopy(good)
            mutation["client_sequence"] = sequence
            mutation["mutation_id"] = str(uuid.uuid4())
            mutation["payload"][field] = value
            before = self.server.snapshot()
            result = self.resolve(mutation)
            self.assertEqual(result["result"]["failure_code"], code)
            self.assertEqual(self.server.snapshot()["facts"], before["facts"])

    def test_parallel_resolvers_serialize_publication_of_one_new_revision(self):
        requests = [self.prepare(), self.prepare("keep_remote")]
        barrier = Barrier(2)
        def send(index):
            barrier.wait(timeout=10)
            return self.resolve(requests[index], device=(A, B)[index])
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(send, i) for i in range(2)]
            results = [future.result() for future in futures]
        self.assertEqual(sorted(row["result"]["status"] for row in results), ["accepted", "rejected"])
        self.assertEqual(next(row["result"]["failure_code"] for row in results if row["result"]["status"] == "rejected"), "SYNC_CONFLICT_ALREADY_RESOLVED")
        self.assertEqual(len(self.server.snapshot()["typed_groups"]), 3)

    def test_process_death_rolls_back_new_revision_pointer_lifecycle_and_receipt_together(self):
        mutation = self.prepare()
        for point in ("owned_resolution_fact:event", "owned_resolution_fact:event_recurrence", "owned_resolution_conflict_lifecycle",
                "owned_resolution_change_group", "resolution_receipt", "resolution_device_sequence"):
            before = self.server.snapshot()
            request = self.path / "crash.json"
            request.write_text(json.dumps({"path": str(self.server.path), "device": B, "mutation": mutation, "point": point}), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/owned_resolution_crash_probe.py"), str(request)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            self.server = OwnedResolutionStore(self.server.path)
            self.assertEqual(self.server.snapshot(), before)
            CRASH_POINTS.append(point)
        self.assertEqual(self.resolve(mutation)["result"]["status"], "accepted")

    def test_fixed_owned_resolution_histories_have_exact_results(self):
        self.assertEqual(json.loads(FIXTURE.read_text(encoding="utf8")), fixed_vectors())
        OBSERVED.clear()
        for case in fixed_vectors()["cases"]:
            self.initialize(case["id"], frozen_input=case["input"])
            before = self.server.snapshot()
            m = self.prepare(case["input"]["mode"])
            result = self.resolve(m)
            graph, _, _ = self.state()
            event = next(row["fact"] for key, row in graph.items() if key[0] == "event")
            selected = graph[("event_recurrence", event["recurrence_id"] + "#" + str(event["recurrence_revision"]))]["fact"]
            group = next(json.loads(row[2]) for row in self.server.snapshot()["typed_groups"] if row[0] == result["result"]["effect"]["effect_change_group_id"])
            actual = {"status": result["result"]["status"], "current_kind": result["current_conflict"]["kind"],
                "root_revision": event["recurrence_revision"], "selected_frequency": selected["frequency"],
                "retained_old_revisions": sum(row[0] == "event_recurrence" and row in self.server.snapshot()["facts"] for row in before["facts"]),
                "root_title": event["title"], "published_item_count": len(group["entity_changes"])}
            self.assertEqual(actual, case["expected"], case["id"])
            OBSERVED.append({"id": case["id"], "actual": actual})

    def bootstrap_local(self, local):
        snapshot = self.server.snapshot()
        with self.server.connect() as db:
            items = [self.server.image(db, row[0], row[1]) for row in snapshot["facts"]]
        items += [{"kind": "unresolved_conflict", "conflict": json.loads(row[3])} for row in snapshot["typed_conflicts"] if row[2] == "unresolved"]
        items += [{"kind": "requesting_device_causal_anchor", "key": {"target_type": row[1], "target_id": row[2], "merge_key": row[3]},
            "client_sequence": row[4], "resulting_field_version": row[5]} for row in snapshot["anchors"] if row[0] == B]
        bootstrap = BootstrapServer(self.path / (str(uuid.uuid4()) + ".db"), account_id=A, device_id=B, keys={KEY_ID: KEY}, key_id=KEY_ID)
        bootstrap.seed(items, highest=next(row[1] for row in snapshot["devices"] if row[0] == B), upper_bound=snapshot["account"][0][1])
        page = bootstrap.begin(now=BOOTSTRAP_NOW, download_limit=50)
        local.begin(page)
        local.stage(page, request_cursor=None)
        local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])

    def download_resolution(self, local):
        groups = [json.loads(row[2]) for row in self.server.snapshot()["typed_groups"] if row[1] == 3]
        request = local.prepare_download()
        state = json.loads(local.snapshot()["state"][0][0])
        local.apply_download({"protocol_version": 1, "device_id": B, "sync_transport_generation": 0, "mode": "normal", "results": [], "changes": groups,
            "account_generation": 0, "snapshot_upper_bound": 3, "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="),
            "has_more": False, "accepted_client_sequence_through": state["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}, request_id=request)

    def test_owned_result_requires_whole_effect_before_local_confirmation_and_survives_bootstrap(self):
        local = NoticeLocalStore(self.path / "local.db", device_id=B)
        self.bootstrap_local(local)
        mutation = self.prepare()
        local.enqueue(mutation)
        request = local.prepare(2)
        result = self.resolve(mutation)
        local.acknowledge(result["result"], request_id=request)
        self.assertEqual(json.loads(local.snapshot()["state"][0][0])["local_ack"], 1)
        self.assertEqual(local.notice_status()["unresolved_conflict_count"], 1)
        self.download_resolution(local)
        self.assertEqual(json.loads(local.snapshot()["state"][0][0])["local_ack"], 2)
        self.assertFalse(local.snapshot()["effect_gates"])
        self.assertEqual(local.notice_status()["unresolved_conflict_count"], 0)
        self.bootstrap_local(local)
        local = NoticeLocalStore(local.path, device_id=B)
        event = next(json.loads(row[1])["fact"] for row in local.snapshot()["presentation"] if json.loads(row[1])["target_type"] == "event")
        self.assertEqual(event["recurrence_revision"], 3)
        self.assertFalse(local.snapshot()["failed"])

    def test_losing_owned_manual_candidate_remains_exact_after_apply_bootstrap_and_restart(self):
        local = NoticeLocalStore(self.path / "loser.db", device_id=B)
        self.bootstrap_local(local)
        mutation = self.prepare("manual_edit")
        local.enqueue(mutation)
        request = local.prepare(2)
        self.resolve(self.prepare("keep_remote"), device=A)
        rejected = self.resolve(mutation)
        local.acknowledge(rejected["result"], request_id=request)
        self.download_resolution(local)
        self.bootstrap_local(local)
        local = NoticeLocalStore(local.path, device_id=B)
        self.assertEqual(len(local.snapshot()["failed"]), 1)
        draft = json.loads(local.snapshot()["retained_drafts"][0][1])
        self.assertEqual((draft["mutation"], draft["payload_hash"]), (mutation, mutation_hash(mutation)))
        self.assertFalse(local.snapshot()["effect_gates"])
        self.assertEqual(local.notice_status()["unresolved_conflict_count"], 0)


if __name__ == "__main__":
    unittest.main()
