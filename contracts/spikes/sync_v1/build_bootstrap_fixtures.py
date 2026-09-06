"""Synthetic snapshots for reviewable bootstrap integrity and publication tests."""
import argparse
import copy
import json
from pathlib import Path

from build_target_fixtures import build
from identity_reference import lineage_id
from protocol_reference import digest, typed_definition

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/bootstrap_vectors.json"
A = "11111111-1111-4111-8111-111111111111"
D = "22222222-2222-4222-8222-222222222222"
BATCH = "33333333-3333-4333-8333-333333333333"
SOURCE = "44444444-4444-4444-8444-444444444444"
NOW = 1788560400
KEY_ID = "55555555-5555-4555-8555-555555555555"
KEY = bytes(range(32))  # Published synthetic test material only.


def identifier(number):
    return f"{number:08x}-aaaa-4aaa-8aaa-aaaaaaaaaaaa"


def after_image(sample, *, provenance=None):
    sample = copy.deepcopy(sample)
    groups = typed_definition(sample["target_type"], sample["fact"])["merge_groups"]
    key = {name: sample[name] for name in ("target_type", "target_id")}
    if sample["target_type"] == "reminder_intent": key["owner_type"] = sample["fact"]["owner_type"]
    return {"kind": "fact_after_image", **sample, "entity_version": 1, "import_provenance": provenance,
        "field_versions": [{"key": {**key, "merge_key": name}, "field_version": 1} for name in sorted(groups)]}


def category_items(count):
    sample = build()["samples"]["category"]
    items = []
    for number in range(count):
        row = copy.deepcopy(sample)
        row["target_id"] = row["fact"]["id"] = identifier(number + 1)
        row["fact"]["name"] = "合成分类 " + str(number + 1)
        items.append(after_image(row))
    return items


def all_kinds():
    lineage = lineage_id(A, SOURCE, 0)
    fact, removed, anchor = category_items(3)
    fact["import_provenance"] = {"import_lineage_id": lineage, "source_workspace_id": SOURCE, "source_epoch": 0,
        "source_target_type": "category", "source_id": fact["target_id"]}
    removed.update(kind="tombstone", deleted_at="2026-09-05T01:00:00Z", delete_server_sequence=5)
    removed["fact"]["deleted_at"] = removed["deleted_at"]
    deleted = {"kind": "deleted_entity_anchor", "target_type": "category", "target_id": anchor["target_id"],
        "entity_version": 2, "delete_server_sequence": 6, "import_provenance": None}
    key = {"target_type": "category", "target_id": fact["target_id"], "merge_key": "name"}
    conflict = {"kind": "unresolved_conflict", "conflict": {"conflict_id": identifier(100), "conflict_version": 1,
        "target_type": "category", "target_id": fact["target_id"], "status": "unresolved", "source_device_id": D,
        "received_at": "2026-09-05T01:00:00Z", "conflicting_groups": [{"key": key,
            "server_candidate": {"kind": "value", "projection": {**key, "value": {"name": fact["fact"]["name"]}}},
            "local_candidate": {"kind": "value", "projection": {**key, "value": {"name": "本地保留"}}}}],
        "auto_merged_groups": [], "recovery_snapshot": {name: fact[name] for name in ("target_type", "target_id", "fact")}}}
    provenance = [{name: fact[name] for name in ("target_type", "target_id", "import_provenance")}]
    marker = {"kind": "import_publish_marker", "import_publish_group_id": BATCH, "import_lineage_id": lineage,
        "import_batch_id": BATCH, "source_workspace_id": SOURCE, "source_epoch": 0, "manifest_hash": "0" * 64,
        "mapping_digest": "1" * 64, "begin_server_sequence": 1, "commit_server_sequence": 3,
        "total_chunk_count": 1, "total_item_count": 1, "publish_digest": "2" * 64,
        "snapshot_provenance_digest": digest(provenance), "snapshot_provenance_count": 1}
    causal = {"kind": "requesting_device_causal_anchor", "key": key, "client_sequence": 1, "resulting_field_version": 1}
    return [fact, removed, deleted, conflict, marker, causal]


def derive():
    cases = []
    for name, scenario, expected in (
        ("EMPTY", "empty", {"pages": 1, "items": 0, "visible_before_finalize": 0}),
        ("SIX-UNION-KINDS", "six_kinds", {"pages": 3, "items": 6, "visible_before_finalize": 0}),
        ("500-ITEMS", "five_hundred", {"pages": 4, "items": 500, "visible_before_finalize": 0}),
        ("FIXED-SNAPSHOT", "fixed_snapshot", {"old_upper_bound": 100, "new_live_items": 3, "snapshot_items": 2}),
        ("RECOVERY-WATERMARK", "recovery", {"local_ack": 4, "server_ack": 2, "next_sequence": 5}),
        ("EXHAUSTED-READONLY", "exhausted", {"local_ack": 9007199254740991, "next_sequence": None, "exhausted": True}),
        ("GENERATION-CHANGED", "generation", {"error": "SYNC_BOOTSTRAP_GENERATION_CHANGED"}),
        ("TTL-BOUNDARY", "expired", {"error": "SYNC_BOOTSTRAP_EXPIRED"}),
        ("LOST-FIRST-RESPONSE", "first_loss", {"same_bootstrap_id": True, "same_page_bytes": True}),
        ("HIGH-WATERMARK-SUPERSEDES", "supersede", {"new_bootstrap_id": True, "old_cursor_error": "SYNC_BOOTSTRAP_EXPIRED"}),
    ):
        cases.append({"id": "FX-BOOTSTRAP-" + name, "family": "FX-BOOTSTRAP", "rule_anchor": "cloud-sync-02/6.3,10-11",
            "validation": "isolated_sqlite_snapshot_and_fresh_apply", "input": {"scenario": scenario}, "expected": expected})
    return {"fixture_version": 1, "scope": "materialized bootstrap and fresh promotion; pending rebase is separately required",
        "samples": {"all_kinds": all_kinds()}, "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
    result = derive()
    if args.check: assert json.loads(FIXTURE.read_text(encoding="utf-8")) == result
    else: FIXTURE.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(result["cases"])}))
