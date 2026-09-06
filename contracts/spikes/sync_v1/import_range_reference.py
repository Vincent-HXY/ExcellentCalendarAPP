"""Actual SQLite import range arbitration with real signed proof production.

Extends the initial staging owner. Reconciliation and guest cleanup are separate
components; every proof here is authenticated by the compiled capsule consumer.
"""
from datetime import datetime, timezone
import json
import uuid

from bootstrap_reference import CAPS, checkpoint
from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_schema
from identity_reference import lineage_id
from import_contract_reference import item_projection
from import_staging_reference import ImportStagingStore
from protocol_reference import canonical, digest, encode

BINDING = ("import_lineage_id", "import_batch_id", "source_workspace_id", "source_epoch", "origin_device_id",
    "origin_sync_transport_generation", "begin_client_sequence", "terminal_client_sequence", "manifest")


def binding_from_begin(begin, device, generation=0):
    manifest = begin["payload"]["manifest"]
    return {"import_lineage_id": begin["import_lineage_id"], "import_batch_id": begin["import_batch_id"],
        "source_workspace_id": begin["import_source_workspace_id"], "source_epoch": begin["import_source_epoch"],
        "origin_device_id": device, "origin_sync_transport_generation": generation, "begin_client_sequence": begin["client_sequence"],
        "terminal_client_sequence": begin["client_sequence"] + manifest["total_item_count"] + 1, "manifest": manifest}


