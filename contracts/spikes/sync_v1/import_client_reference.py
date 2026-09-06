"""Full-graph previews and same-epoch repair over two actual local databases.

The temporary planner is a copy of durable mappings. Only the account staging
transaction installs its assignments, frozen mutations and operation receipt.
Guest replacement recovery retains the old lease until the new receipt exists.
This is an isolated contract oracle; it does not implement a product runtime.
"""
import base64
import json
from pathlib import Path
import secrets
import tempfile
import uuid

from bootstrap_reference import checkpoint
from build_sync_storage_contract import derive as storage_model
from counter_reference import MAXIMUM
from domain_reference import check, validate_schema
from identity_reference import lineage_id
from import_cleanup_reference import GuestImportCleanup, check_cleanup, cleanup_hash
from import_contract_reference import mapping_rows, validate_manifest
from import_graph_reference import ImportGraphPlanner
from import_status_reference import AccountImportStatus
from protocol_reference import digest, encode, mutation_hash, unwrap_terminal, validate_terminal_for_mutation
from sqlite_reference import connect


def validate_prepared_graph(prepared, manifest):
    """Bind the private assignment ledger to the exact frozen wire graph."""
    batch = prepared["batch"]
    check(len(batch) == manifest["total_item_count"] + 2, "IMPORT_REFERENCE_INVALID")
    validate_manifest(manifest, batch[1:-1])
    first = batch[0]
    check(first["operation_type"] == "import_begin" and batch[-1]["operation_type"] == "import_commit" and
          first["payload"]["manifest"] == batch[-1]["payload"]["manifest"] == manifest, "IMPORT_REFERENCE_INVALID")
    common = ("import_lineage_id", "import_batch_id", "import_source_workspace_id", "import_source_epoch",
              "import_manifest_hash", "predecessor_batch_id")
    for index, row in enumerate(batch):
        validate_schema("sync/sync_mutation.schema.json", row)
        check(all(row[name] == first[name] for name in common) and row["client_sequence"] == first["client_sequence"] + index and
              row["import_item_ordinal"] == (None if index in {0, len(batch) - 1} else index - 1), "IMPORT_REFERENCE_INVALID")
    lineage = first["import_lineage_id"]
    expected = {(lineage, row["target_type"], row["source_id"], row["target_id"]) for row in mapping_rows(batch[1:-1])}
    expected.update((lineage, "event_recurrence_family", source.rsplit("#", 1)[0], target.rsplit("#", 1)[0])
                    for _, kind, source, target in list(expected) if kind == "event_recurrence")
    actual = [tuple(row) for row in prepared["mappings"]]
    check(len(set(actual)) == len(actual) and set(actual) == expected, "IMPORT_LINEAGE_MISMATCH")
    check(prepared["source_fact_count"] == sum(row["operation_type"] == "import_put" and row["target_type"] != "user_preferences"
                                              for row in batch[1:-1]), "IMPORT_REFERENCE_INVALID")


