"""Initial guest/account import reservation across two actual SQLite databases.

Guest stores an opaque owner digest, never an account UUID or credential. Network
preparation requires the durable guest active lease and the exact account receipt.
Encryption and the production Android transport remain separate implementations.
"""
import base64
import hashlib
import hmac
import json
import secrets
import uuid

from bootstrap_reference import CAPS, checkpoint
from build_sync_storage_contract import derive as storage_model
from counter_reference import MAXIMUM
from domain_reference import check, validate_graph, validate_schema
from identity_reference import canonical_uuid
from import_download_reference import ImportDownloadStore
from import_staging_reference import build_initial_batch
from protocol_reference import canonical, digest, encode, mutation_hash
from sqlite_reference import connect


def protected_owner_binding(account_id, installation_key):
    canonical_uuid(account_id, 4)
    check(isinstance(installation_key, bytes) and len(installation_key) == 32, "WORKSPACE_KEY_UNAVAILABLE")
    return hmac.new(installation_key, b"ExcellentCalendar.GuestImportOwner.v1\n" + account_id.encode("ascii"), hashlib.sha256).hexdigest()


class AccountImportJournal(ImportDownloadStore):
    def __init__(self, path, *, account_id, installation_key, **kwargs):
        self.account_id = canonical_uuid(account_id, 4)
        self.owner_binding = protected_owner_binding(account_id, installation_key)
        super().__init__(path, **kwargs)
        with connect(path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS local_import_owner(singleton INTEGER PRIMARY KEY CHECK(singleton=1),account_id TEXT NOT NULL,owner_binding TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_operations(operation TEXT PRIMARY KEY,batch TEXT UNIQUE NOT NULL,source TEXT NOT NULL,
                    epoch INTEGER NOT NULL,lineage TEXT NOT NULL,owner_binding TEXT NOT NULL,manifest TEXT NOT NULL,
                    begin_sequence INTEGER NOT NULL,terminal_sequence INTEGER NOT NULL,outbox_digest TEXT NOT NULL,stage TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_outbox(sequence INTEGER PRIMARY KEY,batch TEXT NOT NULL,hash TEXT NOT NULL,mutation TEXT NOT NULL,
                    prepared INTEGER NOT NULL,UNIQUE(batch,sequence));
            """)
            db.execute("INSERT OR IGNORE INTO local_import_owner VALUES(1,?,?)", (self.account_id, self.owner_binding))
            check(db.execute("SELECT account_id,owner_binding FROM local_import_owner").fetchone() == (self.account_id, self.owner_binding), "WORKSPACE_ACCOUNT_MISMATCH")

    @staticmethod
    def _receipt(db, operation):
        row = db.execute("SELECT batch,source,epoch,lineage,owner_binding,manifest,begin_sequence,terminal_sequence,outbox_digest,stage "
            "FROM local_import_operations WHERE operation=?", (operation,)).fetchone()
        if row is None:
            return None
        return {"operation_id": operation, "batch_id": row[0], "source_workspace_id": row[1], "source_epoch": row[2], "import_lineage_id": row[3],
            "protected_owner_binding_digest": row[4], "manifest": json.loads(row[5]), "begin_client_sequence": row[6],
            "terminal_client_sequence": row[7], "outbox_mutation_digest": row[8], "stage": row[9]}

    def receipt(self, operation):
        with connect(self.path) as db:
            return self._receipt(db, operation)

    def stage_reserved(self, preview, *, operation, hook=None):
        check(preview["owner_binding"] == self.owner_binding, "WORKSPACE_ACCOUNT_MISMATCH")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            existing = self._receipt(db, operation)
            if existing:
                check(existing["batch_id"] == preview["response"]["proposed_import_batch_id"] and existing["manifest"] == preview["response"]["manifest"], "IMPORT_LINEAGE_MISMATCH")
                return existing
            self._not_rebuilding(db)
            state = self._state(db)
            check(not state["fresh"], "SYNC_BOOTSTRAP_INCOMPLETE")
            check(not state["exhausted"], "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
            response = preview["response"]
            batch = build_initial_batch(self.account_id, response["source_workspace_id"], response["source_epoch"], preview["records"],
                begin_sequence=state["next_sequence"], batch_id=response["proposed_import_batch_id"], source_snapshot_hash=response["manifest"]["source_snapshot_hash"])
            check(batch[0]["payload"]["manifest"] == response["manifest"] and batch[0]["import_lineage_id"] == response["import_lineage_id"], "IMPORT_LINEAGE_MISMATCH")
            binding = {"operation_id": operation, "batch_id": response["proposed_import_batch_id"], "source_workspace_id": response["source_workspace_id"],
                "source_epoch": response["source_epoch"], "import_lineage_id": response["import_lineage_id"], "protected_owner_binding_digest": self.owner_binding,
                "manifest": response["manifest"], "begin_client_sequence": batch[0]["client_sequence"], "terminal_client_sequence": batch[-1]["client_sequence"],
                "outbox_mutation_digest": digest([{ "client_sequence": row["client_sequence"], "payload_hash": mutation_hash(row)} for row in batch]), "stage": "local_staging"}
            for row in batch:
                db.execute("INSERT INTO local_import_outbox VALUES(?,?,?,?,0)", (row["client_sequence"], binding["batch_id"], mutation_hash(row), encode(row)))
                db.execute("INSERT INTO frozen_intents VALUES(?,?,?)", (row["client_sequence"], mutation_hash(row), row["mutation_id"]))
            checkpoint(hook, "import_account_outbox")
            db.execute("INSERT INTO local_import_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)", (operation, binding["batch_id"], binding["source_workspace_id"],
                binding["source_epoch"], binding["import_lineage_id"], self.owner_binding, encode(binding["manifest"]), binding["begin_client_sequence"],
                binding["terminal_client_sequence"], binding["outbox_mutation_digest"], "local_staging"))
            checkpoint(hook, "import_account_operation_receipt")
            last = binding["terminal_client_sequence"]
            state.update(next_sequence=None if last == MAXIMUM else last + 1, exhausted=last == MAXIMUM)
            self._save_state(db, state)
            checkpoint(hook, "import_account_allocator")
            return binding

    def prepare_import(self, guest, operation, *, after_sequence=0):
        receipt = self.receipt(operation)
        check(receipt is not None, "IMPORT_LINEAGE_MISMATCH")
        if receipt["stage"] not in {"local_staging", "server_staging"}:
            return []
        guest.require_active(receipt)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            current = self._receipt(db, operation)
            check(current == receipt, "IMPORT_VERSION_CONFLICT")
            rows = db.execute("SELECT sequence,hash,mutation FROM local_import_outbox WHERE batch=? ORDER BY sequence", (receipt["batch_id"],)).fetchall()
            terminal_rows = [(sequence, mutation_hash(json.loads(raw)), raw) for sequence, raw in db.execute(
                "SELECT sequence,mutation FROM terminals WHERE sequence BETWEEN ? AND ? ORDER BY sequence",
                (receipt["begin_client_sequence"], receipt["terminal_client_sequence"]))]
            complete = sorted(rows + terminal_rows)
            check(len(complete) == receipt["terminal_client_sequence"] - receipt["begin_client_sequence"] + 1 and
                len({row[0] for row in complete}) == len(complete) and
                digest([{ "client_sequence": sequence, "payload_hash": value} for sequence, value, raw in complete]) == receipt["outbox_mutation_digest"], "SYNC_OUTBOX_CORRUPTED")
            selected = []
            for sequence, value, raw in rows:
                mutation = json.loads(raw)
                check(mutation_hash(mutation) == value and mutation["client_sequence"] == sequence, "SYNC_OUTBOX_CORRUPTED")
                if sequence <= after_sequence:
                    continue
                candidate = selected + [{"mutation": mutation, "payload_hash": value}]
                if len(candidate) > 100 or len(canonical(candidate)) > CAPS["decompressed_request_hard_bytes"]:
                    break
                selected = candidate
                db.execute("UPDATE local_import_outbox SET prepared=1 WHERE sequence=?", (sequence,))
            return selected

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            for name in ("local_import_owner", "local_import_operations", "local_import_outbox"):
                value[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return value


class GuestImportSource:
    def __init__(self, path, *, workspace_id):
        self.path, self.workspace_id = path, canonical_uuid(workspace_id, 4)
        definition = storage_model()
        with connect(path) as db:
            db.execute("PRAGMA journal_mode=WAL")
            for name in ("workspace_metadata", "guest_import_source_leases", "guest_import_cleanup_receipts", "guest_import_audit_anchors"):
                if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is None:
                    db.execute(definition["new_tables"][name])
            db.execute("INSERT OR IGNORE INTO workspace_metadata VALUES(1,?,'local',NULL,6,'guest_plaintext_v1','2026-09-06T00:00:00Z',0,NULL,0,0)", (self.workspace_id,))
            check(db.execute("SELECT workspace_id FROM workspace_metadata").fetchone()[0] == self.workspace_id, "WORKSPACE_ACCOUNT_MISMATCH")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS guest_import_source_facts(target TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,revision INTEGER NOT NULL,PRIMARY KEY(target,id));
                CREATE TABLE IF NOT EXISTS guest_import_previews(token TEXT PRIMARY KEY,operation TEXT NOT NULL UNIQUE,payload TEXT NOT NULL);
            """)

    @staticmethod
    def _source(db):
        rows = [(target, identifier, json.loads(raw), revision) for target, identifier, raw, revision in
            db.execute("SELECT * FROM guest_import_source_facts ORDER BY target,id")]
        records = [row[2] for row in rows]
        validate_graph(records)
        epoch = db.execute("SELECT current_import_source_epoch FROM workspace_metadata").fetchone()[0]
        snapshot_hash = digest({"source_epoch": epoch, "items": [{"record": row[2], "local_version": row[3]} for row in rows]})
        return records, snapshot_hash

    def write(self, record):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT revision FROM guest_import_source_facts WHERE target=? AND id=?", (record["target_type"], record["target_id"])).fetchone()
            revision = old[0] if old else 0
            check(revision < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            db.execute("INSERT OR REPLACE INTO guest_import_source_facts VALUES(?,?,?,?)", (record["target_type"], record["target_id"], encode(record), revision + 1))
            self._source(db)

    def seed(self, records):
        validate_graph(records)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            check(db.execute("SELECT count(*) FROM guest_import_source_facts").fetchone()[0] == 0, "IMPORT_REFERENCE_INVALID")
            db.executemany("INSERT INTO guest_import_source_facts VALUES(?,?,?,1)", ((row["target_type"], row["target_id"], encode(row)) for row in records))

    @staticmethod
    def _lease(db):
        db.row_factory = __import__("sqlite3").Row
        row = db.execute("SELECT * FROM guest_import_source_leases").fetchone()
        db.row_factory = None
        return None if row is None else dict(row)

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
            check(lease is None, "IMPORT_SOURCE_OWNED")
            records, snapshot_hash = self._source(db)
            batch = build_initial_batch(account.account_id, self.workspace_id, epoch, records, source_snapshot_hash=snapshot_hash)
            response = {"disposition": "ready", "source_workspace_id": self.workspace_id, "target_workspace_id": target_workspace_id,
                "source_epoch": epoch, "preview_token": secrets.token_urlsafe(32), "proposed_import_batch_id": batch[0]["import_batch_id"],
                "import_lineage_id": batch[0]["import_lineage_id"], "manifest": batch[0]["payload"]["manifest"], "warnings": []}
            validate_schema("workspace/import_preview_response.schema.json", response)
            value = {"response": response, "records": records, "owner_binding": account.owner_binding}
            db.execute("INSERT INTO guest_import_previews VALUES(?,?,?)", (response["preview_token"], str(uuid.uuid4()), encode(value)))
            return response

    def commit(self, account, token, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT operation,payload FROM guest_import_previews WHERE token=?", (token,)).fetchone()
            check(row is not None, "IMPORT_REFERENCE_INVALID")
            operation, preview = row[0], json.loads(row[1])
            check(preview["owner_binding"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            response = preview["response"]
            lease = self._lease(db)
            if lease:
                check(lease["reserved_operation_id"] == operation and lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            else:
                epoch, pending, exhausted = db.execute("SELECT current_import_source_epoch,previous_epoch_cleanup_pending,source_epoch_exhausted FROM workspace_metadata").fetchone()
                check(not exhausted, "IMPORT_SOURCE_EPOCH_EXHAUSTED")
                check(pending is None and epoch == response["source_epoch"] and self._source(db)[1] == response["manifest"]["source_snapshot_hash"], "IMPORT_REFERENCE_INVALID")
                db.execute("INSERT INTO guest_import_source_leases VALUES(?,?,?,?,?,?,NULL,NULL,NULL,NULL,'reserved',1)",
                    (self.workspace_id, epoch, response["import_lineage_id"], account.owner_binding, response["manifest"]["source_snapshot_hash"], operation))
            checkpoint(hook, "import_guest_reserved")
        checkpoint(hook, "import_guest_reserved_committed")
        # Every dual-store path acquires guest before account. Hold this guest
        # writer lock through receipt creation and active CAS so recovery cannot
        # release a still-reserved lease while its account transaction commits.
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            lease = self._lease(db)
            check(lease is not None and lease["reserved_operation_id"] == operation and
                lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            receipt = account.stage_reserved(preview, operation=operation, hook=hook)
            checkpoint(hook, "import_account_receipt_committed")
            self._activate(db, receipt, hook=hook)
        return receipt

    def activate(self, receipt, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._activate(db, receipt, hook=hook)

    def _activate(self, db, receipt, *, hook=None):
        lease = self._lease(db)
        check(lease is not None and all(lease[a] == receipt[b] for a, b in (("source_workspace_id", "source_workspace_id"),
            ("source_epoch", "source_epoch"), ("lineage_id", "import_lineage_id"), ("reserved_operation_id", "operation_id"),
            ("protected_owner_binding_digest", "protected_owner_binding_digest"))) and lease["source_snapshot_hash"] == receipt["manifest"]["source_snapshot_hash"], "IMPORT_LINEAGE_MISMATCH")
        if lease["state"] == "reserved":
            check(lease["lease_revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            db.execute("UPDATE guest_import_source_leases SET state='active',active_batch_id=?,active_manifest_hash=?,begin_client_sequence=?,terminal_client_sequence=?,lease_revision=lease_revision+1",
                (receipt["batch_id"], receipt["manifest"]["manifest_hash"], receipt["begin_client_sequence"], receipt["terminal_client_sequence"]))
        else:
            self._require_binding(lease, receipt)
        checkpoint(hook, "import_guest_active")

    @staticmethod
    def _require_binding(lease, receipt):
        check(lease is not None and lease["state"] in {"active", "published_cleanup_pending"} and lease["reserved_operation_id"] == receipt["operation_id"] and
            lease["protected_owner_binding_digest"] == receipt["protected_owner_binding_digest"] and lease["active_batch_id"] == receipt["batch_id"] and
            lease["active_manifest_hash"] == receipt["manifest"]["manifest_hash"] and lease["begin_client_sequence"] == receipt["begin_client_sequence"] and
            lease["terminal_client_sequence"] == receipt["terminal_client_sequence"], "IMPORT_SOURCE_OWNED")

    def require_active(self, receipt):
        with connect(self.path) as db:
            self._require_binding(self._lease(db), receipt)

    def recover_reserved(self, account):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            lease = self._lease(db)
            check(lease is not None and lease["protected_owner_binding_digest"] == account.owner_binding, "IMPORT_SOURCE_OWNED")
            receipt = account.receipt(lease["reserved_operation_id"])
            if receipt is None:
                # Durable reserved state proves the mandatory active network
                # gate never opened; active leases cannot use this path.
                check(lease["state"] == "reserved", "IMPORT_SOURCE_OWNED")
                db.execute("DELETE FROM guest_import_source_leases WHERE reserved_operation_id=? AND state='reserved'", (lease["reserved_operation_id"],))
                return "released_never_active"
            self._activate(db, receipt)
            return "active"

    def snapshot(self):
        with connect(self.path) as db:
            return {name: db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall() for name in
                ("workspace_metadata", "guest_import_source_leases", "guest_import_cleanup_receipts", "guest_import_audit_anchors", "guest_import_source_facts", "guest_import_previews")}
