"""Literal owned resolution outcomes linked to immutable input histories."""
import copy
import json
from pathlib import Path
from build_owned_graph_fixtures import derive as owned

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/owned_resolution_vectors.json"


def derive():
    cases = []
    for unpublished, modes in ((False, ("keep_local", "keep_remote", "per_field", "manual_edit")), (True, ("keep_local", "keep_remote"))):
        for mode in modes:
            data = copy.deepcopy(owned()["cases"][2]["input"])
            data["mutations"][1]["client_sequence"] = 1
            if unpublished:
                second = data["mutations"][1]
                second["payload"]["patch"]["recurrence_revision"] = 3
                second["conflict_recovery_snapshot"]["recurrence_revision"] = 3
                child = second["payload"]["owned_dependencies"][0]
                child["target_id"] = child["target_id"].split("#")[0] + "#3"
                child["payload"]["revision"] = 3
            data.update(mode=mode, prepared_at="2026-09-06T04:00:00Z")
            cases.append({"id": "OWNED-RESOLVE-" + ("ABSENT-" if unpublished else "COLLISION-") + mode.upper().replace("_", "-"),
                "rule_anchor": "cloud-sync-01/9.1,9.4;cloud-sync-02/7.1-7.5,8", "input": data,
                "expected": {"status": "accepted", "current_kind": "resolved", "root_revision": 2 if mode == "keep_remote" else 3,
                    "selected_frequency": "weekly" if mode == "keep_remote" else "monthly", "retained_old_revisions": 2,
                    "root_title": "手动根对象" if mode == "manual_edit" else "独立标题", "published_item_count": 1 if mode == "keep_remote" else 2}})
    return {"fixture_version": 1, "scope": "Event immutable revision and exact typed owned resolution reference outcomes", "cases": cases}


if __name__ == "__main__":
    value = derive()
    FIXTURE.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"cases": len(value["cases"])}))