class FullGraphAccountImport(AccountImportStatus):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        ImportGraphPlanner(path)
        with connect(path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS local_import_graph_inputs(batch TEXT PRIMARY KEY,payload TEXT NOT NULL)")

    def _closed_proof(self, db, batch):
        row = db.execute("SELECT proof FROM local_import_range_terminals WHERE batch=?", (batch,)).fetchone()
        return None if row is None else json.loads(row[0])

    def _planning_state(self, db):
        self._not_rebuilding(db)
        state = self._state(db)
        check(not state["fresh"], "SYNC_BOOTSTRAP_INCOMPLETE")
        check(not state["exhausted"], "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
        images = [json.loads(row[0]) for row in db.execute("SELECT payload FROM live ORDER BY identity")]
        versions = {(row["target_type"], row["target_id"]): row["entity_version"] for row in images
                    if "target_type" in row and "entity_version" in row}
        mappings = [list(row) for row in db.execute("SELECT lineage,kind,source,target FROM graph_mapping ORDER BY lineage,kind,source")]
        # A concurrent ordinary write, bootstrap or mapping allocation requires a
        # new preview, before this operation can reserve any client sequence.
        pending = [list(row) for row in db.execute("SELECT * FROM pending ORDER BY 1")]
        fingerprint = digest({"state": state, "live": images, "mappings": mappings, "pending": pending, "transport": self.transport})
        return state, versions, mappings, fingerprint

    def draft(self, records, *, source, epoch, source_hash, predecessor_operation=None):
        with connect(self.path) as db:
            db.execute("BEGIN")
            state, versions, mappings, fingerprint = self._planning_state(db)
            predecessor, revision, reason, proof_id = None, 0, None, None
            if predecessor_operation is not None:
                old = self._receipt(db, predecessor_operation)
                check(old is not None and old["source_workspace_id"] == source and old["source_epoch"] == epoch, "IMPORT_LINEAGE_MISMATCH")
                check(old["stage"] in {"repair_required", "publish_applied", "superseded"}, "IMPORT_PUBLISH_INCOMPLETE")
                control = db.execute("SELECT revision,head FROM local_import_control WHERE batch=?", (old["batch_id"],)).fetchone()
                cached = db.execute("SELECT snapshot FROM local_import_server_status WHERE batch=?", (old["batch_id"],)).fetchone()
                check(control is not None and cached is not None, "IMPORT_VERSION_CONFLICT")
                status = json.loads(cached[0])
                check(status["current_head"] == {"current_head_batch_id": old["batch_id"], "current_import_revision": control[0]} and
                      status["stage"] != "completed", "IMPORT_VERSION_CONFLICT")
                predecessor, revision = old["batch_id"], control[0]
                closed = self._closed_proof(db, predecessor)
                if closed:
                    proof = closed
                    if proof["origin_device_id"] == self.device_id and proof["kind"] == "seen_range_closed":
                        check(state["server_ack"] >= old["terminal_client_sequence"], "SYNC_ACK_WATERMARK_INVALID")
                    ordinary_repair = proof["reason"] == "capacity_rejected" and proof["origin_device_id"] == self.device_id and \
                        proof["origin_sync_transport_generation"] == self.transport
                    reason = None if ordinary_repair else "ttl_payload_reclaimed" if proof["reason"] == "ttl_payload_reclaimed" else \
                        "origin_unavailable" if proof["origin_device_id"] != self.device_id else "local_evidence_lost"
                    if reason == "local_evidence_lost":
                        check(self.transport > proof["origin_sync_transport_generation"], "IMPORT_REFERENCE_INVALID")
                    proof_id = None if ordinary_repair else proof["proof_id"]
                else:
                    check(db.execute("SELECT 1 FROM local_import_outbox WHERE batch=?", (predecessor,)).fetchone() is None,
                          "IMPORT_PUBLISH_INCOMPLETE")
                if old["stage"] == "publish_applied":
                    check(old["manifest"]["source_snapshot_hash"] != source_hash, "IMPORT_REFERENCE_INVALID")
            else:
                check(db.execute("SELECT 1 FROM local_import_operations WHERE lineage=? AND stage!='completed'",
                    (lineage_id(self.account_id, source, epoch),)).fetchone() is None, "IMPORT_SOURCE_OWNED")
        with tempfile.TemporaryDirectory(prefix="excellent-calendar-import-preview-") as temporary:
            planner = ImportGraphPlanner(Path(temporary) / "mapping.db")
            with connect(planner.path) as db:
                db.executemany("INSERT INTO graph_mapping VALUES(?,?,?,?)", mappings)
            batch = planner.prepare(self.account_id, source, epoch, records, occupied=versions,
                begin_sequence=state["next_sequence"], predecessor=predecessor, revision=revision, versions=versions,
                takeover_reason=reason, proof_id=proof_id, source_snapshot_hash=source_hash)
            planned = [list(row) for row in planner.snapshot()["graph_mapping"] if row[0] == lineage_id(self.account_id, source, epoch)]
        return {"batch": batch, "mappings": planned, "account_fingerprint": fingerprint, "source_fact_count": len(records),
                "predecessor_operation": predecessor_operation, "transport": self.transport, "origin_device_id": self.device_id}

    def status(self, operation, *, server_snapshot=None):
        value = super().status(operation, server_snapshot=server_snapshot)
        if value["disposition"] == "found":
            with connect(self.path) as db:
                row = db.execute("SELECT payload FROM local_import_graph_inputs WHERE batch=?", (value["import_batch_id"],)).fetchone()
                if row:
                    prepared = json.loads(row[0])
                    value.update(origin_device_id=prepared["origin_device_id"], origin_sync_transport_generation=prepared["transport"])
            validate_schema("workspace/native_import_status_response.schema.json", value)
        return value

    def stage_reserved(self, preview, *, operation, hook=None):
        check(preview["owner_binding"] == self.owner_binding, "WORKSPACE_ACCOUNT_MISMATCH")
        prepared, response = preview["prepared"], preview["response"]
        batch = prepared["batch"]
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = self._receipt(db, operation)
            if old:
                saved = db.execute("SELECT payload FROM local_import_graph_inputs WHERE batch=?", (old["batch_id"],)).fetchone()
                check(saved is not None and json.loads(saved[0]) == prepared and old["manifest"] == response["manifest"], "IMPORT_LINEAGE_MISMATCH")
                return old
            state, _, _, fingerprint = self._planning_state(db)
            check(prepared["account_fingerprint"] == fingerprint and prepared["transport"] == self.transport, "IMPORT_VERSION_CONFLICT")
            check(batch[0]["client_sequence"] == state["next_sequence"] and batch[0]["import_batch_id"] == response["proposed_import_batch_id"] and
                  batch[0]["payload"]["manifest"] == response["manifest"] and
                  batch[0]["import_lineage_id"] == lineage_id(self.account_id, response["source_workspace_id"], response["source_epoch"]), "IMPORT_LINEAGE_MISMATCH")
            validate_prepared_graph(prepared, response["manifest"])
            for mapping in prepared["mappings"]:
                check(mapping[0] == response["import_lineage_id"], "IMPORT_LINEAGE_MISMATCH")
                existing = db.execute("SELECT target FROM graph_mapping WHERE lineage=? AND kind=? AND source=?", mapping[:3]).fetchone()
                check(existing is None or existing[0] == mapping[3], "IMPORT_LINEAGE_MISMATCH")
                db.execute("INSERT OR IGNORE INTO graph_mapping VALUES(?,?,?,?)", mapping)
                check(db.execute("SELECT target FROM graph_mapping WHERE lineage=? AND kind=? AND source=?", mapping[:3]).fetchone() == (mapping[3],),
                      "IMPORT_DUPLICATE_IDENTITY")
            checkpoint(hook, "import_client_mapping")
            binding = {"operation_id": operation, "batch_id": response["proposed_import_batch_id"], "source_workspace_id": response["source_workspace_id"],
                "source_epoch": response["source_epoch"], "import_lineage_id": response["import_lineage_id"], "protected_owner_binding_digest": self.owner_binding,
                "manifest": response["manifest"], "begin_client_sequence": batch[0]["client_sequence"], "terminal_client_sequence": batch[-1]["client_sequence"],
                "outbox_mutation_digest": digest([{"client_sequence": row["client_sequence"], "payload_hash": mutation_hash(row)} for row in batch]), "stage": "local_staging"}
            for row in batch:
                db.execute("INSERT INTO local_import_outbox VALUES(?,?,?,?,0)", (row["client_sequence"], binding["batch_id"], mutation_hash(row), encode(row)))
                db.execute("INSERT INTO frozen_intents VALUES(?,?,?)", (row["client_sequence"], mutation_hash(row), row["mutation_id"]))
            checkpoint(hook, "import_account_outbox")
            db.execute("INSERT INTO local_import_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)", (operation, binding["batch_id"], binding["source_workspace_id"],
                binding["source_epoch"], binding["import_lineage_id"], self.owner_binding, encode(binding["manifest"]), binding["begin_client_sequence"],
                binding["terminal_client_sequence"], binding["outbox_mutation_digest"], "local_staging"))
            db.execute("INSERT INTO local_import_graph_inputs VALUES(?,?)", (binding["batch_id"], encode(prepared)))
            db.execute("INSERT INTO graph_batches VALUES(?,?,?)", (binding["batch_id"], digest(prepared), encode(batch)))
            checkpoint(hook, "import_account_operation_receipt")
            last = binding["terminal_client_sequence"]
            state.update(next_sequence=None if last == MAXIMUM else last + 1, exhausted=last == MAXIMUM)
            self._save_state(db, state)
            checkpoint(hook, "import_account_allocator")
            return binding

    def acknowledge_import(self, operation, results, *, hook=None):
        # Control revision comes from the frozen begin CAS; item receipts are
        # not allowed to invent a new revision. Replays preserve the actual ack.
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            receipt = self._receipt(db, operation)
            check(receipt is not None, "IMPORT_LINEAGE_MISMATCH")
            prepared = json.loads(db.execute("SELECT payload FROM local_import_graph_inputs WHERE batch=?", (receipt["batch_id"],)).fetchone()[0])
            begin_revision = prepared["batch"][0]["base_entity_version"] + 1
            state = self._state(db)
            for result in results:
                terminal = unwrap_terminal(result)
                sequence = terminal["receipt"]["client_sequence"]
                check(terminal["receipt"]["device_id"] == self.device_id and receipt["begin_client_sequence"] <= sequence <= receipt["terminal_client_sequence"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
                old = db.execute("SELECT result FROM terminals WHERE sequence=?", (sequence,)).fetchone()
                if old:
                    check(json.loads(old[0]) == terminal, "SYNC_SEQUENCE_REPLAY_MISMATCH")
                    continue
                row = db.execute("SELECT mutation,prepared FROM local_import_outbox WHERE sequence=? AND batch=?", (sequence, receipt["batch_id"])).fetchone()
                check(row is not None and row[1] == 1, "SYNC_SEQUENCE_ROUTE_MISMATCH")
                mutation, _ = self._stored_mutation(db, sequence, row[0])
                validate_terminal_for_mutation(result, mutation)
                db.execute("INSERT INTO terminals VALUES(?,?,?,?)", (sequence, row[0], encode(terminal), state["generation"]))
                db.execute("DELETE FROM local_import_outbox WHERE sequence=?", (sequence,))
                if not self._covered(db, terminal, state["generation"]):
                    db.execute("INSERT INTO local_import_effect_gates VALUES(?,?)", (sequence, receipt["batch_id"]))
                revision = begin_revision
                publication = None
                if mutation["operation_type"] == "import_commit":
                    stage = terminal["import_stage"]
                    revision = terminal["import_revision"] if terminal["status"] == "accepted" else terminal["next_revision"]
                    publication = encode(terminal) if terminal["status"] == "accepted" else None
                    db.execute("UPDATE local_import_operations SET stage=? WHERE operation=?", (stage, operation))
                else:
                    db.execute("UPDATE local_import_operations SET stage='server_staging' WHERE operation=? AND stage='local_staging'", (operation,))
                db.execute("INSERT INTO local_import_control VALUES(?,?,?,?,NULL,NULL) ON CONFLICT(batch) DO UPDATE SET "
                    "revision=MAX(revision,excluded.revision),publication=COALESCE(excluded.publication,publication)",
                    (receipt["batch_id"], revision, receipt["batch_id"], publication))
                if prepared["predecessor_operation"] is not None:
                    db.execute("UPDATE local_import_control SET head=? WHERE batch IN(SELECT batch FROM local_import_operations WHERE lineage=? AND batch!=?)",
                               (receipt["batch_id"], receipt["import_lineage_id"], receipt["batch_id"]))
                checkpoint(hook, "import_local_terminal")
            self._refresh_import_applied(db)
            self._advance_ack(db, state)
            self._save_state(db, state)
            checkpoint(hook, "import_local_ack_watermark")

    def publication_evidence(self, operation):
        value = super().publication_evidence(operation)
        with connect(self.path) as db:
            prepared = json.loads(db.execute("SELECT payload FROM local_import_graph_inputs WHERE batch=?", (value["batch_id"],)).fetchone()[0])
            value["source_fact_count"] = prepared["source_fact_count"]
            value["source_identities"] = {(row["target_type"], row["payload"]["source_id"]) for row in prepared["batch"][1:-1]
                                          if "source_id" in row["payload"]}
            cached = db.execute("SELECT snapshot FROM local_import_server_status WHERE batch=?", (value["batch_id"],)).fetchone()
            check(cached is None or json.loads(cached[0])["current_head"]["current_head_batch_id"] == value["batch_id"], "IMPORT_VERSION_CONFLICT")
        return value

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            for table in ("graph_mapping", "graph_batches", "local_import_graph_inputs"):
                value[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return value


class FullGraphGuestImport(GuestImportCleanup):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(path) as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='guest_import_source_lease_replacements'").fetchone() is None:
                db.execute(storage_model()["new_tables"]["guest_import_source_lease_replacements"])

    def _replacement(self, db, operation):
        row = db.execute("SELECT source_workspace_id,source_epoch,payload_version,payload_json,payload_hash "
                         "FROM guest_import_source_lease_replacements WHERE operation_id=?", (operation,)).fetchone()
        if row is None:
            return None
        value = json.loads(row[3])
        validate_schema("storage/guest_import_source_lease_backup.schema.json", value)
        check(row[0] == self.workspace_id == value["source_workspace_id"] and row[1] == value["source_epoch"] and
              row[2] == 1 and row[4] == digest(value) and value["terminal_client_sequence"] > value["begin_client_sequence"], "IMPORT_REFERENCE_INVALID")
        return value

    def preview(self, account, *, target_workspace_id):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            epoch, pending, exhausted = db.execute("SELECT current_import_source_epoch,previous_epoch_cleanup_pending,source_epoch_exhausted FROM workspace_metadata").fetchone()
            check(not exhausted, "IMPORT_SOURCE_EPOCH_EXHAUSTED")
            if pending is not None:
                receipt = db.execute("SELECT receipt_hash FROM guest_import_cleanup_receipts WHERE source_epoch=?", (pending,)).fetchone()
                check(receipt is not None, "IMPORT_REFERENCE_INVALID")
                return {"disposition": "previous_epoch_cleanup_pending", "source_workspace_id": self.workspace_id, "source_epoch": pending,
                        "recovery_handle": base64.urlsafe_b64encode(bytes.fromhex(receipt[0])).decode().rstrip("=")}
            lease = self._lease(db)
            if lease:
                check(lease["state"] == "active" and lease["source_epoch"] == epoch and
                      lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            records, source_hash = self._source(db)
            prepared = account.draft(records, source=self.workspace_id, epoch=epoch, source_hash=source_hash,
                                     predecessor_operation=lease["reserved_operation_id"] if lease else None)
            batch = prepared["batch"]
            response = {"disposition": "ready", "source_workspace_id": self.workspace_id, "target_workspace_id": target_workspace_id,
                "source_epoch": epoch, "preview_token": secrets.token_urlsafe(32), "proposed_import_batch_id": batch[0]["import_batch_id"],
                "import_lineage_id": batch[0]["import_lineage_id"], "manifest": batch[0]["payload"]["manifest"], "warnings": []}
            validate_schema("workspace/import_preview_response.schema.json", response)
            value = {"response": response, "records": records, "owner_binding": account.owner_binding, "prepared": prepared, "previous_lease": lease}
            # Account ownership is only the opaque HMAC. User-authored text and
            # business IDs remain opaque even if they happen to resemble an ID.
            db.execute("INSERT INTO guest_import_previews VALUES(?,?,?)", (response["preview_token"], str(uuid.uuid4()), encode(value)))
            return response

    def commit(self, account, token, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT operation,payload FROM guest_import_previews WHERE token=?", (token,)).fetchone()
            check(row is not None, "IMPORT_REFERENCE_INVALID")
            operation, preview = row[0], json.loads(row[1])
            check(preview["owner_binding"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            lease = self._lease(db)
            if lease is not None and lease["reserved_operation_id"] == operation:
                check(lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            else:
                check(lease == preview["previous_lease"], "IMPORT_SOURCE_OWNED")
                epoch, pending, exhausted = db.execute("SELECT current_import_source_epoch,previous_epoch_cleanup_pending,source_epoch_exhausted FROM workspace_metadata").fetchone()
                response = preview["response"]
                check(not exhausted, "IMPORT_SOURCE_EPOCH_EXHAUSTED")
                check(pending is None and epoch == response["source_epoch"] and self._source(db)[1] == response["manifest"]["source_snapshot_hash"], "IMPORT_REFERENCE_INVALID")
                revision = 1 if lease is None else lease["lease_revision"] + 1
                check(revision < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
                if lease is not None:
                    validate_schema("storage/guest_import_source_lease_backup.schema.json", lease)
                    db.execute("INSERT INTO guest_import_source_lease_replacements VALUES(?,?,?,1,?,?)",
                               (self.workspace_id, operation, epoch, encode(lease), digest(lease)))
                    db.execute("DELETE FROM guest_import_source_leases")
                db.execute("INSERT INTO guest_import_source_leases VALUES(?,?,?,?,?,?,NULL,NULL,NULL,NULL,'reserved',?)",
                    (self.workspace_id, epoch, response["import_lineage_id"], account.owner_binding, response["manifest"]["source_snapshot_hash"], operation, revision))
            checkpoint(hook, "import_guest_reserved")
        checkpoint(hook, "import_guest_reserved_committed")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            lease = self._lease(db)
            check(lease is not None and lease["reserved_operation_id"] == operation and lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            receipt = account.stage_reserved(preview, operation=operation, hook=hook)
            checkpoint(hook, "import_account_receipt_committed")
            self._activate(db, receipt, hook=hook)
            db.execute("DELETE FROM guest_import_source_lease_replacements WHERE operation_id=?", (operation,))
        return receipt

    def recover_reserved(self, account):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            lease = self._lease(db)
            check(lease is not None and lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            operation = lease["reserved_operation_id"]
            receipt = account.receipt(operation)
            if receipt is not None:
                self._activate(db, receipt)
                db.execute("DELETE FROM guest_import_source_lease_replacements WHERE operation_id=?", (operation,))
                return "active"
            check(lease["state"] == "reserved", "IMPORT_SOURCE_OWNED")
            old = self._replacement(db, operation)
            if old is None:
                db.execute("DELETE FROM guest_import_source_leases")
                return "released_never_active"
            previous = old
            prior_receipt = account.receipt(previous["reserved_operation_id"])
            check(prior_receipt is not None, "IMPORT_SOURCE_OWNED")
            self._require_binding(previous, prior_receipt)
            check(lease["lease_revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            previous["lease_revision"] = lease["lease_revision"] + 1
            db.execute("DELETE FROM guest_import_source_leases")
            columns = [row[1] for row in db.execute("PRAGMA table_info(guest_import_source_leases)")]
            db.execute("INSERT INTO guest_import_source_leases VALUES(" + ",".join("?" for _ in columns) + ")", [previous[name] for name in columns])
            db.execute("DELETE FROM guest_import_source_lease_replacements WHERE operation_id=?", (operation,))
            return "restored_previous_active"

    def retire(self, account, operation, *, now, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            evidence = account.publication_evidence(operation)
            lease = self._lease(db)
            self._require_binding(lease, evidence)
            old = self._cleanup_receipt(db, evidence["source_epoch"])
            if old:
                check(old["through_published_batch_id"] == evidence["batch_id"], "IMPORT_LINEAGE_MISMATCH")
                return old
            records, source_hash = self._source(db)
            epoch, pending = db.execute("SELECT current_import_source_epoch,previous_epoch_cleanup_pending FROM workspace_metadata").fetchone()
            check(epoch == evidence["source_epoch"] and pending is None and source_hash == evidence["manifest"]["source_snapshot_hash"] and
                  len(records) == evidence["source_fact_count"], "IMPORT_REFERENCE_INVALID")
            check(lease["lease_revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            receipt = {"source_workspace_id": self.workspace_id, "source_epoch": epoch, "import_lineage_id": evidence["import_lineage_id"],
                "through_published_batch_id": evidence["batch_id"], "through_import_revision": evidence["through_import_revision"],
                "source_snapshot_hash": source_hash, "mapping_digest": evidence["manifest"]["mapping_digest"], "cleaned_at": now}
            receipt["receipt_hash"] = cleanup_hash(receipt)
            check_cleanup(receipt)
            identities = {(row["target_type"], row["target_id"]) for row in records}
            for reminder, target, entity, state in db.execute("SELECT id,target,entity,state FROM guest_execution_reminders").fetchall():
                old_anchor = db.execute("SELECT 1 FROM guest_import_audit_anchors WHERE target_type=? AND target_id=? AND reminder_id=?", (target, entity, reminder)).fetchone()
                if old_anchor:
                    continue
                # Historical identities deleted during repair are also part of
                # the frozen import closure and retain their local audit graph.
                check((target, entity) in identities or (target, entity) in evidence["source_identities"], "IMPORT_REFERENCE_INVALID")
                db.execute("INSERT INTO guest_import_audit_anchors VALUES(?,?,?,?,?,'source_migrated',?,NULL,NULL)",
                    (target, entity, reminder, epoch, evidence["import_lineage_id"], now))
                if state in {"open", "prepared"}:
                    db.execute("UPDATE guest_execution_reminders SET state='cancelled',reason='source_migrated' WHERE id=?", (reminder,))
                db.execute("UPDATE guest_execution_notifications SET state='cancelled',reason='source_migrated' WHERE reminder=? AND state='prepared'", (reminder,))
            checkpoint(hook, "import_guest_execution_retired")
            db.execute("DELETE FROM guest_import_source_facts")
            checkpoint(hook, "import_guest_facts_retired")
            db.execute("INSERT INTO guest_import_cleanup_receipts VALUES(?,?,?,?,?,?,?,?,?,'pending_confirmation')", tuple(receipt[name] for name in
                ("source_workspace_id", "source_epoch", "import_lineage_id", "through_published_batch_id", "through_import_revision", "source_snapshot_hash", "mapping_digest", "cleaned_at", "receipt_hash")))
            db.execute("UPDATE workspace_metadata SET current_import_source_epoch=?,previous_epoch_cleanup_pending=?,source_epoch_exhausted=?",
                (epoch if epoch == MAXIMUM else epoch + 1, epoch, int(epoch == MAXIMUM)))
            db.execute("UPDATE guest_import_source_leases SET state='published_cleanup_pending',lease_revision=lease_revision+1")
            checkpoint(hook, "import_guest_retirement_receipt_epoch")
            return receipt

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            value["guest_import_source_lease_replacements"] = db.execute("SELECT * FROM guest_import_source_lease_replacements ORDER BY 1").fetchall()
        return value
