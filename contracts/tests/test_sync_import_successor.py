"""Complete same-epoch graph replacement, not a per-row import simulation."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from build_owned_graph_fixtures import make_mutation
from build_target_fixtures import build
from import_capacity_reference import combined_graph
from import_contract_reference import validate_publication
from import_graph_reference import ImportGraphPlanner
from import_download_reference import ImportDownloadStore
from import_successor_reference import ImportSuccessorServer
from protocol_reference import mutation_hash

A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
S = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
E = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
CRASH_POINTS = []


class ImportSuccessorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-successor-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.planner = ImportGraphPlanner(self.path / "planner.db")
        # None means this test has no proof producer. Any attempted proof use
        # fails; signed takeover cases use the real authority in the range suite.
        self.server = ImportSuccessorServer(self.path / "server.db", account_id=A, authority=None, staging_ttl_seconds=60)
        self.server.register(D)
        self.server.register(E)

    def send(self, batch, device=D):
        return self.server.exchange(device, 0, [{"mutation": row, "payload_hash": mutation_hash(row)} for row in batch])

    def versions(self):
        with self.server.connect() as db:
            return {(target, identifier): version for target, identifier, version in db.execute("SELECT target,id,version FROM facts")}

    def test_durable_mapping_remaps_all_strong_edges_without_rewriting_text_or_weak_absence(self):
        graph = combined_graph(12)
        occupied = {(row["target_type"], row["target_id"]) for row in graph if row["target_type"] in {"category", "event", "anniversary", "habit"}}
        event = next(row for row in graph if row["target_type"] == "event")
        event["fact"]["title"] = event["target_id"]
        identifier = str(uuid.uuid4())
        batch = self.planner.prepare(A, S, 0, graph, batch_id=identifier, occupied=occupied)
        reopened = ImportGraphPlanner(self.planner.path)
        self.assertEqual(reopened.prepare(A, S, 0, graph, batch_id=identifier, occupied=occupied), batch)
        mapped = next(row for row in batch if row["target_type"] == "event")
        self.assertNotEqual(mapped["target_id"], event["target_id"])
        self.assertEqual(mapped["payload"]["fact"]["title"], event["target_id"])
        self.assertEqual(mapped["payload"]["fact"]["category_id"], "legacy-category😀")
        result = self.send(batch)[-1]
        self.assertEqual(result["status"], "accepted", result)
        self.assertEqual(len(self.server.snapshot()["import_mapping"]), 12)

    def test_invalid_graph_and_allocator_exhaustion_leave_no_mapping_or_batch(self):
        graph = combined_graph(12)
        before = self.planner.snapshot()
        invalid = [row for row in graph if row["target_type"] != "habit_recurrence"]
        for records, kwargs in ((invalid, {}), (graph, {"begin_sequence": 9007199254740991})):
            with self.assertRaises(ValueError):
                self.planner.prepare(A, S, 0, records, **kwargs)
            self.assertEqual(self.planner.snapshot(), before)

    def test_successor_unions_historical_mappings_and_preserves_old_publication_and_epoch(self):
        graph = combined_graph(12)
        initial = self.planner.prepare(A, S, 0, graph)
        accepted = self.send(initial)[-1]
        self.assertEqual(accepted["status"], "accepted", accepted)
        history = self.server.snapshot()["import_publication_lines"]
        before_marker = self.server.snapshot()["import_published_markers"]
        retained = [row for row in graph if row["target_type"] not in {"event", "event_recurrence", "event_occurrence_state"}
                    and not (row["target_type"] == "reminder_intent" and row["fact"]["owner_type"] == "event")]
        batch = self.planner.prepare(A, S, 0, retained, begin_sequence=len(initial) + 1,
            predecessor=initial[0]["import_batch_id"], revision=2, versions=self.versions())
        self.assertEqual(sum(row["operation_type"] == "import_delete" for row in batch), 4)
        result = self.send(batch)[-1]
        self.assertEqual((result["status"], result.get("import_revision")), ("accepted", 4), result)
        snapshot = self.server.snapshot()
        self.assertEqual(snapshot["import_publication_lines"][:len(history)], history)
        self.assertTrue(all(row in snapshot["import_published_markers"] for row in before_marker))
        new_lines = [json.loads(row[2]) for row in snapshot["import_publication_lines"][len(history):]]
        images = validate_publication(new_lines)
        self.assertEqual(sum(row["kind"] in {"tombstone", "deleted_entity_anchor"} for row in images), 4)
        second_epoch = self.planner.prepare(A, S, 1, retained, occupied={(row[0], row[1]) for row in snapshot["facts"]})
        self.assertFalse(any(row["operation_type"] == "import_delete" for row in second_epoch))
        self.assertNotEqual(second_epoch[0]["import_lineage_id"], initial[0]["import_lineage_id"])

    def test_concurrent_cloud_field_conflict_and_independent_auto_merge_publish_together(self):
        sample = copy.deepcopy(build()["samples"]["category"])
        initial = self.planner.prepare(A, S, 0, [sample])
        self.assertEqual(self.send(initial)[-1]["status"], "accepted")
        baseline = self.versions()
        self.send([make_mutation(sample, 1, patch={"name": "云端名称"})], device=E)
        sample["fact"].update(name="游客名称", description="独立说明")
        batch = self.planner.prepare(A, S, 0, [sample], begin_sequence=4, predecessor=initial[0]["import_batch_id"], revision=2, versions=baseline)
        result = self.send(batch)[-1]
        self.assertEqual(result["status"], "accepted", result)
        self.assertEqual(len(result["conflict_ids"]), 1)
        with self.server.connect() as db:
            fact = json.loads(db.execute("SELECT fact FROM facts").fetchone()[0])
            detail = json.loads(db.execute("SELECT detail FROM typed_conflicts").fetchone()[0])
            publication = [json.loads(row[0]) for row in db.execute("SELECT payload FROM import_publication_lines WHERE group_id=? ORDER BY sequence", (result["publish_group_id"],))]
        self.assertEqual((fact["name"], fact["description"]), ("云端名称", "独立说明"))
        self.assertEqual([row["key"]["merge_key"] for row in detail["conflicting_groups"]], ["name"])
        self.assertEqual(sum(row["kind"] == "created" for row in validate_publication(publication)), 1)
        self.assertEqual(self.send(batch)[-1]["original_result"], result)
        before = self.server.snapshot()
        next_batch = self.planner.prepare(A, S, 0, [sample], begin_sequence=7, predecessor=batch[0]["import_batch_id"], revision=4, versions=self.versions())
        rejected = self.send(next_batch)[-1]
        self.assertEqual((rejected["status"], rejected["error"]["code"]), ("rejected", "SYNC_ENTITY_CONFLICT_BLOCKED"))
        self.assertEqual(self.server.snapshot()["facts"], before["facts"])

    def test_consumed_invalid_commit_can_repair_with_complete_historical_set(self):
        graph = combined_graph(12)
        initial = self.planner.prepare(A, S, 0, graph)
        damaged = copy.deepcopy(initial)
        category = next(row for row in damaged if row["target_type"] == "category")
        category["payload"]["fact"]["name"] = "作工"
        result = self.send(damaged)[-1]
        self.assertEqual((result["status"], result["import_stage"]), ("rejected", "repair_required"), result)
        self.assertFalse(self.server.snapshot()["facts"])
        successor = self.planner.prepare(A, S, 0, graph, begin_sequence=len(initial) + 1, predecessor=initial[0]["import_batch_id"], revision=2)
        self.assertEqual(self.send(successor)[-1]["status"], "accepted")
        status = self.server.status({"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "import_batch_id": initial[0]["import_batch_id"]})
        self.assertEqual(status["stage"], "superseded")
        self.assertEqual(status["current_head"]["current_head_batch_id"], successor[0]["import_batch_id"])

    def test_whole_graph_replacement_cannot_rewrite_existing_habit_history(self):
        graph = combined_graph(12)
        initial = self.planner.prepare(A, S, 0, graph)
        self.send(initial)
        before = self.server.snapshot()
        for record in graph:
            if record["target_type"] == "habit":
                record["fact"]["unit"] = "分钟"
            elif record["target_type"] == "habit_check_in":
                record["fact"]["unit_snapshot"] = "分钟"
        batch = self.planner.prepare(A, S, 0, graph, begin_sequence=len(initial) + 1,
            predecessor=initial[0]["import_batch_id"], revision=2, versions=self.versions())
        result = self.send(batch)[-1]
        self.assertEqual((result["status"], result["error"]["code"]), ("rejected", "HABIT_HISTORY_IMMUTABLE"))
        self.assertEqual(self.server.snapshot()["facts"], before["facts"])
        self.assertEqual(self.server.snapshot()["import_publication_lines"], before["import_publication_lines"])

    def test_two_devices_compete_for_one_lineage_revision_with_one_winner(self):
        sample = build()["samples"]["category"]
        initial = self.planner.prepare(A, S, 0, [sample])
        self.assertEqual(self.send(initial)[-1]["status"], "accepted")
        batches = [self.planner.prepare(A, S, 0, [sample], begin_sequence=sequence,
            predecessor=initial[0]["import_batch_id"], revision=2, versions=self.versions()) for sequence in (4, 1)]
        barrier = threading.Barrier(2)

        def begin(index):
            barrier.wait()
            try:
                return self.send(batches[index][:1], device=(D, E)[index])[0]["status"]
            except ValueError as error:
                return str(error)

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(begin, range(2)))
        self.assertEqual(sorted(results), ["IMPORT_VERSION_CONFLICT", "staged"])
        with self.server.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM import_batches WHERE stage='server_staging'").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT revision FROM import_lineage_heads").fetchone()[0], 3)

    def test_successor_download_and_fresh_bootstrap_cover_old_markers_and_deleted_dependencies(self):
        from bootstrap_reference import BootstrapServer, page_set_digest
        from build_bootstrap_fixtures import KEY, KEY_ID, NOW
        from bootstrap_reference import item_key
        import base64
        local = ImportDownloadStore(self.path / "download.db", device_id=D)
        bootstrap = BootstrapServer(self.path / "download_server.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        bootstrap.seed([], highest=0, confirmed=0, upper_bound=0)
        page = bootstrap.begin(now=NOW, download_limit=500)
        local.begin(page)
        local.stage(page, request_cursor=None)
        local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        graph = combined_graph(12)
        initial = self.planner.prepare(A, S, 0, graph)
        self.send(initial)

        def download(batch):
            with self.server.connect() as db:
                lines = [json.loads(raw) for raw, in db.execute("SELECT payload FROM import_publication_lines ORDER BY sequence")
                         if json.loads(raw).get("import_batch_id") == batch]
                header = lines[0]
                lines = [json.loads(raw) for raw, in db.execute("SELECT payload FROM import_publication_lines WHERE group_id=? ORDER BY sequence",
                    (header["import_publish_group_id"],))]
            response = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
                "changes": lines, "account_generation": 0, "snapshot_upper_bound": header["commit_server_sequence"],
                "next_cursor": base64.urlsafe_b64encode(uuid.uuid4().bytes * 2).decode().rstrip("="), "has_more": False,
                "accepted_client_sequence_through": 0, "retention_floor_server_sequence": 0, "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
            local.apply_download(response, request_id=local.prepare_download())

        download(initial[0]["import_batch_id"])
        old_markers = [json.loads(row[1]) for row in local.snapshot()["live"] if json.loads(row[1])["kind"] == "import_publish_marker"]
        added = copy.deepcopy(build()["samples"]["category"])
        graph.append(added)
        successor = self.planner.prepare(A, S, 0, graph, begin_sequence=len(initial) + 1,
            predecessor=initial[0]["import_batch_id"], revision=2, versions=self.versions())
        self.assertEqual(self.send(successor)[-1]["status"], "accepted")
        download(successor[0]["import_batch_id"])
        current_markers = {json.loads(row[1])["import_batch_id"]: json.loads(row[1]) for row in local.snapshot()["live"]
                           if json.loads(row[1])["kind"] == "import_publish_marker"}
        previous = current_markers[initial[0]["import_batch_id"]]
        self.assertEqual(previous["publish_digest"], old_markers[0]["publish_digest"])
        self.assertEqual(previous["snapshot_provenance_count"], 13)
        retained = [row for row in graph if row["target_type"] not in {"event", "event_recurrence", "event_occurrence_state"}
                    and not (row["target_type"] == "reminder_intent" and row["fact"]["owner_type"] == "event")]
        final = self.planner.prepare(A, S, 0, retained, begin_sequence=len(initial) + len(successor) + 1,
            predecessor=successor[0]["import_batch_id"], revision=4, versions=self.versions())
        result = self.send(final)[-1]
        self.assertEqual(result["status"], "accepted", result)
        download(final[0]["import_batch_id"])
        with self.server.connect() as db:
            images = [self.server.image(db, target, identifier) for target, identifier in db.execute("SELECT target,id FROM facts")]
        bootstrap.seed(sorted([*images, *self.server.bootstrap_markers()], key=item_key), highest=0, confirmed=0,
                       upper_bound=result["commit_server_sequence"])
        fresh = ImportDownloadStore(self.path / "fresh.db", device_id=D)
        page = bootstrap.begin(now=NOW + 86400, download_limit=500)
        fresh.begin(page)
        fresh.stage(page, request_cursor=None)
        fresh.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        def facts(store):
            return sorted([json.loads(row[1]) for row in store.snapshot()["live"] if json.loads(row[1])["kind"] != "import_publish_marker"], key=item_key)
        self.assertEqual(facts(fresh), facts(local))
        from bootstrap_reference import validate_snapshot
        invalid = copy.deepcopy(images)
        event = next(row for row in invalid if row["target_type"] == "event")
        event["kind"] = "fact_after_image"
        event["fact"]["deleted_at"] = None
        del event["deleted_at"], event["delete_server_sequence"]
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            validate_snapshot(sorted(invalid, key=item_key), upper_bound=result["commit_server_sequence"], highest=0)
        missing_anchor = [row for row in images if row["target_type"] != "event_recurrence"]
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            validate_snapshot(sorted(missing_anchor, key=item_key), upper_bound=result["commit_server_sequence"], highest=0)

    def test_actual_process_death_rolls_back_and_each_branch_replays_successfully(self):
        sample = build()["samples"]["category"]
        for point in ("import_graph_mapping", "import_graph_frozen_batch"):
            probe_path = self.path / (point + ".db")
            planner = ImportGraphPlanner(probe_path)
            before = planner.snapshot()
            request = {"mode": "planner", "path": str(probe_path), "account": A, "source": S, "records": [sample], "point": point}
            self.crash(request)
            reopened = ImportGraphPlanner(probe_path)
            self.assertEqual(reopened.snapshot(), before)
            self.assertEqual(len(reopened.prepare(A, S, 0, [sample])), 3)
        initial = self.planner.prepare(A, S, 0, [sample])
        self.send(initial)
        changed = copy.deepcopy(sample)
        changed["fact"]["name"] = "后继名称"
        batch = self.planner.prepare(A, S, 0, [changed], begin_sequence=4,
            predecessor=initial[0]["import_batch_id"], revision=2, versions=self.versions())
        self.send(batch[:-1])
        import sqlite3
        for point in ("import_successor_canonical:category", "import_successor_publication_head", "import_receipt", "import_device_sequence"):
            clone = self.path / (point.replace(":", "_") + ".db")
            with self.server.connect() as source:
                target = sqlite3.connect(clone)
                try:
                    source.backup(target)
                finally:
                    target.close()
            store = ImportSuccessorServer(clone, account_id=A, authority=None, staging_ttl_seconds=60)
            before = store.snapshot()
            self.crash({"mode": "server", "path": str(clone), "account": A, "device": D, "messages": batch[-1:], "point": point})
            reopened = ImportSuccessorServer(clone, account_id=A, authority=None, staging_ttl_seconds=60)
            self.assertEqual(reopened.snapshot(), before)
            messages = [{"mutation": row, "payload_hash": mutation_hash(row)} for row in batch[-1:]]
            result = reopened.exchange(D, 0, messages)[0]
            self.assertEqual((result["status"], result["import_revision"]), ("accepted", 4))
            self.assertEqual(reopened.exchange(D, 0, messages)[0]["original_result"], result)

    def crash(self, request):
        path = self.path / "crash.json"
        path.write_text(json.dumps(request, ensure_ascii=False), encoding="utf8")
        process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_successor_crash_probe.py"), str(path)],
            capture_output=True, text=True, timeout=90)
        self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
        self.assertIn("KILL_POINT_REACHED:" + request["point"], process.stdout)
        CRASH_POINTS.append(request["point"])


if __name__ == "__main__":
    unittest.main()
