-- Planned Sync v1 Contract DDL; NOT an activated production migration.
CREATE TABLE user_devices(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,device_id uuid NOT NULL,installation_hash text NOT NULL CHECK(installation_hash ~ '^[0-9a-f]{64}$'),display_name text NOT NULL,device_version bigint NOT NULL CHECK(device_version BETWEEN 0 AND 9007199254740991),protocol_version integer NOT NULL CHECK(protocol_version=1),app_version text NOT NULL,receive_reminders boolean NOT NULL,sync_enabled boolean NOT NULL,settings_revision bigint NOT NULL CHECK(settings_revision BETWEEN 0 AND 9007199254740991),created_at timestamptz NOT NULL,last_seen_at timestamptz NOT NULL,last_sync_at timestamptz,revoked_at timestamptz,revocation_reason text,PRIMARY KEY(account_id,device_id),UNIQUE(device_id),CHECK(char_length(btrim(display_name)) BETWEEN 1 AND 64),CHECK((revoked_at IS NULL AND revocation_reason IS NULL) OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL)));

CREATE TABLE reauth_grants(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,token_hash text NOT NULL CHECK(token_hash ~ '^[0-9a-f]{64}$'),session_id uuid NOT NULL,actor_device_id uuid,attempted_installation_hash text NOT NULL CHECK(attempted_installation_hash ~ '^[0-9a-f]{64}$'),target_device_id uuid NOT NULL,purpose text NOT NULL CHECK(purpose IN ('device_revoke')),issued_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,consumed_at timestamptz,PRIMARY KEY(account_id,token_hash),UNIQUE(token_hash),CHECK(expires_at=issued_at+interval '5 minutes'));

CREATE TABLE account_profile_revisions(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,profile_revision bigint NOT NULL CHECK(profile_revision BETWEEN 0 AND 9007199254740991),preferences_revision bigint NOT NULL CHECK(preferences_revision BETWEEN 0 AND 9007199254740991),updated_at timestamptz NOT NULL,PRIMARY KEY(account_id));

