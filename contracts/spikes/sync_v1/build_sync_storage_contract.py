"""Exact planned v6 additions. The released v4/v5 nodes are never regenerated."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from build_sync_domain_contracts import CONTRACTS, MAX, yaml

V5_HASH = "dcd92464591cae3f74b2454d4b80021298acab1874ac6f946b45c89d8fe5db79"


def counter(name, nullable=False, minimum=0):
    guard = f"typeof({name})='integer' AND {name} BETWEEN {minimum} AND {MAX}"
    if nullable:
        guard = f"{name} IS NULL OR ({guard})"
    return f"{name} INTEGER{' NOT NULL' if not nullable else ''} CHECK({guard})"


def enum(name, values, nullable=False):
    literals = ",".join("'" + v + "'" for v in values)
    return f"{name} TEXT{' NOT NULL' if not nullable else ''} CHECK({name} IN ({literals}))"


def hashed(name, nullable=False):
    return f"{name} TEXT{' NOT NULL' if not nullable else ''} CHECK(length({name})=64 AND {name} NOT GLOB '*[^0-9a-f]*')"


def js(name, nullable=False):
    return f"{name} TEXT{' NOT NULL' if not nullable else ''} CHECK(json_valid({name}){' OR '+name+' IS NULL' if nullable else ''})"


def text(name, nullable=False):
    return name + " TEXT" + ("" if nullable else " NOT NULL")


def boolean(name):
    return f"{name} INTEGER NOT NULL CHECK(typeof({name})='integer' AND {name} IN (0,1))"


def derive():
    tables, indexes, triggers, codecs = {}, {}, {}, {}
    targets = ["category", "event", "event_recurrence", "event_occurrence_state", "anniversary", "anniversary_recurrence",
        "habit", "habit_recurrence", "habit_check_in", "reminder_intent", "user_preferences", "account_profile"]
    target = enum("target_type", targets)

    def table(name, columns, constraints=(), codec=None, account=False, guest=False):
        tables[name] = "CREATE TABLE " + name + "(" + ",".join([*columns, *constraints]) + ") WITHOUT ROWID"
        if codec:
            codecs[name] = codec
        if account or guest:
            kind = "account" if account else "local"
            for verb in ("INSERT", "UPDATE"):
                key = f"guard_{name}_{verb.lower()}_workspace"
                triggers[key] = (f"CREATE TRIGGER {key} BEFORE {verb} ON {name} "
                    f"WHEN COALESCE((SELECT workspace_kind FROM workspace_metadata WHERE singleton=1),'')!='{kind}' "
                    "BEGIN SELECT RAISE(ABORT,'WORKSPACE_ACCOUNT_MISMATCH'); END")

    def index(name, table_name, columns, unique=False, where=None):
        indexes[name] = f"CREATE {'UNIQUE ' if unique else ''}INDEX {name} ON {table_name}({columns})" + (" WHERE " + where if where else "")

    identity = [target, text("target_id")]
    payload = [counter("payload_version", minimum=1), js("payload_json"), hashed("payload_hash")]
    singleton = "singleton INTEGER PRIMARY KEY CHECK(singleton=1)"
    batch_fk = "FOREIGN KEY(batch_id) REFERENCES sync_import_batches(batch_id) ON DELETE CASCADE"
    bootstrap_fk = "FOREIGN KEY(bootstrap_id) REFERENCES sync_bootstrap_sessions(bootstrap_id) ON DELETE CASCADE"

    table("workspace_metadata", [singleton, text("workspace_id"), enum("workspace_kind", ["local", "account"]), text("account_id", True),
        "schema_version INTEGER NOT NULL CHECK(schema_version=6)", enum("encryption_profile", ["guest_plaintext_v1", "account_sqlcipher_v1"]),
        text("created_at"), counter("current_import_source_epoch", True), counter("previous_epoch_cleanup_pending", True),
        "source_epoch_exhausted INTEGER CHECK(source_epoch_exhausted IS NULL OR (typeof(source_epoch_exhausted)='integer' AND source_epoch_exhausted IN (0,1)))",
        counter("native_state_revision")], ["UNIQUE(workspace_id)",
        "CHECK((workspace_kind='local' AND account_id IS NULL AND encryption_profile='guest_plaintext_v1' AND current_import_source_epoch IS NOT NULL AND source_epoch_exhausted IS NOT NULL) OR (workspace_kind='account' AND account_id IS NOT NULL AND encryption_profile='account_sqlcipher_v1' AND current_import_source_epoch IS NULL AND previous_epoch_cleanup_pending IS NULL AND source_epoch_exhausted IS NULL))",
        f"CHECK(source_epoch_exhausted IS NULL OR source_epoch_exhausted=0 OR current_import_source_epoch={MAX})",
        f"CHECK(previous_epoch_cleanup_pending IS NULL OR previous_epoch_cleanup_pending<current_import_source_epoch OR (source_epoch_exhausted=1 AND current_import_source_epoch={MAX} AND previous_epoch_cleanup_pending={MAX}))"])
    table("workspace_preferences", [singleton, "timezone TEXT NOT NULL CHECK(length(timezone)>=1)",
        enum("habit_progress_color", ["teal", "blue", "indigo", "green", "orange", "rose", "purple"]),
        js("default_reminder_methods_json"), boolean("auto_enable_reminders_on_other_devices"), counter("preferences_revision")],
        codec={"columns": {"default_reminder_methods_json": "sync/v1/user_preferences_fact.schema.json#/properties/default_reminder_methods"},
               "note": "Exactly the four portable fields; IANA validation is mandatory at the codec boundary. No locale, generic settings or first-day setting."})
    table("account_profile_cache", [singleton, counter("profile_revision"), counter("preferences_revision"), text("received_at"), text("server_updated_at"), *payload],
          codec={"columns": {"payload_json": "user/account_profile_snapshot.schema.json"}}, account=True)
    table("sync_state", [singleton, text("device_id"), counter("sync_transport_generation"), counter("next_client_sequence", True, 1),
        boolean("client_sequence_exhausted"), counter("highest_local_client_sequence"), counter("local_receipt_ack_through"), counter("server_accepted_ack_through"),
        boolean("ack_watermark_dirty"), text("cursor", True), counter("account_generation", True), counter("server_sequence", True),
        counter("receipt_cleanup_through"), counter("change_cleanup_through"), text("resolved_conflict_cleanup_before", True),
        boolean("sync_enabled"), counter("sync_policy_revision"),
        boolean("reenable_pull_required"), counter("next_notice_sequence", True, 1), counter("last_claimed_notice_sequence"),
        counter("unresolved_conflict_count"), counter("failed_local_change_count"), counter("backlog_count"),
        text("transport_terminal_code", True), hashed("transport_terminal_evidence_hash", True), js("transport_terminal_binding_json", True)],
        ["UNIQUE(device_id)", "CHECK(resolved_conflict_cleanup_before IS NULL OR account_generation IS NOT NULL)",
         "CHECK(resolved_conflict_cleanup_before IS NULL OR (typeof(resolved_conflict_cleanup_before)='text' AND length(resolved_conflict_cleanup_before)=20 AND resolved_conflict_cleanup_before GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'))",
         "CHECK(server_accepted_ack_through<=local_receipt_ack_through AND local_receipt_ack_through<=highest_local_client_sequence)",
         f"CHECK((client_sequence_exhausted=0 AND next_client_sequence IS NOT NULL AND next_client_sequence=highest_local_client_sequence+1) OR (client_sequence_exhausted=1 AND next_client_sequence IS NULL AND highest_local_client_sequence={MAX}))",
         "CHECK((transport_terminal_code IS NULL AND transport_terminal_evidence_hash IS NULL AND transport_terminal_binding_json IS NULL) OR (transport_terminal_code IS NOT NULL AND transport_terminal_evidence_hash IS NOT NULL AND transport_terminal_binding_json IS NOT NULL))"], account=True)
    table("sync_local_device_causal_anchors", [text("device_id"), *identity, text("merge_key"), counter("client_sequence", minimum=1), counter("resulting_field_version")],
          ["PRIMARY KEY(device_id,target_type,target_id,merge_key)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)"], account=True)
    table("sync_awaiting_change_groups", [text("change_group_id"), counter("last_server_sequence", minimum=1), *identity,
        text("mutation_id"), counter("client_sequence", minimum=1), hashed("receipt_hash"), text("created_at")],
          ["PRIMARY KEY(change_group_id,target_type,target_id)"], account=True)
    table("sync_policy_operation_receipts", [singleton, text("operation_id"), counter("expected_policy_revision"), counter("resulting_policy_revision"),
        boolean("sync_enabled"), hashed("request_hash"), hashed("result_hash")], ["UNIQUE(operation_id)", "CHECK(resulting_policy_revision=expected_policy_revision+1)"], account=True)
    table("sync_conflict_notice_queue", [text("device_id"), counter("notice_sequence", minimum=1), text("notice_id"), js("conflict_ids_json"), counter("account_generation"), counter("upper_bound")],
        ["PRIMARY KEY(device_id,notice_sequence)", "UNIQUE(notice_id)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)"], codec={"columns": {"conflict_ids_json": "nonempty_sorted_unique_uuid_array"}}, account=True)
    table("sync_conflict_notice_journal", [text("device_id"), counter("account_generation"), counter("upper_bound"), text("conflict_id"), boolean("was_unresolved_at_start"), boolean("seen_created"), boolean("seen_resolved")],
        ["PRIMARY KEY(device_id,account_generation,upper_bound,conflict_id)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)"], account=True)
    outbox_identity = [enum("target_type", [*targets, "workspace_import"]), text("target_id")]
    table("sync_outbox", [text("mutation_id"), text("device_id"), counter("client_sequence", minimum=1), *outbox_identity, text("operation_type"), counter("base_entity_version"),
        js("causal_predecessors_json"), *payload, enum("route", ["exchange", "conflict_resolution", "import_range"]),
        enum("state", ["pending", "prepared", "sent"]), counter("attempt_count"), text("prepared_request_id", True), text("created_at")],
        ["PRIMARY KEY(mutation_id)", "UNIQUE(device_id,client_sequence)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)",
         "CHECK((state='pending' AND prepared_request_id IS NULL) OR (state IN ('prepared','sent') AND prepared_request_id IS NOT NULL))",
         "CHECK(target_type!='workspace_import' OR (operation_type IN ('import_begin','import_commit') AND route='import_range'))",
         "CHECK((route='conflict_resolution' AND operation_type='resolve_conflict') OR (route='import_range' AND substr(operation_type,1,7)='import_') OR (route='exchange' AND operation_type!='resolve_conflict' AND substr(operation_type,1,7)!='import_'))"],
        codec={"columns": {"payload_json": "sync/sync_outbox_mutation.schema.json", "causal_predecessors_json": "sync/sync_mutation.schema.json#/oneOf/0/properties/causal_predecessors"}, "cross_checks": ["indexed columns equal mutation envelope", "JCS hash excludes only envelope created_at", "causal predecessor is earlier than client sequence", "workspace_import target_id equals import_batch_id; resolution uses its single-item route; all import messages share the device sequence"]}, account=True)
    triggers["guard_sync_outbox_immutable"] = ("CREATE TRIGGER guard_sync_outbox_immutable BEFORE UPDATE ON sync_outbox WHEN "
        "NEW.mutation_id!=OLD.mutation_id OR NEW.device_id!=OLD.device_id OR NEW.client_sequence!=OLD.client_sequence OR NEW.payload_hash!=OLD.payload_hash OR NEW.payload_json!=OLD.payload_json OR NEW.target_type!=OLD.target_type OR NEW.target_id!=OLD.target_id OR NEW.operation_type!=OLD.operation_type OR NEW.base_entity_version!=OLD.base_entity_version OR NEW.causal_predecessors_json!=OLD.causal_predecessors_json OR NEW.route!=OLD.route OR NEW.created_at!=OLD.created_at "
        "BEGIN SELECT RAISE(ABORT,'SYNC_SEQUENCE_REPLAY_MISMATCH'); END")
    table("sync_prepared_requests", [text("request_id"), text("device_id"), counter("sync_transport_generation"), text("runtime_instance_id"), text("run_intent"), *payload],
        ["PRIMARY KEY(request_id)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)"], codec={"columns": {"payload_json": "sync/native_prepared_exchange_request.schema.json"}}, account=True)
    table("sync_failed_local_changes", [text("failed_change_id"), text("mutation_id"), *identity, counter("failed_change_revision"), counter("base_entity_version"),
        js("merge_keys_json"), js("causal_predecessors_json"), js("local_candidate_json"), js("manual_draft_json", True), text("failure_code"), js("failure_context_json", True),
        text("superseding_mutation_id", True), enum("state", ["active", "superseded_pending"]), *payload], ["PRIMARY KEY(failed_change_id)", "UNIQUE(mutation_id)"],
        codec={"columns": {"payload_json": "sync/sync_failed_change_mutation.schema.json", "local_candidate_json": "target_specific_fact", "manual_draft_json": "target_specific_patch", "failure_context_json": "sync/sync_error_registry.yaml"}}, account=True)
    table("sync_entity_state", [*identity, counter("entity_version"), counter("last_server_sequence"), js("field_versions_json"), js("awaiting_server_adjudication_keys_json", True)],
        ["PRIMARY KEY(target_type,target_id)"], codec={"columns": {"field_versions_json": "target_registry_merge_key_safe_integer_map", "awaiting_server_adjudication_keys_json": "target_registry_unique_merge_keys"}}, account=True)
    table("sync_server_baselines", [*identity, counter("entity_version"), *payload], ["PRIMARY KEY(target_type,target_id)"],
        codec={"columns": {"payload_json": "sync/sync_fact_after_image.schema.json"}}, account=True)
    table("sync_deleted_entity_anchors", [*identity, counter("delete_entity_version", minimum=1), counter("delete_server_sequence", minimum=1),
        text("import_lineage_id", True), text("source_workspace_id", True), counter("source_epoch", True), text("source_target_type", True), text("source_id", True)],
        ["PRIMARY KEY(target_type,target_id)", "CHECK((import_lineage_id IS NULL AND source_workspace_id IS NULL AND source_epoch IS NULL AND source_target_type IS NULL AND source_id IS NULL) OR (import_lineage_id IS NOT NULL AND source_workspace_id IS NOT NULL AND source_epoch IS NOT NULL AND source_target_type IS NOT NULL AND source_id IS NOT NULL))"], account=True)
    table("sync_change_receipts", [counter("account_generation"), counter("server_sequence", minimum=1), hashed("payload_hash"), text("applied_at")],
        ["PRIMARY KEY(account_generation,server_sequence)"], account=True)
    table("sync_upload_receipts", [text("device_id"), counter("client_sequence", minimum=1), text("mutation_id"), *payload, text("received_at")],
        ["PRIMARY KEY(device_id,client_sequence)", "UNIQUE(mutation_id)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)"], codec={"columns": {"payload_json": "sync/sync_terminal_upload_result.schema.json"}}, account=True)
    table("sync_conflicts", [text("conflict_id"), *identity, counter("conflict_version", minimum=1), enum("status", ["unresolved", "resolving", "resolved"]),
        text("source_device_id"), text("received_at"), text("resolved_at", True), text("retain_until", True), *payload],
        ["PRIMARY KEY(conflict_id)", "CHECK((status='resolved' AND resolved_at IS NOT NULL AND retain_until IS NOT NULL) OR (status!='resolved' AND resolved_at IS NULL AND retain_until IS NULL))"],
        codec={"columns": {"payload_json": "sync/sync_conflict_detail.schema.json"}}, account=True)
    table("sync_import_batches", [text("batch_id"), text("lease_operation_id"), hashed("protected_owner_binding_digest"), hashed("outbox_mutation_digest"),
        text("lineage_id"), text("predecessor_batch_id", True), text("source_workspace_id"), counter("source_epoch"),
        hashed("source_snapshot_hash"), text("origin_device_id"), counter("sync_transport_generation"), counter("import_revision"),
        counter("begin_client_sequence", minimum=1), counter("terminal_client_sequence", minimum=1), js("per_target_counts_json"), counter("portable_preference_count"),
        counter("total_item_count"), counter("source_fact_count"), counter("total_canonical_bytes"), hashed("mapping_digest"), hashed("manifest_hash"),
        text("takeover_reason", True), text("range_close_proof_id", True),
        enum("stage", ["local_staging", "server_staging", "repair_required", "server_confirmed", "publish_applied", "cleanup_pending", "completed", "superseded", "abandoned"]),
        enum("reconciliation_state", ["not_required", "full_successor_required", "cleanup_recovery_required"]),
        enum("resume_disposition", ["none", "resume_upload", "resume_publish", "close_range_then_successor", "create_successor", "resume_cleanup", "terminal"]),
        enum("abandon_confirmation", ["not_requested", "pending", "confirmed", "unconfirmed", "not_applicable"]),
        text("server_expires_at", True), text("error_code", True), js("server_status_snapshot_json", True), *payload],
        ["PRIMARY KEY(batch_id)", "UNIQUE(lease_operation_id)", "CHECK(terminal_client_sequence=begin_client_sequence+total_item_count+1)",
         "CHECK(total_item_count<=50000 AND total_canonical_bytes<=134217728)",
         "CHECK(source_fact_count<=total_item_count-portable_preference_count)"],
        codec={"columns": {"payload_json": "sync/sync_import_manifest.schema.json", "server_status_snapshot_json": "sync/import_status_response.schema.json"},
            "state_registry": "workspace/native_import_status_response.schema.json"}, account=True)
    index("ux_sync_import_active_source", "sync_import_batches", "source_workspace_id,source_epoch", True,
          "stage IN ('local_staging','server_staging')")
    table("sync_import_items", [text("batch_id"), counter("ordinal"), *identity, text("mutation_id"), text("operation_type"), enum("status", ["pending", "staged", "terminal"]), *payload],
        ["PRIMARY KEY(batch_id,ordinal)", "UNIQUE(batch_id,target_type,target_id)", batch_fk], codec={"columns": {"payload_json": "sync/sync_mutation.schema.json"}}, account=True)
    table("sync_import_mappings", [text("lineage_id"), text("source_workspace_id"), counter("source_epoch"), text("source_target_type"), text("source_id"), *identity,
        text("first_published_batch_id", True), text("last_published_batch_id", True), counter("provenance_version")],
        ["PRIMARY KEY(lineage_id,source_workspace_id,source_epoch,source_target_type,source_id)", "UNIQUE(target_type,target_id)",
         "CHECK(source_target_type=target_type)",
         "CHECK(target_type NOT IN ('user_preferences','account_profile'))",
         "CHECK((provenance_version=0 AND first_published_batch_id IS NULL AND last_published_batch_id IS NULL) OR "
         "(provenance_version>0 AND first_published_batch_id IS NOT NULL AND last_published_batch_id IS NOT NULL))"], account=True)
    triggers["guard_import_mapping_identity"] = """CREATE TRIGGER guard_import_mapping_identity BEFORE UPDATE ON sync_import_mappings
        WHEN NEW.lineage_id IS NOT OLD.lineage_id OR NEW.source_workspace_id IS NOT OLD.source_workspace_id OR NEW.source_epoch IS NOT OLD.source_epoch
          OR NEW.source_target_type IS NOT OLD.source_target_type OR NEW.source_id IS NOT OLD.source_id OR NEW.target_type IS NOT OLD.target_type
          OR NEW.target_id IS NOT OLD.target_id OR NEW.provenance_version<OLD.provenance_version
          OR (OLD.first_published_batch_id IS NOT NULL AND NEW.first_published_batch_id IS NOT OLD.first_published_batch_id)
          OR (NEW.last_published_batch_id IS NOT OLD.last_published_batch_id AND NEW.provenance_version<=OLD.provenance_version)
        BEGIN SELECT RAISE(ABORT,'IMPORT_LINEAGE_MISMATCH'); END"""
    triggers["guard_import_mapping_retention"] = "CREATE TRIGGER guard_import_mapping_retention BEFORE DELETE ON sync_import_mappings BEGIN SELECT RAISE(ABORT,'IMPORT_LINEAGE_MISMATCH'); END"
    table("sync_import_recurrence_families", [text("lineage_id"), text("source_recurrence_id"), text("target_recurrence_id")],
        ["PRIMARY KEY(lineage_id,source_recurrence_id)", "UNIQUE(target_recurrence_id)"], account=True)
    for verb in ("UPDATE", "DELETE"):
        key = "guard_import_family_" + verb.lower()
        triggers[key] = f"CREATE TRIGGER {key} BEFORE {verb} ON sync_import_recurrence_families BEGIN SELECT RAISE(ABORT,'IMPORT_LINEAGE_MISMATCH'); END"
    table("sync_import_publish_staging", [text("publish_group_id"), text("batch_id"), counter("account_generation"), counter("begin_server_sequence", minimum=1),
        counter("total_chunk_count"), counter("total_item_count"), counter("received_chunk_count"), hashed("manifest_hash"), hashed("mapping_digest"), boolean("commit_received")],
        ["PRIMARY KEY(publish_group_id)", "CHECK(received_chunk_count<=total_chunk_count)"], account=True)
    table("sync_import_publish_chunks", [text("publish_group_id"), counter("chunk_ordinal"), counter("server_sequence", minimum=1), *payload],
        ["PRIMARY KEY(publish_group_id,chunk_ordinal)", "FOREIGN KEY(publish_group_id) REFERENCES sync_import_publish_staging(publish_group_id) ON DELETE CASCADE"],
        codec={"columns": {"payload_json": "sync/sync_import_publish_item.schema.json"}}, account=True)
    table("sync_import_publish_markers", [text("batch_id"), text("lineage_id"), text("publish_group_id"), counter("commit_server_sequence", minimum=1), *payload],
        ["PRIMARY KEY(batch_id)"], codec={"columns": {"payload_json": "sync/sync_import_publish_marker.schema.json"}}, account=True)
    table("sync_import_range_close_receipts", [text("proof_id"), text("batch_id"), counter("resulting_import_revision"), *payload],
        ["PRIMARY KEY(proof_id)"], codec={"columns": {"payload_json": "sync/import_range_close_proof.schema.json"}}, account=True)
    table("sync_transport_fence_receipts", [text("operation_id"), counter("expected_transport_generation"), counter("resulting_transport_generation"), *payload],
        ["PRIMARY KEY(operation_id)", "CHECK(resulting_transport_generation=expected_transport_generation+1)"], codec={"columns": {"payload_json": "sync/sync_device_fence_response.schema.json"}}, account=True)
    table("guest_import_cleanup_receipts", [text("source_workspace_id"), counter("source_epoch"), text("lineage_id"), text("through_published_batch_id"),
        counter("import_revision"), hashed("source_snapshot_hash"), hashed("mapping_digest"), text("cleaned_at"), hashed("receipt_hash"), enum("state", ["pending_confirmation", "completed", "account_deleted"])],
        ["PRIMARY KEY(source_workspace_id,source_epoch)"], guest=True)
    table("guest_import_execution_retirements", [text("source_workspace_id"), counter("source_epoch"), hashed("receipt_hash"), *payload],
        ["PRIMARY KEY(source_workspace_id,source_epoch)", "UNIQUE(receipt_hash)"],
        codec={"columns": {"payload_json": "workspace/import_affected_execution.schema.json"},
            "cross_checks": ["source workspace/epoch and receipt hash equal the durable cleanup receipt; private local execution identities never enter HTTP"]}, guest=True)
    table("sync_import_execution_cancellations", [text("import_batch_id"), text("source_workspace_id"), counter("source_epoch"), hashed("receipt_hash"), *payload],
        ["PRIMARY KEY(import_batch_id)", "UNIQUE(receipt_hash)"],
        codec={"columns": {"payload_json": "workspace/import_affected_execution.schema.json"},
            "cross_checks": ["copy only from authenticated local guest retirement transaction; binding and cleanup hash match this batch; status replays the same identities after restart"]}, account=True)
    table("guest_import_source_leases", [text("source_workspace_id"), counter("source_epoch"), text("lineage_id"), hashed("protected_owner_binding_digest"), hashed("source_snapshot_hash"),
        text("reserved_operation_id"), text("active_batch_id", True), hashed("active_manifest_hash", True),
        counter("begin_client_sequence", True, 1), counter("terminal_client_sequence", True, 1),
        enum("state", ["reserved", "active", "published_cleanup_pending"]), counter("lease_revision")], ["PRIMARY KEY(source_workspace_id)",
        "CHECK((state='reserved' AND active_batch_id IS NULL AND active_manifest_hash IS NULL AND begin_client_sequence IS NULL AND terminal_client_sequence IS NULL) OR (state!='reserved' AND active_batch_id IS NOT NULL AND active_manifest_hash IS NOT NULL AND begin_client_sequence IS NOT NULL AND terminal_client_sequence IS NOT NULL AND terminal_client_sequence>begin_client_sequence))"], guest=True)
    table("guest_import_source_lease_terminals", [hashed("release_receipt_hash"), text("source_workspace_id"), counter("source_epoch"), text("lineage_id"),
        hashed("protected_owner_binding_digest"), counter("expected_source_lease_revision"),
        enum("proof_kind", ["prepublish_abandon_range_terminal", "prepublish_abandon_crypto_destroyed", "cleanup_completed", "account_deleted"]),
        hashed("proof_receipt_hash")], ["PRIMARY KEY(release_receipt_hash)"], guest=True)
    table("guest_import_source_lease_replacements", [text("source_workspace_id"), text("operation_id"), counter("source_epoch"), *payload],
        ["PRIMARY KEY(source_workspace_id)", "UNIQUE(operation_id)",
         "FOREIGN KEY(source_workspace_id) REFERENCES guest_import_source_leases(source_workspace_id) DEFERRABLE INITIALLY DEFERRED"],
        codec={"columns": {"payload_json": "storage/guest_import_source_lease_backup.schema.json"},
               "hash": "SHA-256 JCS of the exact previous active lease", "retention": "until matching successor is active or old active lease is restored"}, guest=True)
    table("guest_import_audit_anchors", [*identity, text("reminder_id"), counter("source_epoch"), text("lineage_id"), enum("retired_reason", ["source_migrated"]), text("retired_at"),
        text("occurrence_key", True), text("template_key", True)], ["PRIMARY KEY(target_type,target_id,reminder_id)"], guest=True)
    table("habit_check_in_operations", [text("operation_id"), text("habit_id"), text("check_date"), enum("operation_type", ["increment", "decrement", "replace_total", "clear"]),
        counter("amount_hundredths", True, 1), hashed("operation_hash"), text("mutation_id"), enum("applied_state", ["pending", "accepted", "conflict", "rejected"]),
        text("effect_change_group_id", True), counter("effect_group_last_server_sequence", True, 1)],
        ["PRIMARY KEY(operation_id)", "UNIQUE(mutation_id)",
         "CHECK((operation_type IN ('increment','decrement') AND amount_hundredths IS NOT NULL) OR operation_type='replace_total' OR (operation_type='clear' AND amount_hundredths IS NULL))",
         "CHECK((effect_change_group_id IS NULL)=(effect_group_last_server_sequence IS NULL))",
         "CHECK(applied_state='accepted' OR effect_change_group_id IS NULL)"], account=True)
    triggers["guard_habit_operation_identity"] = """CREATE TRIGGER guard_habit_operation_identity BEFORE UPDATE ON habit_check_in_operations
        WHEN NEW.operation_id IS NOT OLD.operation_id OR NEW.habit_id IS NOT OLD.habit_id OR NEW.check_date IS NOT OLD.check_date
          OR NEW.operation_type IS NOT OLD.operation_type OR NEW.amount_hundredths IS NOT OLD.amount_hundredths OR NEW.operation_hash IS NOT OLD.operation_hash
          OR (OLD.applied_state='accepted' AND (NEW.applied_state IS NOT OLD.applied_state OR NEW.mutation_id IS NOT OLD.mutation_id
            OR NEW.effect_change_group_id IS NOT OLD.effect_change_group_id OR NEW.effect_group_last_server_sequence IS NOT OLD.effect_group_last_server_sequence))
        BEGIN SELECT RAISE(ABORT,'SYNC_HABIT_OPERATION_ID_REUSED'); END"""
    triggers["guard_habit_operation_retention"] = "CREATE TRIGGER guard_habit_operation_retention BEFORE DELETE ON habit_check_in_operations BEGIN SELECT RAISE(ABORT,'SYNC_HABIT_OPERATION_ID_REUSED'); END"
    table("sync_habit_check_in_aliases", [text("sync_entity_id"), text("local_alias_id"), text("habit_id"), text("check_date")],
        ["PRIMARY KEY(sync_entity_id)", "UNIQUE(local_alias_id)", "UNIQUE(habit_id,check_date)"], account=True)
    table("sync_bootstrap_sessions", [text("bootstrap_id"), text("device_id"), counter("sync_transport_generation"), counter("account_generation"), counter("upper_bound"), counter("highest_client_sequence"),
        counter("client_confirmed_through"), counter("next_client_sequence", True, 1), boolean("client_sequence_exhausted"), counter("next_page_ordinal"),
        counter("retention_floor_server_sequence"), text("resolved_conflict_cleanup_before"), counter("snapshot_item_count"), hashed("snapshot_items_hash"),
        counter("total_page_count", minimum=1), "page_item_limit INTEGER NOT NULL CHECK(page_item_limit BETWEEN 1 AND 500)",
        text("next_cursor", True), text("terminal_cursor", True), text("expires_at"), enum("state", ["staging", "ready_to_finalize"])],
        ["PRIMARY KEY(bootstrap_id)", "UNIQUE(device_id)", "FOREIGN KEY(device_id) REFERENCES sync_state(device_id)", "CHECK(client_confirmed_through<=highest_client_sequence)",
         "CHECK(retention_floor_server_sequence<=upper_bound)", "CHECK(next_page_ordinal<=total_page_count)"], account=True)
    table("sync_bootstrap_page_receipts", [text("bootstrap_id"), counter("page_ordinal"), hashed("page_hash"), text("request_cursor", True), text("next_cursor", True)],
        ["PRIMARY KEY(bootstrap_id,page_ordinal)", bootstrap_fk], account=True)
    table("sync_bootstrap_items", [text("bootstrap_id"), counter("item_ordinal"), enum("kind", ["fact_after_image", "tombstone", "deleted_entity_anchor", "unresolved_conflict", "import_publish_marker", "requesting_device_causal_anchor"]), *payload],
        ["PRIMARY KEY(bootstrap_id,item_ordinal)", bootstrap_fk], codec={"columns": {"payload_json": "sync/sync_bootstrap_item.schema.json"}}, account=True)
    for name, table_name, columns in [
        ("ix_sync_outbox_state_sequence", "sync_outbox", "device_id,state,client_sequence"),
        ("ix_sync_failed_entity", "sync_failed_local_changes", "target_type,target_id,state"),
        ("ix_sync_effect_gate_entity", "sync_awaiting_change_groups", "target_type,target_id"),
        ("ix_sync_conflict_status", "sync_conflicts", "status,received_at,conflict_id"),
        ("ix_sync_conflict_retention", "sync_conflicts", "status,retain_until"),
        ("ix_sync_import_lineage", "sync_import_batches", "lineage_id,import_revision"),
        ("ix_sync_import_items_identity", "sync_import_items", "target_type,target_id,batch_id"),
        ("ix_sync_mapping_target", "sync_import_mappings", "target_type,target_id"),
        ("ix_sync_upload_receipts_age", "sync_upload_receipts", "received_at,client_sequence"),
        ("ix_sync_bootstrap_expiry", "sync_bootstrap_sessions", "expires_at"),
        ("ix_guest_audit_reminder", "guest_import_audit_anchors", "reminder_id")]:
        index(name, table_name, columns)
    return {"format_name": "excellent_calendar_core_sqlite", "storage_format_version": 6, "implementation_status": "planned", "release_status": "planned",
        "source_contract": "calendar_core_v5", "source_v5_contract_sha256": V5_HASH,
        "rule_anchor": "cloud-sync-02/10", "sqlite": {"application_id": 0x4543414c, "user_version": 6, "journal_mode": "WAL", "synchronous": "FULL", "transaction_begin": "BEGIN IMMEDIATE", "foreign_keys": "enabled", "bundled_version": "3.53.4", "version_upgrade_forbidden": True},
        "inherited_v5_objects": {"tables": 20, "indexes": 24, "store_generations": 17, "rows": "preserve_record_key_position_payload_json_bytes", "node_hash": V5_HASH},
        "new_tables": tables, "new_indexes": indexes, "new_triggers": triggers, "payload_codecs": codecs,
        "required_tables": {"inherited_count": 20, "new_count": len(tables), "total_count": 20 + len(tables)},
        "required_indexes": {"inherited_count": 24, "new_count": len(indexes), "total_count": 24 + len(indexes)},
        "payload_codec_revisions": {
            "events": {"from": 3, "to": 4, "changed_field": "recurrence_revision", "nullable": True},
            "recurrence_versions": {"from": 3, "to": 4, "changed_field": "revision", "nullable": False},
            "event_occurrence_states": {"from": 3, "to": 4, "changed_field": "recurrence_revision", "nullable": False},
            "reminders": {"from": 4, "to": 5, "changed_field": "recurrence_revision", "nullable": True,
                "additional_semantic_delta": "cancelled audit accepts irreversible last_cancellation_reason=source_migrated"},
            "notifications": {"from": 4, "to": 5, "changed_field": "abandon_reason", "nullable": True,
                "additional_semantic_delta": "prepared attempt retires as abandoned/source_migrated; retains full audit identity and finalization timestamps"}},
        "inherited_audit_store_codecs": {name: {
            "ddl": f"CREATE TABLE {name}(record_key TEXT PRIMARY KEY,position INTEGER NOT NULL UNIQUE CHECK(position >= 0),payload_json TEXT NOT NULL CHECK(json_valid(payload_json))) WITHOUT ROWID",
            "schema": "storage/v6/reminder_record.schema.json" if module == "reminder" else "native_v3/business_compat/notification/notification_response.schema.json",
            "record_key_field": module + "_id", "existing_ddl": "unchanged frozen SQLite record store",
            "retirement": "update complete validated payload in place; preserve record_key, position and terminal audit bytes"}
            for name, module in (("reminders", "reminder"), ("notifications", "notification"))},
        "payload_codec_revision_rules": {"only_change": "checked recurrence int64 in 1..9007199254740991 and explicitly versioned source_migrated Reminder/Notification audit reasons",
            "all_other_fields": "preserve previous exact keys/null/enum/domain semantics", "migration_payload_rewrite": "forbidden",
            "existing_legal_v5_records": "remain valid byte-for-byte", "new_wide_v6_records": "validate with the v6 codec; must not be routed through or downcast into the frozen v5 int32 codec",
            "native_v2": "preserve old schemas and runtime; v5 runtime refuses user_version=6", "native_v3": "planned reader and writer must use the same exact safe integer across Event/Recurrence/OccurrenceState/Reminder and occurrence identity formatting"},
        "migration": {"source_version": 5, "target_version": 6, "input_gate": "complete_frozen_v5_checker_before_any_v6_write",
            "transaction": "BEGIN IMMEDIATE", "metadata_updates": {"storage_format_version": "6", "payload_codec_version.events": "4",
                "payload_codec_version.recurrence_versions": "4", "payload_codec_version.event_occurrence_states": "4", "payload_codec_version.reminders": "5", "payload_codec_version.notifications": "5"},
            "metadata_additions": {"sync_protocol_version": "1", "workspace_schema_version": "1"},
            "history": {"migration_id": "calendar_core_sqlite_v5_to_v6", "source_format": "excellent_calendar_core_sqlite", "source_version": 5, "target_version": 6},
            "steps": ["freeze writers and pass complete v5 checker", "begin immediate and recheck v5 identity", "create exact added objects", "insert workspace and portable preference seed", "for account require encrypted binding and authoritative device sequence/policy seed", "update exact metadata and append one history row", "set user_version=6", "full v6 schema metadata history relation and codec validation", "commit"],
            "rollback": "all added objects rows metadata history and user_version roll back together", "downgrade": "v2/v5 runtime rejects v6 before any write; no reverse migration"},
        "trusted_cleanup_watermarks": {"generation_column": "sync_state.account_generation", "utc_cutoff_column": "sync_state.resolved_conflict_cleanup_before",
            "codec": "UTC datetime exactly YYYY-MM-DDTHH:mm:ssZ; null before authenticated watermarks exist",
            "writers": ["sync.apply_download_batch", "sync.finalize_bootstrap"],
            "atomicity": "facts, conflicts, visible cursor, generation and UTC cutoff commit together",
            "acceptance": "same authenticated account generation; missing or regressing cutoff never permits cleanup; generation replacement clears prior watermarks before installing the authenticated bootstrap values",
            "maintenance": "read only durable sync_state cutoff after reopen; never derive a cutoff from wall clock or a transient HTTP page"},
        "validation": {"ddl": "exact normalized CREATE of all objects; reject unknown and same-name different definition", "quick_check": "required", "foreign_key_check": "required", "json": "json_valid is only a syntax guard; exact target codec + schema + identity/hash/merge registry checks required before write and on open", "inherited_payloads": "preserve old bytes; only declared recurrence-counter and source_migrated audit codec revisions plus audit-anchor relationship closure may change reader rules", "guest_outbox": "all account-only tables reject guest inserts/updates", "encryption": "account must be opened with SQLCipher key and workspace/account/device AAD verified outside SQL before queries"}}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = CONTRACTS / "storage/calendar_core_storage.yaml"
    text_value = path.read_text(encoding="utf-8")
    current = yaml.safe_load(text_value)
    expected = derive()
    if args.check:
        assert current.get("calendar_core_v6") == expected, "v6 definition differs from generator"
        assert current.get("planned_format_contract") == "calendar_core_v6"
        assert current["latest_declared_format_version"] == 6
    else:
        assert hashlib.sha256(json.dumps(current["calendar_core_v5"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest() == V5_HASH
        # Preserve all old bytes, including v4/v5 nodes and comments.
        if "\ncalendar_core_v6:\n" in text_value:
            text_value = text_value[:text_value.index("\ncalendar_core_v6:\n")]
        text_value = text_value.replace("latest_declared_format_version: 5", "latest_declared_format_version: 6")
        if "planned_format_contract:" not in text_value:
            text_value = text_value.replace("active_format_contract: calendar_core_v5\n", "active_format_contract: calendar_core_v5\nplanned_format_contract: calendar_core_v6\n")
        path.write_text(text_value.rstrip() + "\n\n" + yaml.safe_dump({"calendar_core_v6": expected}, allow_unicode=True, sort_keys=False, width=140), encoding="utf-8")
    print(json.dumps({"v6_new_tables": len(expected["new_tables"]), "v6_new_indexes": len(expected["new_indexes"]), "v6_new_triggers": len(expected["new_triggers"])}))


if __name__ == "__main__":
    main()
