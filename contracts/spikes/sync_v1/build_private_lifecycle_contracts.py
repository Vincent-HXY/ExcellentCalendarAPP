"""Freeze private persistence and safe-export shapes without product owners."""
import argparse
import json

from build_sync_protocol_contracts import CONTRACTS, SAFE, UUID4, UUID, HASH, DATE_TIME, const, object_of, ref, document


def derive():
    identity = {"schema_version": const(1), "account_id": UUID4, "workspace_id": UUID4}
    bodies = {
        "workspace/private/crypto_destroy_final_receipt": object_of({**identity,
            "operation_id": UUID4, "device_id": UUID4, "sync_transport_generation": SAFE,
            "lifecycle_revision": SAFE, "expected_source_lease_revision": SAFE, "protected_owner_binding_digest": HASH,
            "source_workspace_id": UUID4, "source_epoch": SAFE, "import_lineage_id": UUID,
            "import_batch_id": UUID4, "manifest_hash": HASH, "account_key_identity_hash": HASH,
            "state": const("final"), "reason": {"enum": ["clear_rebuild", "logout_destroy", "retention_expired", "device_revoked", "security_termination"]}}),
        "device/private/remote_snapshot_cache": object_of({**identity, "device_id": UUID4,
            "captured_at": DATE_TIME, "snapshot": ref("device_list_response", "device")}),
        "sync/diagnostic_export_payload": object_of({"schema_version": const(1),
            "native": ref("diagnostic_snapshot_response", "native_v3/internal"),
            "android_api_bucket": {"enum": ["23", "24_30", "31_plus"]},
            "transport_state": {"enum": ["idle", "running", "offline", "retry_wait", "auth_required", "blocked"]},
            "work_pending": {"type": "boolean"}, "network_available": {"type": "boolean"}}),
        "sync/private/diagnostic_export_journal": object_of({"schema_version": const(1), "export_id": UUID4,
            "sha256": HASH, "boot_id": UUID4, "created_elapsed_ms": SAFE, "ttl_seconds": const(900),
            "state": {"enum": ["ready", "shared"]}}),
    }
    result = {}
    for location, body in bodies.items():
        directory, name = location.rsplit("/", 1)
        schema = document(name, body, "7.6/IMP-08,IMP-10;8.2;13", directory)
        schema.update({"x-contract-domain": "android_private", "x-contract-version": 1,
            "x-owner": "Kotlin WorkspaceLifecycle / private persistence; diagnostics safe projection only"})
        if "/private/" in location:
            schema.update({"x-sensitive": True, "x-exposure": "kotlin_local_only_never_HTTP_MethodChannel_EventChannel_or_JNI"})
        result[CONTRACTS / (location + ".schema.json")] = schema
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            if json.loads(path.read_text(encoding="utf8")) != value:
                raise ValueError("Private lifecycle schema drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
