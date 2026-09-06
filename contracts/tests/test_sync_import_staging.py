"""Actual SQLite staging receipts and indivisible initial import publication."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from bootstrap_reference import item_key, validate_snapshot
from build_owned_graph_fixtures import derive, make_mutation
from build_target_fixtures import build
from import_contract_reference import validate_publication
from import_staging_reference import ImportStagingStore, build_initial_batch
from protocol_reference import mutation_hash, validate_terminal_for_mutation

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"
CRASH_POINTS = []


class ImportStagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-staging-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.server = ImportStagingStore(self.path / "server.db", account_id=A)
        self.server.register(A)
        self.server.register(B)
        self.records = copy.deepcopy(derive()["cases"][2]["input"]["seed"])
        self.batch = build_initial_batch(A, C, 0, self.records)

    def send(self, messages, *, device=A):
        results = self.server.exchange(device, 0, [{"mutation": row, "payload_hash": mutation_hash(row)} for row in messages])
        for result, mutation in zip(results, messages):
            validate_terminal_for_mutation(result, mutation)
        return results

    def test_staged_items_are_invisible_and_complete_commit_publishes_typed_graph_once(self):
        staged = self.send(self.batch[:-1])
        self.assertEqual([row["status"] for row in staged], ["staged"] * 4)
        snapshot = self.server.snapshot()
        for table in ("facts", "fields", "anchors", "conflicts", "groups", "import_provenance", "import_mapping"):
            self.assertFalse(snapshot[table], table)
        self.assertEqual(snapshot["devices"][0][1], 4)
        accepted = self.send(self.batch[-1:])[0]
        self.assertEqual((accepted["status"], accepted["import_stage"]), ("accepted", "server_confirmed"))
        snapshot = self.server.snapshot()
        messages = [json.loads(row[2]) for row in snapshot["import_publication_lines"]]
        items = validate_publication(messages)
        self.assertEqual(len(items), 3)
        self.assertFalse(snapshot["anchors"])
        self.assertTrue(all(row["import_provenance"]["source_epoch"] == 0 for row in items))
        marker = self.server.bootstrap_markers()[0]
        validate_snapshot(sorted([*items, marker], key=item_key), upper_bound=accepted["commit_server_sequence"], highest=5)
        replay = self.send(self.batch)
        self.assertEqual([row["original_result"] for row in replay], [*staged, accepted])
        self.assertEqual(self.server.snapshot(), snapshot)

    def test_reserved_slots_reject_ordinary_writes_other_device_and_wrong_ordinal(self):
        self.send(self.batch[:1])
        ordinary = make_mutation(build()["samples"]["category"], 2, patch={"name": "不能抢占"})
        wrong_ordinal = copy.deepcopy(self.batch[1])
        wrong_ordinal["import_item_ordinal"] = 1
        other_device = copy.deepcopy(self.batch[1])
        other_device["client_sequence"] = 1
        for messages, device in (([ordinary], A), ([wrong_ordinal], A), ([other_device], B)):
            before = self.server.snapshot()
            with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"):
                self.send(messages, device=device)
            self.assertEqual(self.server.snapshot(), before)

    def test_commit_missing_or_changed_payload_is_consumed_repair_without_canonical_writes(self):
        for name in ("missing", "changed"):
            self.server = ImportStagingStore(self.path / (name + ".db"), account_id=A)
            self.server.register(A)
            batch = copy.deepcopy(self.batch)
            if name == "changed":
                event = next(row for row in batch if row["target_type"] == "event")
                title = event["payload"]["fact"]["title"]
                event["payload"]["fact"]["title"] = "X" * len(title)
            self.send(batch[:-1])
            if name == "missing":
                with self.server.connect() as db:
                    db.execute("DELETE FROM import_stage_items WHERE ordinal=0")
            rejected = self.send(batch[-1:])[0]
            self.assertEqual((rejected["status"], rejected["import_stage"]), ("rejected", "repair_required"))
            self.assertFalse(self.server.snapshot()["facts"])
            self.assertFalse(self.server.snapshot()["import_publication_lines"])
            self.assertEqual(self.server.snapshot()["devices"][0][1], 5)
            self.assertEqual(self.send(batch[-1:])[0]["original_result"], rejected)

    def test_server_domain_validation_precedes_every_canonical_write(self):
        invalid = copy.deepcopy(self.records)
        event = next(row for row in invalid if row["target_type"] == "event")
        event["fact"]["end_at"] = event["fact"]["start_at"]
        batch = build_initial_batch(A, C, 0, invalid)
        result = self.send(batch)[-1]
        self.assertEqual(result["error"]["code"], "EVENT_TIME_INVALID")
        self.assertFalse(self.server.snapshot()["facts"])
        self.assertFalse(self.server.snapshot()["groups"])

    def test_actual_process_death_keeps_canonical_graph_and_publication_all_or_nothing(self):
        self.send(self.batch[:-1])
        for point in ("import_canonical_fact:event", "import_canonical_fact:event_recurrence", "import_canonical_fact:reminder_intent",
                "import_publication_and_marker", "import_receipt", "import_device_sequence"):
            before = self.server.snapshot()
            request = self.path / "crash.json"
            request.write_text(json.dumps({"path": str(self.server.path), "account": A, "device": A, "mutation": self.batch[-1], "point": point}), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_staging_crash_probe.py"), str(request)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            self.server = ImportStagingStore(self.server.path, account_id=A)
            self.assertEqual(self.server.snapshot(), before)
            CRASH_POINTS.append(point)
        self.assertEqual(self.send(self.batch[-1:])[0]["status"], "accepted")

    def test_provenance_marker_survives_a_later_ordinary_edit_and_fenced_replay_is_zero_write(self):
        sample = build()["samples"]["category"]
        batch = build_initial_batch(A, C, 0, [sample])
        self.send(batch)
        original = self.server.bootstrap_markers()
        self.send([make_mutation(sample, 4, patch={"name": "导入后编辑"})])
        self.assertEqual(self.server.bootstrap_markers(), original)
        self.server.fence(A, str(uuid.uuid4()), 0)
        before = self.server.snapshot()
        with self.assertRaisesRegex(ValueError, "SYNC_TRANSPORT_GENERATION_MISMATCH"):
            self.send(batch)
        self.assertEqual(self.server.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
