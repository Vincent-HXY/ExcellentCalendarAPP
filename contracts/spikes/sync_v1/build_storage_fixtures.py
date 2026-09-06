"""Fixed observable database boundaries; expected SQLSTATEs are reviewed literals."""
import argparse
import json

from build_sync_postgres_contract import CONTRACTS, derive as model, literal

A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
DEVICE = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
NOW = "2026-09-05T00:00:00Z"


def insert(table, row):
    values = []
    for key, value in row.items():
        if isinstance(value, list):
            values.append("ARRAY[" + ",".join(literal(v) for v in value) + "]::" + ("bigint[]" if key == "days_of_week" else "text[]"))
        else:
            values.append(literal(value))
    return "INSERT INTO " + table + "(" + ",".join('"' + k + '"' for k in row) + ") VALUES(" + ",".join(values) + ")"


def derive():
    schema = model()
    samples = json.loads((CONTRACTS / "fixtures/sync/v1/target_vectors.json").read_text(encoding="utf-8"))["samples"]
    seed = []
    for account, label in ((A, "a"), (B, "b")):
        seed.append(insert("user_accounts", {"id": account, "email": label + "@example.test", "normalized_email": label + "@example.test", "status": "active", "created_at": NOW, "updated_at": NOW}))
        seed.append(insert("sync_account_sequences", {"account_id": account, "account_generation": 0, "highest_server_sequence": 0, "next_server_sequence": 1, "retention_floor": 0}))
    device = {"account_id": A, "device_id": DEVICE, "installation_hash": "d" * 64, "display_name": "Android 设备 😀", "device_version": 0,
        "protocol_version": 1, "app_version": "0.1.0", "receive_reminders": True, "sync_enabled": True, "settings_revision": 0, "created_at": NOW, "last_seen_at": NOW}
    seed.append(insert("user_devices", device))
    for name, sample in samples.items():
        target = sample["target_type"]
        if target in {"user_preferences", "account_profile"}:
            continue
        fact = sample["fact"]
        root = {"account_id": A, "entity_id": sample["target_id"], "entity_version": 1, "last_server_sequence": 1, "is_tombstone": False}
        if target == "reminder_intent":
            owner = fact["owner_type"]
            seed.append(insert("sync_fact_reminder_intent", {**root, **{k: fact[k] for k in ("owner_type", "owner_id", "is_enabled")}}))
            items = [fact["template"]] if owner == "habit" and fact["template"] is not None else fact.get("templates", [])
            for ordinal, template in enumerate(items):
                seed.append(insert("sync_reminder_" + owner + "_templates", {"account_id": A, "intent_id": sample["target_id"], "ordinal": ordinal, **template}))
        else:
            seed.append(insert("sync_fact_" + target, {**root, **fact}))
    cases = []

    def case(identity, sql, expected, **checks):
        cases.append({"id": identity, "family": "FX-WORKSPACE", "rule_anchor": "cloud-sync-02/11", "scope": "postgresql_constraint",
            "sql": sql, "sqlstate": expected, **checks})

    case("PG-FIELD-125-TYPED", "SELECT 1", "00000", query="SELECT count(*) FROM sync_fact_habit WHERE account_id='" + A + "'", scalar=1)
    lineage = {"account_id": A, "lineage_id": DEVICE, "source_workspace_id": B, "source_epoch": 0, "current_head_batch_id": None,
        "import_revision": 0, "cleanup_confirmed_through_batch_id": None, "cleanup_confirmed_through_revision": 0}
    batch = {"account_id": A, "batch_id": DEVICE, "lineage_id": DEVICE, "predecessor_batch_id": None, "origin_device_id": DEVICE,
        "origin_transport_generation": 0, "begin_client_sequence": 1, "terminal_client_sequence": 50003, "total_item_count": 50001,
        "total_canonical_bytes": 1, "manifest_hash": "a" * 64, "mapping_digest": "b" * 64, "source_snapshot_hash": "c" * 64,
        "stage": "repair_required", "capacity_rejected": True, "expires_at": "2026-09-06T00:00:00Z", "published_at": None,
        "payload_version": 1, "payload_json": "{}", "payload_hash": "d" * 64}
    prefix = insert("sync_import_lineages", lineage) + ";"
    case("PG-IMPORT-PUBLICATION-HISTORY-SET", prefix + "UPDATE sync_import_lineages SET ever_published=true", "00000", query="SELECT count(*) FROM sync_import_lineages WHERE ever_published", scalar=1)
    case("PG-IMPORT-PUBLICATION-HISTORY-REGRESSION", prefix + "UPDATE sync_import_lineages SET ever_published=true; UPDATE sync_import_lineages SET ever_published=false", "23514")
    case("PG-IMPORT-LINEAGE-PERMANENT", prefix + "DELETE FROM sync_import_lineages", "23514")
    case("PG-IMPORT-LINEAGE-ACCOUNT-DELETED", prefix + "DELETE FROM user_accounts WHERE id='" + A + "'", "00000", query="SELECT count(*) FROM sync_import_lineages", scalar=0)
    case("PG-IMPORT-OVER-CAP-TERMINAL-DECLARATION", prefix + insert("sync_import_batches", batch), "00000")
    case("PG-IMPORT-OVER-CAP-LIVE-RESERVATION", prefix + insert("sync_import_batches", {**batch, "capacity_rejected": False}), "23514")
    case("PG-IMPORT-OVER-CAP-CANNOT-PUBLISH", prefix + insert("sync_import_batches", {**batch, "stage": "server_confirmed"}), "23514")
    case("PG-IMPORT-STAGE-CLOSED-SET", prefix + insert("sync_import_batches", {**batch, "stage": "failed"}), "23514")
    mapping = {"account_id": A, "lineage_id": DEVICE, "source_workspace_id": B, "source_epoch": 0, "target_type": "category",
        "source_id": samples["category"]["target_id"], "target_id": samples["category"]["target_id"],
        "first_published_batch_id": None, "last_published_batch_id": None, "provenance_version": 0}
    mapping_seed = prefix + insert("sync_import_mappings", mapping) + ";"
    case("PG-IMPORT-UNPUBLISHED-MAPPING", mapping_seed + "SELECT 1", "00000")
    case("PG-IMPORT-MAPPING-IMMUTABLE", mapping_seed + "UPDATE sync_import_mappings SET target_id='another-target'", "23514")
    case("PG-IMPORT-MAPPING-RETAIN", mapping_seed + "DELETE FROM sync_import_mappings", "23514")
    case("PG-IMPORT-MAPPING-EPOCH-BINDING", prefix + insert("sync_import_mappings", {**mapping, "source_epoch": 1}), "23503")
    case("PG-IMPORT-MAPPING-TENANT-BINDING", prefix + insert("sync_import_mappings", {**mapping, "account_id": B}), "23503")
    case("PG-IMPORT-MAPPING-PUBLICATION-NULLS", prefix + insert("sync_import_mappings", {**mapping, "provenance_version": 1}), "23514")
    next_lineage = {**lineage, "lineage_id": B, "source_epoch": 1}
    next_seed = mapping_seed + insert("sync_import_lineages", next_lineage) + ";"
    next_mapping = {**mapping, "lineage_id": B, "source_epoch": 1}
    case("PG-IMPORT-NEXT-EPOCH-TARGET-COLLISION", next_seed + insert("sync_import_mappings", next_mapping), "23505")
    case("PG-IMPORT-NEXT-EPOCH-NEW-TARGET", next_seed + insert("sync_import_mappings", {**next_mapping, "target_id": B}), "00000")
    published_batch = {**batch, "terminal_client_sequence": 2, "total_item_count": 0, "capacity_rejected": False,
                       "stage": "server_confirmed", "published_at": NOW}
    published_seed = mapping_seed + insert("sync_import_batches", published_batch) + "; UPDATE sync_import_mappings SET " \
        "first_published_batch_id='" + DEVICE + "',last_published_batch_id='" + DEVICE + "',provenance_version=1;"
    case("PG-IMPORT-MAPPING-PUBLISH", published_seed + "SELECT 1", "00000")
    case("PG-IMPORT-MAPPING-FIRST-PUBLISH-IMMUTABLE", published_seed + "UPDATE sync_import_mappings SET first_published_batch_id='" + B + "',provenance_version=2", "23514")
    case("PG-IMPORT-MAPPING-PUBLICATION-REGRESSION", published_seed + "UPDATE sync_import_mappings SET provenance_version=0,first_published_batch_id=NULL,last_published_batch_id=NULL", "23514")
    family = {"account_id": A, "lineage_id": DEVICE, "source_recurrence_id": DEVICE, "target_recurrence_id": B}
    family_seed = prefix + insert("sync_import_recurrence_families", family) + ";"
    case("PG-IMPORT-FAMILY-IMMUTABLE", family_seed + "UPDATE sync_import_recurrence_families SET target_recurrence_id='" + DEVICE + "'", "23514")
    case("PG-IMPORT-FAMILY-RETAIN", family_seed + "DELETE FROM sync_import_recurrence_families", "23514")
    case("PG-IMPORT-ACCOUNT-DELETION-RELEASE", mapping_seed + "DELETE FROM user_accounts WHERE id='" + A + "'", "00000",
         query="SELECT count(*) FROM sync_import_mappings", scalar=0)
    operation = {"account_id": A, "operation_id": DEVICE, "habit_id": samples["habit"]["target_id"], "check_date": "2026-09-05",
        "entity_id": samples["habit_check_in"]["target_id"], "operation_type": "increment", "amount_hundredths": 100, "operation_hash": "0" * 64,
        "applied": False, "effect_group_id": None, "effect_group_last_server_sequence": None, "effect_entity_version": None}
    operation_seed = insert("sync_habit_check_in_operations", operation) + ";"
    applied_seed = operation_seed + "UPDATE sync_habit_check_in_operations SET applied=true,effect_group_id='" + DEVICE + "',effect_group_last_server_sequence=1,effect_entity_version=2;"
    case("PG-HABIT-OP-ZERO-DELTA", insert("sync_habit_check_in_operations", {**operation, "amount_hundredths": 0}), "23514")
    case("PG-HABIT-OP-NULL-DELTA", insert("sync_habit_check_in_operations", {**operation, "amount_hundredths": None}), "23514")
    case("PG-HABIT-OP-HASH-IMMUTABLE", operation_seed + "UPDATE sync_habit_check_in_operations SET operation_hash=repeat('1',64)", "23514")
    case("PG-HABIT-OP-ACCEPTED-NOOP", operation_seed + "UPDATE sync_habit_check_in_operations SET applied=true,effect_entity_version=0", "00000")
    case("PG-HABIT-OP-EFFECT-PAIR", operation_seed + "UPDATE sync_habit_check_in_operations SET applied=true,effect_group_id='" + DEVICE + "',effect_entity_version=2", "23514")
    case("PG-HABIT-OP-APPLY", applied_seed + "SELECT 1", "00000")
    case("PG-HABIT-OP-APPLIED-IMMUTABLE", applied_seed + "UPDATE sync_habit_check_in_operations SET effect_group_last_server_sequence=2", "23514")
    case("PG-HABIT-OP-RETAIN", operation_seed + "DELETE FROM sync_habit_check_in_operations", "23514")
    case("PG-HABIT-OP-ACCOUNT-SCOPE", operation_seed + insert("sync_habit_check_in_operations", {**operation, "account_id": B}), "00000", query="SELECT count(*) FROM sync_habit_check_in_operations", scalar=2)
    barrier = insert("sync_habit_completion_barriers", {"account_id": A, "entity_id": samples["habit_check_in"]["target_id"], "completion_version": 2}) + ";"
    case("PG-HABIT-BARRIER-REGRESSION", barrier + "UPDATE sync_habit_completion_barriers SET completion_version=1", "23514")
    case("PG-HABIT-BARRIER-RETAIN", barrier + "DELETE FROM sync_habit_completion_barriers", "23514")
    case("PG-HABIT-ACCOUNT-DELETE-CASCADE", operation_seed + barrier + "DELETE FROM user_accounts WHERE id='" + A + "'", "00000", query="SELECT count(*) FROM sync_habit_check_in_operations", scalar=0)
    case("PG-MAX-SAFE", "UPDATE sync_fact_habit SET target_count_hundredths=9007199254740991 WHERE account_id='" + A + "'", "00000")
    case("PG-OVER-MAX", "UPDATE sync_fact_habit SET target_count_hundredths=9007199254740992 WHERE account_id='" + A + "'", "23514")
    case("PG-NEGATIVE-REVISION", "UPDATE user_devices SET device_version=-1", "23514")
    case("PG-MAX-NEXT-NULL", "UPDATE sync_account_sequences SET highest_server_sequence=9007199254740991,next_server_sequence=NULL WHERE account_id='" + A + "'", "00000")
    case("PG-EARLY-NEXT-NULL", "UPDATE sync_account_sequences SET next_server_sequence=NULL WHERE account_id='" + A + "'", "23514")
    case("PG-ACK-AHEAD", insert("sync_device_state", {"account_id": A, "device_id": DEVICE, "sync_transport_generation": 0, "highest_client_sequence": 1, "client_confirmed_through": 2, "account_generation": 0}), "23514")
    usage = {"account_id": A, "key_id": DEVICE, "account_generation": 0, "maximum_snapshot_upper_bound": 0, "bootstrap_valid_through": None}
    seed.append(insert("sync_cursor_key_usage", usage))
    case("PG-CURSOR-KEY-RANGE-REGRESSION", "UPDATE sync_cursor_key_usage SET account_generation=1", "23514")
    case("PG-CURSOR-KEY-UNSAFE-RETIREMENT", "DELETE FROM sync_cursor_key_usage", "23514")
    case("PG-CURSOR-KEY-RANGE-ADVANCE", "UPDATE sync_cursor_key_usage SET maximum_snapshot_upper_bound=9007199254740991", "00000")
    case("PG-CURSOR-KEY-UPPER-REGRESSION", "UPDATE sync_cursor_key_usage SET maximum_snapshot_upper_bound=1; UPDATE sync_cursor_key_usage SET maximum_snapshot_upper_bound=0", "23514")
    case("PG-CURSOR-KEY-TTL-REGRESSION", "UPDATE sync_cursor_key_usage SET bootstrap_valid_through=transaction_timestamp()+interval '24 hours'; UPDATE sync_cursor_key_usage SET bootstrap_valid_through=NULL", "23514")
    advance_generation = "UPDATE sync_account_sequences SET account_generation=1 WHERE account_id='" + A + "';"
    case("PG-CURSOR-KEY-LIVE-BOOTSTRAP-RETAINS", "UPDATE sync_cursor_key_usage SET bootstrap_valid_through=transaction_timestamp()+interval '24 hours';" + advance_generation + "DELETE FROM sync_cursor_key_usage", "23514")
    case("PG-CURSOR-KEY-OLD-GENERATION-RETIREMENT", advance_generation + "DELETE FROM sync_cursor_key_usage", "00000", query="SELECT count(*) FROM sync_cursor_key_usage", scalar=0)
    case("PG-CURSOR-KEY-FLOOR-RETIREMENT", "UPDATE sync_account_sequences SET highest_server_sequence=1,next_server_sequence=2,retention_floor=1 WHERE account_id='" + A + "'; DELETE FROM sync_cursor_key_usage", "00000", query="SELECT count(*) FROM sync_cursor_key_usage", scalar=0)
    bootstrap = {"account_id": A, "bootstrap_id": DEVICE, "device_id": DEVICE, "cursor_key_id": DEVICE,
        "protocol_version": 1, "sync_transport_generation": 0, "account_generation": 0, "upper_bound": 0,
        "retention_floor_server_sequence": 0, "resolved_conflict_cleanup_before": NOW,
        "highest_client_sequence": 0, "client_confirmed_through": 0, "created_at": NOW,
        "expires_at": "2026-09-06T00:00:00Z", "total_item_count": 0, "snapshot_hash": "0" * 64, "total_page_count": 1, "page_item_limit": 500}
    case("PG-BOOTSTRAP-UNRECORDED-KEY-TTL", insert("sync_bootstrap_sessions", bootstrap), "23514")
    case("PG-BOOTSTRAP-RECORDED-KEY-TTL", "UPDATE sync_cursor_key_usage SET bootstrap_valid_through='2026-09-06T00:00:00Z';" + insert("sync_bootstrap_sessions", bootstrap), "00000")
    bootstrap_seed = "UPDATE sync_cursor_key_usage SET bootstrap_valid_through='2026-09-06T00:00:00Z';" + insert("sync_bootstrap_sessions", {**bootstrap, "total_item_count": 1}) + ";"
    case("PG-BOOTSTRAP-SNAPSHOT-IMMUTABLE", bootstrap_seed + "UPDATE sync_bootstrap_sessions SET snapshot_hash=repeat('1',64)", "23514")
    case("PG-BOOTSTRAP-SUPERSEDE", bootstrap_seed + "UPDATE sync_bootstrap_sessions SET superseded_at=transaction_timestamp()", "00000")
    bootstrap_item = {"account_id": A, "bootstrap_id": DEVICE, "ordinal": 0, "kind": "fact_after_image", "target_type": "category",
        "entity_id": samples["category"]["target_id"], "payload_version": 1, "payload_json": "{}", "payload_hash": "0" * 64}
    case("PG-BOOTSTRAP-ITEM-ORDINAL", bootstrap_seed + insert("sync_bootstrap_items", {**bootstrap_item, "ordinal": 1}), "23514")
    case("PG-BOOTSTRAP-ITEM-IMMUTABLE", bootstrap_seed + insert("sync_bootstrap_items", bootstrap_item) + "; UPDATE sync_bootstrap_items SET payload_hash=repeat('1',64)", "23514")
    copied = {"account_id": B, "entity_id": samples["habit"]["target_id"], "entity_version": 1, "last_server_sequence": 1, "is_tombstone": False, **samples["habit"]["fact"]}
    case("PG-CROSS-ACCOUNT-STRONG-REFERENCE", insert("sync_fact_habit", copied), "23503")
    case("PG-ANNIVERSARY-OPAQUE-WEAK-CATEGORY", "UPDATE sync_fact_anniversary SET category_id='   非 UUID / 😀   '", "00000")
    case("PG-CATEGORY-PHYSICAL-DELETE-WEAK-REFERENCE", "DELETE FROM sync_fact_category", "00000", query="SELECT count(*) FROM sync_fact_anniversary", scalar=1)
    case("PG-TIMED-END-NULL", "UPDATE sync_fact_event SET end_at=NULL WHERE NOT is_all_day", "23514")
    case("PG-HABIT-401-DAYS", "UPDATE sync_fact_habit SET end_date=start_date+400", "23514")
    case("PG-RECURRENCE-TUPLE-IMMUTABLE", "UPDATE sync_fact_event_recurrence SET \"interval\"=2", "23514")
    case("PG-RECURRENCE-LIFECYCLE-METADATA", "UPDATE sync_fact_anniversary_recurrence SET deleted_at='2026-09-06T00:00:00Z',entity_version=2", "00000")
    case("PG-DUPLICATE-ACTIVE-INSTALLATION", insert("user_devices", {**device, "device_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}), "23505")
    ten = [insert("user_devices", {**device, "device_id": f"{n:08x}-0000-4000-8000-000000000000", "installation_hash": f"{n:064x}"}) for n in range(1, 11)]
    case("PG-TENTH-DEVICE", ";".join(ten[:9]), "00000", query="SELECT count(*) FROM user_devices", scalar=10)
    case("PG-ELEVENTH-DEVICE", ";".join(ten), "23514")
    case("PG-REVOKED-ROW-NOT-REACTIVATED", "UPDATE user_devices SET revoked_at='2026-09-06T00:00:00Z',revocation_reason='user_requested'; UPDATE user_devices SET revoked_at=NULL,revocation_reason=NULL", "23514")
    case("PG-DEVICE-UNICODE-64", "UPDATE user_devices SET display_name=repeat('😀',64)", "00000")
    case("PG-DEVICE-UNICODE-65", "UPDATE user_devices SET display_name=repeat('😀',65)", "23514")
    event_intent = samples["reminder_intent_event"]["target_id"]
    case("PG-REMINDER-OWNER-TEMPLATE-MISMATCH", insert("sync_reminder_anniversary_templates", {"account_id": A, "intent_id": event_intent, "ordinal": 0,
        "advance_days": 0, "local_time": "09:00", "timezone_mode": "follow_device", "method": "popup", "is_enabled": True}), "23503")
    case("PG-RAW-LIVE-JSONB-ABSENT", "SELECT 1", "00000", query="SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name LIKE 'sync_fact_%' AND data_type='jsonb'", scalar=0)
    return {"fixture_version": 1, "scope": "isolated PostgreSQL logical schema only; not Backend use cases", "account_id": A,
        "expected_new_tables": len(schema["new_tables"]), "seed_sql": ";\n".join(seed) + ";", "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = derive()
    path = CONTRACTS / "fixtures/sync/v1/postgres_vectors.json"
    if args.check:
        assert json.loads(path.read_text(encoding="utf-8")) == expected
    else:
        path.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"postgres_fixed_cases": len(expected["cases"])}))