CREATE TABLE sync_fact_category(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"id" uuid NOT NULL,"name" text NOT NULL CHECK(char_length("name")>=1 AND char_length("name")<=40),"description" text CHECK(char_length("description")>=1 AND char_length("description")<=200),"color" text,"icon" text CHECK(char_length("icon")>=1 AND char_length("icon")<=64),"sort_order" bigint CHECK("sort_order" BETWEEN 0 AND 9007199254740991),"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,"reorder_revision" bigint NOT NULL CHECK("reorder_revision" BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,id));

CREATE TABLE sync_fact_event(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"id" uuid NOT NULL,"title" text NOT NULL CHECK(char_length("title")>=1),"content" text,"start_at" timestamptz,"end_at" timestamptz,"start_date" date,"end_date" date,"is_all_day" boolean NOT NULL,"has_recurrence" boolean NOT NULL,"status" text NOT NULL CHECK("status" IN ('active','completed','cancelled','archived')),"completed_at" timestamptz,"recurrence_id" uuid,"recurrence_revision" bigint CHECK("recurrence_revision" BETWEEN 1 AND 9007199254740991),"category_id" text,"importance" text CHECK("importance" IN ('unimportant_noturgent','important_noturgent','unimportant_urgent','important_urgent')),"location" text,"timezone" text NOT NULL CHECK(char_length("timezone")>=1),"source" text NOT NULL CHECK("source" IN ('manual','ai_extraction','sync','import','wechat')),"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,id),CHECK((is_all_day AND start_at IS NULL AND end_at IS NULL AND start_date IS NOT NULL AND end_date IS NOT NULL AND end_date>start_date) OR (NOT is_all_day AND start_at IS NOT NULL AND end_at IS NOT NULL AND end_at>start_at AND start_date IS NULL AND end_date IS NULL)),CHECK((has_recurrence AND recurrence_id IS NOT NULL AND recurrence_revision IS NOT NULL) OR (NOT has_recurrence AND recurrence_id IS NULL AND recurrence_revision IS NULL)));

CREATE TABLE sync_fact_event_recurrence(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"recurrence_id" uuid NOT NULL,"revision" bigint NOT NULL CHECK("revision" BETWEEN 1 AND 9007199254740991),"frequency" text NOT NULL CHECK("frequency" IN ('daily','weekly','monthly')),"interval" bigint NOT NULL CHECK("interval" BETWEEN 0 AND 9007199254740991 AND "interval" IN (1)),"start_at" timestamptz,"start_date" date,"timezone" text NOT NULL CHECK(char_length("timezone")>=1),"day_of_month" bigint CHECK("day_of_month" BETWEEN 1 AND 31),"days_of_week" bigint[] NOT NULL CHECK(cardinality("days_of_week")<=1 AND array_position("days_of_week",NULL) IS NULL AND 1<=ALL("days_of_week") AND 7>=ALL("days_of_week")),"month_of_year" text CHECK("month_of_year" IS NULL),"end_at" text CHECK("end_at" IS NULL),"count" text CHECK("count" IS NULL),"created_at" timestamptz NOT NULL,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,recurrence_id,revision));

CREATE TABLE sync_fact_event_occurrence_state(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"event_id" uuid NOT NULL,"recurrence_revision" bigint NOT NULL CHECK("recurrence_revision" BETWEEN 1 AND 9007199254740991),"occurrence_key" uuid NOT NULL,"occurrence_start_at" timestamptz,"occurrence_start_date" date,"status" text NOT NULL CHECK("status" IN ('scheduled','completed','skipped','cancelled')),"state_changed_at" timestamptz NOT NULL,"reopened_at" timestamptz,"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"original_local_start" text NOT NULL,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)));

CREATE TABLE sync_fact_anniversary(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"id" uuid NOT NULL,"title" text NOT NULL CHECK(char_length("title")>=1),"date" date NOT NULL,"calendar_type" text NOT NULL CHECK("calendar_type" IN ('solar')),"category_id" text,"recurrence_id" uuid,"note" text,"importance" text CHECK("importance" IN ('unimportant_noturgent','important_noturgent','unimportant_urgent','important_urgent')),"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,id),UNIQUE(account_id,recurrence_id));

CREATE TABLE sync_fact_anniversary_recurrence(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"recurrence_id" uuid NOT NULL,"frequency" text NOT NULL CHECK("frequency" IN ('yearly')),"interval" bigint NOT NULL CHECK("interval" BETWEEN 0 AND 9007199254740991 AND "interval" IN (1)),"created_at" timestamptz NOT NULL,"deleted_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,recurrence_id));

CREATE TABLE sync_fact_habit(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"id" uuid NOT NULL,"title" text NOT NULL CHECK(char_length("title")>=1 AND char_length("title")<=80),"description" text CHECK(char_length("description")<=2000),"category_id" text,"recurrence_id" uuid NOT NULL,"target_count_hundredths" bigint CHECK("target_count_hundredths" BETWEEN 1 AND 9007199254740991),"unit" text CHECK(char_length("unit")>=1 AND char_length("unit")<=32),"start_date" date NOT NULL,"end_date" date NOT NULL,"ended_date" date,"is_active" boolean NOT NULL,"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,"first_check_in_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,id),UNIQUE(account_id,recurrence_id),CHECK(end_date>=start_date AND end_date-start_date<=399),CHECK((target_count_hundredths IS NULL AND unit IS NULL) OR (target_count_hundredths IS NOT NULL AND unit IS NOT NULL)));

CREATE TABLE sync_fact_habit_recurrence(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"id" uuid NOT NULL,"frequency" text NOT NULL CHECK("frequency" IN ('daily')),"interval" bigint NOT NULL CHECK("interval" BETWEEN 0 AND 9007199254740991 AND "interval" IN (1)),"timezone_mode" text NOT NULL CHECK("timezone_mode" IN ('follow_device')),"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,id));

CREATE TABLE sync_fact_habit_check_in(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),is_tombstone boolean NOT NULL,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,"habit_id" uuid NOT NULL,"check_date" date NOT NULL,"status" text NOT NULL CHECK("status" IN ('done','partial','skipped')),"completed_count_hundredths" bigint CHECK("completed_count_hundredths" BETWEEN 1 AND 9007199254740991),"target_count_snapshot_hundredths" bigint CHECK("target_count_snapshot_hundredths" BETWEEN 1 AND 9007199254740991),"unit_snapshot" text CHECK(char_length("unit_snapshot")>=1 AND char_length("unit_snapshot")<=32),"completed_at" timestamptz,"note" text CHECK(char_length("note")<=500),"source" text NOT NULL CHECK("source" IN ('manual','notification_action')),"created_at" timestamptz NOT NULL,"updated_at" timestamptz NOT NULL,"deleted_at" timestamptz,PRIMARY KEY(account_id,entity_id),CHECK((is_tombstone AND tombstone_expires_at IS NOT NULL) OR (NOT is_tombstone AND tombstone_expires_at IS NULL)),CHECK((import_lineage_id IS NULL AND import_source_workspace_id IS NULL AND import_source_epoch IS NULL AND import_source_id IS NULL) OR (import_lineage_id IS NOT NULL AND import_source_workspace_id IS NOT NULL AND import_source_epoch IS NOT NULL AND import_source_id IS NOT NULL)),UNIQUE(account_id,habit_id,check_date),CHECK((target_count_snapshot_hundredths IS NULL AND unit_snapshot IS NULL) OR (target_count_snapshot_hundredths IS NOT NULL AND unit_snapshot IS NOT NULL)));

CREATE TABLE sync_fact_reminder_intent(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id uuid NOT NULL,owner_type text NOT NULL CHECK(owner_type IN ('event','anniversary','habit')),owner_id uuid NOT NULL,is_enabled boolean NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),event_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='event' THEN owner_id END) STORED,anniversary_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='anniversary' THEN owner_id END) STORED,habit_owner_id uuid GENERATED ALWAYS AS (CASE WHEN owner_type='habit' THEN owner_id END) STORED,is_tombstone boolean NOT NULL,deleted_at timestamptz,tombstone_expires_at timestamptz,import_lineage_id uuid,import_source_workspace_id uuid,import_source_epoch bigint CHECK(import_source_epoch BETWEEN 0 AND 9007199254740991),import_source_id text,PRIMARY KEY(account_id,entity_id),UNIQUE(account_id,owner_type,owner_id),UNIQUE(account_id,entity_id,owner_type));

