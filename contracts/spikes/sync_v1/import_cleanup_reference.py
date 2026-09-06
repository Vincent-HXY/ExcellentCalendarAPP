"""Import receipt/apply/guest retirement composition in isolated SQLite stores.

HTTP inputs are typed authenticated boundary values, as in the download oracle.
Execution rows model persisted Reminder/Notification state only; this does not
pretend to invoke Android alarms, destroy a production key, or delete an account.
"""
import json
import uuid

from bootstrap_reference import checkpoint
from counter_reference import MAXIMUM
from domain_reference import check, validate_schema
from import_lease_reference import AccountImportJournal, GuestImportSource, protected_owner_binding
from build_sync_storage_contract import derive as storage_model
from import_range_reference import ImportRangeStore
from protocol_reference import digest, encode, unwrap_terminal, validate_terminal_for_mutation
from sqlite_reference import connect
from source_retirement_reference import create_audit_tables, audit_rows, write_audit, retire_audits, read_affected


def cleanup_hash(receipt):
    return digest({key: value for key, value in receipt.items() if key != "receipt_hash"})


def check_cleanup(receipt):
    validate_schema("sync/guest_import_cleanup_receipt.schema.json", receipt)
    check(cleanup_hash(receipt) == receipt["receipt_hash"], "IMPORT_REFERENCE_INVALID")


