"""Status discovery and payload TTL using the durable import owners.

The expiry is supplied by the server resource policy when a batch is accepted.
No client supplied TTL claim authorizes takeover or source lease release.
"""
from datetime import datetime, timedelta, timezone
import json

from bootstrap_reference import checkpoint, epoch
from domain_reference import check, validate_schema
from import_cleanup_reference import AccountImportCleanup, ImportCleanupServer
from protocol_reference import encode
from sqlite_reference import connect


def empty_status():
    return {"disposition": "none", "stage": None, "abandon_status": "not_applicable", "reconciliation_status": "not_required",
        "resume_disposition": "none", "import_lineage_id": None, "import_batch_id": None, "source_epoch": None, "current_head": None, "import_revision": None}


class ImportStatusServer(ImportCleanupServer):
    def __init__(self, path, *, staging_ttl_seconds, **kwargs):
        check(type(staging_ttl_seconds) is int and staging_ttl_seconds > 0, "IMPORT_REFERENCE_INVALID")
        self.staging_ttl_seconds = staging_ttl_seconds
        super().__init__(path, **kwargs)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS import_status_metadata(batch TEXT PRIMARY KEY,predecessor TEXT,expires_at TEXT NOT NULL,payload_reclaimed INTEGER NOT NULL);
            """)

    def _import_apply(self, db, device, generation, mutation, payload_hash, hook):
        result = super()._import_apply(db, device, generation, mutation, payload_hash, hook)
        if mutation["operation_type"] == "import_begin":
            expires = datetime.fromtimestamp(epoch(self.clock()), timezone.utc) + timedelta(seconds=self.staging_ttl_seconds)
            db.execute("INSERT INTO import_status_metadata VALUES(?,?,?,0)", (mutation["import_batch_id"], mutation["predecessor_batch_id"], expires.strftime("%Y-%m-%dT%H:%M:%SZ")))
        return result

    def _status(self, db, batch, caller):
        binding = self._batch_binding(db, batch)
        if binding is None:
            return empty_status()
        stage, revision = db.execute("SELECT stage,revision FROM import_batches WHERE id=?", (batch,)).fetchone()
        head, head_revision = db.execute("SELECT id,revision FROM import_batches WHERE lineage=? ORDER BY revision DESC,id DESC LIMIT 1", (binding["import_lineage_id"],)).fetchone()
        metadata = db.execute("SELECT predecessor,expires_at,payload_reclaimed FROM import_status_metadata WHERE batch=?", (batch,)).fetchone()
        fence, published = self._fence(db, batch), self._publication(db, batch)
        value = {"disposition": "found", **binding, "stage": stage, "import_revision": revision,
            "current_head": {"current_head_batch_id": head, "current_import_revision": head_revision},
            "predecessor_batch_id": metadata[0] if metadata else None, "expires_at": metadata[1] if metadata else None,
            "server_staged_item_count": db.execute("SELECT count(*) FROM import_stage_items WHERE batch=?", (batch,)).fetchone()[0],
            "publication": published["publication"] if published else None, "cleanup_confirmation": None,
            "range_close_proof": fence["proof"] if fence else None}
        if stage == "server_staging":
            value.update(abandon_status="not_requested", reconciliation_status="not_required",
                resume_disposition="resume_upload" if caller == binding["origin_device_id"] else "close_range_then_successor")
        elif stage == "repair_required":
            value.update(abandon_status="not_applicable", reconciliation_status="full_successor_required",
                resume_disposition="create_successor" if fence and fence["proof"] is not None else "close_range_then_successor")
        elif stage == "server_confirmed":
            value.update(abandon_status="not_applicable", reconciliation_status="not_required", resume_disposition="resume_publish")
        elif stage == "completed":
            confirmation = db.execute("SELECT response FROM import_cleanup_confirmations WHERE lineage=?", (binding["import_lineage_id"],)).fetchone()
            check(confirmation is not None, "IMPORT_REFERENCE_INVALID")
            value.update(abandon_status="not_applicable", reconciliation_status="not_required", resume_disposition="terminal", cleanup_confirmation=json.loads(confirmation[0]))
        elif stage == "superseded":
            value.update(abandon_status="not_applicable", reconciliation_status="full_successor_required" if batch == head else "not_required",
                resume_disposition="create_successor" if batch == head else "terminal")
        else:
            check(stage == "abandoned", "IMPORT_REFERENCE_INVALID")
            value.update(abandon_status="confirmed", reconciliation_status="not_required", resume_disposition="terminal")
        validate_schema("sync/import_status_response.schema.json", value)
        return value

    def status(self, request):
        validate_schema("sync/import_status_request.schema.json", request)
        with self.connect() as db:
            db.execute("BEGIN")
            actor = self._recovery(db, request["device_id"])
            check(actor["sync_transport_generation"] == request["sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (request["device_id"],)).fetchone() is None, "DEVICE_REVOKED")
            batch = request.get("import_batch_id")
            if batch is None:
                rows = [(identifier, json.loads(raw)) for identifier, raw in db.execute("SELECT id,manifest FROM import_batches WHERE stage!='completed' ORDER BY revision DESC,id DESC")]
                batch = next((identifier for identifier, manifest in rows if manifest["source_workspace_id"] == request["source_workspace_id"] and
                    manifest["source_epoch"] == request["source_epoch"] and (request["source_snapshot_hash"] is None or
                    request["source_snapshot_hash"] == manifest["source_snapshot_hash"])), None)
            return empty_status() if batch is None else self._status(db, batch, request["device_id"])

    def reclaim_expired_payload(self, batch, *, now, hook=None):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            metadata = db.execute("SELECT expires_at,payload_reclaimed FROM import_status_metadata WHERE batch=?", (batch,)).fetchone()
            check(metadata is not None and epoch(now) >= epoch(metadata[0]), "IMPORT_VERSION_CONFLICT")
            published = self._publication(db, batch)
            if published:
                return published
            fence = self._fence(db, batch)
            if metadata[1]:
                check(fence is not None and fence["proof"] is not None, "IMPORT_REFERENCE_INVALID")
                return fence["proof"]
            binding = self._batch_binding(db, batch)
            revision = db.execute("SELECT revision FROM import_batches WHERE id=?", (batch,)).fetchone()[0]
            proof = fence["proof"] if fence and fence["proof"] is not None else self._close(db, binding, revision, "ttl_payload_reclaimed", hook=hook)
            db.execute("DELETE FROM import_stage_items WHERE batch=?", (batch,))
            db.execute("UPDATE import_status_metadata SET payload_reclaimed=1 WHERE batch=?", (batch,))
            checkpoint(hook, "import_ttl_payload_reclaimed")
            return proof

    def snapshot(self):
        value = super().snapshot()
        with self.connect() as db:
            value["import_status_metadata"] = db.execute("SELECT * FROM import_status_metadata ORDER BY 1").fetchall()
        return value


class AccountImportStatus(AccountImportCleanup):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS local_import_server_status(batch TEXT PRIMARY KEY,snapshot TEXT NOT NULL)")

    def accept_server_status(self, operation, value):
        validate_schema("sync/import_status_response.schema.json", value)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            local = self._receipt(db, operation)
            check(local is not None and value["disposition"] == "found" and value["import_batch_id"] == local["batch_id"] and
                value["manifest"] == local["manifest"] and value["import_lineage_id"] == local["import_lineage_id"], "IMPORT_LINEAGE_MISMATCH")
            old = db.execute("SELECT snapshot FROM local_import_server_status WHERE batch=?", (local["batch_id"],)).fetchone()
            check(old is None or json.loads(old[0])["import_revision"] <= value["import_revision"], "IMPORT_VERSION_CONFLICT")
            db.execute("INSERT INTO local_import_server_status VALUES(?,?) ON CONFLICT(batch) DO UPDATE SET snapshot=excluded.snapshot", (local["batch_id"], encode(value)))

    def status(self, operation, *, server_snapshot=None):
        if server_snapshot is not None:
            self.accept_server_status(operation, server_snapshot)
        with connect(self.path) as db:
            local = self._receipt(db, operation)
            if local is None:
                return empty_status()
            cached = db.execute("SELECT snapshot FROM local_import_server_status WHERE batch=?", (local["batch_id"],)).fetchone()
            server_snapshot = json.loads(cached[0]) if cached else None
            control = db.execute("SELECT revision,head,publication,cleanup,completed FROM local_import_control WHERE batch=?", (local["batch_id"],)).fetchone()
            stage = local["stage"]
            revision = control[0] if control else 0
            if server_snapshot is not None:
                # Status can discover server confirmation, but never authorizes
                # retirement or consumes Outbox. Durable exact ack/apply does that.
                if stage in {"local_staging", "server_staging"} and server_snapshot["stage"] == "server_confirmed":
                    stage = "server_confirmed"
                revision = max(revision, server_snapshot["import_revision"])
            begin = db.execute("SELECT mutation FROM local_import_outbox WHERE sequence=? UNION ALL SELECT mutation FROM terminals WHERE sequence=?",
                (local["begin_client_sequence"], local["begin_client_sequence"])).fetchone()
            # Range-closed batches may have no per-item receipt for an unseen begin.
            predecessor = json.loads(begin[0])["predecessor_batch_id"] if begin else None
            published = server_snapshot["publication"] if server_snapshot else None
            if control and control[2] is not None and published is None:
                terminal = json.loads(control[2])
                published = {"import_publish_group_id": terminal["publish_group_id"],
                    "commit_server_sequence": terminal["commit_server_sequence"], "publish_digest": terminal["canonical_digest"],
                    "mapping_digest": local["manifest"]["mapping_digest"], "published_at": None}
            value = {"disposition": "found", "import_lineage_id": local["import_lineage_id"], "import_batch_id": local["batch_id"],
                "source_workspace_id": local["source_workspace_id"], "source_epoch": local["source_epoch"], "origin_device_id": self.device_id,
                "origin_sync_transport_generation": self.transport, "begin_client_sequence": local["begin_client_sequence"],
                "terminal_client_sequence": local["terminal_client_sequence"], "manifest": local["manifest"], "predecessor_batch_id": predecessor,
                "import_revision": revision, "current_head": server_snapshot["current_head"] if server_snapshot and server_snapshot["current_head"]["current_import_revision"] >= revision else
                    {"current_head_batch_id": control[1] if control else local["batch_id"], "current_import_revision": revision},
                "expires_at": server_snapshot["expires_at"] if server_snapshot else None,
                "server_staged_item_count": server_snapshot["server_staged_item_count"] if server_snapshot else 0,
                "local_staged_item_count": local["manifest"]["total_item_count"], "publication": published,
                "cleanup_receipt": json.loads(control[3]) if control and control[3] is not None else None,
                "range_close_proof": server_snapshot["range_close_proof"] if server_snapshot else None, "stage": stage}
            states = {"local_staging": ("not_requested", "not_required", "resume_upload"), "server_staging": ("not_requested", "not_required", "resume_upload"),
                "repair_required": ("not_applicable", "full_successor_required", "create_successor"), "server_confirmed": ("not_applicable", "not_required", "resume_publish"),
                "publish_applied": ("not_applicable", "not_required", "resume_cleanup"), "cleanup_pending": ("not_applicable", "cleanup_recovery_required", "resume_cleanup"),
                "completed": ("not_applicable", "not_required", "terminal"), "superseded": ("not_applicable", "full_successor_required", "create_successor"),
                "abandoned": ("confirmed", "not_required", "terminal")}
            value.update(zip(("abandon_status", "reconciliation_status", "resume_disposition"), states[stage]))
            validate_schema("workspace/native_import_status_response.schema.json", value)
            return value

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            value["local_import_server_status"] = db.execute("SELECT * FROM local_import_server_status ORDER BY 1").fetchall()
        return value