CREATE TABLE sync_reminder_event_templates(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,intent_id uuid NOT NULL,owner_type text NOT NULL DEFAULT 'event' CHECK(owner_type='event'),ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),"remind_at" timestamptz,"advance_minutes" bigint CHECK("advance_minutes" BETWEEN 0 AND 2147483647),"method" text NOT NULL CHECK("method" IN ('ring','popup')),"message" text,"is_enabled" boolean NOT NULL,"source" text NOT NULL CHECK("source" IN ('manual','auto','ai_extraction','sync','import','wechat')),PRIMARY KEY(account_id,intent_id,ordinal),CHECK((remind_at IS NULL)<>(advance_minutes IS NULL)));

CREATE TABLE sync_reminder_anniversary_templates(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,intent_id uuid NOT NULL,owner_type text NOT NULL DEFAULT 'anniversary' CHECK(owner_type='anniversary'),ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),"advance_days" bigint NOT NULL CHECK("advance_days" BETWEEN 0 AND 365),"local_time" text NOT NULL,"timezone_mode" text NOT NULL CHECK("timezone_mode" IN ('follow_device')),"method" text NOT NULL CHECK("method" IN ('popup')),"is_enabled" boolean NOT NULL,PRIMARY KEY(account_id,intent_id,ordinal),CHECK(ordinal<5));

CREATE TABLE sync_reminder_habit_templates(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,intent_id uuid NOT NULL,owner_type text NOT NULL DEFAULT 'habit' CHECK(owner_type='habit'),ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),"local_time" text NOT NULL,"timezone_mode" text NOT NULL CHECK("timezone_mode" IN ('follow_device')),"method" text NOT NULL CHECK("method" IN ('popup')),PRIMARY KEY(account_id,intent_id,ordinal),CHECK(ordinal=0));

CREATE TABLE sync_account_sequences(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,account_generation bigint NOT NULL CHECK(account_generation BETWEEN 0 AND 9007199254740991),highest_server_sequence bigint NOT NULL CHECK(highest_server_sequence BETWEEN 0 AND 9007199254740991),next_server_sequence bigint CHECK(next_server_sequence BETWEEN 1 AND 9007199254740991),retention_floor bigint NOT NULL CHECK(retention_floor BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id),CHECK((highest_server_sequence=9007199254740991 AND next_server_sequence IS NULL) OR (highest_server_sequence<9007199254740991 AND next_server_sequence IS NOT NULL AND next_server_sequence=highest_server_sequence+1)),CHECK(retention_floor<=highest_server_sequence));

CREATE TABLE sync_device_state(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,device_id uuid NOT NULL,sync_transport_generation bigint NOT NULL CHECK(sync_transport_generation BETWEEN 0 AND 9007199254740991),highest_client_sequence bigint NOT NULL CHECK(highest_client_sequence BETWEEN 0 AND 9007199254740991),client_confirmed_through bigint NOT NULL CHECK(client_confirmed_through BETWEEN 0 AND 9007199254740991),blocked_reason text,last_cursor_hash text CHECK(last_cursor_hash ~ '^[0-9a-f]{64}$'),account_generation bigint NOT NULL CHECK(account_generation BETWEEN 0 AND 9007199254740991),last_sync_at timestamptz,PRIMARY KEY(account_id,device_id),CHECK(client_confirmed_through<=highest_client_sequence));

CREATE TABLE sync_device_fence_receipts(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,device_id uuid NOT NULL,operation_id uuid NOT NULL,expected_transport_generation bigint NOT NULL CHECK(expected_transport_generation BETWEEN 0 AND 9007199254740991),resulting_transport_generation bigint NOT NULL CHECK(resulting_transport_generation BETWEEN 0 AND 9007199254740991),reason text NOT NULL,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,device_id,operation_id),CHECK(resulting_transport_generation=expected_transport_generation+1));

CREATE TABLE sync_device_causal_anchors(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,device_id uuid NOT NULL,target_type text NOT NULL,entity_id text NOT NULL,merge_key text NOT NULL,client_sequence bigint NOT NULL CHECK(client_sequence BETWEEN 1 AND 9007199254740991),resulting_field_version bigint NOT NULL CHECK(resulting_field_version BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,device_id,target_type,entity_id,merge_key));

CREATE TABLE sync_deleted_entity_anchors(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,target_type text NOT NULL,entity_id text NOT NULL,delete_entity_version bigint NOT NULL CHECK(delete_entity_version BETWEEN 1 AND 9007199254740991),delete_server_sequence bigint NOT NULL CHECK(delete_server_sequence BETWEEN 1 AND 9007199254740991),import_lineage_id uuid,source_workspace_id uuid,source_epoch bigint CHECK(source_epoch BETWEEN 0 AND 9007199254740991),source_id text,PRIMARY KEY(account_id,target_type,entity_id));

