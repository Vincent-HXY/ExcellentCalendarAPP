import copy
import unittest
from pathlib import Path

from build_sync_domain_contracts import derive
from domain_reference import validate_fact, validate_graph, validate_patch, choose_default_reminder
from validate_sync_v1 import read_data, read_json, read_yaml, validate_baseline

CONTRACTS = Path(__file__).resolve().parents[1]
FIXTURE = read_json(CONTRACTS / "fixtures/sync/v1/target_vectors.json")


class SyncDomainTests(unittest.TestCase):
    def test_fixture_outcomes(self):
        for case in FIXTURE["cases"]:
            with self.subTest(case=case["id"]):
                if case["expected_error"]:
                    with self.assertRaisesRegex(ValueError, "^" + case["expected_error"] + "$"):
                        validate_fact(case["input"])
                else:
                    validate_fact(case["input"])

    def test_registry_schema_merge_keys_and_nullable_close(self):
        for path, expected in derive().items():
            self.assertEqual(read_data(path), expected, str(path))
        registry = read_yaml(CONTRACTS / "sync/sync_field_registry.yaml")
        self.assertEqual(len(registry["targets"]), 12)
        for target, entry in registry["targets"].items():
            for variant in entry["variants"].values():
                fact = read_json(CONTRACTS / variant["fact_schema"])
                self.assertEqual(set(variant["fields"]), set(fact["properties"]), target)
                self.assertEqual(set(fact["required"]), set(fact["properties"]), target)
                for key, members in variant["merge_groups"].items():
                    self.assertTrue(members)
                    for field in members:
                        self.assertEqual(variant["fields"][field]["merge_key"], key)
        self.assertEqual(validate_baseline(read_json(CONTRACTS / "sync/sync_v1_baseline.json")), 220)

    def test_missing_null_and_unknown_fields_are_distinct(self):
        for sample in FIXTURE["samples"].values():
            for field in sample["fact"]:
                missing = copy.deepcopy(sample)
                del missing["fact"][field]
                with self.subTest(target=sample["target_type"], field=field), self.assertRaises(ValueError):
                    validate_fact(missing)
            extra = copy.deepcopy(sample)
            extra["fact"]["unknown"] = None
            with self.assertRaises(ValueError):
                validate_fact(extra)

    def test_no_device_fact_can_enter_typed_upload_projection(self):
        registry = read_yaml(CONTRACTS / "sync/sync_field_registry.yaml")
        for target in registry["excluded_targets"]:
            sample = copy.deepcopy(FIXTURE["samples"]["event"])
            sample["target_type"] = target
            with self.subTest(target=target), self.assertRaises(ValueError):
                validate_fact(sample)

    def test_semantic_groups_are_atomic_and_history_guard_is_immutable(self):
        event = FIXTURE["samples"]["event"]
        self.assertEqual(validate_patch("event", {"title": "changed", "content": None}, event), {"title", "content"})
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            validate_patch("event", {"start_at": "2026-09-05T00:00:00Z"}, event)
        timing = {key: event["fact"][key] for key in ("is_all_day", "start_at", "end_at", "start_date", "end_date", "timezone")}
        self.assertEqual(validate_patch("event", timing, event), {"timing"})
        with self.assertRaisesRegex(ValueError, "HABIT_HISTORY_IMMUTABLE"):
            validate_patch("habit", {"target_count_hundredths": 600, "unit": "页"}, FIXTURE["samples"]["habit"])
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            validate_patch("habit", {"first_check_in_at": None}, FIXTURE["samples"]["habit"])
        with self.assertRaisesRegex(ValueError, "SYNC_OPERATION_UNSUPPORTED"):
            validate_patch("account_profile", {"display_name": "changed"}, FIXTURE["samples"]["account_profile"])

    def test_strong_references_fail_but_missing_category_stays_opaque(self):
        samples = FIXTURE["samples"]
        graph = [samples[name] for name in ("habit", "habit_recurrence", "habit_check_in", "reminder_intent_habit")]
        validate_graph(graph)
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            validate_graph([row for row in graph if row["target_type"] != "habit_recurrence"])
        with self.assertRaisesRegex(ValueError, "IMPORT_DUPLICATE_IDENTITY"):
            validate_graph(graph + [graph[0]])
        cleared_guard = copy.deepcopy(graph)
        cleared_guard[0]["fact"]["first_check_in_at"] = None
        with self.assertRaisesRegex(ValueError, "HABIT_HISTORY_IMMUTABLE"):
            validate_graph(cleared_guard)

    def test_reminder_applicability_requires_target_context(self):
        event = copy.deepcopy(FIXTURE["samples"]["event"])
        intent = copy.deepcopy(FIXTURE["samples"]["reminder_intent_event"])
        intent["fact"]["templates"][0]["method"] = "ring"
        validate_graph([event, intent])
        event["fact"].update(is_all_day=True, start_at=None, end_at=None, start_date="2026-09-05", end_date="2026-09-06")
        with self.assertRaisesRegex(ValueError, "REMINDER_METHOD_UNSUPPORTED"):
            validate_graph([event, intent])
        intent["fact"]["templates"][0]["method"] = "popup"
        validate_graph([event, intent])

    def test_defaults_preserve_order_and_never_invent_popup(self):
        for target in ("habit", "anniversary"):
            self.assertEqual(choose_default_reminder(target, ["ring", "popup"]), "popup")
            self.assertIsNone(choose_default_reminder(target, ["ring"]))
        self.assertEqual(choose_default_reminder("event", ["popup", "ring"]), "popup")
        self.assertEqual(choose_default_reminder("event", ["ring", "popup"]), "ring")
        self.assertIsNone(choose_default_reminder("event", ["ring", "popup"], is_all_day=True, has_recurrence=True))
        with self.assertRaises(ValueError):
            choose_default_reminder("event", ["popup", "popup"])

    def test_graph_checks_history_snapshot_effective_end_and_owned_lifecycle(self):
        samples = FIXTURE["samples"]
        graph = [copy.deepcopy(samples[name]) for name in ("habit", "habit_recurrence", "habit_check_in")]
        for field, value in (("target_count_snapshot_hundredths", 400), ("unit_snapshot", "次")):
            altered = copy.deepcopy(graph); altered[2]["fact"][field] = value
            with self.assertRaisesRegex(ValueError, "HABIT_HISTORY_IMMUTABLE"): validate_graph(altered)
        ended = copy.deepcopy(graph); ended[0]["fact"].update(ended_date="2026-09-04", is_active=False)
        with self.assertRaisesRegex(ValueError, "HABIT_HISTORY_IMMUTABLE"): validate_graph(ended)
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"): validate_graph([samples["habit_recurrence"]])
        anniversary = [copy.deepcopy(samples[name]) for name in ("anniversary", "anniversary_recurrence")]
        anniversary[1]["fact"]["deleted_at"] = "2026-09-05T01:00:00Z"
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"): validate_graph(anniversary)

    def test_sync_uuids_are_canonical_without_normalizing_weak_references(self):
        for name in ("event", "anniversary", "habit", "category"):
            bad = copy.deepcopy(FIXTURE["samples"][name])
            bad["target_id"] = bad["fact"]["id"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
            with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"): validate_fact(bad)
        weak = copy.deepcopy(FIXTURE["samples"]["event"])
        weak["fact"]["category_id"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        validate_fact(weak)


if __name__ == "__main__":
    unittest.main()
