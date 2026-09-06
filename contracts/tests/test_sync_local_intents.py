"""Combined local transactions using literal authenticated-boundary inputs.

These are local Contract fixtures, not a claim that a Backend producer exists.
"""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, after_image
from local_intent_reference import LocalIntentStore
from protocol_reference import mutation_hash, mutation_keys
from test_sync_protocol import mutation, samples
from sqlite_reference import connect


def terminal(m, *, status="rejected", effect=None, device=D):
    return {"status": status, "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
        "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": mutation_hash(m)},
        "effect": effect, "per_key_results": [{"key": {"target_type": m["target_type"], "target_id": m["target_id"], "merge_key": name},
            "causal_disposition": "applied" if status == "accepted" and effect else "no_effect",
            "resulting_field_version": 2 if status == "accepted" and effect else None,
            "effective_prior_sequence": None, "effective_prior_version": m["base_entity_version"]} for name in mutation_keys(m)],
        "conflict_ids": [], "failure_code": "CATEGORY_NOT_FOUND" if status == "rejected" else None, "failure_context": None,
        "import_batch_id": None, "import_stage": None}


class LocalIntentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="excellent-calendar-local-intents-")
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.local = LocalIntentStore(self.directory / "local.sqlite", device_id=D)
        self.server = BootstrapServer(self.directory / "server.sqlite", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        self.category = samples()["category"]
        self.prepared = {}
        self.bootstrap(highest=0, upper=0)

    def bootstrap(self, *, highest, upper, category=None, hook=None, now=NOW):
        self.server.seed([after_image(category or self.category)], highest=highest, confirmed=0, upper_bound=upper)
        page = self.server.begin(now=now, download_limit=5)
        self.local.begin(page)
        self.local.stage(page, request_cursor=None)
        self.local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"], hook=hook)

    def fact(self):
        return json.loads(self.local.snapshot()["presentation"][0][1])["fact"]

    def state(self):
        return json.loads(self.local.snapshot()["state"][0][0])

    def queue(self, m, **options):
        self.local.enqueue(m, **options)
        self.prepared[m["client_sequence"]] = self.local.prepare(m["client_sequence"])

    def ack(self, result, **options):
        self.local.acknowledge(result, request_id=self.prepared[result["receipt"]["client_sequence"]], **options)

    def test_rejected_intent_survives_bootstrap_restart_and_exact_discard(self):
        m = mutation(self.category, patch={"name": "本机未同步的输入"})
        self.queue(m)
        self.ack(terminal(m))
        self.assertEqual(self.fact()["name"], "本机未同步的输入")
        remote = copy.deepcopy(self.category)
        remote["fact"]["description"] = "远端新备注"
        self.bootstrap(highest=1, upper=2, category=remote)
        self.local = LocalIntentStore(self.local.path, device_id=D)
        self.assertEqual(self.fact()["name"], "本机未同步的输入")
        self.assertEqual(self.fact()["description"], "远端新备注")
        self.assertEqual(len(self.local.snapshot()["pending"]), 0)
        self.assertEqual(len(self.local.snapshot()["failed"]), 1)
        with self.assertRaisesRegex(ValueError, "SYNC_FAILED_CHANGE_VERSION_CONFLICT"):
            self.local.discard(1, expected_revision=2)
        self.local.discard(1, expected_revision=1)
        self.assertEqual(self.fact()["name"], self.category["fact"]["name"])

    def test_existing_pending_is_not_deleted_or_confirmed_from_snapshot_highest(self):
        m = mutation(self.category, patch={"name": "等待确切回执"})
        self.queue(m)
        self.bootstrap(highest=1, upper=1)
        self.assertEqual(self.state()["local_ack"], 0)
        self.assertEqual(len(self.local.snapshot()["pending"]), 1)
        draft = json.loads(self.local.snapshot()["retained_drafts"][0][1])
        self.assertEqual(draft["reason"], "awaiting_exact_receipt")
        self.assertEqual(draft["mutation"], m)
        with self.assertRaisesRegex(ValueError, "SYNC_ENTITY_SYNC_EFFECT_PENDING"):
            self.local.enqueue(mutation(self.category, 2, patch={"description": "新编辑"}))
        self.ack(terminal(m))
        self.assertEqual(self.state()["local_ack"], 1)
        self.assertEqual(self.fact()["name"], "等待确切回执")

    def test_effect_gate_clears_only_when_full_bootstrap_covers_it(self):
        m = mutation(self.category, patch={"name": "已成功但尚未应用"})
        effect = {"effect_change_group_id": A, "effect_group_last_server_sequence": 5}
        self.queue(m)
        self.ack(terminal(m, status="accepted", effect=effect))
        self.assertEqual(self.state()["local_ack"], 0)
        self.bootstrap(highest=1, upper=4)
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 1)
        self.assertEqual(self.state()["local_ack"], 0)
        remote = copy.deepcopy(self.category)
        remote["fact"]["name"] = "已成功但尚未应用"
        self.bootstrap(highest=1, upper=5, category=remote, now=NOW + 86400)
        self.assertEqual(len(self.local.snapshot()["effect_gates"]), 0)
        self.assertEqual(self.state()["local_ack"], 1)

    def test_replacement_failure_preserves_both_drafts_and_success_waits_for_apply(self):
        old = mutation(self.category, patch={"name": "旧失败"})
        self.queue(old)
        self.ack(terminal(old))
        new = mutation(self.category, 2, patch={"name": "修复后仍失败"})
        self.queue(new, replaces=1, expected_failed_revision=1)
        self.ack(terminal(new))
        self.assertEqual(len(self.local.snapshot()["failed"]), 2)
        self.assertEqual(self.fact()["name"], "修复后仍失败")
        latest = mutation(self.category, 3, patch={"name": "最终修复"})
        self.queue(latest, replaces=2, expected_failed_revision=1)
        effect = {"effect_change_group_id": A, "effect_group_last_server_sequence": 3}
        self.ack(terminal(latest, status="accepted", effect=effect))
        self.assertEqual(len(self.local.snapshot()["failed"]), 2)
        remote = copy.deepcopy(self.category)
        remote["fact"]["name"] = "最终修复"
        self.bootstrap(highest=3, upper=3, category=remote)
        self.assertEqual(len(self.local.snapshot()["failed"]), 0)
        self.assertEqual(self.fact()["name"], "最终修复")


if __name__ == "__main__":
    unittest.main()