CREATE TABLE sync_mutation_receipts(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,device_id uuid NOT NULL,client_sequence bigint NOT NULL CHECK(client_sequence BETWEEN 1 AND 9007199254740991),mutation_id uuid NOT NULL,mutation_payload_hash text NOT NULL CHECK(mutation_payload_hash ~ '^[0-9a-f]{64}$'),route text NOT NULL,status text NOT NULL CHECK(status IN ('accepted','partially_merged','conflict','rejected','staged')),received_at timestamptz NOT NULL,retain_until timestamptz NOT NULL,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,device_id,client_sequence),UNIQUE(account_id,mutation_id),CHECK(retain_until>=received_at+interval '180 days'));

CREATE TABLE sync_entity_field_versions(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,target_type text NOT NULL,entity_id text NOT NULL,merge_key text NOT NULL,entity_version bigint NOT NULL CHECK(entity_version BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,target_type,entity_id,merge_key));

CREATE TABLE sync_change_groups(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,group_id uuid NOT NULL,account_generation bigint NOT NULL CHECK(account_generation BETWEEN 0 AND 9007199254740991),first_server_sequence bigint NOT NULL CHECK(first_server_sequence BETWEEN 1 AND 9007199254740991),last_server_sequence bigint NOT NULL CHECK(last_server_sequence BETWEEN 1 AND 9007199254740991),kind text NOT NULL CHECK(kind IN ('ordinary','import_publish')),group_hash text NOT NULL CHECK(group_hash ~ '^[0-9a-f]{64}$'),canonical_bytes bigint NOT NULL CHECK(canonical_bytes BETWEEN 0 AND 9007199254740991),created_at timestamptz NOT NULL,PRIMARY KEY(account_id,group_id),UNIQUE(account_id,account_generation,first_server_sequence),CHECK(last_server_sequence>=first_server_sequence));

CREATE TABLE sync_change_items(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,group_id uuid NOT NULL,server_sequence bigint NOT NULL CHECK(server_sequence BETWEEN 1 AND 9007199254740991),ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,group_id,ordinal));

CREATE TABLE sync_habit_check_in_operations(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,operation_id uuid NOT NULL,habit_id uuid NOT NULL,check_date date NOT NULL,entity_id text NOT NULL,operation_type text NOT NULL CHECK(operation_type IN ('increment','decrement','replace_total','clear')),amount_hundredths bigint CHECK(amount_hundredths BETWEEN 1 AND 9007199254740991),operation_hash text NOT NULL CHECK(operation_hash ~ '^[0-9a-f]{64}$'),applied boolean NOT NULL DEFAULT false,effect_group_id uuid,effect_group_last_server_sequence bigint CHECK(effect_group_last_server_sequence BETWEEN 1 AND 9007199254740991),effect_entity_version bigint CHECK(effect_entity_version BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,operation_id),CHECK((operation_type IN ('increment','decrement') AND amount_hundredths IS NOT NULL) OR operation_type='replace_total' OR (operation_type='clear' AND amount_hundredths IS NULL)),CHECK((effect_group_id IS NULL)=(effect_group_last_server_sequence IS NULL)),CHECK((NOT applied AND effect_group_id IS NULL AND effect_entity_version IS NULL) OR (applied AND effect_entity_version IS NOT NULL)));

CREATE TABLE sync_habit_completion_barriers(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,entity_id text NOT NULL,completion_version bigint NOT NULL CHECK(completion_version BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,entity_id));

CREATE TABLE sync_conflicts(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,conflict_id uuid NOT NULL,target_type text NOT NULL,entity_id text NOT NULL,conflict_version bigint NOT NULL CHECK(conflict_version BETWEEN 1 AND 9007199254740991),source_device_id uuid NOT NULL,status text NOT NULL CHECK(status IN ('unresolved','resolved')),received_at timestamptz NOT NULL,resolved_at timestamptz,retain_until timestamptz,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,conflict_id),CHECK((status='unresolved' AND resolved_at IS NULL AND retain_until IS NULL) OR (status='resolved' AND resolved_at IS NOT NULL AND retain_until>=resolved_at+interval '30 days')));

CREATE TABLE sync_conflict_tombstone_pins(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,conflict_id uuid NOT NULL,target_type text NOT NULL,entity_id text NOT NULL,PRIMARY KEY(account_id,conflict_id,target_type,entity_id));

CREATE TABLE sync_import_lineages(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,lineage_id uuid NOT NULL,source_workspace_id uuid NOT NULL,source_epoch bigint NOT NULL CHECK(source_epoch BETWEEN 0 AND 9007199254740991),current_head_batch_id uuid,import_revision bigint NOT NULL CHECK(import_revision BETWEEN 0 AND 9007199254740991),ever_published boolean NOT NULL DEFAULT false,cleanup_confirmed_through_batch_id uuid,cleanup_confirmed_through_revision bigint NOT NULL CHECK(cleanup_confirmed_through_revision BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,lineage_id),UNIQUE(account_id,source_workspace_id,source_epoch),UNIQUE(account_id,lineage_id,source_workspace_id,source_epoch),CHECK(cleanup_confirmed_through_revision<=import_revision));

