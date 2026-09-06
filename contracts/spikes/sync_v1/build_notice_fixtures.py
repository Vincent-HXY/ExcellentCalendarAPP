"""Reviewable notice histories; queue identity and count expectations are fixed."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/notice_vectors.json"
MAXIMUM = 9007199254740991


def derive():
    cases = []
    for name, steps, expected in (
        ("NET-ZERO", ["begin", "create_a", "resolve_a", "terminal"], [0, 0, 1, 0, False, None]),
        ("LATER-B-SURVIVES-OLD-CLAIM", ["begin", "create_a", "terminal", "begin", "create_b", "terminal", "claim_a", "claim_a"], [2, 1, 3, 1, False, "no_longer_actionable"]),
        ("RESOLVED-HEAD", ["begin", "create_a", "terminal", "begin", "resolve_a", "terminal", "claim_a"], [0, 0, 2, 1, False, "no_longer_actionable"]),
        ("MAX-CONTINUES-DOWNLOAD", ["maximum", "begin", "create_a", "terminal", "begin", "create_b", "terminal", "claim_a"], [2, 0, None, MAXIMUM, True, "claimed"]),
        ("BOOTSTRAP-CARRIES-UNNOTIFIED", ["begin", "create_a", "bootstrap", "terminal"], [1, 1, 2, 0, False, None]),
        ("KNOWN-IS-NOT-NEW", ["known_a", "begin", "create_a", "terminal"], [1, 0, 1, 0, False, None]),
    ):
        cases.append({"id": "FX-CONFLICT-NOTICE-" + name, "family": "FX-CONFLICT", "rule_anchor": "cloud-sync-02/8.2,10,13",
            "input": {"steps": steps}, "expected": dict(zip(("unresolved", "queue", "next_sequence", "last_claimed", "exhausted", "claim_disposition"), expected))})
    return {"fixture_version": 1, "scope": "isolated durable notice journal histories, with separate typed apply composition tests",
        "cases": cases, "capacity": {"windows": 1000000, "windows_per_commit": 1000,
            "maximum_live_queue_rows": 1, "maximum_live_members": 1, "retained_terminal_discovery_rows": 0}}


if __name__ == "__main__":
    FIXTURE.write_text(json.dumps(derive(), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"cases": len(derive()["cases"])}))