class ImportCleanupServer(ImportRangeStore):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS import_cleanup_confirmations(lineage TEXT PRIMARY KEY,request TEXT NOT NULL,response TEXT NOT NULL);
            """)

    def cleanup_confirm(self, request, *, hook=None):
        validate_schema("sync/import_cleanup_confirm_request.schema.json", request)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            actor = self._recovery(db, request["device_id"])
            check(actor["sync_transport_generation"] == request["sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (request["device_id"],)).fetchone() is None, "DEVICE_REVOKED")
            # The confirmation identity is independent of the current caller and
            # CAS revision, so another registered device can retry a lost result.
            identity = {key: value for key, value in request.items() if key not in
                {"protocol_version", "device_id", "sync_transport_generation", "expected_import_revision"}}
            old = db.execute("SELECT request,response FROM import_cleanup_confirmations WHERE lineage=?", (request["import_lineage_id"],)).fetchone()
            if old:
                check(json.loads(old[0]) == identity, "IMPORT_VERSION_CONFLICT")
                return {**json.loads(old[1]), "disposition": "already_cleanup_confirmed"}
            head = db.execute("SELECT id,revision,manifest,publication FROM import_batches WHERE lineage=? ORDER BY revision DESC,id DESC LIMIT 1",
                (request["import_lineage_id"],)).fetchone()
            check(head is not None and head[0] == request["through_published_batch_id"] and head[3] is not None, "IMPORT_VERSION_CONFLICT")
            manifest = json.loads(head[2])
            check(head[1] == request["through_import_revision"] == request["expected_import_revision"], "IMPORT_VERSION_CONFLICT")
            check(all(manifest[name] == request[name] for name in ("source_workspace_id", "source_epoch", "source_snapshot_hash", "mapping_digest")), "IMPORT_LINEAGE_MISMATCH")
            check(head[1] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            result = {"disposition": "cleanup_confirmed", "import_lineage_id": request["import_lineage_id"],
                "source_workspace_id": request["source_workspace_id"], "source_epoch": request["source_epoch"],
                "resulting_import_revision": head[1] + 1, "confirmed_through_published_batch_id": head[0],
                "confirmed_through_import_revision": request["through_import_revision"], "guest_cleanup_receipt_hash": request["guest_cleanup_receipt_hash"]}
            validate_schema("sync/import_cleanup_confirm_response.schema.json", result)
            db.execute("UPDATE import_batches SET stage='completed',revision=? WHERE lineage=? AND publication IS NOT NULL", (head[1] + 1, request["import_lineage_id"]))
            checkpoint(hook, "import_server_cleanup_stage")
            db.execute("INSERT INTO import_cleanup_confirmations VALUES(?,?,?)", (request["import_lineage_id"], encode(identity), encode(result)))
            checkpoint(hook, "import_server_cleanup_receipt")
            return result

    def ack_only(self, request, *, hook=None):
        validate_schema("sync/sync_exchange_request.schema.json", request)
        check(request["mode"] == "ack_only", "SYNC_SEQUENCE_ROUTE_MISMATCH")
        self.exchange(request["device_id"], request["sync_transport_generation"], [],
            confirmed=request["acknowledged_client_sequence_through"], **({"hook": hook} if hook is not None else {}))
        response = {"protocol_version": 1, "device_id": request["device_id"], "sync_transport_generation": request["sync_transport_generation"],
            "mode": "ack_only", "results": [], "changes": [], "account_generation": None, "snapshot_upper_bound": None,
            "next_cursor": None, "has_more": False, "accepted_client_sequence_through": request["acknowledged_client_sequence_through"],
            "retention_floor_server_sequence": None, "resolved_conflict_cleanup_before": None}
        validate_schema("sync/sync_exchange_response.schema.json", response)
        return response

    def snapshot(self):
        value = super().snapshot()
        with self.connect() as db:
            value["import_cleanup_confirmations"] = db.execute("SELECT * FROM import_cleanup_confirmations ORDER BY 1").fetchall()
        return value


class AccountImportCleanup(AccountImportJournal):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(path) as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='sync_import_execution_cancellations'").fetchone() is None:
                db.execute(storage_model()["new_tables"]["sync_import_execution_cancellations"])
            db.executescript("""
                CREATE TABLE IF NOT EXISTS local_import_control(batch TEXT PRIMARY KEY,revision INTEGER NOT NULL,head TEXT NOT NULL,publication TEXT,cleanup TEXT,completed TEXT);
                CREATE TABLE IF NOT EXISTS local_import_effect_gates(sequence INTEGER PRIMARY KEY,batch TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_ack_requests(id TEXT PRIMARY KEY,payload TEXT NOT NULL,response TEXT);
                CREATE TABLE IF NOT EXISTS local_import_reminder_gates(batch TEXT PRIMARY KEY,source_receipt_hash TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_range_terminals(batch TEXT PRIMARY KEY,first_sequence INTEGER NOT NULL,last_sequence INTEGER NOT NULL,proof TEXT NOT NULL,receipt TEXT NOT NULL);
            """)

    def acknowledge_import(self, operation, results, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            receipt = self._receipt(db, operation)
            check(receipt is not None, "IMPORT_LINEAGE_MISMATCH")
            state = self._state(db)
            for result in results:
                terminal = unwrap_terminal(result)
                sequence = terminal["receipt"]["client_sequence"]
                check(terminal["receipt"]["device_id"] == self.device_id and
                    receipt["begin_client_sequence"] <= sequence <= receipt["terminal_client_sequence"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
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
                if mutation["operation_type"] == "import_commit":
                    stage = terminal["import_stage"]
                    revision = terminal["import_revision"] if terminal["status"] == "accepted" else terminal["next_revision"]
                    db.execute("INSERT INTO local_import_control VALUES(?,?,?,?,NULL,NULL) ON CONFLICT(batch) DO UPDATE SET revision=excluded.revision,publication=excluded.publication",
                        (receipt["batch_id"], revision, receipt["batch_id"], encode(terminal) if terminal["status"] == "accepted" else None))
                    db.execute("UPDATE local_import_operations SET stage=? WHERE operation=?", (stage, operation))
                elif receipt["stage"] == "local_staging":
                    db.execute("UPDATE local_import_operations SET stage='server_staging' WHERE operation=?", (operation,))
                    db.execute("INSERT OR IGNORE INTO local_import_control VALUES(?,1,?,NULL,NULL,NULL)", (receipt["batch_id"], receipt["batch_id"]))
                checkpoint(hook, "import_local_terminal")
            self._refresh_import_applied(db)
            self._advance_ack(db, state)
            self._save_state(db, state)
            checkpoint(hook, "import_local_ack_watermark")

    def _advance_ack(self, db, state):
        while True:
            before = state["local_ack"]
            super()._advance_ack(db, state)
            row = db.execute("SELECT last_sequence FROM local_import_range_terminals WHERE ? BETWEEN first_sequence AND last_sequence",
                (state["local_ack"] + 1,)).fetchone()
            if row:
                state["local_ack"] = row[0]
            if before == state["local_ack"]:
                return

    def accept_range_close(self, operation, proof, *, authority, hook=None):
        validate_schema("sync/import_range_close_proof.schema.json", proof)
        claims = {name: value for name, value in proof.items() if name not in {"proof_token", "proof_hash"}}
        check(authority.verify(self.account_id, "import_range_close", claims, proof["proof_token"], proof["proof_hash"]), "IMPORT_REFERENCE_INVALID")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            receipt = self._receipt(db, operation)
            check(receipt is not None and all(receipt[a] == proof[b] for a, b in (("batch_id", "import_batch_id"),
                ("source_workspace_id", "source_workspace_id"), ("source_epoch", "source_epoch"), ("import_lineage_id", "import_lineage_id"),
                ("manifest", "manifest"), ("begin_client_sequence", "begin_client_sequence"), ("terminal_client_sequence", "terminal_client_sequence"))), "IMPORT_LINEAGE_MISMATCH")
            check(proof["origin_device_id"] == self.device_id and proof["kind"] == "seen_range_closed" and
                proof["origin_sync_transport_generation"] == proof["recovery"]["sync_transport_generation"] == self.transport,
                "SYNC_TRANSPORT_GENERATION_MISMATCH")
            old = db.execute("SELECT proof,receipt FROM local_import_range_terminals WHERE batch=?", (receipt["batch_id"],)).fetchone()
            if old:
                check(json.loads(old[0]) == proof, "IMPORT_VERSION_CONFLICT")
                return json.loads(old[1])
            control = db.execute("SELECT revision,publication FROM local_import_control WHERE batch=?", (receipt["batch_id"],)).fetchone()
            check(control is None or (control[1] is None and control[0] <= proof["previous_import_revision"]), "IMPORT_VERSION_CONFLICT")
            check(db.execute("SELECT 1 FROM local_import_applied WHERE batch=?", (receipt["batch_id"],)).fetchone() is None, "IMPORT_PUBLISH_INCOMPLETE")
            frozen = []
            for sequence, value, raw in db.execute("SELECT sequence,hash,mutation FROM local_import_outbox WHERE batch=?", (receipt["batch_id"],)):
                mutation, actual = self._stored_mutation(db, sequence, raw)
                check(actual == value, "SYNC_OUTBOX_CORRUPTED")
                frozen.append({"client_sequence": sequence, "payload_hash": actual})
            for sequence, raw, result in db.execute("SELECT sequence,mutation,result FROM terminals WHERE sequence BETWEEN ? AND ?",
                    (receipt["begin_client_sequence"], receipt["terminal_client_sequence"])):
                mutation, actual = self._stored_mutation(db, sequence, raw)
                validate_terminal_for_mutation(json.loads(result), mutation)
                frozen.append({"client_sequence": sequence, "payload_hash": actual})
            frozen.sort(key=lambda value: value["client_sequence"])
            check(len(frozen) == receipt["terminal_client_sequence"] - receipt["begin_client_sequence"] + 1 and
                  len({value["client_sequence"] for value in frozen}) == len(frozen) and
                  digest(frozen) == receipt["outbox_mutation_digest"], "SYNC_OUTBOX_CORRUPTED")
            terminal = {"import_batch_id": receipt["batch_id"], "import_lineage_id": receipt["import_lineage_id"], "source_epoch": receipt["source_epoch"],
                "first_client_sequence": receipt["begin_client_sequence"], "last_client_sequence": receipt["terminal_client_sequence"],
                "proof_hash": proof["proof_hash"], "frozen_outbox_digest": receipt["outbox_mutation_digest"]}
            terminal["terminal_local_range_receipt_hash"] = digest(terminal)
            # Preserve every actual receipt. The compact proof supplies coverage
            # for the missing range; no unseen mutation gets a fabricated receipt.
            db.execute("DELETE FROM local_import_outbox WHERE batch=?", (receipt["batch_id"],))
            db.execute("INSERT INTO local_import_range_terminals VALUES(?,?,?,?,?)", (receipt["batch_id"], receipt["begin_client_sequence"],
                receipt["terminal_client_sequence"], encode(proof), encode(terminal)))
            checkpoint(hook, "import_local_range_terminal")
            stage = "abandoned" if proof["reason"] == "abandoned" and not proof["lineage_ever_published"] else \
                "repair_required" if proof["reason"] == "capacity_rejected" else "superseded"
            db.execute("UPDATE local_import_operations SET stage=? WHERE operation=?", (stage, operation))
            db.execute("INSERT INTO local_import_control VALUES(?,?,?,NULL,NULL,NULL) ON CONFLICT(batch) DO UPDATE SET revision=excluded.revision,head=excluded.head",
                (receipt["batch_id"], proof["resulting_import_revision"], proof["resulting_head_batch_id"]))
            state = self._state(db)
            recovery = proof["recovery"]
            check(recovery["client_confirmed_through"] <= state["local_ack"], "SYNC_ACK_WATERMARK_INVALID")
            if recovery["client_sequence_exhausted"]:
                state.update(next_sequence=None, exhausted=True)
            elif not state["exhausted"]:
                state["next_sequence"] = max(state["next_sequence"], recovery["next_client_sequence"])
            self._advance_ack(db, state)
            self._save_state(db, state)
            checkpoint(hook, "import_local_range_allocator_ack")
            return terminal

    def range_terminal_receipt(self, batch):
        with connect(self.path) as db:
            row = db.execute("SELECT receipt FROM local_import_range_terminals WHERE batch=?", (batch,)).fetchone()
            return None if row is None else json.loads(row[0])

    def _refresh_import_applied(self, db):
        for batch, raw in db.execute("SELECT batch,metadata FROM local_import_applied").fetchall():
            row = db.execute("SELECT operation,manifest,stage FROM local_import_operations WHERE batch=?", (batch,)).fetchone()
            if row is None:
                continue
            manifest, metadata = json.loads(row[1]), json.loads(raw)
            check(all(manifest[name] == metadata[name] for name in ("source_workspace_id", "source_epoch", "mapping_digest", "manifest_hash")), "IMPORT_LINEAGE_MISMATCH")
            if row[2] in {"local_staging", "server_staging", "server_confirmed", "publish_applied"}:
                db.execute("UPDATE local_import_operations SET stage='publish_applied' WHERE operation=?", (row[0],))
            db.execute("DELETE FROM local_import_effect_gates WHERE batch=?", (batch,))

    def _install_publication(self, db, messages, state, hook):
        super()._install_publication(db, messages, state, hook)
        self._refresh_import_applied(db)

    def _finalize_local_intents(self, db, state, metadata, hook):
        super()._finalize_local_intents(db, state, metadata, hook)
        self._refresh_import_applied(db)

    def publication_evidence(self, operation):
        with connect(self.path) as db:
            receipt = self._receipt(db, operation)
            check(receipt is not None and receipt["stage"] in {"publish_applied", "cleanup_pending", "completed"}, "IMPORT_PUBLISH_INCOMPLETE")
            row = db.execute("SELECT revision,head,publication FROM local_import_control WHERE batch=?", (receipt["batch_id"],)).fetchone()
            check(row is not None and row[1] == receipt["batch_id"] and row[2] is not None, "IMPORT_PUBLISH_INCOMPLETE")
            applied = db.execute("SELECT metadata FROM local_import_applied WHERE batch=?", (receipt["batch_id"],)).fetchone()
            check(applied is not None, "IMPORT_PUBLISH_INCOMPLETE")
            metadata, terminal = json.loads(applied[0]), json.loads(row[2])
            check(metadata["import_publish_group_id"] == terminal["publish_group_id"] and metadata["publish_digest"] == terminal["canonical_digest"] and
                metadata["commit_server_sequence"] == terminal["commit_server_sequence"], "IMPORT_PUBLISH_INCOMPLETE")
            return {**receipt, "through_import_revision": terminal["import_revision"], "current_import_revision": row[0], "publication": metadata}

    def observe_retirement(self, guest, receipt, *, operation, hook=None):
        check_cleanup(receipt)
        # This read is an actual durable guest receipt, never a caller boolean.
        check(guest.cleanup_receipt(receipt["source_epoch"]) == receipt, "IMPORT_REFERENCE_INVALID")
        affected = guest.affected_execution(receipt["source_epoch"])
        check(affected["retirement_receipt_hash"] == receipt["receipt_hash"], "IMPORT_REFERENCE_INVALID")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            local = self._receipt(db, operation)
            check(local is not None and local["batch_id"] == receipt["through_published_batch_id"] and
                local["import_lineage_id"] == receipt["import_lineage_id"] and local["manifest"]["source_snapshot_hash"] == receipt["source_snapshot_hash"], "IMPORT_LINEAGE_MISMATCH")
            check(db.execute("SELECT 1 FROM local_import_applied WHERE batch=?", (local["batch_id"],)).fetchone() is not None, "IMPORT_PUBLISH_INCOMPLETE")
            db.execute("UPDATE local_import_control SET cleanup=? WHERE batch=?", (encode(receipt), local["batch_id"]))
            db.execute("INSERT OR REPLACE INTO sync_import_execution_cancellations VALUES(?,?,?,?,?,?,?)",
                (local["batch_id"], receipt["source_workspace_id"], receipt["source_epoch"], receipt["receipt_hash"], 1, encode(affected), digest(affected)))
            db.execute("UPDATE local_import_operations SET stage='cleanup_pending' WHERE operation=? AND stage!='completed'", (operation,))
            db.execute("INSERT OR IGNORE INTO local_import_reminder_gates VALUES(?,?)", (local["batch_id"], receipt["receipt_hash"]))
            checkpoint(hook, "import_account_retirement_observed")

    def reminder_materialization_allowed(self, batch):
        with connect(self.path) as db:
            return db.execute("SELECT 1 FROM local_import_reminder_gates WHERE batch=?", (batch,)).fetchone() is not None

    def cleanup_request(self, operation):
        with connect(self.path) as db:
            local = self._receipt(db, operation)
            check(local is not None, "IMPORT_LINEAGE_MISMATCH")
            row = db.execute("SELECT revision,cleanup FROM local_import_control WHERE batch=?", (local["batch_id"],)).fetchone()
            check(row is not None and row[1] is not None, "IMPORT_PUBLISH_INCOMPLETE")
            receipt = json.loads(row[1])
            request = {"protocol_version": 1, "device_id": self.device_id, "sync_transport_generation": self.transport,
                **{name: receipt[name] for name in ("import_lineage_id", "source_workspace_id", "source_epoch", "through_published_batch_id",
                    "through_import_revision", "source_snapshot_hash", "mapping_digest")}, "guest_cleanup_receipt_hash": receipt["receipt_hash"], "expected_import_revision": row[0]}
            validate_schema("sync/import_cleanup_confirm_request.schema.json", request)
            return request

    def accept_cleanup(self, receipt, response, *, hook=None):
        check_cleanup(receipt)
        validate_schema("sync/import_cleanup_confirm_response.schema.json", response)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT revision,cleanup,completed FROM local_import_control WHERE batch=?", (receipt["through_published_batch_id"],)).fetchone()
            check(row is not None and json.loads(row[1]) == receipt, "IMPORT_REFERENCE_INVALID")
            check(all(response[a] == receipt[b] for a, b in (("import_lineage_id", "import_lineage_id"), ("source_workspace_id", "source_workspace_id"),
                ("source_epoch", "source_epoch"), ("confirmed_through_published_batch_id", "through_published_batch_id"),
                ("confirmed_through_import_revision", "through_import_revision"), ("guest_cleanup_receipt_hash", "receipt_hash"))), "IMPORT_LINEAGE_MISMATCH")
            normalized = {**response, "disposition": "cleanup_confirmed"}
            if row[2] is not None:
                check(json.loads(row[2])["server_confirmation"] == normalized, "IMPORT_VERSION_CONFLICT")
                return json.loads(row[2])
            check(response["resulting_import_revision"] == row[0] + 1 <= MAXIMUM, "IMPORT_VERSION_CONFLICT")
            completed = {"guest_receipt": receipt, "server_confirmation": normalized}
            completed["native_completed_receipt_hash"] = digest(completed)
            db.execute("UPDATE local_import_control SET revision=?,completed=? WHERE batch=?", (response["resulting_import_revision"], encode(completed), receipt["through_published_batch_id"]))
            db.execute("UPDATE local_import_operations SET stage='completed' WHERE batch=?", (receipt["through_published_batch_id"],))
            checkpoint(hook, "import_native_cleanup_completed")
            return completed

    def completed_receipt(self, batch):
        with connect(self.path) as db:
            row = db.execute("SELECT completed FROM local_import_control WHERE batch=?", (batch,)).fetchone()
            return None if row is None or row[0] is None else json.loads(row[0])

    def prepare_ack_only(self):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            state = self._state(db)
            if state["server_ack"] == state["local_ack"]:
                return None
            request = {"protocol_version": 1, "device_id": self.device_id, "sync_transport_generation": self.transport,
                "mode": "ack_only", "cursor": None, "acknowledged_client_sequence_through": state["local_ack"], "upload_mutations": [], "download_limit": 0}
            validate_schema("sync/sync_exchange_request.schema.json", request)
            identifier = str(uuid.uuid4())
            db.execute("INSERT INTO local_import_ack_requests VALUES(?,?,NULL)", (identifier, encode(request)))
            return identifier, request

    def accept_ack_only(self, identifier, response, *, hook=None):
        validate_schema("sync/sync_exchange_response.schema.json", response)
        check(response["mode"] == "ack_only", "SYNC_SEQUENCE_ROUTE_MISMATCH")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT payload,response FROM local_import_ack_requests WHERE id=?", (identifier,)).fetchone()
            check(row is not None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            request, state = json.loads(row[0]), self._state(db)
            check(response["device_id"] == request["device_id"] == self.device_id and
                response["sync_transport_generation"] == request["sync_transport_generation"] == self.transport and
                response["accepted_client_sequence_through"] == request["acknowledged_client_sequence_through"], "SYNC_ACK_WATERMARK_INVALID")
            if row[1] is not None:
                check(json.loads(row[1]) == response, "SYNC_ACK_WATERMARK_INVALID")
                return
            check(state["server_ack"] <= response["accepted_client_sequence_through"] <= state["local_ack"], "SYNC_ACK_WATERMARK_INVALID")
            state["server_ack"] = response["accepted_client_sequence_through"]
            self._save_state(db, state)
            db.execute("UPDATE local_import_ack_requests SET response=? WHERE id=?", (encode(response), identifier))
            checkpoint(hook, "import_ack_only_accepted")

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            for table in ("local_import_control", "local_import_effect_gates", "local_import_ack_requests", "local_import_reminder_gates", "local_import_range_terminals", "sync_import_execution_cancellations"):
                value[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return value


class GuestImportCleanup(GuestImportSource):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(path) as db:
            create_audit_tables(db)
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='guest_import_execution_retirements'").fetchone() is None:
                db.execute(storage_model()["new_tables"]["guest_import_execution_retirements"])
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='guest_import_source_lease_terminals'").fetchone() is None:
                db.execute(storage_model()["new_tables"]["guest_import_source_lease_terminals"])
            db.executescript("""
                CREATE TABLE IF NOT EXISTS guest_search_history(position INTEGER PRIMARY KEY,keyword TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS guest_lease_release_receipts(operation TEXT PRIMARY KEY,identity TEXT NOT NULL,result TEXT NOT NULL);
            """)

    @staticmethod
    def _cleanup_receipt(db, epoch):
        row = db.execute("SELECT source_workspace_id,source_epoch,lineage_id,through_published_batch_id,import_revision,source_snapshot_hash,mapping_digest,cleaned_at,receipt_hash "
            "FROM guest_import_cleanup_receipts WHERE source_epoch=?", (epoch,)).fetchone()
        return None if row is None else dict(zip(("source_workspace_id", "source_epoch", "import_lineage_id", "through_published_batch_id", "through_import_revision",
            "source_snapshot_hash", "mapping_digest", "cleaned_at", "receipt_hash"), row))

    def cleanup_receipt(self, epoch):
        with connect(self.path) as db:
            return self._cleanup_receipt(db, epoch)

    def affected_execution(self, epoch):
        with connect(self.path) as db:
            value = read_affected(db, epoch)
            receipt = self._cleanup_receipt(db, epoch)
            check(receipt is not None and value["retirement_receipt_hash"] == receipt["receipt_hash"], "IMPORT_REFERENCE_INVALID")
            return value

    def retire(self, account, operation, *, now, hook=None):
        # Guest -> account is the same global lock order as reservation/recovery.
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
                len(records) == evidence["manifest"]["total_item_count"], "IMPORT_REFERENCE_INVALID")
            check(lease["lease_revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            receipt = {"source_workspace_id": self.workspace_id, "source_epoch": epoch, "import_lineage_id": evidence["import_lineage_id"],
                "through_published_batch_id": evidence["batch_id"], "through_import_revision": evidence["through_import_revision"],
                "source_snapshot_hash": source_hash, "mapping_digest": evidence["manifest"]["mapping_digest"], "cleaned_at": now}
            receipt["receipt_hash"] = cleanup_hash(receipt)
            check_cleanup(receipt)
            identities = {(row["target_type"], row["target_id"]) for row in records}
            retire_audits(db, identities, receipt, now)
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

    def finalize_notification(self, notification, *, now=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = next((value for key, _, value in audit_rows(db, "notifications") if key == notification), None)
            check(row is not None, "IMPORT_REFERENCE_INVALID")
            if row["status"] != "prepared":
                return "no_effect"
            parent = next((value for key, _, value in audit_rows(db, "reminders") if key == row["reminder_id"]), None)
            if parent is None or parent["last_cancellation_reason"] == "source_migrated":
                return "no_effect"
            check(now is not None, "IMPORT_REFERENCE_INVALID")
            row.update(status="sent", sent_at=now, finalized_at=now, updated_at=now)
            write_audit(db, "notifications", row)
            return "sent"

    def release_completed(self, account, completed, *, expected_source_lease_revision=None, hook=None):
        receipt = completed["guest_receipt"]
        check_cleanup(receipt)
        identity = {"source_workspace_id": receipt["source_workspace_id"], "source_epoch": receipt["source_epoch"],
            "import_lineage_id": receipt["import_lineage_id"], "protected_owner_binding_digest": account.owner_binding,
            "native_completed_receipt_hash": completed["native_completed_receipt_hash"]}
        key = completed["native_completed_receipt_hash"]
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT identity,result FROM guest_lease_release_receipts WHERE operation=?", (key,)).fetchone()
            if old:
                check(json.loads(old[0]) == identity, "IMPORT_LINEAGE_MISMATCH")
                return json.loads(old[1])
            lease = self._lease(db)
            check(lease is not None and lease["source_epoch"] == receipt["source_epoch"] and lease["lineage_id"] == receipt["import_lineage_id"] and
                lease["protected_owner_binding_digest"] == account.owner_binding and lease["active_batch_id"] == receipt["through_published_batch_id"], "IMPORT_SOURCE_OWNED")
            if expected_source_lease_revision is not None:
                check(lease["lease_revision"] == expected_source_lease_revision, "IMPORT_VERSION_CONFLICT")
            check(account.completed_receipt(receipt["through_published_batch_id"]) == completed and
                self._cleanup_receipt(db, receipt["source_epoch"]) == receipt, "IMPORT_REFERENCE_INVALID")
            check(db.execute("SELECT previous_epoch_cleanup_pending FROM workspace_metadata").fetchone()[0] == receipt["source_epoch"], "IMPORT_LINEAGE_MISMATCH")
            db.execute("UPDATE guest_import_cleanup_receipts SET state='completed' WHERE source_epoch=?", (receipt["source_epoch"],))
            db.execute("UPDATE workspace_metadata SET previous_epoch_cleanup_pending=NULL")
            db.execute("DELETE FROM guest_import_source_leases")
            db.execute("DELETE FROM guest_import_previews")
            result = {"disposition": "released", "source_epoch": receipt["source_epoch"], "receipt_hash": key}
            db.execute("INSERT INTO guest_import_source_lease_terminals VALUES(?,?,?,?,?,?,?,?)", (digest(identity), self.workspace_id,
                receipt["source_epoch"], receipt["import_lineage_id"], account.owner_binding, lease["lease_revision"], "cleanup_completed", key))
            db.execute("INSERT INTO guest_lease_release_receipts VALUES(?,?,?)", (key, encode(identity), encode(result)))
            checkpoint(hook, "import_guest_completed_release")
            return result

    def release_account_deleted(self, request, *, expected_account_id, installation_key, authority, hook=None):
        validate_schema("workspace/import_finalize_source_lease_request.schema.json", request)
        proof = request["proof"]
        check(proof["kind"] == "account_deleted" and request["source_workspace_id"] == self.workspace_id, "IMPORT_SOURCE_OWNED")
        owner = protected_owner_binding(expected_account_id, installation_key)
        check(owner == request["protected_owner_binding_digest"], "IMPORT_SOURCE_OWNED")
        check(authority.verify(expected_account_id, "account_deleted", {"account_id": expected_account_id, "state": "deleted"},
            proof["owner_bound_account_deleted_proof"], proof["deletion_receipt_hash"]), "IMPORT_REFERENCE_INVALID")
        # A proof may authorize several outstanding leases of the deleted owner.
        # The durable local result is separately bound to this source/epoch/CAS.
        identity = {key: value for key, value in request.items() if key != "proof"}
        identity.update(proof_kind="account_deleted", proof_receipt_hash=proof["deletion_receipt_hash"])
        key = digest(identity)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT identity,result FROM guest_lease_release_receipts WHERE operation=?", (key,)).fetchone()
            if old:
                check(json.loads(old[0]) == identity, "IMPORT_LINEAGE_MISMATCH")
                return json.loads(old[1])
            lease = self._lease(db)
            check(lease is not None and all(lease[a] == request[b] for a, b in (("source_workspace_id", "source_workspace_id"),
                ("source_epoch", "source_epoch"), ("lineage_id", "import_lineage_id"), ("protected_owner_binding_digest", "protected_owner_binding_digest"))), "IMPORT_SOURCE_OWNED")
            check(lease["lease_revision"] == request["expected_source_lease_revision"], "IMPORT_VERSION_CONFLICT")
            db.execute("UPDATE guest_import_cleanup_receipts SET state='account_deleted' WHERE source_epoch=? AND lineage_id=?",
                (request["source_epoch"], request["import_lineage_id"]))
            db.execute("UPDATE workspace_metadata SET previous_epoch_cleanup_pending=NULL WHERE previous_epoch_cleanup_pending=?", (request["source_epoch"],))
            db.execute("DELETE FROM guest_import_source_leases WHERE source_workspace_id=?", (self.workspace_id,))
            db.execute("DELETE FROM guest_import_previews")
            result = {"disposition": "released", "source_epoch": request["source_epoch"], "receipt_hash": key}
            db.execute("INSERT INTO guest_import_source_lease_terminals VALUES(?,?,?,?,?,?,?,?)", (key, self.workspace_id, request["source_epoch"],
                request["import_lineage_id"], owner, lease["lease_revision"], "account_deleted", proof["deletion_receipt_hash"]))
            db.execute("INSERT INTO guest_lease_release_receipts VALUES(?,?,?)", (key, encode(identity), encode(result)))
            checkpoint(hook, "import_guest_account_deleted_release")
            return result

    def release_abandoned(self, request, account, *, authority, hook=None):
        validate_schema("workspace/import_finalize_source_lease_request.schema.json", request)
        proof = request["proof"]
        check(proof["kind"] == "prepublish_abandon_range_terminal" and request["source_workspace_id"] == self.workspace_id and
            request["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
        response = proof["server_abandon"]
        check(response["disposition"] in {"abandoned", "already_abandoned"} and response["proof"] is not None, "IMPORT_SOURCE_OWNED")
        closed = response["proof"]
        check(not closed["lineage_ever_published"], "IMPORT_SOURCE_OWNED")
        check(closed["reason"] == "abandoned" and all(closed[name] == request[name] for name in
            ("source_workspace_id", "source_epoch", "import_lineage_id")), "IMPORT_LINEAGE_MISMATCH")
        check(authority.verify(account.account_id, "import_range_close", {key: value for key, value in closed.items()
            if key not in {"proof_token", "proof_hash"}}, closed["proof_token"], closed["proof_hash"]), "IMPORT_REFERENCE_INVALID")
        identity = {key: value for key, value in request.items() if key != "proof"}
        identity.update(proof_kind=proof["kind"], proof_receipt_hash=proof["terminal_local_range_receipt_hash"])
        key = digest(identity)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT identity,result FROM guest_lease_release_receipts WHERE operation=?", (key,)).fetchone()
            if old:
                check(json.loads(old[0]) == identity, "IMPORT_LINEAGE_MISMATCH")
                return json.loads(old[1])
            lease = self._lease(db)
            check(lease is not None and lease["state"] == "active" and lease["source_epoch"] == request["source_epoch"] and
                lease["lineage_id"] == request["import_lineage_id"] and lease["protected_owner_binding_digest"] == account.owner_binding and
                lease["active_batch_id"] == closed["import_batch_id"], "IMPORT_SOURCE_OWNED")
            check(lease["lease_revision"] == request["expected_source_lease_revision"], "IMPORT_VERSION_CONFLICT")
            check(self._cleanup_receipt(db, request["source_epoch"]) is None, "IMPORT_SOURCE_OWNED")
            terminal = account.range_terminal_receipt(closed["import_batch_id"])
            check(terminal is not None and terminal["proof_hash"] == closed["proof_hash"] and
                terminal["terminal_local_range_receipt_hash"] == proof["terminal_local_range_receipt_hash"], "IMPORT_REFERENCE_INVALID")
            db.execute("DELETE FROM guest_import_source_leases")
            db.execute("DELETE FROM guest_import_previews")
            result = {"disposition": "released", "source_epoch": request["source_epoch"], "receipt_hash": key}
            db.execute("INSERT INTO guest_import_source_lease_terminals VALUES(?,?,?,?,?,?,?,?)", (key, self.workspace_id, request["source_epoch"],
                request["import_lineage_id"], account.owner_binding, lease["lease_revision"], proof["kind"], proof["terminal_local_range_receipt_hash"]))
            db.execute("INSERT INTO guest_lease_release_receipts VALUES(?,?,?)", (key, encode(identity), encode(result)))
            checkpoint(hook, "import_guest_abandoned_release")
            return result

    def release_destroyed(self, request, *, journal, authority, hook=None):
        """Consume an authenticated trusted-owner journal after account DB loss.

        The journal's finality is an owner precondition, never inferred from a
        missing database/key. Android deletion itself belongs to the OS spike.
        """
        validate_schema("workspace/import_finalize_source_lease_request.schema.json", request)
        proof = request["proof"]
        check(proof["kind"] == "prepublish_abandon_crypto_destroyed", "IMPORT_SOURCE_OWNED")
        final = journal.load("crypto_destroy_final", proof["crypto_destroy_final_receipt_hash"])
        validate_schema("workspace/private/crypto_destroy_final_receipt.schema.json", final)
        check(all(request[key] == final[key] for key in ("source_workspace_id", "source_epoch", "import_lineage_id",
            "protected_owner_binding_digest", "expected_source_lease_revision")), "IMPORT_SOURCE_OWNED")
        response = proof["server_abandon"]
        closed = response.get("proof")
        check(response["disposition"] in {"abandoned", "already_abandoned"} and closed is not None and
            closed["reason"] == "abandoned" and not closed["lineage_ever_published"], "IMPORT_SOURCE_OWNED")
        check(all(closed[key] == final[key] for key in ("source_workspace_id", "source_epoch", "import_lineage_id", "import_batch_id")) and
            closed["manifest"]["manifest_hash"] == final["manifest_hash"] and closed["origin_device_id"] == final["device_id"] and
            closed["origin_sync_transport_generation"] <= final["sync_transport_generation"], "IMPORT_LINEAGE_MISMATCH")
        check(authority.verify(final["account_id"], "import_range_close", {key: value for key, value in closed.items()
            if key not in {"proof_token", "proof_hash"}}, closed["proof_token"], closed["proof_hash"]), "IMPORT_REFERENCE_INVALID")
        identity = {key: value for key, value in request.items() if key != "proof"}
        identity.update(proof_kind=proof["kind"], proof_receipt_hash=proof["crypto_destroy_final_receipt_hash"])
        key = digest(identity)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT identity,result FROM guest_lease_release_receipts WHERE operation=?", (key,)).fetchone()
            if old:
                check(json.loads(old[0]) == identity, "IMPORT_LINEAGE_MISMATCH")
                return json.loads(old[1])
            lease = self._lease(db)
            check(request["source_workspace_id"] == self.workspace_id and lease is not None and lease["state"] == "active" and
                lease["source_epoch"] == final["source_epoch"] and lease["lineage_id"] == final["import_lineage_id"] and
                lease["protected_owner_binding_digest"] == final["protected_owner_binding_digest"] and
                lease["active_batch_id"] == final["import_batch_id"] and lease["active_manifest_hash"] == final["manifest_hash"], "IMPORT_SOURCE_OWNED")
            check(lease["lease_revision"] == request["expected_source_lease_revision"], "IMPORT_VERSION_CONFLICT")
            check(self._cleanup_receipt(db, request["source_epoch"]) is None, "IMPORT_SOURCE_OWNED")
            db.execute("DELETE FROM guest_import_source_leases")
            db.execute("DELETE FROM guest_import_previews")
            result = {"disposition": "released", "source_epoch": request["source_epoch"], "receipt_hash": key}
            db.execute("INSERT INTO guest_import_source_lease_terminals VALUES(?,?,?,?,?,?,?,?)", (key, self.workspace_id, request["source_epoch"],
                request["import_lineage_id"], final["protected_owner_binding_digest"], lease["lease_revision"], proof["kind"], proof["crypto_destroy_final_receipt_hash"]))
            db.execute("INSERT INTO guest_lease_release_receipts VALUES(?,?,?)", (key, encode(identity), encode(result)))
            checkpoint(hook, "import_guest_destroyed_release")
            return result

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            for table in ("reminders", "notifications", "guest_import_execution_retirements", "guest_search_history", "guest_lease_release_receipts", "guest_import_source_lease_terminals"):
                value[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return value
