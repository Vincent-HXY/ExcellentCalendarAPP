"""Import manifests bind real item contents; publication never skips a chunk."""
import copy
from pathlib import Path
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from bootstrap_reference import CAPS
from build_bootstrap_fixtures import after_image
from build_target_fixtures import build
from counter_reference import MAXIMUM
from import_contract_reference import (make_manifest, manifest_digest, publication, validate_manifest, validate_publication)
from protocol_reference import canonical, digest

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"


class ImportContractTests(unittest.TestCase):
    def setUp(self):
        self.sample = build()["samples"]["category"]
        self.items = []
        for index in range(2):
            fact = copy.deepcopy(self.sample["fact"])
            fact["id"] = f"{index + 1:08x}-9999-4999-8999-999999999999"
            fact["name"] = "A"
            self.items.append({"target_type": "category", "target_id": fact["id"], "operation_type": "import_put",
                "payload": {"source_id": fact["id"], "fact": fact}})
        self.manifest = make_manifest(A, 0, "0" * 64, self.items)
        self.binding = {"source_workspace_id": A, "source_epoch": 0, "import_lineage_id": B, "import_batch_id": C,
            "manifest_hash": self.manifest["manifest_hash"], "mapping_digest": self.manifest["mapping_digest"]}

    def test_manifest_rejects_same_size_content_swap_despite_unchanged_counts_and_mapping(self):
        changed = copy.deepcopy(self.items)
        changed[0]["payload"]["fact"]["name"] = "B"
        other = make_manifest(A, 0, "0" * 64, changed)
        for name in ("total_item_count", "total_canonical_bytes", "mapping_digest", "target_counts"):
            self.assertEqual(self.manifest[name], other[name])
        self.assertNotEqual(self.manifest["manifest_hash"], other["manifest_hash"])
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            validate_manifest(self.manifest, changed)

    def test_manifest_order_duplicates_missing_items_and_underreported_bytes_are_rejected(self):
        for value in (self.items[::-1], self.items[:1], [self.items[0], self.items[0]]):
            with self.assertRaises(ValueError):
                validate_manifest(self.manifest, value)
        with self.assertRaisesRegex(ValueError, "SYNC_IMPORT_CAPACITY_EXCEEDED"):
            validate_manifest({**self.manifest, "total_canonical_bytes": self.manifest["total_canonical_bytes"] - 1}, self.items)

    def test_manifest_has_no_circular_dependency_on_transport_hash_or_sequence(self):
        transported = [{**row, "client_sequence": 123 + index, "mutation_id": str(uuid.uuid4()), "created_at": "2026-09-06T00:00:00Z",
            "import_manifest_hash": self.manifest["manifest_hash"]} for index, row in enumerate(self.items)]
        self.assertEqual(manifest_digest(self.manifest, transported), self.manifest["manifest_hash"])
        self.assertEqual(manifest_digest({**self.manifest, "manifest_hash": "f" * 64}, self.items), self.manifest["manifest_hash"])

    def images(self, count, *, large=False):
        sample = build()["samples"]["event"] if large else self.sample
        result = []
        for index in range(count):
            record = copy.deepcopy(sample)
            record["target_id"] = record["fact"]["id"] = f"{index + 1:08x}-8888-4888-8888-888888888888"
            if large:
                record["fact"]["content"] = "a" * 4000
            image = after_image(record)
            image["import_provenance"] = {"source_workspace_id": A, "source_epoch": 0, "import_lineage_id": B,
                "source_target_type": record["target_type"], "source_id": record["target_id"]}
            result.append(image)
        return result

    def test_501_images_partition_by_item_limit_and_round_trip_all_actual_items(self):
        images = self.images(501)
        messages = publication(self.binding, images, 10, A)
        self.assertEqual([len(row["items"]) for row in messages[1:-1]], [500, 1])
        self.assertEqual([row["server_sequence"] for row in messages], [10, 11, 12, 13])
        self.assertEqual(validate_publication(messages), images)

    def test_large_images_partition_before_the_byte_cap_without_truncation(self):
        images = self.images(260, large=True)
        messages = publication(self.binding, images, 1, A)
        self.assertGreater(len(messages[1:-1]), 1)
        self.assertTrue(all(len(canonical(row)) <= CAPS["import_chunk_hard_bytes"] for row in messages[1:-1]))
        self.assertEqual(validate_publication(messages), images)

    def test_tampered_missing_reordered_and_huge_range_publications_fail_closed(self):
        messages = publication(self.binding, self.images(501), 1, A)
        changes = [messages[:-1], [messages[0], messages[2], messages[1], messages[3]]]
        changed = copy.deepcopy(messages)
        changed[1]["items"][0]["fact"]["name"] = "其他名称"
        changes.append(changed)
        changed = copy.deepcopy(messages)
        for index in (0, -1):
            changed[index]["commit_server_sequence"] = MAXIMUM
        changed[-1]["server_sequence"] = MAXIMUM
        changes.append(changed)
        for candidate in changes:
            with self.assertRaises(ValueError):
                validate_publication(candidate)
        # Even a freshly recomputed chunk hash cannot change the begin/commit digest.
        changed = copy.deepcopy(messages)
        changed[1]["items"][0]["fact"]["name"] = "其他名称"
        changed[1]["payload_hash"] = digest({key: value for key, value in changed[1].items() if key != "payload_hash"})
        with self.assertRaisesRegex(ValueError, "IMPORT_PUBLISH_INCOMPLETE"):
            validate_publication(changed)


if __name__ == "__main__":
    unittest.main()
