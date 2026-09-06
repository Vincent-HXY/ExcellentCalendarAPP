"""Atomic graph and concurrency regressions independent of generator expectations."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from build_owned_graph_fixtures import derive, FIXTURE, make_mutation
from owned_graph_reference import OwnedGraphStore


class OwnedGraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="excellent-calendar-owned-test-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def test_fixed_graph_outcomes(self):
        fixed = derive()
        self.assertEqual(json.loads(FIXTURE.read_text(encoding="utf-8")), fixed)
        for i, case in enumerate(fixed["cases"]):
            with self.subTest(case=case["id"]):
                store = OwnedGraphStore(self.path / f"{i}.sqlite"); store.seed(case["input"]["seed"])
                expected = case["expected"]
                if "error" in expected:
                    before = store.snapshot()
                    with self.assertRaisesRegex(ValueError, "^" + expected["error"] + "$"):
                        for mutation in case["input"]["mutations"]: store.apply(mutation)
                    self.assertEqual(store.snapshot(), before)
                else:
                    results = [store.apply(m) for m in case["input"]["mutations"]]
                    self.assertEqual([r["status"] for r in results], expected["statuses"])
                    snapshot = store.snapshot()
                    self.assertEqual(len(snapshot["conflicts"]), expected["conflicts"])
                    facts = {(t, i): json.loads(p)["fact"] for t, i, _, p in snapshot["facts"]}
                    if "event_start" in expected:
                        event = next(row for (kind, _), row in facts.items() if kind == "event")
                        self.assertEqual((event["start_at"], event["title"]), (expected["event_start"], expected["event_title"]))
                        second = next(row for (kind, i), row in facts.items() if kind == "event_recurrence" and i.endswith("#2"))
                        self.assertEqual(second["frequency"], expected["revision_two_frequency"])
                        self.assertTrue(any(row[0] == "event_recurrence" for row in results[-1]["conflicting"]))
                        self.assertEqual({row[-1] for row in results[-1]["applied"]}, {"title"})
                    if "second_changed_count" in expected: self.assertEqual(len(results[1]["changed"]), expected["second_changed_count"])
                self.assertEqual(len(store.snapshot()["facts"]), expected["fact_count"])

    def test_every_fact_and_receipt_boundary_rolls_back_whole_graph(self):
        mutation = derive()["cases"][0]["input"]["mutations"][0]
        for i, phase in enumerate((0, 1, 2, "receipt")):
            store = OwnedGraphStore(self.path / f"rollback-{i}.sqlite")
            before = store.snapshot()
            with self.assertRaisesRegex(RuntimeError, "injected_owned_graph_rollback"): store.apply(mutation, fail_after=phase)
            self.assertEqual(store.snapshot(), before)
            self.assertEqual(store.apply(mutation)["status"], "accepted")
            self.assertEqual(len(store.snapshot()["facts"]), 3)

    def test_response_loss_reopen_is_exact_replay_and_changed_payload_is_refused(self):
        mutation = derive()["cases"][0]["input"]["mutations"][0]
        path = self.path / "replay.sqlite"; store = OwnedGraphStore(path)
        result = store.apply(mutation); snapshot = store.snapshot()
        store = OwnedGraphStore(path)
        self.assertEqual(store.apply(mutation), result)
        self.assertEqual(store.snapshot(), snapshot)
        different = copy.deepcopy(mutation); different["payload"]["fact"]["title"] = "不同请求"
        with self.assertRaisesRegex(ValueError, "SYNC_SEQUENCE_REPLAY_MISMATCH"): store.apply(different)
        self.assertEqual(store.snapshot(), snapshot)

    def test_unverified_child_predecessor_does_not_bypass_version_checks(self):
        mutation = copy.deepcopy(derive()["cases"][0]["input"]["mutations"][0])
        mutation["client_sequence"] = 2
        mutation["payload"]["owned_dependencies"][0]["causal_predecessors"][0]["client_sequence"] = 1
        store = OwnedGraphStore(self.path / "causal.sqlite")
        with self.assertRaisesRegex(ValueError, "REFERENCE_CAUSAL_EVIDENCE_REQUIRED"): store.apply(mutation)
        self.assertEqual(len(store.snapshot()["facts"]), 0)


if __name__ == "__main__": unittest.main()
