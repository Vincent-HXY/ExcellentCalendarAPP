"""Identity and mapping failures must not silently duplicate/rewrite the guest graph."""
import tempfile
import unittest
from pathlib import Path

from identity_reference import (MappingLedger, check_in_id, lineage_id, occurrence_key,
                                reminder_intent_id, remap_strong, remap_weak_category)

ACCOUNT = "11111111-1111-4111-8111-111111111111"
WORKSPACE = "22222222-2222-4222-8222-222222222222"
SOURCE = "33333333-3333-4333-8333-333333333333"
MAPPED = "44444444-4444-4444-8444-444444444444"


class SyncIdentityTests(unittest.TestCase):
    def test_business_day_identity_ignores_local_row_alias_and_clear(self):
        self.assertEqual(check_in_id(SOURCE, "2026-09-05"), check_in_id(SOURCE, "2026-09-05"))
        self.assertNotEqual(check_in_id(SOURCE, "2026-09-05"), check_in_id(SOURCE, "2026-09-06"))
        self.assertNotEqual(check_in_id(SOURCE, "2026-09-05"), check_in_id(MAPPED, "2026-09-05"))
        with self.assertRaises(ValueError):
            check_in_id(SOURCE, "2026-02-30")

    def test_lineage_account_workspace_epoch_are_independent(self):
        baseline = lineage_id(ACCOUNT, WORKSPACE, 0)
        for args in ((SOURCE, WORKSPACE, 0), (ACCOUNT, SOURCE, 0), (ACCOUNT, WORKSPACE, 1)):
            self.assertNotEqual(baseline, lineage_id(*args))
        for invalid in (True, -1, 9007199254740992, 1.5):
            with self.assertRaises(ValueError):
                lineage_id(ACCOUNT, WORKSPACE, invalid)

    def test_existing_occurrence_golden_and_dst_pre_resolution_identity(self):
        self.assertEqual(occurrence_key(ACCOUNT, 1, "2026-03-29T01:30:00"),
                         "24c7eda2-669c-5400-bf21-b8291b40395e")
        self.assertNotEqual(occurrence_key(ACCOUNT, 1, "2026-03-29T02:30:00"),
                            occurrence_key(ACCOUNT, 1, "2026-03-29T03:00:00"))
        self.assertNotEqual(occurrence_key(ACCOUNT, 1, "2026-03-29T02:30:00"),
                            occurrence_key(MAPPED, 1, "2026-03-29T02:30:00"))

    def test_reminder_aggregate_has_stable_owner_identity(self):
        self.assertEqual(len({reminder_intent_id(kind, SOURCE) for kind in ("event", "anniversary", "habit")}), 3)
        with self.assertRaises(ValueError):
            reminder_intent_id("notification", SOURCE)

    def test_collision_mapping_survives_reopen_and_preserves_all_weak_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mapping.sqlite"
            lineage = lineage_id(ACCOUNT, WORKSPACE, 0)
            ledger = MappingLedger(path, lambda: MAPPED)
            mapping = ledger.reserve(lineage, [("category", SOURCE)], {("category", SOURCE)})
            self.assertEqual(mapping[("category", SOURCE)], MAPPED)
            ledger.close()
            ledger = MappingLedger(path, lambda: self.fail("durable retry allocated a second identity"))
            self.assertEqual(ledger.reserve(lineage, [("category", SOURCE)], set()), mapping)
            self.assertEqual(remap_weak_category(SOURCE, mapping), MAPPED)
            for weak in (None, "", "legacy-category", "目录😀", "e\u0301", "é", SOURCE.upper() + "A"):
                self.assertEqual(remap_weak_category(weak, mapping), weak)
            self.assertEqual(remap_strong("category", SOURCE, mapping), MAPPED)
            with self.assertRaises(ValueError):
                remap_strong("habit", SOURCE, mapping)
            ledger.close()

    def test_allocation_failure_rolls_back_entire_graph(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = MappingLedger(Path(directory) / "mapping.sqlite", lambda: "invalid")
            with self.assertRaises(ValueError):
                ledger.reserve(lineage_id(ACCOUNT, WORKSPACE, 0),
                               [("category", SOURCE), ("habit", SOURCE)], {("habit", SOURCE)})
            self.assertEqual(ledger.db.execute("SELECT count(*) FROM mapping").fetchone()[0], 0)
            ledger.close()

    def test_legacy_uuid_lexeme_maps_without_mutating_source_or_category_rules(self):
        legacy = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        with tempfile.TemporaryDirectory() as directory:
            ledger = MappingLedger(Path(directory) / "mapping.sqlite", lambda: MAPPED)
            lineage = lineage_id(ACCOUNT, WORKSPACE, 0)
            result = ledger.reserve(lineage, [("event", legacy)], set())
            self.assertEqual(result, {("event", legacy): MAPPED})
            with self.assertRaises(ValueError):
                ledger.reserve(lineage, [("category", legacy)], set())
            self.assertEqual(ledger.db.execute("SELECT source_id FROM mapping").fetchone()[0], legacy)
            ledger.close()

    def test_successor_deletes_cover_historical_assignments_in_this_epoch(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = MappingLedger(Path(directory) / "mapping.sqlite", lambda: MAPPED)
            old, new = lineage_id(ACCOUNT, WORKSPACE, 0), lineage_id(ACCOUNT, WORKSPACE, 1)
            ledger.reserve(old, [("category", SOURCE)], set())
            self.assertEqual(len(ledger.successor_deletes(old, set())), 1)
            ledger.mark_published(old)
            self.assertEqual(len(ledger.successor_deletes(old, set())), 1)
            self.assertEqual(ledger.successor_deletes(new, set()), [])
            self.assertEqual(ledger.successor_deletes(old, {("category", SOURCE)}), [])
            ledger.close()


if __name__ == "__main__":
    unittest.main()
