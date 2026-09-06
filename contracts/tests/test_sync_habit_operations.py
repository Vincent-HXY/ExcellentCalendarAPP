"""Independent concurrent-history and failure recovery checks for Habit operations."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
import sqlite3
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
               str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_habit_operation_fixtures import A, B, TIME, FIXTURE, derive, operation
from habit_operation_reference import HabitOperationStore, operation_hash, validate_local_date
from protocol_reference import mutation_hash, validate_terminal_for_mutation
from domain_reference import validate_fact

OBSERVED = []
CRASH_POINTS = ["operation_binding", "check_in_fact", "parent_history_guard", "change_group", "operation_effect"]


def send(store, mutation, device=A, **options):
    result = store.exchange(device, 0, [{"mutation": mutation, "payload_hash": mutation_hash(mutation)}], **options)[0]
    validate_terminal_for_mutation(result, mutation)
    return result


def seed(path, case):
    store = HabitOperationStore(path)
    store.register(A)
    store.register(B)
    store.seed(case["input"]["habit"])
    if case["input"]["initial"]:
        store.seed(case["input"]["initial"])
    return store


def observe(store, result):
    facts = [r for r in store.snapshot()["facts"] if r[0] == "habit_check_in"]
    fact = json.loads(facts[0][3]) if facts else None
    if fact:
        validate_fact({"target_type": "habit_check_in", "target_id": facts[0][1], "fact": fact})
    return {"status": result["status"], "failure_code": result.get("failure_code"),
            "total": fact["completed_count_hundredths"] if fact else None,
            "deleted": fact["deleted_at"] is not None if fact else False}


class HabitOperationTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="excellent-calendar-habit-operations-")
        self.addCleanup(self.scratch.cleanup)
        self.path = Path(self.scratch.name)

    def test_fixed_operation_histories_and_restart(self):
        vectors = json.loads(FIXTURE.read_text(encoding="utf8"))
        self.assertEqual(vectors, derive())
        OBSERVED.clear()
        for index, case in enumerate(vectors["cases"]):
            with self.subTest(fixture=case["id"]):
                path = self.path / f"case-{index}.db"
                store = seed(path, case)
                values = []
                for step in case["input"]["steps"]:
                    # Every attempted request crosses a real close/reopen.
                    store = HabitOperationStore(path)
                    result = send(store, step["mutation"], step["device"])
                    value = observe(store, result)
                    self.assertEqual(value, step["expected"])
                    values.append(value)
                OBSERVED.append({"id": case["id"], "actual": values})

    def test_actual_parallel_additive_requests_keep_both_updates(self):
        case = derive()["cases"][0]
        store = seed(self.path / "concurrent.db", case)
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(send, store, step["mutation"], step["device"]) for step in case["input"]["steps"]]
            results = [f.result() for f in futures]
        self.assertTrue(all(r["status"] == "accepted" for r in results))
        self.assertEqual(observe(store, results[-1])["total"], 800)
        self.assertEqual(len(store.snapshot()["habit_operations"]), 2)

    def test_first_parent_guard_and_all_five_boundaries_roll_back(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("first-increment-with-atomic-parent-guard"))
        path = self.path / "rollback.db"
        store = seed(path, case)
        before = store.snapshot()
        for point in CRASH_POINTS:
            def crash(name):
                if name == point:
                    raise RuntimeError("injected_" + name)
            store = HabitOperationStore(path, checkpoint=crash)
            with self.assertRaisesRegex(RuntimeError, point):
                send(store, case["input"]["steps"][0]["mutation"])
            self.assertEqual(HabitOperationStore(path).snapshot(), before)
        store = HabitOperationStore(path)
        send(store, case["input"]["steps"][0]["mutation"])
        parent = next(r for r in store.snapshot()["facts"] if r[0] == "habit")
        self.assertEqual(json.loads(parent[3])["first_check_in_at"], TIME)
        group = json.loads(store.snapshot()["groups"][0][2])
        self.assertEqual(group["owned_after_image"]["version"], 2)

    def test_actual_process_death_at_all_transaction_boundaries(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("first-increment-with-atomic-parent-guard"))
        path = self.path / "process-death.db"
        request = self.path / "request.json"
        request.write_text(json.dumps(case["input"]["steps"][0]), encoding="utf8")
        before = seed(path, case).snapshot()
        for point in CRASH_POINTS:
            result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/habit_operation_crash_probe.py"),
                str(path), point, str(request)], capture_output=True, text=True, encoding="utf8", timeout=60)
            self.assertEqual(result.returncode, 79, result.stderr)
            self.assertEqual(HabitOperationStore(path).snapshot(), before, point)
        send(HabitOperationStore(path), case["input"]["steps"][0]["mutation"])

    def test_operation_identity_survives_safe_receipt_and_group_cleanup(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("new-envelope-same-operation"))
        store = seed(self.path / "retained-identity.db", case)
        original = send(store, case["input"]["steps"][0]["mutation"])
        with store.connect() as db:
            db.execute("UPDATE devices SET confirmed=highest")
            db.execute("DELETE FROM receipts")
            db.execute("DELETE FROM groups")
        retry = send(HabitOperationStore(store.path), case["input"]["steps"][1]["mutation"], confirmed=1)
        self.assertEqual(retry["effect"], original["effect"])
        self.assertEqual(observe(store, retry)["total"], 600)
        self.assertEqual(len(store.snapshot()["groups"]), 0)

    def test_exact_sqlite_operation_ddl_retains_binding_and_successful_effect(self):
        from build_sync_storage_contract import derive as storage
        model = storage()
        with sqlite3.connect(":memory:") as db:
            # Only this DDL component is under test. Full v5/v6 open, encryption
            # and migration are verified by their existing separate runners.
            db.execute("CREATE TABLE workspace_metadata(singleton INTEGER PRIMARY KEY,workspace_kind TEXT)")
            db.execute("INSERT INTO workspace_metadata VALUES(1,'account')")
            db.execute(model["new_tables"]["habit_check_in_operations"])
            for name, sql in model["new_triggers"].items():
                if name.startswith("guard_habit_operation") or name.startswith("guard_habit_check_in_operations"):
                    db.execute(sql)
            db.execute("INSERT INTO habit_check_in_operations VALUES(?,?,?,?,?,?,?,?,NULL,NULL)",
                (A, B, "2026-09-05", "increment", 100, "0" * 64, A, "pending"))
            for statement in ("UPDATE habit_check_in_operations SET operation_hash='" + "1" * 64 + "'",
                              "DELETE FROM habit_check_in_operations", "UPDATE habit_check_in_operations SET amount_hundredths=0"):
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute(statement)
            db.execute("UPDATE habit_check_in_operations SET applied_state='accepted',effect_change_group_id=?,effect_group_last_server_sequence=1", (B,))
            for statement in ("UPDATE habit_check_in_operations SET applied_state='pending'",
                              "UPDATE habit_check_in_operations SET effect_group_last_server_sequence=2"):
                with self.assertRaises(sqlite3.IntegrityError):
                    db.execute(statement)

    def test_no_effect_rebase_keeps_original_effect_and_success_anchor(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("new-envelope-same-operation"))
        store = seed(self.path / "effect.db", case)
        original = send(store, case["input"]["steps"][0]["mutation"])
        before = store.snapshot()
        replay = send(store, case["input"]["steps"][1]["mutation"])
        after = store.snapshot()
        self.assertEqual(replay["effect"], original["effect"])
        self.assertTrue(all(r["causal_disposition"] == "no_effect" for r in replay["per_key_results"]))
        for name in ("facts", "fields", "anchors", "groups", "habit_operations"):
            self.assertEqual(before[name], after[name], name)

    def test_delete_barrier_blocks_later_stale_writer_and_does_not_resurrect(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("clear-versus-increment"))
        store = seed(self.path / "barrier.db", case)
        for step in case["input"]["steps"]:
            send(store, step["mutation"], step["device"])
        stale = operation(case["input"]["initial"], "increment", 2, op=9)
        result = send(store, stale)
        self.assertEqual(result["failure_code"], "SYNC_ENTITY_CONFLICT_BLOCKED")
        self.assertIsNotNone(result["effect"])
        self.assertEqual(result["effect"]["effect_group_last_server_sequence"], 2)
        self.assertTrue(observe(store, result)["deleted"])
        self.assertEqual(len(store.snapshot()["conflicts"]), 1)

    def test_operation_hash_separates_user_intent_from_transport_rebase(self):
        case = derive()["cases"][0]
        m = case["input"]["steps"][0]["mutation"]
        changed = copy.deepcopy(m)
        changed.update(client_sequence=100, base_entity_version=77, created_at="2030-01-01T00:00:00Z")
        changed["conflict_recovery_snapshot"]["note"] = "reprojected candidate"
        self.assertEqual(operation_hash(m), operation_hash(changed))
        changed["payload"]["delta_hundredths"] += 1
        self.assertNotEqual(operation_hash(m), operation_hash(changed))

    def test_operation_reuse_receipt_cannot_claim_another_operation(self):
        case = next(c for c in derive()["cases"] if c["id"].endswith("operation-id-content-reuse"))
        store = seed(self.path / "operation-context.db", case)
        for step in case["input"]["steps"]:
            result = send(store, step["mutation"], step["device"])
        result["failure_context"]["operation_id"] = B
        with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_ROUTE_MISMATCH"):
            validate_terminal_for_mutation(result, case["input"]["steps"][-1]["mutation"])

    def test_current_device_civil_date_and_timezone_remain_writer_owned(self):
        habit = derive()["cases"][0]["input"]["habit"]["fact"]
        validate_local_date(habit, "2026-09-05", timezone="Asia/Shanghai", now="2026-09-04T17:00:00Z")
        with self.assertRaisesRegex(ValueError, "HABIT_CHECK_IN_FUTURE_DATE"):
            validate_local_date(habit, "2026-09-05", timezone="America/Los_Angeles", now="2026-09-04T17:00:00Z")
        with self.assertRaisesRegex(ValueError, "HABIT_CHECK_IN_DATE_OUT_OF_RANGE"):
            validate_local_date(habit, "2026-08-31", timezone="Asia/Shanghai", now=TIME)
        with self.assertRaisesRegex(ValueError, "SYNC_TIMEZONE_INVALID"):
            validate_local_date(habit, "2026-09-05", timezone="Invalid/Zone", now=TIME)


if __name__ == "__main__":
    unittest.main()
