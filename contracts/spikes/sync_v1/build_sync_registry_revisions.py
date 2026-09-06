"""Expose planned versioned registries while keeping historical nodes unchanged."""
import argparse
import json

from build_sync_domain_contracts import CONTRACTS, yaml
from build_sync_lifecycle_contracts import PHASES, SESSIONS

REVISION_PATHS = {
    "method_channels.yaml": ("native", 3, "native_v3/method_channels.yaml"),
    "native_calls.yaml": ("native", 3, "native_v3/native_calls.yaml"),
    "backend_api.yaml": ("backend_api", 1, "backend_sync_v1/backend_api.yaml"),
    "enums.yaml": ("sync_protocol", 1, "sync/sync_enums.yaml"),
    "error_codes.yaml": ("sync_protocol", 1, "sync/sync_error_registry.yaml"),
}


def extension(path):
    domain, version, target = REVISION_PATHS[path]
    return [{"revision": "cloud_sync_v1", "contract_domain": domain, "version": version,
        "registry": target, "implementation_status": "planned", "release_status": "planned",
        "compatibility": "historical registry and schemas retained; explicit revision selection only; no fallback"}]


def derive():
    fields = yaml.safe_load((CONTRACTS / "sync/sync_field_registry.yaml").read_text(encoding="utf-8"))
    preference = json.loads((CONTRACTS / "sync/v1/user_preferences_fact.schema.json").read_text(encoding="utf-8"))
    enums = {
        "WorkspaceKind": ["local", "account"], "WorkspaceRouteState": ["ready", "locked", "empty"],
        "SyncPhase": PHASES, "SessionState": SESSIONS,
        "SyncRunIntent": ["normal", "logout_final", "receipt_ack_flush", "reenable_pull_only", "clear_rebuild_bootstrap"],
        "SyncTargetType": list(fields["targets"]), "SyncUploadTerminalStatus": ["accepted", "partially_merged", "conflict", "rejected", "staged"],
        "SyncConflictResolutionMode": ["keep_local", "keep_remote", "per_field", "manual_edit"],
        "SyncConflictStatus": ["unresolved", "resolving", "resolved"],
        "ImportStage": ["local_staging", "server_staging", "repair_required", "server_confirmed", "publish_applied", "cleanup_pending", "completed", "superseded", "abandoned"],
        "BacklogState": ["normal", "warning", "critical"], "DeviceState": ["active", "revoked"], "DevicePlatform": ["android"],
        "BackendSessionRegistrationState": ["unregistered", "pending_registration", "registered"],
        "PortableHabitProgressColor": preference["properties"]["habit_progress_color"]["enum"],
        "ReminderIntentOwnerType": ["event", "habit", "anniversary"], "SyncReminderMethod": ["ring", "popup"],
        "BootEpochSource": ["global_boot_count", "process_only"],
        "RetentionClockState": ["trusted", "untrusted", "expired", "deleting", "destroyed", "not_applicable"],
    }
    value = {"version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/9,12",
        "preserved_registry": "../enums.yaml", "unknown_value": "reject_no_default_no_case_or_ordinal_coercion",
        "enums": {name: {"wire_type": "string", "values": values} for name, values in enums.items()}}
    return {CONTRACTS / "sync/sync_enums.yaml": value}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            assert yaml.safe_load(path.read_text(encoding="utf-8")) == value
        else:
            path.write_text(yaml.safe_dump(value, allow_unicode=True, sort_keys=False), encoding="utf-8")
    for relative in REVISION_PATHS:
        path = CONTRACTS / relative
        content = path.read_text(encoding="utf-8")
        actual = yaml.safe_load(content)
        expected = extension(relative)
        if "planned_revisions" in actual:
            assert actual["planned_revisions"] == expected, relative
        else:
            assert not args.check, relative
            with path.open("a", encoding="utf-8", newline="") as stream:
                stream.write("\n" + yaml.safe_dump({"planned_revisions": expected}, allow_unicode=True, sort_keys=False))
    print("Planned registry links added; active historical definitions retained")
