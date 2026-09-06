"""Actual server terminal results, local failed drafts and atomic resolution apply."""
import base64
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, after_image
from conflict_resolution_reference import ConflictStore
from local_intent_reference import LocalIntentStore
from protocol_reference import mutation_hash
from test_sync_protocol import mutation, samples


class ConflictLocalRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="excellent-calendar-conflict-local-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.server = ConflictStore(self.root / "business.db")
        self.server.register(A)
        self.server.register(D)
        self.sample = samples()["category"]
        self.server.seed(self.sample)
        self.bootstrap_server = BootstrapServer(self.root / "bootstrap.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        self.local = LocalIntentStore(self.root / "local.db", device_id=D)
        self.bootstrap([after_image(self.sample)], highest=0, upper=0)

    def bootstrap(self, items, *, highest, upper):
        self.bootstrap_server.seed(items, highest=highest, upper_bound=upper)
        page = self.bootstrap_server.begin(now=NOW, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        self.local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])

    def upload(self, m, device):
        return self.server.exchange(device, 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])[0]

    def download(self, after=0):
        groups = sorted((json.loads(row[2]) for row in self.server.snapshot()["typed_groups"] if row[1] > after), key=lambda row: row["server_sequence"])
        request = self.local.prepare_download()
        state = json.loads(self.local.snapshot()["state"][0][0])
        response = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [], "changes": groups,
            "account_generation": 0, "snapshot_upper_bound": groups[-1]["server_sequence"], "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip("="),
            "has_more": False, "accepted_client_sequence_through": state["server_ack"], "retention_floor_server_sequence": 0,
            "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
        self.local.apply_download(response, request_id=request)

    def conflict(self):
        local = mutation(self.sample, patch={"name": "本机候选"})
        self.local.enqueue(local)
        request = self.local.prepare(1)
        self.upload(mutation(self.sample, patch={"name": "远端候选"}), A)
        terminal = self.upload(local, D)
        self.assertEqual(terminal["status"], "conflict")
        self.local.acknowledge(terminal, request_id=request)
        self.download()
        return terminal["conflict_ids"][0]

    def resolution(self, identifier, *, manual):
        with self.server.connect() as db:
            baseline = self.server.image(db, self.sample["target_type"], self.sample["target_id"])
        candidate = {name: copy.deepcopy(baseline[name]) for name in ("target_type", "target_id", "fact")}
        if manual:
            candidate["fact"]["name"] = "不能丢的手动草稿"
        return {"protocol_version": 1, "mutation_id": str(uuid.uuid4()), "client_sequence": 2,
            "target_type": self.sample["target_type"], "target_id": self.sample["target_id"], "operation_type": "resolve_conflict",
            "base_entity_version": baseline["entity_version"], "causal_predecessors": [{"merge_key": "name", "client_sequence": None}],
            "import_lineage_id": None, "import_batch_id": None, "import_source_workspace_id": None, "import_source_epoch": None,
            "import_item_ordinal": None, "import_manifest_hash": None, "predecessor_batch_id": None,
            "payload": {"conflict_id": identifier, "expected_conflict_version": 1, "prepared_owned_dependencies": [],
                "resolution": {"mode": "manual_edit" if manual else "keep_remote", "manual_candidate": candidate if manual else None, "group_choices": []}},
            "conflict_recovery_snapshot": candidate, "created_at": "2026-09-06T01:00:00Z"}

    def prepare_losing_manual_resolution(self):
        identifier = self.conflict()
        local = self.resolution(identifier, manual=True)
        self.local.enqueue(local)
        request = self.local.prepare(2)
        winner = self.resolution(identifier, manual=False)
        accepted = self.server.resolve(A, 0, winner, mutation_hash(winner))
        rejected = self.server.resolve(D, 0, local, mutation_hash(local))
        self.assertEqual(accepted["result"]["status"], "accepted")
        self.assertEqual(rejected["result"]["failure_code"], "SYNC_CONFLICT_ALREADY_RESOLVED")
        self.local.acknowledge(rejected["result"], request_id=request)
        self.assertEqual(len(self.local.snapshot()["failed"]), 1)
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 1)
        return local

    def test_success_is_visible_only_after_typed_group_applies_and_replay_is_exact(self):
        identifier = self.conflict()
        m = self.resolution(identifier, manual=True)
        self.local.enqueue(m)
        request = self.local.prepare(2)
        response = self.server.resolve(D, 0, m, mutation_hash(m))
        self.local.acknowledge(response["result"], request_id=request)
        before = self.local.snapshot()
        self.assertEqual(sum(json.loads(row[1])["kind"] == "unresolved_conflict" for row in before["live"]), 1)
        self.assertEqual(len(before["effect_gates"]), 1)
        self.download(after=2)
        after = self.local.snapshot()
        self.assertEqual(sum(json.loads(row[1])["kind"] == "unresolved_conflict" for row in after["live"]), 0)
        self.assertEqual(json.loads(after["state"][0][0])["local_ack"], 2)
        self.assertEqual(json.loads(after["presentation"][0][1])["fact"]["name"], "不能丢的手动草稿")
        duplicate = self.server.resolve(D, 0, m, mutation_hash(m))
        self.local.acknowledge(duplicate["result"], request_id=request)
        self.assertEqual(self.local.snapshot(), after)

    def test_losing_resolution_retains_manual_draft_after_download_restart_and_new_edit(self):
        original = self.prepare_losing_manual_resolution()
        self.download(after=2)
        self.local = LocalIntentStore(self.local.path, device_id=D)
        draft = json.loads(self.local.snapshot()["retained_drafts"][0][1])
        self.assertEqual(draft["mutation"], original)
        self.assertEqual(draft["error"], "SYNC_CONFLICT_NOT_FOUND")
        self.assertEqual(json.loads(self.local.snapshot()["state"][0][0])["local_ack"], 2)
        edit = mutation(self.sample, 3, patch={"name": "不能丢的手动草稿"}, base=3)
        self.local.enqueue(edit, replaces=2, expected_failed_revision=1)
        request = self.local.prepare(3)
        self.local.acknowledge(self.upload(edit, D), request_id=request)
        self.assertEqual(len(self.local.snapshot()["failed"]), 1)
        self.download(after=3)
        self.assertEqual(len(self.local.snapshot()["failed"]), 0)
        self.assertEqual(json.loads(self.local.snapshot()["presentation"][0][1])["fact"]["name"], "不能丢的手动草稿")

    def test_losing_resolution_survives_full_bootstrap_and_explicit_discard(self):
        original = self.prepare_losing_manual_resolution()
        with self.server.connect() as db:
            image = self.server.image(db, self.sample["target_type"], self.sample["target_id"])
        self.bootstrap([image], highest=2, upper=3)
        self.local = LocalIntentStore(self.local.path, device_id=D)
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 0)
        self.assertEqual(json.loads(self.local.snapshot()["retained_drafts"][0][1])["mutation"], original)
        self.local.discard(2, expected_revision=1)
        self.assertEqual(len(self.local.snapshot()["failed"]), 0)
        self.assertEqual(len(self.local.snapshot()["retained_drafts"]), 0)
