"""Fixed private-record and safe diagnostic payload shape expectations."""
import copy
import json
from build_sync_protocol_contracts import CONTRACTS

A, W, D, S = [str(n) * 8 + "-" + str(n) * 4 + "-4" + str(n) * 3 + "-8" + str(n) * 3 + "-" + str(n) * 12 for n in range(1, 5)]
NOW = "2026-09-06T07:00:00Z"


def derive():
    native = {"schema_version": 1, "native_contract_version": 3, "sync_protocol_version": 1, "storage_format_version": 6,
        "sync_enabled": False, "pending_count_bucket": "1_99", "oldest_pending_age_bucket": "under_72h", "outbox_bytes_bucket": "under_64mib",
        "failed_count": 0, "unresolved_count": 0, "unclaimed_notice_count": 0, "native_blocked_reason": None,
        "ack_watermark_dirty": True, "bootstrap_active": False, "import_active": True}
    samples = {
        "workspace/private/crypto_destroy_final_receipt.schema.json": {"schema_version": 1, "account_id": A, "workspace_id": W,
            "operation_id": D, "device_id": D, "sync_transport_generation": 1, "lifecycle_revision": 2,
            "expected_source_lease_revision": 3, "protected_owner_binding_digest": "1" * 64,
            "source_workspace_id": S, "source_epoch": 0, "import_lineage_id": W, "import_batch_id": D,
            "manifest_hash": "2" * 64, "account_key_identity_hash": "3" * 64, "state": "final", "reason": "clear_rebuild"},
        "device/private/remote_snapshot_cache.schema.json": {"schema_version": 1, "account_id": A, "workspace_id": W, "device_id": D,
            "captured_at": NOW, "snapshot": {"registration_pending": False, "current_device_id": D, "devices": []}},
        "sync/diagnostic_export_payload.schema.json": {"schema_version": 1, "native": native, "android_api_bucket": "31_plus",
            "transport_state": "offline", "work_pending": True, "network_available": False},
        "sync/private/diagnostic_export_journal.schema.json": {"schema_version": 1, "export_id": D, "sha256": "4" * 64,
            "boot_id": S, "created_elapsed_ms": 10, "ttl_seconds": 900, "state": "ready"},
    }
    cases = []
    def add(identity, schema, value, valid):
        cases.append({"id": "FX-PRIVATE-" + identity, "family": "FX-IMPORT-CLEANUP" if "crypto_destroy" in schema else "FX-MAINTENANCE",
            "rule_anchor": "cloud-sync-02/7.6/IMP-10,8.2,13", "schema": schema, "input": value, "expected": {"schema_valid": valid}})
    for schema, value in samples.items():
        name = schema.split("/")[-1].removesuffix(".schema.json")
        add(name, schema, value, True)
        add(name + "-extra", schema, {**value, "unexpected": 1}, False)
        add(name + "-missing-version", schema, {k: v for k, v in value.items() if k != "schema_version"}, False)
    schema = "sync/diagnostic_export_payload.schema.json"
    for key in ("title", "business_payload", "conflict_candidate", "token", "cursor", "account_id", "device_id", "directory", "key_alias"):
        value = copy.deepcopy(samples[schema])
        value["native"][key] = "must never be exported"
        add("diagnostic-denies-" + key, schema, value, False)
    return {"fixture_version": 1, "scope": "Shape/authorization inputs; OS primitives are independently verified", "cases": cases, "samples": samples}


if __name__ == "__main__":
    (CONTRACTS / "fixtures/sync/v1/private_lifecycle_vectors.json").write_text(json.dumps(derive(), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
