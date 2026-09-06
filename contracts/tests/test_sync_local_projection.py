"""Pure rebase checks; durable combined promotion is tested separately."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_bootstrap_fixtures import after_image
from build_habit_operation_fixtures import operation
from build_owned_graph_fixtures import derive as owned_vectors
from local_projection_reference import project_local_intents
from protocol_reference import mutation_hash
from test_sync_protocol import mutation, samples


def intent(m, kind="pending", state="active"):
    return {"kind": kind, "state": state, "mutation": m, "payload_hash": mutation_hash(m)}


class LocalProjectionTests(unittest.TestCase):
    def test_rebase_keeps_existing_immutable_recurrence_and_retains_whole_invalid_candidate(self):
        case = next(row for row in owned_vectors()["cases"] if row["id"].endswith("offline-same-revision-different-content"))
        value = project_local_intents([after_image(record) for record in case["input"]["seed"]],
            [intent(m) for m in case["input"]["mutations"]], server_highest=0)
        self.assertEqual(value["projected_sequences"], [1])
        rule = next(row["fact"] for row in value["facts"] if row["target_type"] == "event_recurrence" and row["fact"]["revision"] == 2)
        self.assertEqual(rule["frequency"], "weekly")
        self.assertEqual(value["retained_drafts"][0]["candidate"]["title"], "独立标题")

    def test_pending_and_failed_are_replayed_in_sequence_without_mutating_evidence(self):
        category = samples()["category"]
        rows = [intent(mutation(category, 3, patch={"name": "第三次"})),
                intent(mutation(category, 2, patch={"name": "失败后保留"}), "failed"),
                intent(mutation(category, 1, patch={"description": "保留备注"}))]
        before = copy.deepcopy(rows)
        value = project_local_intents([after_image(category)], rows, server_highest=0)
        self.assertEqual(value["projected_sequences"], [1, 2, 3])
        self.assertEqual(value["facts"][0]["fact"]["name"], "第三次")
        self.assertEqual(value["facts"][0]["fact"]["description"], "保留备注")
        self.assertEqual(rows, before)

    def test_processed_but_unacknowledged_increment_is_not_added_to_snapshot_twice(self):
        data = samples()
        m = operation(data["habit_check_in"], "increment")
        snapshot = [after_image(data[name]) for name in ("habit", "habit_recurrence", "habit_check_in")]
        checkin = next(item for item in snapshot if item["target_type"] == "habit_check_in")
        checkin["fact"]["completed_count_hundredths"] = 600
        checkin["entity_version"] = 2
        value = project_local_intents(snapshot, [intent(m)], server_highest=1)
        self.assertEqual(next(r for r in value["facts"] if r["target_type"] == "habit_check_in")["fact"]["completed_count_hundredths"], 600)
        self.assertEqual(value["retained_drafts"][0]["reason"], "awaiting_exact_receipt")
        self.assertEqual(value["retained_drafts"][0]["mutation"], m)

    def test_remote_delete_preserves_local_candidate_without_resurrection(self):
        category = samples()["category"]
        m = mutation(category, patch={"name": "未同步输入"})
        deleted = {"kind": "deleted_entity_anchor", "target_type": "category", "target_id": category["target_id"], "entity_version": 2}
        value = project_local_intents([deleted], [intent(m, "failed")], server_highest=1)
        self.assertEqual(value["facts"], [])
        self.assertEqual(value["retained_drafts"][0]["candidate"]["name"], "未同步输入")
        self.assertEqual(value["retained_drafts"][0]["reason"], "deleted_baseline")

    def test_superseded_draft_is_retained_when_replacement_failed(self):
        category = samples()["category"]
        rows = [intent(mutation(category, 1, patch={"name": "旧失败"}), "failed", "superseded_pending"),
                intent(mutation(category, 2, patch={"name": "新失败"}), "failed")]
        value = project_local_intents([after_image(category)], rows, server_highest=2)
        self.assertEqual(value["facts"][0]["fact"]["name"], "新失败")
        self.assertEqual(value["retained_drafts"][0]["candidate"]["name"], "旧失败")
        self.assertEqual(len(rows), 2)

    def test_illegal_rebased_quantity_keeps_candidate_and_last_valid_baseline(self):
        data = samples()
        m = operation(data["habit_check_in"], "decrement", number=400)
        snapshot = [after_image(data[name]) for name in ("habit", "habit_recurrence", "habit_check_in")]
        fact = next(item for item in snapshot if item["target_type"] == "habit_check_in")["fact"]
        fact.update(completed_count_hundredths=100, status="partial")
        value = project_local_intents(snapshot, [intent(m, "failed")], server_highest=1)
        self.assertEqual(next(r for r in value["facts"] if r["target_type"] == "habit_check_in")["fact"]["completed_count_hundredths"], 100)
        self.assertEqual(value["retained_drafts"][0]["error"], "HABIT_CHECK_IN_STATE_INVALID")
        self.assertEqual(value["retained_drafts"][0]["candidate"]["completed_count_hundredths"], 100)

    def test_corrupt_hash_or_duplicate_sequence_fails_before_projection(self):
        category = samples()["category"]
        row = intent(mutation(category, patch={"name": "输入"}))
        with self.assertRaisesRegex(ValueError, "SYNC_OUTBOX_CORRUPTED"):
            project_local_intents([after_image(category)], [row, row], server_highest=0)
        row["payload_hash"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_HASH_MISMATCH"):
            project_local_intents([after_image(category)], [row], server_highest=0)


if __name__ == "__main__":
    unittest.main()