class ImportRangeStore(ImportStagingStore):
    def __init__(self, path, *, authority, clock=None, **kwargs):
        self.authority = authority
        self.clock = clock or (lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
        super().__init__(path, **kwargs)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS import_range_fences(batch TEXT PRIMARY KEY,binding TEXT NOT NULL,reason TEXT NOT NULL,
                    state TEXT NOT NULL,revision INTEGER NOT NULL,fence_id TEXT NOT NULL,proof TEXT);
                CREATE TABLE IF NOT EXISTS import_range_usage(batch TEXT PRIMARY KEY,bytes INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS import_publication_times(batch TEXT PRIMARY KEY,published_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS import_revoked_devices(device TEXT PRIMARY KEY,revoked_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS import_device_fence_results(operation TEXT PRIMARY KEY,hash TEXT NOT NULL,result TEXT NOT NULL);
            """)

    @staticmethod
    def _recovery(db, device):
        row = db.execute("SELECT highest,generation,confirmed FROM devices WHERE id=?", (device,)).fetchone()
        check(row is not None, "DEVICE_NOT_REGISTERED")
        highest, generation, confirmed = row
        return {"sync_transport_generation": generation, "highest_client_sequence": highest, "client_confirmed_through": confirmed,
            "next_client_sequence": None if highest == MAXIMUM else highest + 1, "client_sequence_exhausted": highest == MAXIMUM}

    def _validate_binding(self, binding):
        manifest = binding["manifest"]
        validate_schema("sync/sync_import_manifest.schema.json", manifest)
        check(binding["import_lineage_id"] == lineage_id(self.account_id, binding["source_workspace_id"], binding["source_epoch"]), "IMPORT_LINEAGE_MISMATCH")
        check(manifest["source_workspace_id"] == binding["source_workspace_id"] and manifest["source_epoch"] == binding["source_epoch"], "IMPORT_LINEAGE_MISMATCH")
        check(sum(manifest["target_counts"].values()) + manifest["portable_preferences_count"] == manifest["total_item_count"], "IMPORT_REFERENCE_INVALID")
        first, last = integer(binding["begin_client_sequence"]), integer(binding["terminal_client_sequence"])
        check(1 <= first <= MAXIMUM - manifest["total_item_count"] - 1 and last == first + manifest["total_item_count"] + 1, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")

    @staticmethod
    def _batch_binding(db, batch):
        row = db.execute("SELECT lineage,origin,generation,begin_sequence,terminal_sequence,manifest FROM import_batches WHERE id=?", (batch,)).fetchone()
        if row is None:
            return None
        manifest = json.loads(row[5])
        return dict(zip(BINDING, (row[0], batch, manifest["source_workspace_id"], manifest["source_epoch"], row[1], row[2], row[3], row[4], manifest)))

    @staticmethod
    def _fence(db, batch):
        row = db.execute("SELECT binding,reason,state,revision,fence_id,proof FROM import_range_fences WHERE batch=?", (batch,)).fetchone()
        return None if row is None else {"binding": json.loads(row[0]), "reason": row[1], "state": row[2], "revision": row[3],
            "fence_id": row[4], "proof": None if row[5] is None else json.loads(row[5])}

    @staticmethod
    def _minimal_batch(db, binding, revision, stage):
        db.execute("INSERT INTO import_batches VALUES(?,?,?,?,?,?,?, ?,?,NULL)", (binding["import_batch_id"], binding["import_lineage_id"],
            binding["origin_device_id"], binding["origin_sync_transport_generation"], binding["begin_client_sequence"], binding["terminal_client_sequence"],
            stage, revision, encode(binding["manifest"])))

    def _close(self, db, binding, previous, reason, *, never=False, fence_operation=None, hook=None):
        check(previous < MAXIMUM, "IMPORT_VERSION_CONFLICT")
        batch = binding["import_batch_id"]
        old = self._fence(db, batch)
        if old and old["proof"] is not None:
            return old["proof"]
        existing = self._batch_binding(db, batch)
        check(existing is None or existing == binding, "IMPORT_LINEAGE_MISMATCH")
        published_before = db.execute("SELECT 1 FROM import_batches WHERE lineage=? AND publication IS NOT NULL",
                                     (binding["import_lineage_id"],)).fetchone() is not None
        stage = "abandoned" if reason == "abandoned" and not published_before else "repair_required" if reason == "capacity_rejected" else "superseded"
        if existing is None:
            self._minimal_batch(db, binding, previous, stage)
        before_highest = self._recovery(db, binding["origin_device_id"])["highest_client_sequence"]
        if not never:
            db.execute("UPDATE devices SET highest=MAX(highest,?) WHERE id=?", (binding["terminal_client_sequence"], binding["origin_device_id"]))
        checkpoint(hook, "import_range_highest")
        recovery = self._recovery(db, binding["origin_device_id"])
        data = {**binding, "proof_id": str(uuid.uuid4()), "previous_import_revision": previous, "resulting_import_revision": previous + 1,
            "resulting_head_batch_id": batch, "issued_at": self.clock(), "recovery": recovery,
            "kind": "never_visible_after_transport_fence" if never else "seen_range_closed",
            "sequence_advanced": not never and binding["terminal_client_sequence"] > before_highest,
            "reason": reason, "fence_operation_id": fence_operation, "lineage_ever_published": published_before}
        if never:
            data["resulting_sync_transport_generation"] = recovery["sync_transport_generation"]
        token, claimed_hash = self.authority.sign(self.account_id, "import_range_close", data)
        proof = {**data, "proof_token": token, "proof_hash": claimed_hash}
        validate_schema("sync/import_range_close_proof.schema.json", proof)
        db.execute("INSERT OR REPLACE INTO import_range_fences VALUES(?,?,?,?,?,?,?)", (batch, encode(binding), reason,
            "never_visible" if never else "closed", previous + 1, old["fence_id"] if old else str(uuid.uuid4()), encode(proof)))
        db.execute("UPDATE import_batches SET stage=?,revision=? WHERE id=?", (stage, previous + 1, batch))
        checkpoint(hook, "import_range_proof_and_stage")
        return proof

    def _publication(self, db, batch):
        row = db.execute("SELECT publication,revision FROM import_batches WHERE id=?", (batch,)).fetchone()
        if row is None or row[0] is None:
            return None
        metadata = json.loads(row[0])
        published = db.execute("SELECT published_at FROM import_publication_times WHERE batch=?", (batch,)).fetchone()
        check(published is not None, "IMPORT_PUBLISH_INCOMPLETE")
        return {"disposition": "already_confirmed", "publication": {**{name: metadata[name] for name in
            ("import_publish_group_id", "commit_server_sequence", "publish_digest", "mapping_digest")}, "published_at": published[0]},
            "current_head": {"current_head_batch_id": batch, "current_import_revision": row[1]}}

    def _validate_close_context(self, db, request, takeover):
        """The successor component validates authoritative predecessor history."""

    def close_request(self, request, *, takeover=False, hook=None):
        validate_schema("sync/import_takeover_request.schema.json" if takeover else "sync/import_abandon_request.schema.json", request)
        binding = {name: request[name] for name in BINDING}
        self._validate_binding(binding)
        batch = binding["import_batch_id"]
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            actor = self._recovery(db, request["device_id"])
            check(actor["sync_transport_generation"] == request["sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (request["device_id"],)).fetchone() is None, "DEVICE_REVOKED")
            self._validate_close_context(db, request, takeover)
            existing = self._batch_binding(db, batch)
            check(existing is None or existing == binding, "IMPORT_LINEAGE_MISMATCH")
            fence = self._fence(db, batch)
            check(fence is None or fence["binding"] == binding, "IMPORT_LINEAGE_MISMATCH")
            published = self._publication(db, batch)
            if published:
                return published
            if fence and fence["proof"] is not None:
                proof = fence["proof"]
                check(request["expected_import_revision"] in {proof["previous_import_revision"], proof["resulting_import_revision"]}, "IMPORT_VERSION_CONFLICT")
                disposition = "already_range_closed" if takeover else "already_abandoned"
            else:
                previous = db.execute("SELECT revision FROM import_batches WHERE id=?", (batch,)).fetchone()
                previous = previous[0] if previous else 0
                check(request["expected_import_revision"] == previous, "IMPORT_VERSION_CONFLICT")
                origin = self._recovery(db, binding["origin_device_id"])
                if takeover:
                    reason = request["takeover_reason"]
                    if reason == "origin_unavailable":
                        check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (binding["origin_device_id"],)).fetchone() is not None,
                            "IMPORT_SOURCE_OWNED")
                    elif reason == "local_evidence_lost":
                        check(request["device_id"] == binding["origin_device_id"] and origin["sync_transport_generation"] > binding["origin_sync_transport_generation"],
                            "IMPORT_SOURCE_OWNED")
                    else:
                        check(fence is not None and fence["reason"] == "ttl_payload_reclaimed", "IMPORT_SOURCE_OWNED")
                    terminal_reason = "superseded"
                else:
                    check(request["predecessor_batch_id"] is None or request["reason"] == "privacy_destroy", "IMPORT_SOURCE_OWNED")
                    terminal_reason = "capacity_rejected" if request["reason"] == "capacity_rejected" else "abandoned"
                if existing is None:
                    check(origin["sync_transport_generation"] == binding["origin_sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
                    if binding["begin_client_sequence"] != origin["highest_client_sequence"] + 1:
                        check(not takeover, "IMPORT_VERSION_CONFLICT")
                        identifier = fence["fence_id"] if fence else str(uuid.uuid4())
                        db.execute("INSERT OR IGNORE INTO import_range_fences VALUES(?,?,?,'absent',0,?,NULL)",
                            (batch, encode(binding), terminal_reason, identifier))
                        checkpoint(hook, "import_absent_identity_fence")
                        return {"disposition": "absent_fenced", "proof": None, "sequence_advanced": False, "absent_batch_fence_id": identifier, "current_head": None}
                proof = self._close(db, binding, previous, terminal_reason, hook=hook)
                disposition = "range_closed" if takeover else "abandoned"
            value = {"disposition": disposition, "proof": proof, "current_head": {"current_head_batch_id": batch,
                "current_import_revision": proof["resulting_import_revision"]}}
            if not takeover:
                value["sequence_advanced"] = proof["sequence_advanced"]
            validate_schema("sync/import_takeover_response.schema.json" if takeover else "sync/import_abandon_response.schema.json", value)
            return value

    def _matching_fence(self, db, device, generation, mutation):
        fence = self._fence(db, mutation.get("import_batch_id"))
        if fence is None:
            return None
        binding = fence["binding"]
        check(device == binding["origin_device_id"] and generation == binding["origin_sync_transport_generation"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(mutation["import_lineage_id"] == binding["import_lineage_id"] and mutation["import_source_workspace_id"] == binding["source_workspace_id"] and
            mutation["import_source_epoch"] == binding["source_epoch"] and mutation["import_manifest_hash"] == binding["manifest"]["manifest_hash"], "IMPORT_LINEAGE_MISMATCH")
        sequence, first, last = mutation["client_sequence"], binding["begin_client_sequence"], binding["terminal_client_sequence"]
        operation = mutation["operation_type"]
        check((operation == "import_begin" and sequence == first) or (operation == "import_commit" and sequence == last) or
            (operation in {"import_put", "import_delete"} and first < sequence < last and mutation["import_item_ordinal"] == sequence - first - 1),
            "SYNC_SEQUENCE_ROUTE_MISMATCH")
        if operation in {"import_begin", "import_commit"}:
            check(mutation["target_id"] == binding["import_batch_id"] and mutation["payload"]["manifest"] == binding["manifest"], "IMPORT_LINEAGE_MISMATCH")
        return fence

    def _identity_fence(self, db, device, generation, items, hook):
        for row in items:
            fence = self._matching_fence(db, device, generation, row["mutation"])
            if fence is None or fence["reason"] == "capacity_rejected":
                continue
            if fence["state"] == "absent":
                recovery = self._recovery(db, device)
                if generation == recovery["sync_transport_generation"] and fence["binding"]["begin_client_sequence"] == recovery["highest_client_sequence"] + 1:
                    self._close(db, fence["binding"], fence["revision"], fence["reason"], hook=hook)
                    db.commit()  # Only the prior identity fence closes; no supplied mutation is applied.
            raise ValueError("IMPORT_BATCH_ABANDONED" if fence["reason"] == "abandoned" else "IMPORT_BATCH_SUPERSEDED")
        check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (device,)).fetchone() is None, "DEVICE_REVOKED")

    def _virtual_no_effect(self, db, device, mutation):
        fence = self._fence(db, mutation.get("import_batch_id"))
        return fence is not None and fence["state"] == "closed" and fence["reason"] == "capacity_rejected"

    @staticmethod
    def _capacity_terminal(mutation, receipt, revision):
        common = {"status": "rejected", "receipt": receipt, "effect": None, "per_key_results": [], "conflict_ids": [],
            "import_batch_id": mutation["import_batch_id"], "import_stage": "repair_required"}
        if mutation["operation_type"] == "import_commit":
            check(revision > mutation["base_entity_version"], "IMPORT_VERSION_CONFLICT")
            return {**common, "import_disposition": "repair_required", "error": {"code": "SYNC_IMPORT_CAPACITY_EXCEEDED", "context": None}, "next_revision": revision}
        return {**common, "failure_code": "SYNC_IMPORT_CAPACITY_EXCEEDED", "failure_context": None}

    def _begin_capacity_result(self, db, device, generation, mutation, receipt, hook):
        try:
            super()._begin_capacity_result(db, device, generation, mutation, receipt, hook)
            return None
        except ValueError as error:
            check(str(error) == "REFERENCE_IMPORT_CAPACITY_RANGE_REQUIRED", str(error))
        binding = binding_from_begin(mutation, device, generation)
        self._minimal_batch(db, binding, 1, "repair_required")
        proof = self._close(db, binding, 1, "capacity_rejected", hook=hook)
        return self._capacity_terminal(mutation, receipt, proof["resulting_import_revision"])

    def _item_capacity_result(self, db, device, generation, mutation, receipt, manifest, hook):
        previous = db.execute("SELECT bytes FROM import_range_usage WHERE batch=?", (mutation["import_batch_id"],)).fetchone()
        size = (previous[0] if previous else 0) + len(canonical(item_projection(mutation)))
        if size > min(manifest["total_canonical_bytes"], CAPS["import_batch_canonical_bytes"]):
            binding = self._batch_binding(db, mutation["import_batch_id"])
            revision = db.execute("SELECT revision FROM import_batches WHERE id=?", (mutation["import_batch_id"],)).fetchone()[0]
            proof = self._close(db, binding, revision, "capacity_rejected", hook=hook)
            return self._capacity_terminal(mutation, receipt, proof["resulting_import_revision"])
        db.execute("INSERT OR REPLACE INTO import_range_usage VALUES(?,?)", (mutation["import_batch_id"], size))
        return None

    def _import_apply(self, db, device, generation, mutation, payload_hash, hook):
        fence = self._fence(db, mutation.get("import_batch_id"))
        if fence and fence["reason"] == "capacity_rejected":
            receipt = {"receipt_id": str(uuid.uuid4()), "device_id": device, "client_sequence": mutation["client_sequence"],
                "mutation_id": mutation["mutation_id"], "payload_hash": payload_hash}
            return self._capacity_terminal(mutation, receipt, fence["revision"])
        result = super()._import_apply(db, device, generation, mutation, payload_hash, hook)
        if mutation["operation_type"] == "import_commit" and result["status"] == "accepted":
            db.execute("INSERT INTO import_publication_times VALUES(?,?)", (mutation["import_batch_id"], self.clock()))
        return result

    def revoke(self, device):
        with self.connect() as db:
            db.execute("INSERT OR IGNORE INTO import_revoked_devices VALUES(?,?)", (device, self.clock()))

    def fence_transport(self, request, *, hook=None):
        validate_schema("sync/sync_device_fence_request.schema.json", request)
        device, operation, expected = request["device_id"], request["fence_operation_id"], request["expected_sync_transport_generation"]
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT hash,result FROM import_device_fence_results WHERE operation=?", (operation,)).fetchone()
            if old:
                check(old[0] == digest(request), "SYNC_SEQUENCE_REPLAY_MISMATCH")
                return json.loads(old[1])
            recovery = self._recovery(db, device)
            check(recovery["sync_transport_generation"] == expected, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(expected < MAXIMUM, "SYNC_TRANSPORT_GENERATION_EXHAUSTED")
            db.execute("UPDATE devices SET generation=generation+1 WHERE id=?", (device,))
            checkpoint(hook, "import_fence_generation")
            proofs = []
            for raw, revision in db.execute("SELECT binding,revision FROM import_range_fences WHERE state='absent'").fetchall():
                binding = json.loads(raw)
                if binding["origin_device_id"] == device and binding["origin_sync_transport_generation"] == expected:
                    check(db.execute("SELECT 1 FROM receipts WHERE device=? AND json_extract(result,'$.import_batch_id')=?", (device, binding["import_batch_id"])).fetchone() is None,
                        "IMPORT_LINEAGE_MISMATCH")
                    proofs.append(self._close(db, binding, revision, "abandoned", never=True, fence_operation=operation, hook=hook))
            recovery = self._recovery(db, device)
            data = {"protocol_version": 1, "device_id": device, "fence_operation_id": operation, "previous_sync_transport_generation": expected,
                "recovery": recovery, "resolved_absent_import_fences": proofs}
            token, claimed_hash = self.authority.sign(self.account_id, "device_fence", data)
            result = {**data, "fence_receipt": token, "result_hash": claimed_hash}
            validate_schema("sync/sync_device_fence_response.schema.json", result)
            db.execute("INSERT INTO fences VALUES(?,?,?,?)", (device, operation, str(expected), encode(recovery)))
            db.execute("INSERT INTO import_device_fence_results VALUES(?,?,?)", (operation, digest(request), encode(result)))
            checkpoint(hook, "import_fence_receipt")
            return result

    def snapshot(self):
        value = super().snapshot()
        with self.connect() as db:
            for name in ("import_range_fences", "import_range_usage", "import_publication_times", "import_revoked_devices", "import_device_fence_results"):
                value[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return value
