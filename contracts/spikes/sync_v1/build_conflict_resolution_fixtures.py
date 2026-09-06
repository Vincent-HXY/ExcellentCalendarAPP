"""Reviewable root conflict decisions; IDs come from the actual reference owner."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/conflict_resolution_vectors.json"


def derive():
    samples = json.loads((ROOT / "contracts/fixtures/sync/v1/target_vectors.json").read_text(encoding="utf8"))["samples"]
    cases = []
    rows = [
        ("KEEP-LOCAL", "keep_local", None, "本机选择", "resolved", 2, 3, ["name"]),
        ("KEEP-REMOTE", "keep_remote", None, "远端选择", "resolved", 2, 3, []),
        ("PER-FIELD", "per_field", None, "本机选择", "resolved", 2, 3, ["name"]),
        ("MANUAL", "manual_edit", None, "手动结果", "resolved", 2, 3, ["name"]),
        ("NOT-FOUND", "keep_remote", "SYNC_CONFLICT_NOT_FOUND", samples["category"]["fact"]["name"], "missing", 1, 0, []),
        ("VERSION-MISMATCH", "keep_local", "SYNC_CONFLICT_VERSION_MISMATCH", "远端选择", "unresolved", 2, 2, []),
        ("ALREADY-RESOLVED", "keep_local", "SYNC_CONFLICT_ALREADY_RESOLVED", "远端选择", "resolved", 2, 3, []),
        ("DOMAIN-REJECTED", "manual_edit", "HABIT_DATE_RANGE_INVALID", "远端选择", "unresolved", 2, 2, []),
    ]
    for name, mode, error, value, current, high, groups, applied in rows:
        target = "habit" if name == "DOMAIN-REJECTED" else "category"
        baseline = copy.deepcopy(samples[target])
        label = "title" if target == "habit" else "name"
        manual = copy.deepcopy(baseline) if mode == "manual_edit" else None
        if manual:
            if target == "habit":
                manual["fact"].update(start_date="2026-10-01", end_date="2026-09-30")
            else:
                manual["fact"][label] = "手动结果"
        cases.append({"id": "FX-CONFLICT-RESOLUTION-" + name, "family": "FX-CONFLICT", "rule_anchor": "cloud-sync-02/6.2-6.3,7.5,12",
            "input": {"scenario": name, "baseline": baseline, "dependencies": [samples["habit_recurrence"]] if target == "habit" else [],
                "remote_patch": {label: "远端选择"}, "local_patch": {label: "本机选择"}, "mode": mode, "manual_candidate": manual,
                "expected_conflict_version": 2 if name == "VERSION-MISMATCH" else 1,
                "conflict_id_binding": "missing-random-uuid" if name == "NOT-FOUND" else "actual-created-conflict-id"},
            "expected": {"status": "rejected" if error else "accepted", "failure_code": error, "value": value,
                "current_kind": current, "device_highest": high, "change_groups": groups, "applied_keys": applied}})
    return {"fixture_version": 1, "scope": "four resolution modes and four consumed business rejections on real synthetic SQLite roots; owned revisions remain separate",
        "cases": cases}


if __name__ == "__main__":
    FIXTURE.write_text(json.dumps(derive(), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"cases": len(derive()["cases"])}))
