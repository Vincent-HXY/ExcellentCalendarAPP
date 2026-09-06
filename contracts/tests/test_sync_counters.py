"""Counter golden + real transaction, durable replay and concurrent writer evidence."""
from __future__ import annotations

import concurrent.futures
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

import yaml

CONTRACTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CONTRACTS / "spikes/sync_v1"))
from counter_reference import CounterStore, MAXIMUM, integer

REGISTRY = yaml.safe_load((CONTRACTS / "sync/sync_counter_registry.yaml").read_text(encoding="utf-8"))


class CounterTests(unittest.TestCase):
    def test_closed_owners_and_actions(self):
        required = {"client_sequence", "server_sequence", "sync_transport_generation", "source_epoch", "active_route_revision",
                    "local_settings_revision", "lifecycle_revision", "access_token_generation", "sync_policy_revision",
                    "native_state_revision", "status_revision", "notice_sequence", "account_generation", "device_version",
                    "entity_version", "field_version", "conflict_version", "account_profile_revision", "preferences_revision",
                    "import_revision", "reorder_revision", "session_generation", "history_revision", "failed_change_revision",
                    "source_lease_revision", "logout_risk_revision", "recurrence_revision"}
        self.assertEqual(set(REGISTRY["counter_kinds"]), required)
        self.assertEqual(REGISTRY["maximum"], MAXIMUM)
        self.assertFalse(set(REGISTRY["derived_values"]) & required)
        for kind, row in REGISTRY["counter_kinds"].items():
            with self.subTest(kind=kind):
                self.assertEqual(set(row), {"owner", "scope", "initial_value", "error", "at_last_increment", "at_max"})
                self.assertIsInstance(row["owner"], str)
                self.assertTrue(row["owner"].startswith(("cpp.", "kotlin.", "backend.")))
                integer(row["initial_value"])
        self.assertTrue(all(row["decreases_allowed"] for row in REGISTRY["derived_values"].values()))

    def test_wire_integer_domain(self):
        for bad in (-1, MAXIMUM + 1, 2 ** 63, 10 ** 1000, True, False, None, "1", 1.5, float("nan"), float("inf")):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                integer(bad)
        self.assertEqual(integer(MAXIMUM), MAXIMUM)
        self.assertEqual(integer(1.0), 1)
        self.assertEqual(integer(-0.0), 0)
        self.assertEqual(integer(float(MAXIMUM)), MAXIMUM)

    def test_boundary_golden(self):
        fixture = json.loads((CONTRACTS / "fixtures/sync/v1/counter_vectors.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["kind"], "contract_model_not_product_behavior")
        for case in fixture["cases"]:
            with self.subTest(case=case["id"]), tempfile.TemporaryDirectory(prefix="sync-counter-") as folder:
                policy = REGISTRY["counter_kinds"][case["counter_kind"]]
                store = CounterStore(Path(folder) / "counter.sqlite", case["counter_kind"], policy, case["initial"])
                actual = store.allocate("synthetic-op", "payload", case["expected_cas"])
                for field, expected in case["expected"].items():
                    self.assertEqual(actual[field], expected, field)
                self.assertEqual(store.snapshot()[0], case["expected"]["value"])

    def test_receipt_survives_response_loss_and_input_cannot_change(self):
        for kind, policy in REGISTRY["counter_kinds"].items():
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(prefix="sync-counter-") as folder:
                path = Path(folder) / "counter.sqlite"
                owner = CounterStore(path, kind, policy, MAXIMUM - 1)
                original = owner.allocate("operation", "original", MAXIMUM - 1)
                snapshot = owner.snapshot()
                reopened = CounterStore(path, kind, policy)
                duplicate = reopened.allocate("operation", "original", MAXIMUM - 1)
                self.assertEqual(duplicate["disposition"], "duplicate")
                self.assertEqual(duplicate["value"], original["value"])
                self.assertEqual(reopened.allocate("operation", "changed", MAXIMUM - 1)["disposition"], "replay_mismatch")
                self.assertEqual(reopened.snapshot(), snapshot)

    def test_mid_transaction_rollback_restores_counter_facts_and_receipt(self):
        for kind, policy in REGISTRY["counter_kinds"].items():
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(prefix="sync-counter-") as folder:
                path = Path(folder) / "counter.sqlite"
                owner = CounterStore(path, kind, policy, MAXIMUM - 1)
                owner.allocate("operation", "payload", MAXIMUM - 1, rollback_before_commit=True)
                self.assertEqual(owner.snapshot(), (MAXIMUM - 1, 0, 0))
                self.assertIn(owner.allocate("operation", "payload", MAXIMUM - 1)["disposition"], ("committed", "blocked"))

    def test_concurrent_double_write_cannot_wrap_or_duplicate(self):
        for kind, policy in REGISTRY["counter_kinds"].items():
            for cas in (None, MAXIMUM - 1):
                with self.subTest(kind=kind, cas=cas), tempfile.TemporaryDirectory(prefix="sync-counter-") as folder:
                    path = Path(folder) / "counter.sqlite"
                    owner = CounterStore(path, kind, policy, MAXIMUM - 1)
                    start = threading.Barrier(2)
                    def write(index):
                        start.wait(timeout=10)
                        return CounterStore(path, kind, policy).allocate(str(index), "payload", cas)
                    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                        results = list(pool.map(write, [1, 2]))
                    winners = [result for result in results if result["write"]]
                    self.assertEqual(len(winners), 1)
                    loser = next(result for result in results if not result["write"])
                    self.assertEqual(loser["disposition"], "exhausted" if cas is None else "stale_cas")
                    self.assertEqual(owner.snapshot()[0], MAXIMUM)
                    self.assertEqual(owner.snapshot()[2], int(kind not in ("native_state_revision", "status_revision")))


if __name__ == "__main__":
    unittest.main()
