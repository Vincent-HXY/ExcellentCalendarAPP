"""Retire complete audit payloads in the declared SQLite record stores.

This isolated transaction does not invoke Android. The durable, workspace-bound
result is the only input allowed for subsequent platform cancellation.
"""
import json

from build_sync_storage_contract import derive
from domain_reference import check, validate_schema
from protocol_reference import digest, encode


def create_audit_tables(db):
    for table, codec in derive()["inherited_audit_store_codecs"].items():
        if db.execute("SELECT 1 FROM sqlite_master WHERE name=?", (table,)).fetchone() is None:
            db.execute(codec["ddl"])


def audit_rows(db, table):
    codec = derive()["inherited_audit_store_codecs"][table]
    for key, position, raw in db.execute(f"SELECT record_key,position,payload_json FROM {table} ORDER BY position").fetchall():
        value = json.loads(raw)
        validate_schema(codec["schema"], value)
        check(value[codec["record_key_field"]] == key, "IMPORT_REFERENCE_INVALID")
        yield key, position, value


def write_audit(db, table, value, *, position=None):
    codec = derive()["inherited_audit_store_codecs"][table]
    validate_schema(codec["schema"], value)
    key = value[codec["record_key_field"]]
    if position is None:
        db.execute(f"UPDATE {table} SET payload_json=? WHERE record_key=?", (encode(value), key))
    else:
        db.execute(f"INSERT INTO {table}(record_key,position,payload_json) VALUES(?,?,?)", (key, position, encode(value)))


def retire_audits(db, identities, receipt, now):
    affected = {"workspace_id": receipt["source_workspace_id"], "workspace_kind": "local",
        "source_epoch": receipt["source_epoch"], "retirement_receipt_hash": receipt["receipt_hash"],
        "reminder_ids": [], "notifications": [], "recovery_batch_ids": []}
    moved_reminders, moved_recovery, recovery = set(), set(), set()
    for key, _, value in audit_rows(db, "reminders"):
        target = value["target_type"], value["target_id"]
        old = db.execute("SELECT 1 FROM guest_import_audit_anchors WHERE target_type=? AND target_id=? AND reminder_id=?", (*target, key)).fetchone()
        if old:
            continue
        check(target in identities, "IMPORT_REFERENCE_INVALID")
        db.execute("INSERT INTO guest_import_audit_anchors VALUES(?,?,?,?,?,'source_migrated',?,NULL,NULL)",
            (*target, key, receipt["source_epoch"], receipt["import_lineage_id"], now))
        moved_reminders.add(key)
        if value["recovery_batch_id"] is not None:
            moved_recovery.add(value["recovery_batch_id"])
        if value["status"] in {"pending", "scheduled"}:
            value.update(status="cancelled", is_enabled=False, scheduled_at=None,
                last_cancellation_reason="source_migrated", last_cancelled_at=now, updated_at=now)
            write_audit(db, "reminders", value)
            affected["reminder_ids"].append(key)
            if value["recovery_batch_id"] is not None:
                recovery.add(value["recovery_batch_id"])
    for key, _, value in audit_rows(db, "notifications"):
        references = set(value["covered_reminder_ids"])
        if value["reminder_id"] is not None:
            references.add(value["reminder_id"])
        if value["status"] != "prepared" or not (references.intersection(moved_reminders) or value["recovery_batch_id"] in moved_recovery):
            continue
        value.update(status="abandoned", abandon_reason="source_migrated", finalized_at=now, updated_at=now)
        write_audit(db, "notifications", value)
        affected["notifications"].append({field: value[field] for field in
            ("notification_id", "delivery_id", "delivery_attempt_id", "recovery_batch_id")})
        if value["recovery_batch_id"] is not None:
            recovery.add(value["recovery_batch_id"])
    affected["reminder_ids"].sort()
    affected["notifications"].sort(key=lambda row: row["notification_id"])
    affected["recovery_batch_ids"] = sorted(recovery)
    validate_schema("workspace/import_affected_execution.schema.json", affected)
    db.execute("INSERT INTO guest_import_execution_retirements VALUES(?,?,?,?,?,?)", (
        receipt["source_workspace_id"], receipt["source_epoch"], receipt["receipt_hash"], 1, encode(affected), digest(affected)))
    return affected


def read_affected(db, epoch):
    row = db.execute("SELECT source_workspace_id,receipt_hash,payload_json,payload_hash FROM guest_import_execution_retirements WHERE source_epoch=?", (epoch,)).fetchone()
    check(row is not None, "IMPORT_REFERENCE_INVALID")
    value = json.loads(row[2])
    validate_schema("workspace/import_affected_execution.schema.json", value)
    check(value["workspace_id"] == row[0] and value["source_epoch"] == epoch and value["retirement_receipt_hash"] == row[1]
        and digest(value) == row[3], "IMPORT_REFERENCE_INVALID")
    return value