CREATE TABLE sync_import_mappings(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,lineage_id uuid NOT NULL,source_workspace_id uuid NOT NULL,source_epoch bigint NOT NULL CHECK(source_epoch BETWEEN 0 AND 9007199254740991),target_type text NOT NULL CHECK(target_type IN ('category','event','event_recurrence','event_occurrence_state','anniversary','anniversary_recurrence','habit','habit_recurrence','habit_check_in','reminder_intent')),source_id text NOT NULL,target_id text NOT NULL,first_published_batch_id uuid,last_published_batch_id uuid,provenance_version bigint NOT NULL CHECK(provenance_version BETWEEN 0 AND 9007199254740991),PRIMARY KEY(account_id,lineage_id,target_type,source_id),UNIQUE(account_id,target_type,target_id),CHECK((provenance_version=0 AND first_published_batch_id IS NULL AND last_published_batch_id IS NULL) OR (provenance_version>0 AND first_published_batch_id IS NOT NULL AND last_published_batch_id IS NOT NULL)));

CREATE TABLE sync_import_recurrence_families(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,lineage_id uuid NOT NULL,source_recurrence_id uuid NOT NULL,target_recurrence_id uuid NOT NULL,PRIMARY KEY(account_id,lineage_id,source_recurrence_id),UNIQUE(account_id,target_recurrence_id));

CREATE TABLE sync_import_batches(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,batch_id uuid NOT NULL,lineage_id uuid NOT NULL,predecessor_batch_id uuid,origin_device_id uuid NOT NULL,origin_transport_generation bigint NOT NULL CHECK(origin_transport_generation BETWEEN 0 AND 9007199254740991),begin_client_sequence bigint NOT NULL CHECK(begin_client_sequence BETWEEN 1 AND 9007199254740991),terminal_client_sequence bigint NOT NULL CHECK(terminal_client_sequence BETWEEN 1 AND 9007199254740991),total_item_count bigint NOT NULL CHECK(total_item_count BETWEEN 0 AND 9007199254740991),total_canonical_bytes bigint NOT NULL CHECK(total_canonical_bytes BETWEEN 0 AND 9007199254740991),manifest_hash text NOT NULL CHECK(manifest_hash ~ '^[0-9a-f]{64}$'),mapping_digest text NOT NULL CHECK(mapping_digest ~ '^[0-9a-f]{64}$'),source_snapshot_hash text NOT NULL CHECK(source_snapshot_hash ~ '^[0-9a-f]{64}$'),stage text NOT NULL CHECK(stage IN ('server_staging','repair_required','server_confirmed','completed','superseded','abandoned')),capacity_rejected boolean NOT NULL DEFAULT false,expires_at timestamptz NOT NULL,published_at timestamptz,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,batch_id),UNIQUE(account_id,lineage_id,batch_id),CHECK((NOT capacity_rejected AND total_item_count<=50000 AND total_canonical_bytes<=134217728) OR (capacity_rejected AND stage IN ('repair_required','superseded','abandoned') AND published_at IS NULL)),CHECK(terminal_client_sequence=begin_client_sequence+total_item_count+1));

CREATE TABLE sync_import_staging_items(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,batch_id uuid NOT NULL,ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),target_type text NOT NULL,entity_id text NOT NULL,operation_type text NOT NULL CHECK(operation_type IN ('import_put','import_delete')),payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,batch_id,ordinal),UNIQUE(account_id,batch_id,target_type,entity_id));

CREATE TABLE sync_import_receipts(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,batch_id uuid NOT NULL,ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),mutation_id uuid NOT NULL,client_sequence bigint NOT NULL CHECK(client_sequence BETWEEN 1 AND 9007199254740991),payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,batch_id,ordinal));

CREATE TABLE sync_import_absent_batch_fences(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,batch_id uuid NOT NULL,origin_device_id uuid NOT NULL,origin_transport_generation bigint NOT NULL CHECK(origin_transport_generation BETWEEN 0 AND 9007199254740991),manifest_hash text NOT NULL CHECK(manifest_hash ~ '^[0-9a-f]{64}$'),begin_client_sequence bigint NOT NULL CHECK(begin_client_sequence BETWEEN 1 AND 9007199254740991),terminal_client_sequence bigint NOT NULL CHECK(terminal_client_sequence BETWEEN 1 AND 9007199254740991),resolved_fence_operation_id uuid,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,batch_id));

CREATE TABLE sync_import_publish_markers(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,batch_id uuid NOT NULL,lineage_id uuid NOT NULL,publish_group_id uuid NOT NULL,commit_server_sequence bigint NOT NULL CHECK(commit_server_sequence BETWEEN 1 AND 9007199254740991),manifest_hash text NOT NULL CHECK(manifest_hash ~ '^[0-9a-f]{64}$'),mapping_digest text NOT NULL CHECK(mapping_digest ~ '^[0-9a-f]{64}$'),payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,batch_id));

