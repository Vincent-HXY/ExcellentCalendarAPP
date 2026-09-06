"""Legacy conversion must never conflate namespaces or discard unsupported live data."""
import copy
from pathlib import Path
import tempfile
import unittest

from build_legacy_identity_fixtures import derive, TARGET
from identity_reference import MappingLedger, lineage_id
from legacy_identity_reference import legacy_source_id, decode_legacy_source_id, project_legacy_graph


class LegacyIdentityTests(unittest.TestCase):
    def test_source_encoding_preserves_exact_lexemes_and_rejects_noncanonical(self):
        values = ["e\u0301", "é", " x ", "目录😀", TARGET, TARGET.upper(), "\0"]
        # TARGET has only digits; use a separately distinct uppercase UUID lexeme.
        values[-2] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        self.assertEqual(len(set(map(legacy_source_id, values))), len(values))
        for value in values:
            encoded = legacy_source_id(value)
            self.assertEqual(decode_legacy_source_id(encoded), value)
            with self.assertRaises(ValueError): decode_legacy_source_id(encoded + "=")
        for value in ("", "中" * 100, "\ud800", None):
            with self.assertRaises(ValueError): legacy_source_id(value)

    def test_legacy_and_modern_uuid_cannot_alias_and_mapping_survives_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mapping.sqlite"
            lineage = lineage_id(TARGET, "88888888-8888-4888-8888-888888888888", 0)
            allocated = "99999999-9999-4999-8999-999999999999"
            ledger = MappingLedger(path, lambda: allocated)
            modern = ledger.reserve(lineage, [("event", TARGET)], set())
            legacy = ledger.reserve_legacy_events(lineage, [TARGET], set())
            self.assertEqual(modern[("event", TARGET)], TARGET)
            self.assertEqual(legacy[("event", legacy_source_id(TARGET))], allocated)
            ledger.close()
            ledger = MappingLedger(path, lambda: self.fail("Retry reallocated legacy identity"))
            self.assertEqual(legacy, ledger.reserve_legacy_events(lineage, [TARGET], set()))
            ledger.close()

    def test_projection_preserves_config_and_omits_execution_state(self):
        case = derive()["cases"][1]["input"]
        old = copy.deepcopy(case)
        output = project_legacy_graph(case["events"], case["reminders"], {legacy_source_id(case["events"][0]["id"]): TARGET})
        self.assertEqual(case, old)
        self.assertEqual(output[0]["fact"]["category_id"], "  e\u0301😀  ")
        self.assertEqual([row["method"] for row in output[1]["fact"]["templates"]], ["ring", "popup"])
        self.assertEqual(set(output[1]["fact"]), {"owner_type", "owner_id", "is_enabled", "templates"})
        for field in ("scheduled_at", "last_triggered_at", "failure_reason", "reminder_id", "notification_id"):
            self.assertNotIn(field, str(output))

    def test_unsupported_member_rejects_whole_graph_without_source_mutation(self):
        event = derive()["cases"][0]["input"]["events"][0]
        for bad in ({**event, "id": "second", "timezone": None}, {**event, "id": "second", "has_recurrence": True},
                    {**event, "id": "second", "unrecognized_fact": "must not be dropped"}):
            graph = [copy.deepcopy(event), bad]; before = copy.deepcopy(graph)
            mapping = {legacy_source_id(event["id"]): TARGET, legacy_source_id("second"): "99999999-9999-4999-8999-999999999999"}
            with self.assertRaises(ValueError): project_legacy_graph(graph, [], mapping)
            self.assertEqual(graph, before)
        with self.assertRaisesRegex(ValueError, "IMPORT_DUPLICATE_IDENTITY"):
            project_legacy_graph([event, event], [], {})


if __name__ == "__main__": unittest.main()
