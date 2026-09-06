"""Synthetic file categories and two-destination restore policy vectors; no user files."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/backup_policy_vectors.json"
CATEGORIES = ("installation", "workspace_registry", "device_registry", "broker_token", "broker_pending", "wrapped_key",
    "guest_db", "guest_wal", "guest_shm", "guest_legacy_json", "account_db", "account_wal", "account_shm",
    "transport_journal", "import_journal", "clear_seed", "logout_journal", "source_lease", "retention_deadline", "boot_epoch",
    "proof_revocations", "remote_device_cache", "profile_cache", "guest_search_history", "account_search_history")
BASE = ("root", "file", "database", "sharedpref", "external")
DEVICE = ("device_root", "device_file", "device_database", "device_sharedpref")
OLD_INSTALL = "11111111-1111-4111-8111-111111111111"
OLD_GUEST = "22222222-2222-4222-8222-222222222222"


def files(api_level):
    return [{"id": domain + ":" + category, "category": category, "domain": domain,
        "path": "synthetic/" + category + "/bytes.bin"} for domain in BASE + (DEVICE if api_level >= 24 else ()) for category in CATEGORIES]


def derive():
    cases = []
    for api in (23, 24, 30, 31, 33):
        for transport in ("cloud", "device_transfer"):
            cases.append({"id": f"FX-RETENTION-NOTIFY-backup-{api}-{transport}", "family": "FX-RETENTION-NOTIFY",
                "rule_anchor": "cloud-sync-02/4.1,4.2", "input": {"operation": "export_projection", "api_level": api,
                    "transport": transport, "files": files(api)}, "expected": {"exported_entries": [], "guest_entries_exported": 0}})
    cases.append({"id": "FX-RETENTION-NOTIFY-backup-two-destinations", "family": "FX-RETENTION-NOTIFY", "rule_anchor": "cloud-sync-02/4.2",
        "input": {"operation": "two_destinations", "restored_files": files(33), "previous_installation_id": OLD_INSTALL,
            "previous_guest_workspace_id": OLD_GUEST,
            "destinations": [{"new_installation_id": "33333333-3333-4333-8333-333333333333", "new_guest_workspace_id": "44444444-4444-4444-8444-444444444444"},
                {"new_installation_id": "55555555-5555-4555-8555-555555555555", "new_guest_workspace_id": "66666666-6666-4666-8666-666666666666"}]},
        "expected": {"distinct_new_installations": True, "distinct_new_guests": True, "active_restored_entries": 0,
            "restored_account_or_broker_or_lease_or_lineage_allowed": False, "guest_rehome_performed": False}})
    return {"fixture_version": 1, "scope": "explicit packaged-resource policy model only; no cloud/OEM transport is executed",
        "categories": list(CATEGORIES), "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
    result = derive()
    if args.check: assert json.loads(FIXTURE.read_text(encoding="utf-8")) == result
    else: FIXTURE.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(result["cases"]), "categories": len(CATEGORIES)}))
