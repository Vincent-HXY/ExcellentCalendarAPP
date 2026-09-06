"""Fixed local-journal histories; no simulated production producer claim."""
import copy
import json
from pathlib import Path
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/local_intent_vectors.json"


def intent(sample, sequence, name):
    value = {"protocol_version": 1, "mutation_id": str(uuid.UUID(int=200000 + sequence, version=4)),
        "client_sequence": sequence, "target_type": "category", "target_id": sample["target_id"], "operation_type": "update",
        "base_entity_version": 1, "causal_predecessors": [{"merge_key": "name", "client_sequence": None}],
        "import_lineage_id": None, "import_batch_id": None, "import_source_workspace_id": None, "import_source_epoch": None,
        "import_item_ordinal": None, "import_manifest_hash": None, "predecessor_batch_id": None,
        "payload": {"patch": {"name": name}, "owned_dependencies": []}, "conflict_recovery_snapshot": copy.deepcopy(sample["fact"]),
        "created_at": "2026-09-05T01:00:00Z"}
    value["conflict_recovery_snapshot"]["name"] = name
    return value


def derive():
    sample = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]["category"]
    original, original_description = sample["fact"]["name"], sample["fact"]["description"]
    cases = []
    for scenario, name, description, pending, failed, drafts, ack, next_sequence, error in (
        ("rejected", "本机输入", original_description, 0, 1, 0, 1, 2, None),
        ("rejected_download", "本机输入", "远端备注", 0, 1, 0, 1, 2, None),
        ("no_effect_replacement", original, original_description, 0, 1, 1, 2, 3, None),
        ("discard_failed_replacement", original, original_description, 0, 1, 1, 2, 3, None),
        ("missing_receipt_bootstrap", "远端名字", original_description, 1, 0, 1, 0, 2, None),
        ("stale_failed_revision", "本机输入", original_description, 0, 1, 0, 1, 2, "SYNC_FAILED_CHANGE_VERSION_CONFLICT"),
        ("pending_above_snapshot", "本机输入", "远端备注", 1, 0, 0, 0, 2, None),
        ("failed_then_pending", "后续输入", "远端备注", 1, 1, 0, 1, 3, None),
    ):
        cases.append({"id": "FX-FAILED-LOCAL-" + scenario.upper().replace("_", "-"), "family": "FX-FAILED-LOCAL",
            "rule_anchor": "cloud-sync-02/6.2-6.3,7.3,7.5,10", "input": {"scenario": scenario, "baseline": sample,
                "original": intent(sample, 1, "本机输入"), "replacement": intent(sample, 2,
                    original if scenario == "no_effect_replacement" else "后续输入")},
            "expected": {"name": name, "description": description, "pending": pending, "failed": failed,
                "drafts": drafts, "effects": 0, "local_ack": ack, "next_sequence": next_sequence, "error": error}})
    return {"fixture_version": 1, "scope": "combined synthetic SQLite journal and authenticated-boundary recovery inputs; production owners remain separate",
        "cases": cases}


if __name__ == "__main__":
    FIXTURE.write_text(json.dumps(derive(), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"cases": len(derive()["cases"])}))
