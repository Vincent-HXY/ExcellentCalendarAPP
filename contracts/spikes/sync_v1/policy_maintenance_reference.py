"""Isolated durable policy and bounded maintenance over real local journals.

The operation receipt uses the planned v6 DDL. Other local tables are the same
logical projections used by the existing bootstrap/download Contract oracles.
"""
import json
import uuid
from datetime import datetime, timezone

from bootstrap_reference import checkpoint
from build_sync_storage_contract import derive
from counter_reference import MAXIMUM
from domain_reference import check, validate_schema
from local_intent_reference import LocalIntentStore
from import_cleanup_reference import AccountImportCleanup
from protocol_reference import digest, encode
from sqlite_reference import connect


class PolicyMaintenanceStore(LocalIntentStore):
    prepare_ack_only = AccountImportCleanup.prepare_ack_only
    accept_ack_only = AccountImportCleanup.accept_ack_only

    def __init__(self, path, *, workspace_id, runtime_id, **kwargs):
        self.workspace_id, self.runtime_id = workspace_id, runtime_id
        super().__init__(path, **kwargs)
        with connect(path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS policy_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),revision INTEGER NOT NULL,pull_required INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS policy_bootstrap(id TEXT PRIMARY KEY,revision INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_ack_requests(id TEXT PRIMARY KEY,payload TEXT NOT NULL,response TEXT);
                INSERT OR IGNORE INTO policy_state VALUES(1,1,0,0);
            """)
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='sync_policy_operation_receipts'").fetchone() is None:
                db.execute(derive()["new_tables"]["sync_policy_operation_receipts"])

    def set_enabled(self, request, *, hook=None):
        validate_schema("sync/native_set_sync_enabled_request.schema.json", request)
        check(request["workspace_id"] == self.workspace_id and request["runtime_instance_id"] == self.runtime_id and
              request["device_id"] == self.device_id, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        # Runtime handles change after a process restart. The operation's stable
        # identity excludes that invocation-only handle after route validation.
        request_hash = digest({key: value for key, value in request.items() if key != "runtime_instance_id"})
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT operation_id,request_hash,resulting_policy_revision,sync_enabled,result_hash FROM sync_policy_operation_receipts").fetchone()
            if old and old[0] == request["operation_id"]:
                check(old[1] == request_hash, "SYNC_POLICY_VERSION_CONFLICT")
                result = {"operation_id": old[0], "sync_enabled": bool(old[3]), "sync_policy_revision": old[2]}
                check(digest(result) == old[4], "SYNC_OUTBOX_CORRUPTED")
                return result
            enabled, revision, gate = db.execute("SELECT enabled,revision,pull_required FROM policy_state").fetchone()
            check(revision == request["expected_sync_policy_revision"], "SYNC_POLICY_VERSION_CONFLICT")
            check(revision < MAXIMUM, "SYNC_POLICY_REVISION_EXHAUSTED")
            gate = bool(gate) or not enabled and request["enabled"]
            result = {"operation_id": request["operation_id"], "sync_enabled": request["enabled"], "sync_policy_revision": revision + 1}
            db.execute("UPDATE policy_state SET enabled=?,revision=?,pull_required=?", (int(request["enabled"]), revision + 1, int(gate)))
            checkpoint(hook, "policy_state_and_pull_gate")
            db.execute("INSERT OR REPLACE INTO sync_policy_operation_receipts VALUES(1,?,?,?,?,?,?)",
                (request["operation_id"], revision, revision + 1, int(request["enabled"]), request_hash, digest(result)))
            checkpoint(hook, "policy_latest_receipt")
            return result

    def prepare(self, sequence):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            enabled, gate = db.execute("SELECT enabled,pull_required FROM policy_state").fetchone()
            check(enabled and not gate, "SYNC_OPERATION_INVALID")
            self._not_rebuilding(db)
            row = db.execute("SELECT payload FROM pending WHERE sequence=?", (sequence,)).fetchone()
            check(row is not None, "SYNC_SEQUENCE_REPLAY_MISMATCH")
            _, frozen_hash = self._stored_mutation(db, sequence, row[0])
            request_id = str(uuid.uuid4())
            db.execute("INSERT INTO prepared_intents VALUES(?,?,?,?,?)", (request_id, sequence, self._state(db)["generation"], self.transport, frozen_hash))
            return request_id

    def prepare_download(self, *, run_intent="normal"):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            state = self._state(db)
            enabled, revision, gate = db.execute("SELECT enabled,revision,pull_required FROM policy_state").fetchone()
            check(enabled and (run_intent == "reenable_pull_only" if gate else run_intent == "normal"), "SYNC_OPERATION_INVALID")
            check(not state["fresh"] and state["cursor"] is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            prepared = {"generation": state["generation"], "transport": self.transport, "cursor": state["cursor"],
                "position": state["upper_bound"], "fixed_upper": state.get("download_upper"), "reported_ack": state["server_ack"],
                "policy_revision": revision, "run_intent": run_intent}
            request_id = str(uuid.uuid4())
            db.execute("INSERT INTO prepared_pages VALUES(?,?)", (request_id, encode(prepared)))
            return request_id

    def _finish_download_control(self, db, response, prepared, hook):
        if not response["has_more"] and prepared.get("run_intent") == "reenable_pull_only":
            db.execute("UPDATE policy_state SET pull_required=0 WHERE enabled=1 AND revision=?", (prepared["policy_revision"],))
            checkpoint(hook, "policy_terminal_pull_gate")

    def _begin_bootstrap_discovery(self, db, metadata):
        enabled, revision, gate = db.execute("SELECT enabled,revision,pull_required FROM policy_state").fetchone()
        db.execute("DELETE FROM policy_bootstrap")
        if enabled and gate:
            db.execute("INSERT INTO policy_bootstrap VALUES(?,?)", (metadata["bootstrap_id"], revision))

    def _finish_bootstrap_discovery(self, db, metadata, hook):
        row = db.execute("SELECT revision FROM policy_bootstrap WHERE id=?", (metadata["bootstrap_id"],)).fetchone()
        if row:
            db.execute("UPDATE policy_state SET pull_required=0 WHERE enabled=1 AND revision=?", row)
            checkpoint(hook, "policy_bootstrap_pull_gate")
        db.execute("DELETE FROM policy_bootstrap WHERE id=?", (metadata["bootstrap_id"],))

    @staticmethod
    def _covered(db, terminal, generation):
        # An accepted ack watermark is durable evidence that this receipt's
        # local effect had already passed the coverage gate before GC.
        if terminal["receipt"]["client_sequence"] <= PolicyMaintenanceStore._state(db)["server_ack"]:
            return True
        return LocalIntentStore._covered(db, terminal, generation)

    def maintenance(self, *, max_items=500, hook=None):
        check(type(max_items) is int and 1 <= max_items <= 500, "SYNC_PAYLOAD_INVALID")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            state = self._state(db)
            check(not state["fresh"] and state["cursor"] is not None and state["generation"] is not None and
                  0 <= state["floor"] <= state["upper_bound"], "SYNC_BOOTSTRAP_INCOMPLETE")
            cutoff = datetime.fromtimestamp(state["cleanup"], timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            resolved = [identifier for identifier, in db.execute("SELECT id FROM conflict_history WHERE status='resolved' AND "
                "json_extract(payload,'$.resolved_at')<=? ORDER BY id LIMIT ?", (cutoff, max_items + 1))]
            # Effect receipts remain pinned until their actual client receipts
            # have been acknowledged; mappings/Outbox are never age-collected.
            remaining = max_items + 1 - len(resolved)
            groups = [identifier for identifier, in db.execute("SELECT g.id FROM applied_groups g WHERE generation=? AND sequence<=? AND "
                "NOT EXISTS(SELECT 1 FROM terminals t WHERE t.sequence>? AND json_extract(t.result,'$.effect.effect_change_group_id')=g.id) "
                "ORDER BY g.sequence,g.id LIMIT ?", (state["generation"], state["floor"], state["server_ack"], remaining))]
            actions = [("conflict", identifier) for identifier in resolved] + [("receipt", identifier) for identifier in groups]
            selected = actions[:max_items]
            for kind, identifier in selected:
                db.execute("DELETE FROM " + ("conflict_history" if kind == "conflict" else "applied_groups") + " WHERE id=?", (identifier,))
            checkpoint(hook, "maintenance_bounded_deletes")
            return {"resolved_conflicts_deleted": sum(kind == "conflict" for kind, _ in selected),
                "change_receipts_deleted": sum(kind == "receipt" for kind, _ in selected), "has_more": len(actions) > max_items,
                "retention_floor_server_sequence": state["floor"]}

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            for table in ("policy_state", "policy_bootstrap", "sync_policy_operation_receipts", "local_import_ack_requests"):
                value[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return value