CREATE TABLE sync_cursor_key_usage(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,key_id uuid NOT NULL,account_generation bigint NOT NULL CHECK(account_generation BETWEEN 0 AND 9007199254740991),maximum_snapshot_upper_bound bigint NOT NULL CHECK(maximum_snapshot_upper_bound BETWEEN 0 AND 9007199254740991),bootstrap_valid_through timestamptz,PRIMARY KEY(account_id,key_id,account_generation));

CREATE TABLE sync_bootstrap_sessions(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,bootstrap_id uuid NOT NULL,device_id uuid NOT NULL,cursor_key_id uuid NOT NULL,protocol_version integer NOT NULL CHECK(protocol_version=1),sync_transport_generation bigint NOT NULL CHECK(sync_transport_generation BETWEEN 0 AND 9007199254740991),account_generation bigint NOT NULL CHECK(account_generation BETWEEN 0 AND 9007199254740991),upper_bound bigint NOT NULL CHECK(upper_bound BETWEEN 0 AND 9007199254740991),retention_floor_server_sequence bigint NOT NULL CHECK(retention_floor_server_sequence BETWEEN 0 AND 9007199254740991),resolved_conflict_cleanup_before timestamptz NOT NULL,highest_client_sequence bigint NOT NULL CHECK(highest_client_sequence BETWEEN 0 AND 9007199254740991),client_confirmed_through bigint NOT NULL CHECK(client_confirmed_through BETWEEN 0 AND 9007199254740991),created_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,superseded_at timestamptz,total_item_count bigint NOT NULL CHECK(total_item_count BETWEEN 0 AND 9007199254740991),snapshot_hash text NOT NULL CHECK(snapshot_hash ~ '^[0-9a-f]{64}$'),total_page_count bigint NOT NULL CHECK(total_page_count BETWEEN 1 AND 9007199254740991),page_item_limit integer NOT NULL CHECK(page_item_limit BETWEEN 1 AND 500),PRIMARY KEY(account_id,bootstrap_id),CHECK(client_confirmed_through<=highest_client_sequence),CHECK(retention_floor_server_sequence<=upper_bound),CHECK(expires_at=created_at+interval '24 hours'));

CREATE TABLE sync_bootstrap_items(account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,bootstrap_id uuid NOT NULL,ordinal bigint NOT NULL CHECK(ordinal BETWEEN 0 AND 9007199254740991),kind text NOT NULL CHECK(kind IN ('fact_after_image','tombstone','deleted_entity_anchor','unresolved_conflict','import_publish_marker','requesting_device_causal_anchor')),target_type text,entity_id text,conflict_id uuid,merge_key text,payload_version integer NOT NULL CHECK(payload_version=1),payload_json jsonb NOT NULL CHECK(jsonb_typeof(payload_json)='object'),payload_hash text NOT NULL CHECK(payload_hash ~ '^[0-9a-f]{64}$'),PRIMARY KEY(account_id,bootstrap_id,ordinal),UNIQUE NULLS NOT DISTINCT(account_id,bootstrap_id,kind,target_type,entity_id,conflict_id,merge_key));

ALTER TABLE user_sessions ADD COLUMN device_id uuid;

ALTER TABLE user_sessions ADD COLUMN registration_state text NOT NULL DEFAULT 'unregistered' CHECK(registration_state IN ('unregistered','pending_registration','registered'));

ALTER TABLE user_sessions ADD COLUMN attempted_installation_hash text CHECK(attempted_installation_hash ~ '^[0-9a-f]{64}$');

ALTER TABLE user_sessions ADD CONSTRAINT ck_session_registration_binding CHECK((registration_state='registered' AND device_id IS NOT NULL AND attempted_installation_hash IS NOT NULL) OR (registration_state IN ('unregistered','pending_registration') AND device_id IS NULL));

ALTER TABLE user_sessions ADD CONSTRAINT uq_session_account_id UNIQUE(user_id,id);

