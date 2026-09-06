"""Typed root conflict lifecycle, terminal errors, cross-device order and rollback."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import tempfile
import subprocess
from threading import Barrier
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
from conflict_resolution_reference import ConflictStore, validate_resolution
from domain_reference import validate_schema
from protocol_reference import mutation_hash, typed_definition
from test_sync_protocol import A, B, mutation, samples
from build_conflict_resolution_fixtures import derive, FIXTURE

CRASH_POINTS = []
OBSERVED = []


class ConflictResolutionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="excellent-calendar-conflict-resolution-")
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.server = ConflictStore(self.path / "server.db")
        self.server.register(A)
        self.server.register(B)
        self.sample = samples()["category"]
        self.server.seed(self.sample)

    def send(self, m, device=A):
        return self.server.exchange(device, 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])[0]

    def competing(self, *, name="name", partial=False):
        self.send(mutation(self.sample, patch={name: "远端选择"}))
        result = self.send(mutation(self.sample, patch={name: "本机选择", **({"description": "已自动合并"} if partial else {})}), B)
        self.assertEqual(result["status"], "partially_merged" if partial else "conflict")
        return result["conflict_ids"][0]

    def resolve_mutation(self, identifier, sequence=2, mode="keep_local", *, expected=1, manual=None):
        row = next((row for row in self.server.snapshot()["typed_conflicts"] if row[0] == identifier), None)
        record = next(row for row in self.server.snapshot()["facts"] if (row[0], row[1]) == (self.sample["target_type"], self.sample["target_id"]))
        detail = json.loads(row[3]) if row else None
        baseline = {"target_type": record[0], "target_id": record[1], "fact": json.loads(record[3]) if record[3] else copy.deepcopy(detail["recovery_snapshot"]["fact"])}
        keys = {item["key"]["merge_key"] for item in detail["conflicting_groups"]} if detail else {"name"}
        if manual:
            keys |= {key for key, fields in typed_definition(record[0], baseline["fact"])["merge_groups"].items()
                if any(baseline["fact"][field] != manual["fact"][field] for field in fields)}
        m = {"protocol_version": 1, "mutation_id": str(uuid.uuid4()), "client_sequence": sequence,
            "target_type": record[0], "target_id": record[1], "operation_type": "resolve_conflict", "base_entity_version": record[2],
            "causal_predecessors": [{"merge_key": key, "client_sequence": None} for key in sorted(keys)],
            "import_lineage_id": None, "import_batch_id": None, "import_source_workspace_id": None, "import_source_epoch": None,
            "import_item_ordinal": None, "import_manifest_hash": None, "predecessor_batch_id": None,
            "payload": {"conflict_id": identifier, "expected_conflict_version": expected, "prepared_owned_dependencies": [],
                "resolution": {"mode": mode, "group_choices": [{"key": item["key"], "source": "local"} for item in detail["conflicting_groups"]]
                    if mode == "per_field" else [], "manual_candidate": manual}},
            "conflict_recovery_snapshot": baseline, "created_at": "2026-09-06T01:00:00Z"}
        validate_resolution(m, mutation_hash(m))
        return m

    def resolve(self, m, device=B, **options):
        response = self.server.resolve(device, 0, m, mutation_hash(m), **options)
        validate_schema("sync/backend_sync_conflict_resolution_response.schema.json", response)
        return response

    def test_created_partial_projection_is_typed_and_all_four_choices_resolve(self):
        for mode in ("keep_local", "keep_remote", "per_field", "manual_edit"):
            with self.subTest(mode=mode):
                self.server = ConflictStore(self.path / (mode + ".db"))
                self.server.register(A)
                self.server.register(B)
                self.server.seed(self.sample)
                identifier = self.competing(partial=True)
                detail = json.loads(self.server.snapshot()["typed_conflicts"][0][3])
                self.assertEqual(detail["auto_merged_groups"][0]["projection"]["value"], {"description": "已自动合并"})
                manual = copy.deepcopy(self.sample) if mode == "manual_edit" else None
                if manual:
                    manual["fact"].update(name="手动解决", description="已自动合并")
                m = self.resolve_mutation(identifier, mode=mode, manual=manual)
                response = self.resolve(m)
                self.assertEqual(response["result"]["status"], "accepted")
                self.assertEqual(response["current_conflict"]["kind"], "resolved")
                fact = json.loads(self.server.snapshot()["facts"][0][3])
                self.assertEqual(fact["name"], "手动解决" if manual else "远端选择" if mode == "keep_remote" else "本机选择")
                self.assertEqual(fact["description"], "已自动合并")
                # Query by the result's exact identity; UUID order is not server order.
                group = next(json.loads(row[2]) for row in self.server.snapshot()["typed_groups"] if row[0] == response["result"]["effect"]["effect_change_group_id"])
                self.assertEqual(group["conflict_deltas"][0]["kind"], "resolved")
                self.assertEqual(group["conflict_deltas"][0]["resolution_receipt"], response["result"]["receipt"])

    def test_not_found_stale_and_already_resolved_consume_sequence_and_replay(self):
        missing = self.resolve_mutation(str(uuid.uuid4()), sequence=1)
        not_found = self.resolve(missing)
        self.assertEqual(not_found["result"]["failure_code"], "SYNC_CONFLICT_NOT_FOUND")
        # Device B has consumed 1, so create its conflict with 2.
        self.send(mutation(self.sample, patch={"name": "remote"}))
        result = self.send(mutation(self.sample, 2, patch={"name": "local"}), B)
        identifier = result["conflict_ids"][0]
        stale = self.resolve_mutation(identifier, sequence=3, expected=2)
        stale_response = self.resolve(stale)
        self.assertEqual(stale_response["result"]["failure_code"], "SYNC_CONFLICT_VERSION_MISMATCH")
        good = self.resolve_mutation(identifier, sequence=4)
        accepted = self.resolve(good)
        duplicate = self.resolve(stale)
        self.assertEqual(duplicate["result"]["original_result"], stale_response["result"])
        self.assertEqual(duplicate["current_conflict"], stale_response["current_conflict"])
        finished = self.resolve(self.resolve_mutation(identifier, sequence=5))
        self.assertEqual(finished["result"]["failure_code"], "SYNC_CONFLICT_ALREADY_RESOLVED")
        self.assertEqual(finished["result"]["effect"], accepted["result"]["effect"])
        self.assertEqual(next(row[1] for row in self.server.snapshot()["devices"] if row[0] == B), 5)
        self.assertEqual(len(self.server.snapshot()["typed_groups"]), 3)

    def test_domain_rejection_keeps_graph_and_allows_next_resolution(self):
        self.server = ConflictStore(self.path / "habit.db")
        self.server.register(A)
        self.server.register(B)
        self.sample = samples()["habit"]
        self.server.seed(self.sample)
        self.server.seed(samples()["habit_recurrence"])
        identifier = self.competing(name="title")
        invalid = copy.deepcopy(self.sample)
        invalid["fact"].update(start_date="2026-10-01", end_date="2026-09-30")
        m = self.resolve_mutation(identifier, mode="manual_edit", manual=invalid)
        before = self.server.snapshot()
        response = self.resolve(m)
        self.assertEqual(response["result"]["status"], "rejected")
        self.assertEqual(response["result"]["failure_code"], "HABIT_DATE_RANGE_INVALID")
        after = self.server.snapshot()
        for table in ("facts", "fields", "anchors", "conflicts", "groups", "typed_conflicts", "typed_groups"):
            self.assertEqual(after[table], before[table])
        good = self.resolve(self.resolve_mutation(identifier, sequence=3))
        self.assertEqual(good["result"]["status"], "accepted")

    def test_unresolved_writer_gate_and_cross_device_resolution_race(self):
        identifier = self.competing()
        blocked = self.send(mutation(self.sample, 2, patch={"description": "普通编辑"}), A)
        self.assertEqual(blocked["failure_code"], "SYNC_ENTITY_CONFLICT_BLOCKED")
        first = self.resolve_mutation(identifier, sequence=2)
        second = self.resolve_mutation(identifier, sequence=3, mode="keep_remote")
        self.assertEqual(self.resolve(first)["result"]["status"], "accepted")
        self.assertEqual(self.resolve(second, A)["result"]["failure_code"], "SYNC_CONFLICT_ALREADY_RESOLVED")
        ordinary = mutation(self.sample, 4, patch={"description": "现在可编辑"}, base=3)
        self.assertEqual(self.send(ordinary, A)["status"], "accepted")

    def test_exact_success_duplicate_changes_no_facts_or_versions(self):
        identifier = self.competing()
        m = self.resolve_mutation(identifier)
        original = self.resolve(m)
        before = self.server.snapshot()
        result = self.resolve(m)
        self.assertEqual(result["result"]["original_result"], original["result"])
        self.assertEqual(self.server.snapshot(), before)

    def test_every_resolution_transaction_boundary_rolls_back(self):
        identifier = self.competing()
        m = self.resolve_mutation(identifier)
        before = self.server.snapshot()
        for point in ("resolution_fact_and_fields", "resolution_conflict_lifecycle", "resolution_change_group", "resolution_receipt", "resolution_device_sequence"):
            def crash(name):
                if name == point:
                    raise RuntimeError(point)
            with self.assertRaisesRegex(RuntimeError, point):
                self.resolve(m, hook=crash)
            self.assertEqual(ConflictStore(self.server.path).snapshot(), before)
        self.assertEqual(self.resolve(m)["result"]["status"], "accepted")

    def test_wrong_hash_transport_and_gap_never_consume_resolution_sequence(self):
        identifier = self.competing()
        m = self.resolve_mutation(identifier)
        for generation, h, error in ((0, "f" * 64, "SYNC_PAYLOAD_HASH_MISMATCH"), (1, mutation_hash(m), "SYNC_TRANSPORT_GENERATION_MISMATCH")):
            before = self.server.snapshot()
            with self.assertRaisesRegex(ValueError, error):
                self.server.resolve(B, generation, m, h)
            self.assertEqual(self.server.snapshot(), before)
        m["client_sequence"] = 3
        with self.assertRaisesRegex(ValueError, "SYNC_CLIENT_SEQUENCE_GAP"):
            self.resolve(m)

    def test_actual_parallel_resolvers_have_one_winner_and_two_terminal_receipts(self):
        identifier = self.competing()
        requests = [self.resolve_mutation(identifier), self.resolve_mutation(identifier, mode="keep_remote")]
        barrier = Barrier(2)
        def send(index):
            barrier.wait(timeout=10)
            return self.resolve(requests[index], (A, B)[index])
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(send, index) for index in range(2)]
            results = [future.result() for future in futures]
        self.assertEqual(sorted(row["result"]["status"] for row in results), ["accepted", "rejected"])
        loser = next(row for row in results if row["result"]["status"] == "rejected")
        self.assertEqual(loser["result"]["failure_code"], "SYNC_CONFLICT_ALREADY_RESOLVED")
        self.assertEqual([row[1] for row in self.server.snapshot()["devices"]], [2, 2])
        self.assertEqual(len(self.server.snapshot()["typed_groups"]), 3)

    def test_deleted_tombstone_keep_local_restores_and_keep_remote_stays_deleted(self):
        for mode in ("keep_local", "keep_remote"):
            with self.subTest(mode=mode):
                self.server = ConflictStore(self.path / ("deleted-" + mode + ".db"))
                self.server.register(A)
                self.server.register(B)
                self.server.seed(self.sample)
                self.send(mutation(self.sample, operation="delete"))
                outcome = self.send(mutation(self.sample, patch={"name": "保留本机编辑"}), B)
                m = self.resolve_mutation(outcome["conflict_ids"][0], mode=mode)
                if mode == "keep_local":
                    m["causal_predecessors"].append({"merge_key": "lifecycle", "client_sequence": None})
                    m["causal_predecessors"].sort(key=lambda row: row["merge_key"])
                response = self.resolve(m)
                self.assertEqual(response["result"]["status"], "accepted")
                row = self.server.snapshot()["facts"][0]
                self.assertEqual(row[4], int(mode == "keep_remote"))
                self.assertEqual(json.loads(row[3])["name"], "保留本机编辑" if mode == "keep_local" else self.sample["fact"]["name"])
                if mode == "keep_remote":
                    image = next(json.loads(row[2])["entity_changes"][0] for row in self.server.snapshot()["typed_groups"]
                        if row[0] == response["result"]["effect"]["effect_change_group_id"])
                    self.assertEqual(image["delete_server_sequence"], 1)

    def test_actual_process_death_leaves_no_half_resolved_graph_or_receipt(self):
        identifier = self.competing()
        m = self.resolve_mutation(identifier)
        for point in ("resolution_fact_and_fields", "resolution_conflict_lifecycle", "resolution_change_group", "resolution_receipt", "resolution_device_sequence"):
            before = self.server.snapshot()
            request = self.path / "crash.json"
            request.write_text(json.dumps({"path": str(self.server.path), "device": B, "mutation": m, "point": point}), encoding="utf8")
            result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/conflict_resolution_crash_probe.py"), str(request)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 79, result.stdout + result.stderr)
            self.server = ConflictStore(self.server.path)
            self.assertEqual(self.server.snapshot(), before)
            CRASH_POINTS.append(point)
        self.assertEqual(self.resolve(m)["result"]["status"], "accepted")

    def test_retained_unresolved_tombstone_is_pinned_after_180_days(self):
        self.send(mutation(self.sample, operation="delete"))
        outcome = self.send(mutation(self.sample, patch={"name": "旧离线编辑"}), B)
        self.server.server_time = "2027-04-01T00:00:00Z"
        before = self.server.snapshot()
        self.assertFalse(self.server.retire_tombstone_payload(self.sample["target_type"], self.sample["target_id"], retention_floor=2))
        self.assertEqual(self.server.snapshot(), before)
        response = self.resolve(self.resolve_mutation(outcome["conflict_ids"][0], mode="keep_remote"))
        self.assertEqual(response["result"]["status"], "accepted")
        self.assertFalse(self.server.retire_tombstone_payload(self.sample["target_type"], self.sample["target_id"], retention_floor=3))
        self.server.server_time = "2027-05-01T00:00:00Z"
        self.assertTrue(self.server.retire_tombstone_payload(self.sample["target_type"], self.sample["target_id"], retention_floor=3))
        self.assertIsNone(self.server.snapshot()["facts"][0][3])
        self.assertEqual(self.server.snapshot()["deletion_sequences"][0][2], 1)

    def test_late_edit_after_payload_retirement_can_keep_remote_or_restore(self):
        for mode in ("keep_remote", "keep_local"):
            with self.subTest(mode=mode):
                self.server = ConflictStore(self.path / ("anchor-" + mode + ".db"))
                self.server.register(A)
                self.server.register(B)
                self.server.seed(self.sample)
                self.send(mutation(self.sample, operation="delete"))
                self.server.server_time = "2027-04-01T00:00:00Z"
                self.assertTrue(self.server.retire_tombstone_payload(self.sample["target_type"], self.sample["target_id"], retention_floor=1))
                outcome = self.send(mutation(self.sample, patch={"name": "完整保留的本机候选"}), B)
                self.assertEqual(outcome["status"], "conflict")
                m = self.resolve_mutation(outcome["conflict_ids"][0], mode=mode)
                if mode == "keep_local":
                    m["causal_predecessors"] = [{"merge_key": key, "client_sequence": None}
                        for key in sorted(typed_definition(self.sample["target_type"], self.sample["fact"])["merge_groups"])]
                response = self.resolve(m)
                self.assertEqual(response["result"]["status"], "accepted")
                fact = self.server.snapshot()["facts"][0]
                if mode == "keep_remote":
                    self.assertIsNone(fact[3])
                    self.assertEqual(fact[4], 1)
                else:
                    self.assertEqual(json.loads(fact[3])["name"], "完整保留的本机候选")
                    self.assertIsNone(json.loads(fact[3])["deleted_at"])

    def test_manual_resolution_cannot_rewrite_identity_audit_or_server_owned_fields(self):
        identifier = self.competing()
        before = self.server.snapshot()
        for sequence, (field, value) in enumerate((("created_at", "2025-01-01T00:00:00Z"),
                ("updated_at", "2025-01-01T00:00:00Z"), ("reorder_revision", 10)), start=2):
            manual = copy.deepcopy(self.sample)
            manual["fact"] = json.loads(before["facts"][0][3])
            manual["fact"][field] = value
            m = self.resolve_mutation(identifier, sequence=sequence, mode="manual_edit", manual=manual)
            result = self.resolve(m)
            self.assertEqual(result["result"]["failure_code"], "SYNC_RESOLUTION_CANDIDATE_INVALID")
            self.assertEqual(self.server.snapshot()["facts"], before["facts"])
            self.assertEqual(self.server.snapshot()["typed_groups"], before["typed_groups"])
            self.assertEqual(self.resolve(m)["result"]["original_result"], result["result"])

    def test_manual_resolution_preserves_habit_history_even_without_check_in_payload(self):
        self.sample = samples()["habit"]
        self.sample["fact"]["first_check_in_at"] = "2026-01-01T00:00:00Z"
        self.server = ConflictStore(self.path / "history.db")
        self.server.register(A)
        self.server.register(B)
        self.server.seed(self.sample)
        if self.sample["fact"]["recurrence_id"]:
            self.server.seed(samples()["habit_recurrence"])
        identifier = self.competing(name="title")
        before = self.server.snapshot()
        for sequence, (field, value) in enumerate((("first_check_in_at", None),
                ("target_count_hundredths", self.sample["fact"]["target_count_hundredths"] + 100)), start=2):
            manual = copy.deepcopy(self.sample)
            manual["fact"] = json.loads(next(row[3] for row in before["facts"] if row[0] == "habit"))
            manual["fact"][field] = value
            result = self.resolve(self.resolve_mutation(identifier, sequence=sequence, mode="manual_edit", manual=manual))
            self.assertEqual(result["result"]["failure_code"], "HABIT_HISTORY_IMMUTABLE")
            self.assertEqual(self.server.snapshot()["facts"], before["facts"])
            self.assertEqual(self.server.snapshot()["typed_conflicts"], before["typed_conflicts"])

    def test_deleted_entity_per_field_must_choose_one_coherent_lifecycle(self):
        self.send(mutation(self.sample, operation="delete"))
        self.server.server_time = "2027-04-01T00:00:00Z"
        self.assertTrue(self.server.retire_tombstone_payload(self.sample["target_type"], self.sample["target_id"], retention_floor=1))
        outcome = self.send(mutation(self.sample, patch={"name": "恢复标题", "description": "恢复说明"}), B)
        m = self.resolve_mutation(outcome["conflict_ids"][0], mode="per_field")
        m["payload"]["resolution"]["group_choices"][0]["source"] = "remote"
        before = self.server.snapshot()
        rejected = self.resolve(m)
        self.assertEqual(rejected["result"]["failure_code"], "SYNC_RESOLUTION_CANDIDATE_INVALID")
        self.assertEqual(self.server.snapshot()["facts"], before["facts"])
        self.assertEqual(self.resolve(m)["result"]["original_result"], rejected["result"])
        replacement = self.resolve_mutation(outcome["conflict_ids"][0], sequence=3, mode="keep_local")
        replacement["causal_predecessors"] = [{"merge_key": key, "client_sequence": None}
            for key in sorted(typed_definition(self.sample["target_type"], self.sample["fact"])["merge_groups"])]
        self.assertEqual(self.resolve(replacement)["result"]["status"], "accepted")
        restored = json.loads(self.server.snapshot()["facts"][0][3])
        self.assertEqual((restored["name"], restored["description"], restored["deleted_at"]), ("恢复标题", "恢复说明", None))

    def test_fixed_resolution_histories_have_exact_durable_outcomes(self):
        vectors = json.loads(FIXTURE.read_text(encoding="utf8"))
        self.assertEqual(vectors, derive())
        OBSERVED.clear()
        for index, case in enumerate(vectors["cases"]):
            with self.subTest(fixture=case["id"]):
                self.server = ConflictStore(self.path / (str(index) + ".db"))
                self.server.register(A)
                self.server.register(B)
                data = case["input"]
                self.sample = data["baseline"]
                self.server.seed(self.sample)
                for record in data["dependencies"]:
                    self.server.seed(record)
                name = "title" if self.sample["target_type"] == "habit" else "name"
                missing = data["scenario"] == "NOT-FOUND"
                if missing:
                    identifier = str(uuid.uuid4())
                else:
                    self.send(mutation(self.sample, patch=data["remote_patch"]), A)
                    identifier = self.send(mutation(self.sample, patch=data["local_patch"]), B)["conflict_ids"][0]
                if data["scenario"] == "ALREADY-RESOLVED":
                    self.resolve(self.resolve_mutation(identifier, mode="keep_remote"), A)
                m = self.resolve_mutation(identifier, sequence=1 if missing else 2, mode=data["mode"],
                    manual=data["manual_candidate"], expected=data["expected_conflict_version"])
                response = self.resolve(m)
                self.server = ConflictStore(self.server.path)
                snapshot = self.server.snapshot()
                fact = next(json.loads(row[3]) for row in snapshot["facts"] if row[:2] == (self.sample["target_type"], self.sample["target_id"]))
                actual = {"status": response["result"]["status"], "failure_code": response["result"]["failure_code"], "value": fact[name],
                    "current_kind": response["current_conflict"]["kind"], "device_highest": next(row[1] for row in snapshot["devices"] if row[0] == B),
                    "change_groups": len(snapshot["typed_groups"]), "applied_keys": sorted(row["key"]["merge_key"] for row in response["result"]["per_key_results"]
                        if row["causal_disposition"] == "applied")}
                self.assertEqual(actual, case["expected"])
                OBSERVED.append({"id": case["id"], "actual": actual})
