"""Typed import publication is invisible until a complete, durable local commit."""
import base64
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
from bootstrap_reference import BootstrapServer, page_set_digest, provenance_entries
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, after_image
from build_owned_graph_fixtures import derive
from build_target_fixtures import build
from import_contract_reference import PUBLISH_FIELDS, publication
from import_download_reference import ImportDownloadStore
from import_staging_reference import ImportStagingStore, build_initial_batch
from protocol_reference import digest, mutation_hash
from test_sync_local_download import group

SOURCE = "33333333-3333-4333-8333-333333333333"
CRASH_POINTS = []


class ImportDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-download-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.local = ImportDownloadStore(self.path / "local.db", device_id=D)
        self.bootstrap_server = BootstrapServer(self.path / "bootstrap.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        self.bootstrap([], upper=0)

    def bootstrap(self, images, *, upper):
        self.bootstrap_server.seed(images, highest=0, confirmed=0, upper_bound=upper)
        now = NOW + (86400 if upper else 0)
        page = self.bootstrap_server.begin(now=now, download_limit=500)
        self.local.begin(page)
        pages, cursor = [], None
        while True:
            self.local.stage(page, request_cursor=cursor)
            pages.append(page)
            if not page["has_more"]:
                break
            cursor = page["next_bootstrap_cursor"]
            page = self.bootstrap_server.download(cursor, now=now, download_limit=500)
        self.local.finalize(expected_page_set_digest=page_set_digest(pages), final_cursor=page["terminal_sync_cursor"])

    def published(self):
        server = ImportStagingStore(self.path / "source.db", account_id=A)
        server.register(D)
        records = derive()["cases"][2]["input"]["seed"]
        batch = build_initial_batch(A, SOURCE, 0, records)
        accepted = server.exchange(D, 0, [{"mutation": row, "payload_hash": mutation_hash(row)} for row in batch])[-1]
        self.assertEqual(accepted["status"], "accepted")
        return [json.loads(row[2]) for row in server.snapshot()["import_publication_lines"]]

    def response(self, changes, *, upper, more):
        return {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
            "changes": changes, "account_generation": 0, "snapshot_upper_bound": upper,
            "next_cursor": base64.urlsafe_b64encode(b"opaque import page " + uuid.uuid4().bytes).decode().rstrip("="), "has_more": more,
            "accepted_client_sequence_through": 0, "retention_floor_server_sequence": 0, "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}

    def pull(self, response):
        request = self.local.prepare_download()
        self.local.apply_download(response, request_id=request)
        return request

    def state(self):
        return json.loads(self.local.snapshot()["state"][0][0])

    def test_real_staged_and_commit_receipts_never_publish_until_download_commit(self):
        messages = self.published()
        before = self.local.snapshot()
        self.assertFalse(before["live"])
        response = self.response(messages[:-1], upper=3, more=True)
        request = self.pull(response)
        stage = self.local.snapshot()
        for table in ("live", "presentation", "local_import_applied", "state"):
            self.assertEqual(stage[table], before[table])
        self.assertEqual(stage["local_import_stage"][0][3], 2)
        self.local.apply_download(response, request_id=request)
        self.assertEqual(self.local.snapshot(), stage)
        self.local = ImportDownloadStore(self.local.path, device_id=D)
        final = self.response(messages[-1:], upper=3, more=False)
        request = self.pull(final)
        self.assertEqual(len(self.local.snapshot()["presentation"]), 3)
        self.assertEqual(self.state()["upper_bound"], 3)
        self.assertEqual(len(self.local.snapshot()["local_import_applied"]), 1)
        self.assertFalse(self.local.snapshot()["local_import_stage"])
        complete = self.local.snapshot()
        self.local.apply_download(final, request_id=request)
        self.assertEqual(self.local.snapshot(), complete)

    def test_501_actual_images_remain_invisible_across_pages_and_restart(self):
        sample = build()["samples"]["category"]
        images = []
        for index in range(501):
            record = copy.deepcopy(sample)
            record["target_id"] = record["fact"]["id"] = f"{index + 1:08x}-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            image = after_image(record)
            image["import_provenance"] = {"source_workspace_id": SOURCE, "source_epoch": 0,
                "import_lineage_id": A, "source_target_type": "category", "source_id": record["target_id"]}
            images.append(image)
        binding = {"import_lineage_id": A, "import_batch_id": SOURCE, "source_workspace_id": SOURCE,
            "source_epoch": 0, "manifest_hash": "a" * 64, "mapping_digest": "b" * 64}
        messages = publication(binding, images, 1, str(uuid.uuid4()))
        self.assertEqual([len(row["items"]) for row in messages[1:-1]], [500, 1])
        self.pull(self.response(messages[:2], upper=4, more=True))
        self.assertFalse(self.local.snapshot()["live"])
        self.local = ImportDownloadStore(self.local.path, device_id=D)
        self.pull(self.response(messages[2:3], upper=4, more=True))
        self.assertEqual(self.state()["upper_bound"], 0)
        self.assertFalse(self.local.snapshot()["presentation"])
        self.pull(self.response(messages[-1:], upper=4, more=False))
        self.assertEqual(len(self.local.snapshot()["presentation"]), 501)
        self.assertEqual(self.state()["upper_bound"], 4)

    def test_missing_reordered_mixed_tampered_and_changed_upper_pages_are_zero_write(self):
        messages = self.published()
        request = self.local.prepare_download()
        invalid = [self.response(messages[:-1], upper=3, more=False), self.response(messages[1:], upper=3, more=False),
            self.response([messages[0], group(after_image(build()["samples"]["category"]), sequence=2)], upper=3, more=True)]
        tampered = copy.deepcopy(messages[:-1])
        tampered[1]["payload_hash"] = "0" * 64
        invalid.append(self.response(tampered, upper=3, more=True))
        for response in invalid:
            before = self.local.snapshot()
            with self.assertRaises(ValueError):
                self.local.apply_download(response, request_id=request)
            self.assertEqual(self.local.snapshot(), before)
        self.pull(self.response(messages[:-1], upper=3, more=True))
        request = self.local.prepare_download()
        for response in (self.response(messages[-1:], upper=4, more=False), self.response([], upper=3, more=False)):
            before = self.local.snapshot()
            with self.assertRaises(ValueError):
                self.local.apply_download(response, request_id=request)
            self.assertEqual(self.local.snapshot(), before)

    def test_actual_process_death_preserves_partial_staging_or_complete_visibility(self):
        messages = self.published()
        first = self.response(messages[:-1], upper=3, more=True)
        request = self.local.prepare_download()
        self.kill(first, request, ("import_download_staged_line", "import_download_staging_cursor", "import_download_page_receipt"))
        self.local.apply_download(first, request_id=request)
        final = self.response(messages[-1:], upper=3, more=False)
        request = self.local.prepare_download()
        self.kill(final, request, ("import_download_fact:event", "import_download_fact:event_recurrence", "import_download_fact:reminder_intent",
            "import_download_marker", "import_download_effect_coverage", "import_download_projection", "import_download_visible_cursor", "import_download_page_receipt"))
        self.local.apply_download(final, request_id=request)
        self.assertEqual(len(self.local.snapshot()["presentation"]), 3)

    def kill(self, response, request, points):
        for point in points:
            before = self.local.snapshot()
            path = self.path / "kill.json"
            path.write_text(json.dumps({"path": str(self.local.path), "device": D, "response": response, "request": request, "point": point}), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_download_crash_probe.py"), str(path)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            self.local = ImportDownloadStore(self.local.path, device_id=D)
            self.assertEqual(self.local.snapshot(), before)
            CRASH_POINTS.append(point)

    def test_authoritative_bootstrap_can_complete_partial_publication(self):
        messages = self.published()
        self.pull(self.response(messages[:-1], upper=3, more=True))
        images = messages[1]["items"]
        metadata = {name: messages[0][name] for name in PUBLISH_FIELDS}
        entries = provenance_entries(images, metadata)
        marker = {"kind": "import_publish_marker", **metadata, "snapshot_provenance_count": len(entries), "snapshot_provenance_digest": digest(entries)}
        self.bootstrap([*images, marker], upper=3)
        self.assertEqual(len(self.local.snapshot()["presentation"]), 3)
        self.assertFalse(self.local.snapshot()["local_import_stage"])
        self.assertEqual(self.local.snapshot()["local_import_applied"][0][3], "bootstrap")


if __name__ == "__main__":
    unittest.main()
