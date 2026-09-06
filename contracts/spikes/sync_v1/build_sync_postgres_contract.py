"""Generate a planned, typed PostgreSQL model; no production migration is edited."""
from __future__ import annotations

import argparse
import json

from build_sync_domain_contracts import CONTRACTS, MAX, yaml


def literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + value.replace("'", "''") + "'"


def scalar_column(name, schema):
    types = schema.get("type")
    values = schema.get("enum", [schema["const"]] if "const" in schema else None)
    if types is None and values:
        types = "integer" if isinstance(values[0], int) else "string"
    types = [types] if isinstance(types, str) else types or []
    null = "null" in types or values is not None and None in values
    kind = next((t for t in types if t != "null"), "string")
    checks = []
    quoted = '"' + name + '"'
    if types == ["null"]:
        sql_type = "text"
        checks.append(quoted + " IS NULL")
    elif kind == "array":
        items = schema["items"]
        sql_type = "bigint[]" if items.get("type") == "integer" else "text[]"
        if "minItems" in schema:
            checks.append(f"cardinality({quoted})>={schema['minItems']}")
        if "maxItems" in schema:
            checks.append(f"cardinality({quoted})<={schema['maxItems']}")
        checks.append(f"array_position({quoted},NULL) IS NULL")
        if "enum" in items:
            checks.append(f"{quoted}<@ARRAY[{','.join(literal(v) for v in items['enum'])}]::{sql_type}")
        if items.get("type") == "integer":
            checks.append(f"{items.get('minimum',0)}<=ALL({quoted}) AND {items.get('maximum',MAX)}>=ALL({quoted})")
    elif kind == "integer":
        sql_type = "bigint"
        checks.append(f"{quoted} BETWEEN {schema.get('minimum',0)} AND {min(schema.get('maximum',MAX), MAX)}")
    elif kind == "boolean":
        sql_type = "boolean"
    elif kind == "string":
        sql_type = {"uuid": "uuid", "date": "date", "date-time": "timestamptz"}.get(schema.get("format"), "text")
        if sql_type == "text":
            if "minLength" in schema:
                checks.append(f"char_length({quoted})>={schema['minLength']}")
            if "maxLength" in schema:
                checks.append(f"char_length({quoted})<={schema['maxLength']}")
    else:
        raise ValueError("Object/union requires an explicit typed relation: " + name)
    if values:
        non_null = [v for v in values if v is not None]
        if non_null:
            checks.append(f"{quoted} IN ({','.join(literal(v) for v in non_null)})")
    return quoted + " " + sql_type + ("" if null else " NOT NULL") + (" CHECK(" + " AND ".join(checks) + ")" if checks else "")


