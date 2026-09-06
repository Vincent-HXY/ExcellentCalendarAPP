"""Fresh account recovery using real signed fences and retained guest evidence.

No old mutation is turned into a local upload receipt. The reconstructed import
control record is explicitly separate from terminals; visibility still requires
an authenticated complete bootstrap and its canonical publication marker.
"""
import json

from bootstrap_reference import checkpoint
from counter_reference import MAXIMUM
from domain_reference import check, validate_schema
from import_client_reference import FullGraphAccountImport, validate_prepared_graph
from protocol_reference import digest, encode, mutation_hash
from sqlite_reference import connect


class FreshImportAccount(FullGraphAccountImport):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS local_import_fresh_recovery(singleton INTEGER PRIMARY KEY CHECK(singleton=1),"
                       "batch TEXT NOT NULL,phase TEXT NOT NULL,evidence TEXT NOT NULL)")

    def _require_recovered(self):
        with connect(self.path) as db:
            row = db.execute("SELECT phase FROM local_import_fresh_recovery").fetchone()
            check(row is not None and row[0] == "ready", "SYNC_BOOTSTRAP_INCOMPLETE")

    def enqueue(self, mutation, **kwargs):
        self._require_recovered()
        return super().enqueue(mutation, **kwargs)

    def draft(self, records, **kwargs):
        self._require_recovered()
        return super().draft(records, **kwargs)

    def prepare_import(self, guest, operation, **kwargs):
        self._require_recovered()
        return super().prepare_import(guest, operation, **kwargs)

    def _closed_proof(self, db, batch):
        row = db.execute("SELECT evidence FROM local_import_fresh_recovery WHERE batch=?", (batch,)).fetchone()
        return json.loads(row[0])["proof"] if row else super()._closed_proof(db, batch)

    def _restore_reserved_predecessor(self, guest, source, receipt, *, hook=None):
        lease = guest._lease(source)
        if lease is None or lease["state"] != "reserved":
            return
        previous = guest._replacement(source, lease["reserved_operation_id"])
        if previous is None:
            return
        guest._require_binding(previous, receipt)
        check(lease["protected_owner_binding_digest"] == self.owner_binding and lease["source_epoch"] == previous["source_epoch"] and
              lease["lineage_id"] == previous["lineage_id"], "IMPORT_SOURCE_OWNED")
        check(lease["lease_revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
        previous["lease_revision"] = lease["lease_revision"] + 1
        source.execute("DELETE FROM guest_import_source_leases")
        columns = [row[1] for row in source.execute("PRAGMA table_info(guest_import_source_leases)")]
        source.execute("INSERT INTO guest_import_source_leases VALUES(" + ",".join("?" for _ in columns) + ")", [previous[name] for name in columns])
        source.execute("DELETE FROM guest_import_source_lease_replacements WHERE operation_id=?", (lease["reserved_operation_id"],))
        checkpoint(hook, "import_fresh_restore_previous_lease")

    def recover(self, guest, fence, status, *, authority, proof=None, hook=None):
        validate_schema("sync/sync_device_fence_response.schema.json", fence)
        validate_schema("sync/import_status_response.schema.json", status)
        fence_claims = {key: value for key, value in fence.items() if key not in {"fence_receipt", "result_hash"}}
        check(authority.verify(self.account_id, "device_fence", fence_claims, fence["fence_receipt"], fence["result_hash"]), "IMPORT_REFERENCE_INVALID")
        check(fence["device_id"] == self.device_id and fence["recovery"]["sync_transport_generation"] == self.transport and
              self.transport == fence["previous_sync_transport_generation"] + 1, "SYNC_TRANSPORT_GENERATION_MISMATCH")
        if proof is not None:
            validate_schema("sync/import_range_close_proof.schema.json", proof)
            claims = {key: value for key, value in proof.items() if key not in {"proof_token", "proof_hash"}}
            check(authority.verify(self.account_id, "import_range_close", claims, proof["proof_token"], proof["proof_hash"]), "IMPORT_REFERENCE_INVALID")
        evidence = {"fence": fence, "status": status, "proof": proof}
        with connect(self.path) as db:
            old = db.execute("SELECT batch,evidence FROM local_import_fresh_recovery").fetchone()
            if old:
                check(json.loads(old[1]) == evidence, "IMPORT_VERSION_CONFLICT")
                operation = db.execute("SELECT operation FROM local_import_operations WHERE batch=?", (old[0],)).fetchone()
                check(operation is not None, "IMPORT_REFERENCE_INVALID")
                receipt = self._receipt(db, operation[0])
                with connect(guest.path) as source:
                    source.execute("BEGIN IMMEDIATE")
                    self._restore_reserved_predecessor(guest, source, receipt, hook=hook)
                return receipt
        with connect(guest.path) as source:
            source.execute("BEGIN IMMEDIATE")
            lease = guest._lease(source)
            if lease is not None and lease["state"] == "reserved":
                # An unactivated successor could never have been uploaded. Its
                # backup still identifies the previous active source lease.
                lease = guest._replacement(source, lease["reserved_operation_id"])
            check(lease is not None and lease["state"] == "active" and lease["protected_owner_binding_digest"] == self.owner_binding, "IMPORT_SOURCE_OWNED")
            saved = source.execute("SELECT payload FROM guest_import_previews WHERE operation=?", (lease["reserved_operation_id"],)).fetchone()
            check(saved is not None, "IMPORT_REFERENCE_INVALID")
            preview = json.loads(saved[0])
            prepared = preview["prepared"]
            batch, manifest = prepared["batch"], preview["response"]["manifest"]
            validate_prepared_graph(prepared, manifest)
            binding = {"import_batch_id": lease["active_batch_id"], "import_lineage_id": lease["lineage_id"], "source_workspace_id": guest.workspace_id,
                "source_epoch": lease["source_epoch"], "manifest": manifest, "begin_client_sequence": lease["begin_client_sequence"],
                "terminal_client_sequence": lease["terminal_client_sequence"], "origin_device_id": prepared["origin_device_id"],
                "origin_sync_transport_generation": prepared["transport"]}
            check(status["disposition"] == "found" and all(status[name] == value for name, value in binding.items()), "IMPORT_LINEAGE_MISMATCH")
            check(status["current_head"]["current_head_batch_id"] == binding["import_batch_id"], "IMPORT_VERSION_CONFLICT")
            check(preview["owner_binding"] == self.owner_binding and lease["active_manifest_hash"] == manifest["manifest_hash"] and
                  lease["source_snapshot_hash"] == manifest["source_snapshot_hash"], "IMPORT_LINEAGE_MISMATCH")
            recovery = fence["recovery"]
            if proof:
                check(all(proof[name] == value for name, value in binding.items()) and
                      status["current_head"]["current_import_revision"] == proof["resulting_import_revision"], "IMPORT_LINEAGE_MISMATCH")
                if proof["origin_device_id"] == self.device_id:
                    proof_recovery = proof["recovery"]
                    if proof_recovery["sync_transport_generation"] == self.transport:
                        recovery = proof_recovery
                    else:
                        # A confirmed range may have closed before privacy
                        # destruction. The newer fence owns fresh allocation.
                        check(proof_recovery["sync_transport_generation"] <= fence["previous_sync_transport_generation"] and
                              proof_recovery["highest_client_sequence"] <= recovery["highest_client_sequence"] and
                              proof_recovery["client_confirmed_through"] <= recovery["client_confirmed_through"],
                              "SYNC_TRANSPORT_GENERATION_MISMATCH")
                    if proof["kind"] == "never_visible_after_transport_fence":
                        check(proof["fence_operation_id"] == fence["fence_operation_id"] and proof in fence["resolved_absent_import_fences"], "IMPORT_REFERENCE_INVALID")
                check(recovery["highest_client_sequence"] >= fence["recovery"]["highest_client_sequence"], "SYNC_ACK_WATERMARK_INVALID")
            else:
                check(status["stage"] == "server_confirmed" and status["publication"] is not None, "IMPORT_PUBLISH_INCOMPLETE")
            with connect(self.path) as db:
                db.execute("BEGIN IMMEDIATE")
                old = db.execute("SELECT evidence FROM local_import_fresh_recovery").fetchone()
                if old:
                    check(json.loads(old[0]) == evidence, "IMPORT_VERSION_CONFLICT")
                    return self._receipt(db, lease["reserved_operation_id"])
                state = self._state(db)
                check(state["fresh"] and not any(db.execute("SELECT 1 FROM " + table).fetchone() for table in
                    ("pending", "terminals", "frozen_intents", "local_import_operations", "local_import_outbox")), "SYNC_BOOTSTRAP_INCOMPLETE")
                operation = lease["reserved_operation_id"]
                frozen_digest = digest([{"client_sequence": row["client_sequence"], "payload_hash": mutation_hash(row)} for row in batch])
                stage = "repair_required" if proof else "server_confirmed"
                db.execute("INSERT INTO local_import_operations VALUES(?,?,?,?,?,?,?,?,?,?,?)", (operation, lease["active_batch_id"], guest.workspace_id,
                    lease["source_epoch"], lease["lineage_id"], self.owner_binding, encode(manifest), lease["begin_client_sequence"], lease["terminal_client_sequence"], frozen_digest, stage))
                db.execute("INSERT INTO local_import_graph_inputs VALUES(?,?)", (lease["active_batch_id"], encode(prepared)))
                db.execute("INSERT INTO graph_batches VALUES(?,?,?)", (lease["active_batch_id"], digest(prepared), encode(batch)))
                for mapping in prepared["mappings"]:
                    check(mapping[0] == lease["lineage_id"], "IMPORT_LINEAGE_MISMATCH")
                    db.execute("INSERT INTO graph_mapping VALUES(?,?,?,?)", mapping)
                checkpoint(hook, "import_fresh_mapping_and_control")
                db.execute("INSERT INTO local_import_control VALUES(?,?,?,NULL,NULL,NULL)",
                           (lease["active_batch_id"], status["current_head"]["current_import_revision"], lease["active_batch_id"]))
                db.execute("INSERT INTO local_import_server_status VALUES(?,?)", (lease["active_batch_id"], encode(status)))
                state.update(next_sequence=recovery["next_client_sequence"], exhausted=recovery["client_sequence_exhausted"],
                             local_ack=recovery["client_confirmed_through"], server_ack=recovery["client_confirmed_through"])
                self._save_state(db, state)
                db.execute("INSERT INTO local_import_fresh_recovery VALUES(1,?,'awaiting_bootstrap',?)", (lease["active_batch_id"], encode(evidence)))
                checkpoint(hook, "import_fresh_seed_and_receipt")
                receipt = self._receipt(db, operation)
            checkpoint(hook, "import_fresh_account_committed")
            self._restore_reserved_predecessor(guest, source, receipt, hook=hook)
            return receipt

    def finish_recovery(self, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT batch,phase,evidence FROM local_import_fresh_recovery").fetchone()
            check(row is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            if row[1] == "ready":
                return
            evidence, state = json.loads(row[2]), self._state(db)
            check(not state["fresh"] and state["cursor"] is not None and db.execute("SELECT 1 FROM finalized").fetchone() is not None,
                  "SYNC_BOOTSTRAP_INCOMPLETE")
            check(state["server_ack"] == state["local_ack"], "SYNC_ACK_WATERMARK_INVALID")
            if evidence["proof"] is None:
                applied = db.execute("SELECT metadata FROM local_import_applied WHERE batch=?", (row[0],)).fetchone()
                check(applied is not None, "IMPORT_PUBLISH_INCOMPLETE")
                marker = json.loads(applied[0])
                published = evidence["status"]["publication"]
                check(all(marker[name] == published[name] for name in ("import_publish_group_id", "commit_server_sequence", "publish_digest", "mapping_digest")),
                      "IMPORT_PUBLISH_INCOMPLETE")
            db.execute("UPDATE local_import_fresh_recovery SET phase='ready'")
            checkpoint(hook, "import_fresh_ready")

    def publication_evidence(self, operation):
        with connect(self.path) as db:
            local = self._receipt(db, operation)
            row = db.execute("SELECT batch,phase,evidence FROM local_import_fresh_recovery").fetchone()
            if local is None or row is None or local["batch_id"] != row[0] or json.loads(row[2])["proof"] is not None:
                return super().publication_evidence(operation)
            check(row[1] == "ready" and local["stage"] in {"publish_applied", "cleanup_pending", "completed"}, "IMPORT_PUBLISH_INCOMPLETE")
            status = json.loads(row[2])["status"]
            control = db.execute("SELECT revision,head FROM local_import_control WHERE batch=?", (local["batch_id"],)).fetchone()
            check(control is not None and control[1] == local["batch_id"], "IMPORT_VERSION_CONFLICT")
            applied = db.execute("SELECT metadata FROM local_import_applied WHERE batch=?", (local["batch_id"],)).fetchone()
            check(applied is not None, "IMPORT_PUBLISH_INCOMPLETE")
            metadata = json.loads(applied[0])
            check(all(metadata[name] == status["publication"][name] for name in
                ("import_publish_group_id", "commit_server_sequence", "publish_digest", "mapping_digest")), "IMPORT_PUBLISH_INCOMPLETE")
            prepared = json.loads(db.execute("SELECT payload FROM local_import_graph_inputs WHERE batch=?", (local["batch_id"],)).fetchone()[0])
            return {**local, "through_import_revision": status["import_revision"], "current_import_revision": control[0], "publication": metadata,
                "source_fact_count": prepared["source_fact_count"], "source_identities": {(item["target_type"], item["payload"]["source_id"])
                    for item in prepared["batch"][1:-1] if "source_id" in item["payload"]}}

    def snapshot(self):
        value = super().snapshot()
        with connect(self.path) as db:
            value["local_import_fresh_recovery"] = db.execute("SELECT * FROM local_import_fresh_recovery").fetchall()
        return value