ALTER TABLE user_sessions ADD FOREIGN KEY(user_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE user_sessions DROP CONSTRAINT ck_user_sessions_revocation_reason;

ALTER TABLE user_sessions ADD CONSTRAINT ck_user_sessions_revocation_reason CHECK(revocation_reason IN ('logout','logout_all','password_changed','password_reset','email_changed','refresh_token_reused','account_disabled','expired','device_revoked','account_deleted'));

ALTER TABLE reauth_grants ADD FOREIGN KEY(account_id,session_id) REFERENCES user_sessions(user_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE reauth_grants ADD FOREIGN KEY(account_id,actor_device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE reauth_grants ADD FOREIGN KEY(account_id,target_device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE user_preferences ADD COLUMN habit_progress_color text NOT NULL DEFAULT 'teal' CHECK(habit_progress_color IN ('teal','blue','indigo','green','orange','rose','purple'));

ALTER TABLE user_preferences ADD COLUMN auto_enable_reminders_on_other_devices boolean NOT NULL DEFAULT false;

ALTER TABLE sync_fact_event ADD FOREIGN KEY(account_id,recurrence_id,recurrence_revision) REFERENCES sync_fact_event_recurrence(account_id,recurrence_id,revision) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_event_occurrence_state ADD FOREIGN KEY(account_id,event_id) REFERENCES sync_fact_event(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_anniversary ADD FOREIGN KEY(account_id,recurrence_id) REFERENCES sync_fact_anniversary_recurrence(account_id,recurrence_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_habit ADD FOREIGN KEY(account_id,recurrence_id) REFERENCES sync_fact_habit_recurrence(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_habit_check_in ADD FOREIGN KEY(account_id,habit_id) REFERENCES sync_fact_habit(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_reminder_intent ADD FOREIGN KEY(account_id,event_owner_id) REFERENCES sync_fact_event(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_reminder_intent ADD FOREIGN KEY(account_id,anniversary_owner_id) REFERENCES sync_fact_anniversary(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_fact_reminder_intent ADD FOREIGN KEY(account_id,habit_owner_id) REFERENCES sync_fact_habit(account_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_reminder_event_templates ADD FOREIGN KEY(account_id,intent_id,owner_type) REFERENCES sync_fact_reminder_intent(account_id,entity_id,owner_type) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_reminder_anniversary_templates ADD FOREIGN KEY(account_id,intent_id,owner_type) REFERENCES sync_fact_reminder_intent(account_id,entity_id,owner_type) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_reminder_habit_templates ADD FOREIGN KEY(account_id,intent_id,owner_type) REFERENCES sync_fact_reminder_intent(account_id,entity_id,owner_type) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE user_avatar_assets ADD CONSTRAINT uq_avatar_account_id UNIQUE(user_id,id);

ALTER TABLE user_profiles ADD CONSTRAINT fk_profile_avatar_account FOREIGN KEY(user_id,avatar_asset_id) REFERENCES user_avatar_assets(user_id,id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_device_state ADD FOREIGN KEY(account_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_device_fence_receipts ADD FOREIGN KEY(account_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_device_causal_anchors ADD FOREIGN KEY(account_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_mutation_receipts ADD FOREIGN KEY(account_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_change_items ADD FOREIGN KEY(account_id,group_id) REFERENCES sync_change_groups(account_id,group_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_conflict_tombstone_pins ADD FOREIGN KEY(account_id,conflict_id) REFERENCES sync_conflicts(account_id,conflict_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_mappings ADD FOREIGN KEY(account_id,lineage_id,source_workspace_id,source_epoch) REFERENCES sync_import_lineages(account_id,lineage_id,source_workspace_id,source_epoch) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_recurrence_families ADD FOREIGN KEY(account_id,lineage_id) REFERENCES sync_import_lineages(account_id,lineage_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_batches ADD FOREIGN KEY(account_id,lineage_id) REFERENCES sync_import_lineages(account_id,lineage_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_batches ADD FOREIGN KEY(account_id,origin_device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_batches ADD FOREIGN KEY(account_id,predecessor_batch_id) REFERENCES sync_import_batches(account_id,batch_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_mappings ADD FOREIGN KEY(account_id,lineage_id,first_published_batch_id) REFERENCES sync_import_batches(account_id,lineage_id,batch_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_mappings ADD FOREIGN KEY(account_id,lineage_id,last_published_batch_id) REFERENCES sync_import_batches(account_id,lineage_id,batch_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_staging_items ADD FOREIGN KEY(account_id,batch_id) REFERENCES sync_import_batches(account_id,batch_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_import_receipts ADD FOREIGN KEY(account_id,batch_id) REFERENCES sync_import_batches(account_id,batch_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_bootstrap_sessions ADD FOREIGN KEY(account_id,device_id) REFERENCES user_devices(account_id,device_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_bootstrap_sessions ADD FOREIGN KEY(account_id,cursor_key_id,account_generation) REFERENCES sync_cursor_key_usage(account_id,key_id,account_generation) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE sync_bootstrap_items ADD FOREIGN KEY(account_id,bootstrap_id) REFERENCES sync_bootstrap_sessions(account_id,bootstrap_id) DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX ux_active_device_installation ON user_devices(account_id,installation_hash) WHERE revoked_at IS NULL;

CREATE INDEX ix_sync_fact_category_change ON sync_fact_category(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_event_change ON sync_fact_event(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_event_recurrence_change ON sync_fact_event_recurrence(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_event_occurrence_state_change ON sync_fact_event_occurrence_state(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_anniversary_change ON sync_fact_anniversary(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_anniversary_recurrence_change ON sync_fact_anniversary_recurrence(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_habit_change ON sync_fact_habit(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_habit_recurrence_change ON sync_fact_habit_recurrence(account_id,last_server_sequence);

CREATE INDEX ix_sync_fact_habit_check_in_change ON sync_fact_habit_check_in(account_id,last_server_sequence);

CREATE INDEX ix_sync_mutation_receipts_scan ON sync_mutation_receipts(account_id,device_id,retain_until,client_sequence);

CREATE INDEX ix_sync_conflicts_scan ON sync_conflicts(account_id,status,received_at,conflict_id);

CREATE INDEX ix_sync_import_batches_scan ON sync_import_batches(account_id,stage,expires_at);

CREATE INDEX ix_sync_bootstrap_sessions_scan ON sync_bootstrap_sessions(account_id,device_id,expires_at);

CREATE INDEX ix_sync_change_groups_scan ON sync_change_groups(account_id,account_generation,last_server_sequence);

CREATE FUNCTION guard_device_registration() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_immutable_event_recurrence() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF ROW(OLD."recurrence_id",OLD."revision",OLD."frequency",OLD."interval",OLD."start_at",OLD."start_date",OLD."timezone",OLD."day_of_month",OLD."days_of_week",OLD."month_of_year",OLD."end_at",OLD."count",OLD."created_at") IS DISTINCT FROM ROW(NEW."recurrence_id",NEW."revision",NEW."frequency",NEW."interval",NEW."start_at",NEW."start_date",NEW."timezone",NEW."day_of_month",NEW."days_of_week",NEW."month_of_year",NEW."end_at",NEW."count",NEW."created_at") THEN RAISE EXCEPTION 'IMMUTABLE_RECURRENCE_REVISION' USING ERRCODE='23514'; END IF; RETURN NEW; END $$;

CREATE FUNCTION guard_immutable_anniversary_recurrence() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF ROW(OLD."recurrence_id",OLD."frequency",OLD."interval",OLD."created_at") IS DISTINCT FROM ROW(NEW."recurrence_id",NEW."frequency",NEW."interval",NEW."created_at") THEN RAISE EXCEPTION 'IMMUTABLE_RECURRENCE_REVISION' USING ERRCODE='23514'; END IF; RETURN NEW; END $$;

CREATE FUNCTION guard_immutable_habit_recurrence() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF ROW(OLD."id",OLD."frequency",OLD."interval",OLD."timezone_mode",OLD."created_at") IS DISTINCT FROM ROW(NEW."id",NEW."frequency",NEW."interval",NEW."timezone_mode",NEW."created_at") THEN RAISE EXCEPTION 'IMMUTABLE_RECURRENCE_REVISION' USING ERRCODE='23514'; END IF; RETURN NEW; END $$;

CREATE FUNCTION guard_habit_operation() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_habit_barrier() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_import_publication_history() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_import_mapping() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_cursor_key_usage() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_bootstrap_key_usage() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE FUNCTION guard_bootstrap_item() RETURNS trigger LANGUAGE plpgsql AS $$
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
END $$;

CREATE TRIGGER guard_device_registration BEFORE INSERT OR UPDATE ON user_devices FOR EACH ROW EXECUTE FUNCTION guard_device_registration();

CREATE TRIGGER guard_immutable_event_recurrence BEFORE UPDATE ON sync_fact_event_recurrence FOR EACH ROW EXECUTE FUNCTION guard_immutable_event_recurrence();

CREATE TRIGGER guard_immutable_anniversary_recurrence BEFORE UPDATE ON sync_fact_anniversary_recurrence FOR EACH ROW EXECUTE FUNCTION guard_immutable_anniversary_recurrence();

CREATE TRIGGER guard_immutable_habit_recurrence BEFORE UPDATE ON sync_fact_habit_recurrence FOR EACH ROW EXECUTE FUNCTION guard_immutable_habit_recurrence();

CREATE TRIGGER guard_habit_operation BEFORE UPDATE OR DELETE ON sync_habit_check_in_operations FOR EACH ROW EXECUTE FUNCTION guard_habit_operation();

CREATE TRIGGER guard_habit_barrier BEFORE UPDATE OR DELETE ON sync_habit_completion_barriers FOR EACH ROW EXECUTE FUNCTION guard_habit_barrier();

CREATE TRIGGER guard_import_publication_history BEFORE UPDATE OR DELETE ON sync_import_lineages FOR EACH ROW EXECUTE FUNCTION guard_import_publication_history();

CREATE TRIGGER guard_sync_import_mappings BEFORE UPDATE OR DELETE ON sync_import_mappings FOR EACH ROW EXECUTE FUNCTION guard_import_mapping();

CREATE TRIGGER guard_sync_import_recurrence_families BEFORE UPDATE OR DELETE ON sync_import_recurrence_families FOR EACH ROW EXECUTE FUNCTION guard_import_mapping();

CREATE TRIGGER guard_cursor_key_usage BEFORE UPDATE OR DELETE ON sync_cursor_key_usage FOR EACH ROW EXECUTE FUNCTION guard_cursor_key_usage();

CREATE TRIGGER guard_bootstrap_key_usage BEFORE INSERT OR UPDATE ON sync_bootstrap_sessions FOR EACH ROW EXECUTE FUNCTION guard_bootstrap_key_usage();

CREATE TRIGGER guard_bootstrap_item BEFORE INSERT OR UPDATE OR DELETE ON sync_bootstrap_items FOR EACH ROW EXECUTE FUNCTION guard_bootstrap_item();