def derive():
    registry = yaml.safe_load((CONTRACTS / "sync/sync_field_registry.yaml").read_text(encoding="utf-8"))
    tables, indexes, alterations, mappings = {}, {}, [], {}
    functions, triggers = {}, {}

    def safe(name, nullable=False, minimum=0):
        return f"{name} bigint{' NOT NULL' if not nullable else ''} CHECK({name} BETWEEN {minimum} AND {MAX})"

    def text(name, nullable=False):
        return name + " text" + ("" if nullable else " NOT NULL")

    def uid(name, nullable=False):
        return name + " uuid" + ("" if nullable else " NOT NULL")

    def time(name, nullable=False):
        return name + " timestamptz" + ("" if nullable else " NOT NULL")

    def hashed(name, nullable=False):
        return f"{name} text{' NOT NULL' if not nullable else ''} CHECK({name} ~ '^[0-9a-f]{{64}}$')"

    def choice(name, values, nullable=False):
        return text(name, nullable) + f" CHECK({name} IN ({','.join(literal(v) for v in values)}))"

    def snap():
        return ["payload_version integer NOT NULL CHECK(payload_version=1)", "payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object')", hashed("payload_hash")]

    def table(name, columns, constraints=()):
        tables[name] = "CREATE TABLE " + name + "(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE," + ",".join([*columns, *constraints]) + ")"

    def fk(table_name, columns, referenced, reference_columns):
        # Account participates in EVERY cross-tenant relationship.
        alterations.append(f"ALTER TABLE {table_name} ADD FOREIGN KEY(account_id,{columns}) REFERENCES {referenced}(account_id,{reference_columns}) DEFERRABLE INITIALLY DEFERRED")

    table("user_devices", [uid("device_id"), hashed("installation_hash"), text("display_name"), safe("device_version"), "protocol_version integer NOT NULL CHECK(protocol_version=1)",
        text("app_version"), "receive_reminders boolean NOT NULL", "sync_enabled boolean NOT NULL", safe("settings_revision"),
        time("created_at"), time("last_seen_at"), time("last_sync_at", True), time("revoked_at", True), text("revocation_reason", True)],
        ["PRIMARY KEY(account_id,device_id)", "UNIQUE(device_id)", "CHECK(char_length(btrim(display_name)) BETWEEN 1 AND 64)",
         "CHECK((revoked_at IS NULL AND revocation_reason IS NULL) OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))"])
    indexes["ux_active_device_installation"] = "CREATE UNIQUE INDEX ux_active_device_installation ON user_devices(account_id,installation_hash) WHERE revoked_at IS NULL"
    functions["guard_device_registration"] = """CREATE FUNCTION guard_device_registration() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'DEVICE_REVOKED' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' AND NEW.revoked_at IS NULL THEN
    PERFORM id FROM user_accounts WHERE id=NEW.account_id FOR UPDATE;
    IF (SELECT count(*) FROM user_devices WHERE account_id=NEW.account_id AND revoked_at IS NULL)>=10 THEN
      RAISE EXCEPTION 'DEVICE_LIMIT_REACHED' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END $$"""
    triggers["guard_device_registration"] = "CREATE TRIGGER guard_device_registration BEFORE INSERT OR UPDATE ON user_devices FOR EACH ROW EXECUTE FUNCTION guard_device_registration()"
    alterations += ["ALTER TABLE user_sessions ADD COLUMN device_id uuid", "ALTER TABLE user_sessions ADD COLUMN registration_state text NOT NULL DEFAULT 'unregistered' CHECK(registration_state IN ('unregistered','pending_registration','registered'))",
        "ALTER TABLE user_sessions ADD COLUMN attempted_installation_hash text CHECK(attempted_installation_hash ~ '^[0-9a-f]{64}$')",
        "ALTER TABLE user_sessions ADD CONSTRAINT ck_session_registration_binding CHECK((registration_state='registered' AND device_id IS NOT NULL AND attempted_installation_hash IS NOT NULL) OR (registration_state IN ('unregistered','pending_registration') AND device_id IS NULL))",
        "ALTER TABLE user_sessions ADD CONSTRAINT uq_session_account_id UNIQUE(user_id,id)",
        "ALTER TABLE user_sessions ADD FOREIGN KEY(user_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED",
        "ALTER TABLE user_sessions DROP CONSTRAINT ck_user_sessions_revocation_reason",
        "ALTER TABLE user_sessions ADD CONSTRAINT ck_user_sessions_revocation_reason CHECK(revocation_reason IN ('logout','logout_all','password_changed','password_reset','email_changed','refresh_token_reused','account_disabled','expired','device_revoked','account_deleted'))"]
    table("reauth_grants", [hashed("token_hash"), uid("session_id"), uid("actor_device_id", True), hashed("attempted_installation_hash"), uid("target_device_id"),
        choice("purpose", ["device_revoke"]), time("issued_at"), time("expires_at"), time("consumed_at", True)],
        ["PRIMARY KEY(account_id,token_hash)", "UNIQUE(token_hash)", "CHECK(expires_at=issued_at+interval '5 minutes')",
         "FOREIGN KEY(account_id,session_id) REFERENCES user_sessions(user_id,id) DEFERRABLE INITIALLY DEFERRED"])
    # Its referenced session composite key is added after CREATE; move that FK.
    tables["reauth_grants"] = tables["reauth_grants"].replace(",FOREIGN KEY(account_id,session_id) REFERENCES user_sessions(user_id,id) DEFERRABLE INITIALLY DEFERRED", "")
    alterations.append("ALTER TABLE reauth_grants ADD FOREIGN KEY(account_id,session_id) REFERENCES user_sessions(user_id,id) DEFERRABLE INITIALLY DEFERRED")
    fk("reauth_grants", "actor_device_id", "user_devices", "device_id")
    fk("reauth_grants", "target_device_id", "user_devices", "device_id")
    table("account_profile_revisions", [safe("profile_revision"), safe("preferences_revision"), time("updated_at")], ["PRIMARY KEY(account_id)"])
    alterations += ["ALTER TABLE user_preferences ADD COLUMN habit_progress_color text NOT NULL DEFAULT 'teal' CHECK(habit_progress_color IN ('teal','blue','indigo','green','orange','rose','purple'))",
        "ALTER TABLE user_preferences ADD COLUMN auto_enable_reminders_on_other_devices boolean NOT NULL DEFAULT false"]
    names = {}
    for target, config in registry["targets"].items():
        if target in {"user_preferences", "account_profile", "reminder_intent"}:
            continue
        definition = config["variants"]["default"]
        name = "sync_fact_" + target
        names[target] = name
        columns = [text("entity_id"), safe("entity_version", minimum=1), safe("last_server_sequence", minimum=1), "is_tombstone boolean NOT NULL", time("tombstone_expires_at", True),
            uid("import_lineage_id", True), uid("import_source_workspace_id", True), safe("import_source_epoch", True), text("import_source_id", True)]
        columns += [scalar_column(field, metadata["schema"]) for field, metadata in definition["fields"].items()]
        constraints = ["PRIMARY KEY(account_id,entity_id)",
            "CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL))",
            "CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL))"]
        if "id" in definition["fields"]:
            constraints.append("UNIQUE(account_id,id)")
        if target == "event_recurrence":
            constraints.append("UNIQUE(account_id,recurrence_id,revision)")
        if target == "anniversary_recurrence":
            constraints.append("UNIQUE(account_id,recurrence_id)")
        if target == "event":
            constraints += ["CHECK((is_all_day AND start_at IS NULL AND end_at IS NULL AND start_date IS NOT NULL AND end_date IS NOT NULL AND end_date>start_date) OR (NOT is_all_day AND start_at IS NOT NULL AND end_at IS NOT NULL AND end_at>start_at AND start_date IS NULL AND end_date IS NULL))",
                "CHECK((has_recurrence AND recurrence_id IS NOT NULL AND recurrence_revision IS NOT NULL) OR (NOT has_recurrence AND recurrence_id IS NULL AND recurrence_revision IS NULL))"]
        if target == "habit":
            constraints += ["UNIQUE(account_id,recurrence_id)", "CHECK(end_date>=start_date AND end_date-start_date<=399)",
                "CHECK((target_count_hundredths IS NULL AND unit IS NULL) OR (target_count_hundredths IS NOT NULL AND unit IS NOT NULL))"]
        if target == "anniversary":
            constraints.append("UNIQUE(account_id,recurrence_id)")
        if target == "habit_check_in":
            constraints += ["UNIQUE(account_id,habit_id,check_date)", "CHECK((target_count_snapshot_hundredths IS NULL AND unit_snapshot IS NULL) OR (target_count_snapshot_hundredths IS NOT NULL AND unit_snapshot IS NOT NULL))"]
        table(name, columns, constraints)
        if target in {"event_recurrence", "anniversary_recurrence", "habit_recurrence"}:
            frozen = [field for field in definition["fields"] if field not in {"deleted_at", "updated_at"}]
            before = ",".join('OLD."' + field + '"' for field in frozen)
            after = ",".join('NEW."' + field + '"' for field in frozen)
            function = "guard_immutable_" + target
            functions[function] = f"CREATE FUNCTION {function}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF ROW({before}) IS DISTINCT FROM ROW({after}) THEN RAISE EXCEPTION 'IMMUTABLE_RECURRENCE_REVISION' USING ERRCODE='23514'; END IF; RETURN NEW; END $$"
            triggers[function] = f"CREATE TRIGGER {function} BEFORE UPDATE ON {name} FOR EACH ROW EXECUTE FUNCTION {function}()"
        mappings[target] = {field: {"table": name, "column": field} for field in definition["fields"]}
        indexes["ix_" + name + "_change"] = f"CREATE INDEX ix_{name}_change ON {name}(account_id,last_server_sequence)"
    fk(names["event"], "recurrence_id,recurrence_revision", names["event_recurrence"], "recurrence_id,revision")
    fk(names["event_occurrence_state"], "event_id", names["event"], "id")
    fk(names["anniversary"], "recurrence_id", names["anniversary_recurrence"], "recurrence_id")
    fk(names["habit"], "recurrence_id", names["habit_recurrence"], "id")
    fk(names["habit_check_in"], "habit_id", names["habit"], "id")
    table("sync_fact_reminder_intent", [uid("entity_id"), choice("owner_type", ["event", "anniversary", "habit"]), uid("owner_id"), "is_enabled boolean NOT NULL", safe("entity_version", minimum=1), safe("last_server_sequence", minimum=1),
        "event_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='event' THEN owner_id END) STORED",
        "anniversary_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='anniversary' THEN owner_id END) STORED",
        "habit_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='habit' THEN owner_id END) STORED",
        "is_tombstone boolean NOT NULL", time("deleted_at", True), time("tombstone_expires_at", True), uid("import_lineage_id", True), uid("import_source_workspace_id", True), safe("import_source_epoch", True), text("import_source_id", True)],
        ["PRIMARY KEY(account_id,entity_id)", "UNIQUE(account_id,owner_type,owner_id)", "UNIQUE(account_id,entity_id,owner_type)"])
    for owner in ("event", "anniversary", "habit"):
        fk("sync_fact_reminder_intent", owner + "_owner_id", names[owner], "id")
    for owner, config in registry["targets"]["reminder_intent"]["variants"].items():
        field = "template" if owner == "habit" else "templates"
        nested = config["fields"][field]["schema"]
        item = nested if owner == "habit" else nested["items"]
        name = "sync_reminder_" + owner + "_templates"
        table(name, [uid("intent_id"), "owner_type text NOT NULL DEFAULT " + literal(owner) + " CHECK(owner_type=" + literal(owner) + ")", safe("ordinal"), *[scalar_column(n, s) for n, s in item["properties"].items()]],
            ["PRIMARY KEY(account_id,intent_id,ordinal)"] + (["CHECK(ordinal=0)"] if owner == "habit" else ["CHECK(ordinal<5)"] if owner == "anniversary" else []) +
            (["CHECK((remind_at IS NULL)<>(advance_minutes IS NULL))"] if owner == "event" else []))
        fk(name, "intent_id,owner_type", "sync_fact_reminder_intent", "entity_id,owner_type")
        mappings["reminder_intent/" + owner] = {n: {"table": name if n == field else "sync_fact_reminder_intent", "column": "typed_child_rows" if n == field else n} for n in config["fields"]}
    mappings["user_preferences"] = {n: {"table": "user_preferences", "column": n} for n in registry["targets"]["user_preferences"]["variants"]["default"]["fields"]}
    mappings["account_profile"] = {"email": {"table": "user_accounts", "column": "email"}, "username": {"table": "user_profiles", "column": "username"},
        "display_name": {"table": "user_profiles", "column": "display_name"}, "avatar": {"table": "user_profiles", "column": "avatar_asset_id", "join": "user_avatar_assets through account-qualified FK; safe avatar projection only"}}
    alterations += ["ALTER TABLE user_avatar_assets ADD CONSTRAINT uq_avatar_account_id UNIQUE(user_id,id)",
        "ALTER TABLE user_profiles ADD CONSTRAINT fk_profile_avatar_account FOREIGN KEY(user_id,avatar_asset_id) REFERENCES user_avatar_assets(user_id,id) DEFERRABLE INITIALLY DEFERRED"]
    table("sync_account_sequences", [safe("account_generation"), safe("highest_server_sequence"), safe("next_server_sequence", True, 1), safe("retention_floor")],
        ["PRIMARY KEY(account_id)", f"CHECK((highest_server_sequence={MAX} AND next_server_sequence IS NULL) OR (highest_server_sequence<{MAX} AND next_server_sequence IS NOT NULL AND next_server_sequence=highest_server_sequence+1))", "CHECK(retention_floor<=highest_server_sequence)"])
    table("sync_device_state", [uid("device_id"), safe("sync_transport_generation"), safe("highest_client_sequence"), safe("client_confirmed_through"), text("blocked_reason", True),
        hashed("last_cursor_hash", True), safe("account_generation"), time("last_sync_at", True)], ["PRIMARY KEY(account_id,device_id)", "CHECK(client_confirmed_through<=highest_client_sequence)"])
    fk("sync_device_state", "device_id", "user_devices", "device_id")
    table("sync_device_fence_receipts", [uid("device_id"), uid("operation_id"), safe("expected_transport_generation"), safe("resulting_transport_generation"), text("reason"), *snap()],
        ["PRIMARY KEY(account_id,device_id,operation_id)", "CHECK(resulting_transport_generation=expected_transport_generation+1)"])
    table("sync_device_causal_anchors", [uid("device_id"), text("target_type"), text("entity_id"), text("merge_key"), safe("client_sequence", minimum=1), safe("resulting_field_version")],
        ["PRIMARY KEY(account_id,device_id,target_type,entity_id,merge_key)"])
    table("sync_deleted_entity_anchors", [text("target_type"), text("entity_id"), safe("delete_entity_version", minimum=1), safe("delete_server_sequence", minimum=1),
        uid("import_lineage_id", True), uid("source_workspace_id", True), safe("source_epoch", True), text("source_id", True)], ["PRIMARY KEY(account_id,target_type,entity_id)"])
    table("sync_mutation_receipts", [uid("device_id"), safe("client_sequence", minimum=1), uid("mutation_id"), hashed("mutation_payload_hash"), text("route"),
        choice("status", ["accepted", "partially_merged", "conflict", "rejected", "staged"]), time("received_at"), time("retain_until"), *snap()],
        ["PRIMARY KEY(account_id,device_id,client_sequence)", "UNIQUE(account_id,mutation_id)", "CHECK(retain_until>=received_at+interval '180 days')"])
    for name in ("sync_device_fence_receipts", "sync_device_causal_anchors", "sync_mutation_receipts"):
        fk(name, "device_id", "user_devices", "device_id")
    table("sync_entity_field_versions", [text("target_type"), text("entity_id"), text("merge_key"), safe("entity_version")], ["PRIMARY KEY(account_id,target_type,entity_id,merge_key)"])
    table("sync_change_groups", [uid("group_id"), safe("account_generation"), safe("first_server_sequence", minimum=1), safe("last_server_sequence", minimum=1),
        choice("kind", ["ordinary", "import_publish"]), hashed("group_hash"), safe("canonical_bytes"), time("created_at")],
        ["PRIMARY KEY(account_id,group_id)", "UNIQUE(account_id,account_generation,first_server_sequence)", "CHECK(last_server_sequence>=first_server_sequence)"])
    table("sync_change_items", [uid("group_id"), safe("server_sequence", minimum=1), safe("ordinal"), *snap()], ["PRIMARY KEY(account_id,group_id,ordinal)"])
    fk("sync_change_items", "group_id", "sync_change_groups", "group_id")
    table("sync_habit_check_in_operations", [uid("operation_id"), uid("habit_id"), "check_date date NOT NULL", text("entity_id"),
        choice("operation_type", ["increment", "decrement", "replace_total", "clear"]), safe("amount_hundredths", True, 1),
        hashed("operation_hash"), "applied boolean NOT NULL DEFAULT false", uid("effect_group_id", True), safe("effect_group_last_server_sequence", True, 1), safe("effect_entity_version", True)],
        ["PRIMARY KEY(account_id,operation_id)",
         "CHECK((operation_type IN ('increment','decrement') AND amount_hundredths IS NOT NULL) OR operation_type='replace_total' OR (operation_type='clear' AND amount_hundredths IS NULL))",
         "CHECK((effect_group_id IS NULL)=(effect_group_last_server_sequence IS NULL))",
         "CHECK((NOT applied AND effect_group_id IS NULL AND effect_entity_version IS NULL) OR (applied AND effect_entity_version IS NOT NULL))"])
    table("sync_habit_completion_barriers", [text("entity_id"), safe("completion_version")], ["PRIMARY KEY(account_id,entity_id)"])
    # Both rows survive ordinary fact/receipt cleanup: a rejected operation can
    # refer to an absent Habit and a clear can retain only a deleted anchor.
    functions["guard_habit_operation"] = """CREATE FUNCTION guard_habit_operation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) THEN
      RAISE EXCEPTION 'operation identity retained until account deletion' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  END IF;
  IF (NEW.account_id,NEW.operation_id,NEW.habit_id,NEW.check_date,NEW.entity_id,NEW.operation_type,NEW.amount_hundredths,NEW.operation_hash)
      IS DISTINCT FROM (OLD.account_id,OLD.operation_id,OLD.habit_id,OLD.check_date,OLD.entity_id,OLD.operation_type,OLD.amount_hundredths,OLD.operation_hash)
      OR (OLD.applied AND (NEW.applied,NEW.effect_group_id,NEW.effect_group_last_server_sequence,NEW.effect_entity_version) IS DISTINCT FROM
                         (OLD.applied,OLD.effect_group_id,OLD.effect_group_last_server_sequence,OLD.effect_entity_version)) THEN
    RAISE EXCEPTION 'operation identity or applied effect immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$"""
    triggers["guard_habit_operation"] = "CREATE TRIGGER guard_habit_operation BEFORE UPDATE OR DELETE ON sync_habit_check_in_operations FOR EACH ROW EXECUTE FUNCTION guard_habit_operation()"
    functions["guard_habit_barrier"] = """CREATE FUNCTION guard_habit_barrier() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) THEN
      RAISE EXCEPTION 'completion barrier retained until account deletion' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  END IF;
  IF (NEW.account_id,NEW.entity_id) IS DISTINCT FROM (OLD.account_id,OLD.entity_id) OR NEW.completion_version<OLD.completion_version THEN
    RAISE EXCEPTION 'completion barrier cannot regress' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$"""
    triggers["guard_habit_barrier"] = "CREATE TRIGGER guard_habit_barrier BEFORE UPDATE OR DELETE ON sync_habit_completion_barriers FOR EACH ROW EXECUTE FUNCTION guard_habit_barrier()"
    table("sync_conflicts", [uid("conflict_id"), text("target_type"), text("entity_id"), safe("conflict_version", minimum=1), uid("source_device_id"),
        choice("status", ["unresolved", "resolved"]), time("received_at"), time("resolved_at", True), time("retain_until", True), *snap()],
        ["PRIMARY KEY(account_id,conflict_id)", "CHECK((status='unresolved' AND resolved_at IS NULL AND retain_until IS NULL) OR (status='resolved' AND resolved_at IS NOT NULL AND retain_until>=resolved_at+interval '30 days'))"])
    table("sync_conflict_tombstone_pins", [uid("conflict_id"), text("target_type"), text("entity_id")], ["PRIMARY KEY(account_id,conflict_id,target_type,entity_id)"])
    fk("sync_conflict_tombstone_pins", "conflict_id", "sync_conflicts", "conflict_id")
    table("sync_import_lineages", [uid("lineage_id"), uid("source_workspace_id"), safe("source_epoch"), uid("current_head_batch_id", True), safe("import_revision"),
        "ever_published boolean NOT NULL DEFAULT false",
        uid("cleanup_confirmed_through_batch_id", True), safe("cleanup_confirmed_through_revision")], ["PRIMARY KEY(account_id,lineage_id)", "UNIQUE(account_id,source_workspace_id,source_epoch)",
          "UNIQUE(account_id,lineage_id,source_workspace_id,source_epoch)", "CHECK(cleanup_confirmed_through_revision<=import_revision)"])
    functions["guard_import_publication_history"] = """CREATE FUNCTION guard_import_publication_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) THEN
      RAISE EXCEPTION 'import lineage retained until account deletion' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  END IF;
  IF (OLD.ever_published AND NOT NEW.ever_published) OR
     ROW(NEW.account_id,NEW.lineage_id,NEW.source_workspace_id,NEW.source_epoch) IS DISTINCT FROM
     ROW(OLD.account_id,OLD.lineage_id,OLD.source_workspace_id,OLD.source_epoch) THEN
    RAISE EXCEPTION 'immutable import lineage publication history' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$"""
    triggers["guard_import_publication_history"] = "CREATE TRIGGER guard_import_publication_history BEFORE UPDATE OR DELETE ON sync_import_lineages FOR EACH ROW EXECUTE FUNCTION guard_import_publication_history()"
    table("sync_import_mappings", [uid("lineage_id"), uid("source_workspace_id"), safe("source_epoch"),
        choice("target_type", ["category", "event", "event_recurrence", "event_occurrence_state", "anniversary", "anniversary_recurrence", "habit", "habit_recurrence", "habit_check_in", "reminder_intent"]),
        text("source_id"), text("target_id"), uid("first_published_batch_id", True), uid("last_published_batch_id", True), safe("provenance_version")],
        ["PRIMARY KEY(account_id,lineage_id,target_type,source_id)", "UNIQUE(account_id,target_type,target_id)",
         "CHECK((provenance_version=0 AND first_published_batch_id IS NULL AND last_published_batch_id IS NULL) OR "
         "(provenance_version>0 AND first_published_batch_id IS NOT NULL AND last_published_batch_id IS NOT NULL))"])
    fk("sync_import_mappings", "lineage_id,source_workspace_id,source_epoch", "sync_import_lineages", "lineage_id,source_workspace_id,source_epoch")
    table("sync_import_recurrence_families", [uid("lineage_id"), uid("source_recurrence_id"), uid("target_recurrence_id")],
        ["PRIMARY KEY(account_id,lineage_id,source_recurrence_id)", "UNIQUE(account_id,target_recurrence_id)"])
    fk("sync_import_recurrence_families", "lineage_id", "sync_import_lineages", "lineage_id")
    functions["guard_import_mapping"] = """CREATE FUNCTION guard_import_mapping() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) THEN
      RAISE EXCEPTION 'import assignment retained until account deletion' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_TABLE_NAME='sync_import_recurrence_families' THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION 'immutable recurrence family assignment' USING ERRCODE='23514';
    END IF;
  ELSE
    IF ROW(NEW.account_id,NEW.lineage_id,NEW.source_workspace_id,NEW.source_epoch,NEW.target_type,NEW.source_id,NEW.target_id)
       IS DISTINCT FROM ROW(OLD.account_id,OLD.lineage_id,OLD.source_workspace_id,OLD.source_epoch,OLD.target_type,OLD.source_id,OLD.target_id)
       OR NEW.provenance_version<OLD.provenance_version
       OR (OLD.first_published_batch_id IS NOT NULL AND NEW.first_published_batch_id IS DISTINCT FROM OLD.first_published_batch_id)
       OR (NEW.last_published_batch_id IS DISTINCT FROM OLD.last_published_batch_id AND NEW.provenance_version<=OLD.provenance_version) THEN
      RAISE EXCEPTION 'immutable import assignment or publication regression' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END $$"""
    for name in ("sync_import_mappings", "sync_import_recurrence_families"):
        triggers["guard_" + name] = "CREATE TRIGGER guard_" + name + " BEFORE UPDATE OR DELETE ON " + name + " FOR EACH ROW EXECUTE FUNCTION guard_import_mapping()"
    table("sync_import_batches", [uid("batch_id"), uid("lineage_id"), uid("predecessor_batch_id", True), uid("origin_device_id"), safe("origin_transport_generation"),
        safe("begin_client_sequence", minimum=1), safe("terminal_client_sequence", minimum=1), safe("total_item_count"), safe("total_canonical_bytes"),
        hashed("manifest_hash"), hashed("mapping_digest"), hashed("source_snapshot_hash"),
        choice("stage", ["server_staging", "repair_required", "server_confirmed", "completed", "superseded", "abandoned"]),
        "capacity_rejected boolean NOT NULL DEFAULT false", time("expires_at"), time("published_at", True), *snap()],
        ["PRIMARY KEY(account_id,batch_id)", "UNIQUE(account_id,lineage_id,batch_id)",
         "CHECK((NOT capacity_rejected AND total_item_count<=50000 AND total_canonical_bytes<=134217728) OR (capacity_rejected AND stage IN ('repair_required','superseded','abandoned') AND published_at IS NULL))",
         "CHECK(terminal_client_sequence=begin_client_sequence+total_item_count+1)"])
    fk("sync_import_batches", "lineage_id", "sync_import_lineages", "lineage_id")
    fk("sync_import_batches", "origin_device_id", "user_devices", "device_id")
    fk("sync_import_batches", "predecessor_batch_id", "sync_import_batches", "batch_id")
    for column in ("first_published_batch_id", "last_published_batch_id"):
        fk("sync_import_mappings", "lineage_id," + column, "sync_import_batches", "lineage_id,batch_id")
    table("sync_import_staging_items", [uid("batch_id"), safe("ordinal"), text("target_type"), text("entity_id"), choice("operation_type", ["import_put", "import_delete"]), *snap()],
        ["PRIMARY KEY(account_id,batch_id,ordinal)", "UNIQUE(account_id,batch_id,target_type,entity_id)"])
    table("sync_import_receipts", [uid("batch_id"), safe("ordinal"), uid("mutation_id"), safe("client_sequence", minimum=1), *snap()], ["PRIMARY KEY(account_id,batch_id,ordinal)"])
    for name in ("sync_import_staging_items", "sync_import_receipts"):
        fk(name, "batch_id", "sync_import_batches", "batch_id")
    table("sync_import_absent_batch_fences", [uid("batch_id"), uid("origin_device_id"), safe("origin_transport_generation"), hashed("manifest_hash"), safe("begin_client_sequence", minimum=1), safe("terminal_client_sequence", minimum=1),
        uid("resolved_fence_operation_id", True), *snap()], ["PRIMARY KEY(account_id,batch_id)"])
    table("sync_import_publish_markers", [uid("batch_id"), uid("lineage_id"), uid("publish_group_id"), safe("commit_server_sequence", minimum=1), hashed("manifest_hash"), hashed("mapping_digest"), *snap()], ["PRIMARY KEY(account_id,batch_id)"])
    table("sync_cursor_key_usage", [uid("key_id"), safe("account_generation"), safe("maximum_snapshot_upper_bound"), time("bootstrap_valid_through", True)],
        ["PRIMARY KEY(account_id,key_id,account_generation)"])
    functions["guard_cursor_key_usage"] = """CREATE FUNCTION guard_cursor_key_usage() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF ROW(NEW.account_id,NEW.key_id,NEW.account_generation) IS DISTINCT FROM ROW(OLD.account_id,OLD.key_id,OLD.account_generation)
       OR NEW.maximum_snapshot_upper_bound<OLD.maximum_snapshot_upper_bound
       OR (OLD.bootstrap_valid_through IS NOT NULL AND (NEW.bootstrap_valid_through IS NULL OR NEW.bootstrap_valid_through<OLD.bootstrap_valid_through)) THEN
      RAISE EXCEPTION 'cursor key usage regression' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
  END IF;
  IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) AND
     ((OLD.bootstrap_valid_through IS NOT NULL AND OLD.bootstrap_valid_through>transaction_timestamp()) OR
      NOT EXISTS(SELECT 1 FROM sync_account_sequences s WHERE s.account_id=OLD.account_id AND
        (s.account_generation>OLD.account_generation OR (s.account_generation=OLD.account_generation AND s.retention_floor>OLD.maximum_snapshot_upper_bound)))) THEN
    RAISE EXCEPTION 'cursor verification key still required' USING ERRCODE='23514';
  END IF;
  RETURN OLD;
END $$"""
    triggers["guard_cursor_key_usage"] = "CREATE TRIGGER guard_cursor_key_usage BEFORE UPDATE OR DELETE ON sync_cursor_key_usage FOR EACH ROW EXECUTE FUNCTION guard_cursor_key_usage()"
    table("sync_bootstrap_sessions", [uid("bootstrap_id"), uid("device_id"), uid("cursor_key_id"), "protocol_version integer NOT NULL CHECK(protocol_version=1)",
        safe("sync_transport_generation"), safe("account_generation"), safe("upper_bound"), safe("retention_floor_server_sequence"), time("resolved_conflict_cleanup_before"),
        safe("highest_client_sequence"), safe("client_confirmed_through"), time("created_at"), time("expires_at"), time("superseded_at", True), safe("total_item_count"), hashed("snapshot_hash"),
        safe("total_page_count", minimum=1), "page_item_limit integer NOT NULL CHECK(page_item_limit BETWEEN 1 AND 500)"],
        ["PRIMARY KEY(account_id,bootstrap_id)", "CHECK(client_confirmed_through<=highest_client_sequence)",
         "CHECK(retention_floor_server_sequence<=upper_bound)", "CHECK(expires_at=created_at+interval '24 hours')"])
    fk("sync_bootstrap_sessions", "device_id", "user_devices", "device_id")
    fk("sync_bootstrap_sessions", "cursor_key_id,account_generation", "sync_cursor_key_usage", "key_id,account_generation")
    functions["guard_bootstrap_key_usage"] = """CREATE FUNCTION guard_bootstrap_key_usage() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' AND
     (((to_jsonb(NEW)-'superseded_at') IS DISTINCT FROM (to_jsonb(OLD)-'superseded_at')) OR
      (OLD.superseded_at IS NOT NULL AND NEW.superseded_at IS DISTINCT FROM OLD.superseded_at)) THEN
    RAISE EXCEPTION 'bootstrap session identity immutable' USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM sync_cursor_key_usage u WHERE u.account_id=NEW.account_id AND u.key_id=NEW.cursor_key_id
      AND u.account_generation=NEW.account_generation AND u.maximum_snapshot_upper_bound>=NEW.upper_bound
      AND u.bootstrap_valid_through>=NEW.expires_at) THEN
    RAISE EXCEPTION 'bootstrap signing range not recorded' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$"""
    triggers["guard_bootstrap_key_usage"] = "CREATE TRIGGER guard_bootstrap_key_usage BEFORE INSERT OR UPDATE ON sync_bootstrap_sessions FOR EACH ROW EXECUTE FUNCTION guard_bootstrap_key_usage()"
    table("sync_bootstrap_items", [uid("bootstrap_id"), safe("ordinal"), choice("kind", ["fact_after_image", "tombstone", "deleted_entity_anchor", "unresolved_conflict", "import_publish_marker", "requesting_device_causal_anchor"]),
        text("target_type", True), text("entity_id", True), uid("conflict_id", True), text("merge_key", True), *snap()], ["PRIMARY KEY(account_id,bootstrap_id,ordinal)",
        "UNIQUE NULLS NOT DISTINCT(account_id,bootstrap_id,kind,target_type,entity_id,conflict_id,merge_key)"])
    fk("sync_bootstrap_items", "bootstrap_id", "sync_bootstrap_sessions", "bootstrap_id")
    functions["guard_bootstrap_item"] = """CREATE FUNCTION guard_bootstrap_item() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='UPDATE' THEN
    RAISE EXCEPTION 'materialized bootstrap item immutable' USING ERRCODE='23514';
  ELSIF TG_OP='INSERT' THEN
    IF NOT EXISTS(SELECT 1 FROM sync_bootstrap_sessions s WHERE s.account_id=NEW.account_id AND s.bootstrap_id=NEW.bootstrap_id
        AND NEW.ordinal<s.total_item_count AND s.superseded_at IS NULL) THEN
      RAISE EXCEPTION 'bootstrap item outside frozen snapshot' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
  ELSE
    IF EXISTS(SELECT 1 FROM user_accounts WHERE id=OLD.account_id) AND EXISTS(
        SELECT 1 FROM sync_bootstrap_sessions s WHERE s.account_id=OLD.account_id AND s.bootstrap_id=OLD.bootstrap_id
        AND s.superseded_at IS NULL AND s.expires_at>transaction_timestamp()) THEN
      RAISE EXCEPTION 'active bootstrap item cannot be removed' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  END IF;
END $$"""
    triggers["guard_bootstrap_item"] = "CREATE TRIGGER guard_bootstrap_item BEFORE INSERT OR UPDATE OR DELETE ON sync_bootstrap_items FOR EACH ROW EXECUTE FUNCTION guard_bootstrap_item()"
    for name, columns in (("sync_mutation_receipts", "device_id,retain_until,client_sequence"), ("sync_conflicts", "status,received_at,conflict_id"),
        ("sync_import_batches", "stage,expires_at"), ("sync_bootstrap_sessions", "device_id,expires_at"), ("sync_change_groups", "account_generation,last_server_sequence")):
        indexes["ix_" + name + "_scan"] = f"CREATE INDEX ix_{name}_scan ON {name}(account_id,{columns})"
    return {"model_version": 1, "protocol_version": 1, "release_status": "planned", "implementation_status": "planned", "rule_anchor": "cloud-sync-02/11",
        "postgresql_major": 17, "existing_migrations": ["V1__identity_schema.sql", "V2__email_change_requests.sql", "V3__avatar_assets.sql"],
        "new_tables": tables, "alterations": alterations, "new_indexes": indexes, "new_functions": functions, "new_triggers": triggers, "field_mappings": mappings,
        "transaction_rules": {"scope": "Principal account required in every query and account_id participates in every PK/FK; do not infer scope from client account id",
            "sequence": "lock account/device allocator rows; checked safe increment with facts/receipts/groups in the same transaction",
            "habit_operations": "sync/sync_habit_operation_protocol.yaml; permanent account-qualified operation digest and successful effect, independent of transport receipt TTL; adjudication+barrier+history guard+change+receipt atomic",
            "import_capacity": "lock account allocator; at most 2 unpublished batches, 100000 items and 268435456 bytes per account; per-batch SQL constraints additionally apply",
            "import_publication_history": "set sync_import_lineages.ever_published=true in the first publication transaction, including zero-item imports; never regress or garbage-collect the lineage until authoritative account deletion; signed range proofs read this value under the lineage lock",
            "reauth": "consume unexpired grant and revoke target device + all bound sessions atomically",
            "device_limit": "lock account then enforce at most 10 active devices; revoked rows never reactivate",
            "device_reminder_genesis": "first registered device receive_reminders=true; later devices read current portable auto_enable_reminders_on_other_devices, whose default is false; preference changes never modify existing devices",
            "strong_graph": "deferred account-qualified FKs plus target semantic/ownership checker before commit; Category references are intentionally weak and Anniversary opaque bytes are preserved",
            "immutable_recurrence": "INSERT-only revision tuple; a different payload at the same tuple is a graph conflict, never UPDATE",
            "payload_json": "only versioned, hashed, strict Schema-validated mutation/patch/result/snapshot journals; live facts are typed columns/child rows, not a generic JSONB entity",
            "legacy_preferences": "locale/settings remain legacy storage only; target writer owns exactly four portable columns; existing rows calibrated and legacy values not silently copied into new fields"}}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    model = derive()
    path = CONTRACTS / "storage/cloud_sync_postgresql_v1.yaml"
    sql_path = CONTRACTS / "storage/cloud_sync_postgresql_v1.sql"
    sql = "-- Planned Sync v1 Contract DDL; NOT an activated production migration.\n" + "\n\n".join(s + ";" for s in [*model["new_tables"].values(), *model["alterations"], *model["new_indexes"].values(), *model["new_functions"].values(), *model["new_triggers"].values()]) + "\n"
    if args.check:
        assert yaml.safe_load(path.read_text(encoding="utf-8")) == model
        assert sql_path.read_text(encoding="utf-8") == sql
    else:
        path.write_text(yaml.safe_dump(model, allow_unicode=True, sort_keys=False, width=140), encoding="utf-8")
        sql_path.write_text(sql, encoding="utf-8")
    print(json.dumps({"tables": len(model["new_tables"]), "alterations": len(model["alterations"]), "indexes": len(model["new_indexes"]), "mapped_fields": sum(map(len, model["field_mappings"].values()))}))


if __name__ == "__main__":
    main()
