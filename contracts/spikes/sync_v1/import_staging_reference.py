"""Synthetic ordered import staging and initial canonical publication.

This component deliberately refuses reconciliation and lifecycle proof operations
until their separate composition is supplied. It never writes a product database.
"""
import copy
import json
import uuid

from bootstrap_reference import CAPS, checkpoint, provenance_entries
from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_fact, validate_graph, validate_schema
from identity_reference import canonical_uuid, lineage_id
from import_contract_reference import (item_projection, make_manifest, mapping_rows, publication, validate_manifest)
from owned_resolution_reference import OwnedResolutionStore
from protocol_reference import canonical, digest, encode, mutation_hash, typed_definition, validate_mutation, validate_terminal_for_mutation


def build_initial_batch(account, source, epoch, records, *, begin_sequence=1, created_at="2026-09-06T05:00:00Z", batch_id=None, source_snapshot_hash=None):
    """Freeze inputs before Outbox allocation; transport fields do not enter item bytes."""
    batch_id = batch_id or str(uuid.uuid4())
    lineage = lineage_id(account, source, epoch)
    items = [{"target_type": row["target_type"], "target_id": row["target_id"], "operation_type": "import_put",
        "payload": {"source_id": row["target_id"], "fact": copy.deepcopy(row["fact"])}} for row in records]
    items.sort(key=lambda row: (row["target_type"].encode("utf-16-be"), row["payload"]["source_id"].encode("utf-16-be")))
    manifest = make_manifest(source, epoch, source_snapshot_hash if source_snapshot_hash is not None else digest(records), items)
    check(manifest["total_item_count"] <= CAPS["import_batch_items"] and
        manifest["total_canonical_bytes"] <= CAPS["import_batch_canonical_bytes"], "SYNC_IMPORT_CAPACITY_EXCEEDED")
    check(1 <= begin_sequence <= MAXIMUM - len(items) - 1, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
    envelope = {"protocol_version": 1, "base_entity_version": 0, "causal_predecessors": [], "import_lineage_id": lineage,
        "import_batch_id": batch_id, "import_source_workspace_id": source, "import_source_epoch": epoch,
        "import_manifest_hash": manifest["manifest_hash"], "predecessor_batch_id": None, "conflict_recovery_snapshot": None, "created_at": created_at}
    messages = []
    for offset in range(len(items) + 2):
        control = offset in {0, len(items) + 1}
        body = {"target_type": "workspace_import", "target_id": batch_id, "operation_type": "import_begin" if offset == 0 else "import_commit",
            "payload": {"manifest": manifest, "takeover_reason": None, "range_close_proof_id": None}} if control else items[offset - 1]
        mutation = {**envelope, **body, "mutation_id": str(uuid.uuid4()), "client_sequence": begin_sequence + offset,
            "base_entity_version": 1 if offset == len(items) + 1 else 0,
            "import_item_ordinal": None if control else offset - 1}
        validate_schema("sync/sync_mutation.schema.json", mutation)
        messages.append(mutation)
    return messages


class ImportStagingStore(OwnedResolutionStore):
    def __init__(self, path, *, account_id, **kwargs):
        super().__init__(path, **kwargs)
        self.account_id = canonical_uuid(account_id)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS import_account(singleton INTEGER PRIMARY KEY CHECK(singleton=1),id TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS import_batches(id TEXT PRIMARY KEY,lineage TEXT NOT NULL,origin TEXT NOT NULL,
                    generation INTEGER NOT NULL,begin_sequence INTEGER NOT NULL,terminal_sequence INTEGER NOT NULL,
                    stage TEXT NOT NULL,revision INTEGER NOT NULL,manifest TEXT NOT NULL,publication TEXT);
                CREATE TABLE IF NOT EXISTS import_stage_items(batch TEXT NOT NULL,ordinal INTEGER NOT NULL,target TEXT NOT NULL,
                    id TEXT NOT NULL,hash TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(batch,ordinal),UNIQUE(batch,target,id));
                CREATE TABLE IF NOT EXISTS import_mapping(lineage TEXT,target TEXT,source TEXT,id TEXT,PRIMARY KEY(lineage,target,source),UNIQUE(target,id));
                CREATE TABLE IF NOT EXISTS import_provenance(target TEXT,id TEXT,payload TEXT NOT NULL,PRIMARY KEY(target,id));
                CREATE TABLE IF NOT EXISTS import_publication_lines(sequence INTEGER PRIMARY KEY,group_id TEXT NOT NULL,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS import_published_markers(batch TEXT PRIMARY KEY,payload TEXT NOT NULL);
            """)
            db.execute("INSERT OR IGNORE INTO import_account VALUES(1,?)", (self.account_id,))
            check(db.execute("SELECT id FROM import_account").fetchone()[0] == self.account_id, "WORKSPACE_ACCOUNT_MISMATCH")

    def image(self, db, target, identifier):
        value = super().image(db, target, identifier)
        row = db.execute("SELECT payload FROM import_provenance WHERE target=? AND id=?", (target, identifier)).fetchone()
        if row:
            value["import_provenance"] = json.loads(row[0])
        return value

    def snapshot(self):
        value = super().snapshot()
        with self.connect() as db:
            for name in ("import_account", "import_batches", "import_stage_items", "import_mapping", "import_provenance", "import_publication_lines", "import_published_markers"):
                value[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return value

    def _identity_fence(self, db, device, generation, items, hook):
        """The range owner may terminate a matching request before generic replay."""

    def _virtual_no_effect(self, db, device, mutation):
        return False

    def _begin_capacity_result(self, db, device, generation, mutation, receipt, hook):
        manifest = mutation["payload"]["manifest"]
        active = [json.loads(row[0]) for row in db.execute("SELECT manifest FROM import_batches WHERE stage='server_staging'")]
        check(manifest["total_item_count"] <= CAPS["import_batch_items"] and manifest["total_canonical_bytes"] <= CAPS["import_batch_canonical_bytes"] and
            len(active) < 2 and sum(row["total_item_count"] for row in active) + manifest["total_item_count"] <= CAPS["account_staging_items"] and
            sum(row["total_canonical_bytes"] for row in active) + manifest["total_canonical_bytes"] <= CAPS["account_staging_canonical_bytes"],
            "REFERENCE_IMPORT_CAPACITY_RANGE_REQUIRED")
        return None

    def _item_capacity_result(self, db, device, generation, mutation, receipt, manifest, hook):
        return None

    def exchange(self, device, generation, items, *, confirmed=0, hook=None):
        integer(generation)
        integer(confirmed)
        check(len(items) <= 100 and len(canonical(items)) <= CAPS["decompressed_request_hard_bytes"], "SYNC_BATCH_TOO_LARGE")
        sequences = [row["mutation"]["client_sequence"] for row in items]
        check(sequences == sorted(set(sequences)), "SYNC_CLIENT_SEQUENCE_GAP")
        for row in items:
            check(set(row) == {"mutation", "payload_hash"}, "SYNC_PAYLOAD_INVALID")
            mutation = row["mutation"]
            validate_schema("sync/sync_mutation.schema.json", mutation)
            check(mutation_hash(mutation) == row["payload_hash"], "SYNC_PAYLOAD_HASH_MISMATCH")
            if not mutation["operation_type"].startswith("import_"):
                validate_mutation(mutation, row["payload_hash"])
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            state = db.execute("SELECT highest,generation,confirmed,blocked FROM devices WHERE id=?", (device,)).fetchone()
            check(state is not None, "DEVICE_NOT_REGISTERED")
            self._identity_fence(db, device, generation, items, hook)
            check(state[1] == generation, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(not state[3], "SYNC_SEQUENCE_REPLAY_MISMATCH")
            check(state[2] <= confirmed <= state[0], "SYNC_ACK_WATERMARK_INVALID")
            next_sequence = state[0] + 1
            for row in items:
                mutation = row["mutation"]
                old = db.execute("SELECT device,sequence,mutation,hash FROM receipts WHERE (device=? AND sequence=?) OR mutation=?",
                    (device, mutation["client_sequence"], mutation["mutation_id"])).fetchall()
                if old:
                    if old != [(device, mutation["client_sequence"], mutation["mutation_id"], row["payload_hash"])]:
                        db.execute("UPDATE devices SET blocked=1 WHERE id=?", (device,))
                        db.commit()
                        raise ValueError("SYNC_SEQUENCE_REPLAY_MISMATCH")
                else:
                    if self._virtual_no_effect(db, device, mutation):
                        continue
                    check(mutation["client_sequence"] == next_sequence, "SYNC_CLIENT_SEQUENCE_GAP")
                    next_sequence += 1
            results = []
            for row in items:
                mutation = row["mutation"]
                prior = db.execute("SELECT result FROM receipts WHERE device=? AND sequence=?", (device, mutation["client_sequence"])).fetchone()
                if prior:
                    original = json.loads(prior[0])
                    results.append({"status": "duplicate", "original_status": original["status"], "original_result": original,
                        "client_sequence": mutation["client_sequence"], "mutation_id": mutation["mutation_id"], "payload_hash": row["payload_hash"]})
                    continue
                result = self._import_apply(db, device, generation, mutation, row["payload_hash"], hook)
                validate_terminal_for_mutation(result, mutation)
                db.execute("INSERT INTO receipts VALUES(?,?,?,?,?)", (device, mutation["client_sequence"], mutation["mutation_id"], row["payload_hash"], encode(result)))
                checkpoint(hook, "import_receipt")
                db.execute("UPDATE devices SET highest=MAX(highest,?) WHERE id=?", (mutation["client_sequence"], device))
                checkpoint(hook, "import_device_sequence")
                results.append(result)
            db.execute("UPDATE devices SET confirmed=? WHERE id=?", (confirmed, device))
            return results

    def _import_apply(self, db, device, generation, mutation, payload_hash, hook):
        sequence, operation = mutation["client_sequence"], mutation["operation_type"]
        reservation = db.execute("SELECT id FROM import_batches WHERE origin=? AND stage='server_staging' AND ? BETWEEN begin_sequence AND terminal_sequence",
            (device, sequence)).fetchone()
        if not operation.startswith("import_"):
            check(reservation is None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            return super()._apply(db, device, mutation, payload_hash)
        batch_id = mutation["import_batch_id"]
        check(mutation["import_lineage_id"] == lineage_id(self.account_id, mutation["import_source_workspace_id"], mutation["import_source_epoch"]), "IMPORT_LINEAGE_MISMATCH")
        check(mutation["predecessor_batch_id"] is None, "REFERENCE_IMPORT_RECONCILIATION_REQUIRED")
        receipt = {"receipt_id": str(uuid.uuid4()), "device_id": device, "client_sequence": sequence,
            "mutation_id": mutation["mutation_id"], "payload_hash": payload_hash}
        staged = {"status": "staged", "receipt": receipt, "effect": None, "per_key_results": [], "conflict_ids": [],
            "failure_code": None, "failure_context": None, "import_batch_id": batch_id, "import_stage": "server_staging"}
        if operation == "import_begin":
            manifest = mutation["payload"]["manifest"]
            check(mutation["base_entity_version"] == 0, "IMPORT_VERSION_CONFLICT")
            check(mutation["target_id"] == batch_id and all(manifest[a] == mutation[b] for a, b in
                (("source_workspace_id", "import_source_workspace_id"), ("source_epoch", "import_source_epoch"), ("manifest_hash", "import_manifest_hash"))), "IMPORT_LINEAGE_MISMATCH")
            check(reservation is None and db.execute("SELECT 1 FROM import_batches WHERE id=? OR lineage=?", (batch_id, mutation["import_lineage_id"])).fetchone() is None,
                "REFERENCE_IMPORT_RECONCILIATION_REQUIRED")
            count = manifest["total_item_count"]
            check(count == sum(manifest["target_counts"].values()) + manifest["portable_preferences_count"], "IMPORT_REFERENCE_INVALID")
            check(sequence <= MAXIMUM - count - 1, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
            capacity = self._begin_capacity_result(db, device, generation, mutation, receipt, hook)
            if capacity is not None:
                return capacity
            db.execute("INSERT INTO import_batches VALUES(?,?,?,?,?,?,'server_staging',1,?,NULL)",
                (batch_id, mutation["import_lineage_id"], device, generation, sequence, sequence + count + 1, encode(manifest)))
            checkpoint(hook, "import_begin_reservation")
            return staged
        batch = db.execute("SELECT lineage,origin,generation,begin_sequence,terminal_sequence,stage,revision,manifest FROM import_batches WHERE id=?", (batch_id,)).fetchone()
        check(batch is not None and batch[1:3] == (device, generation), "SYNC_SEQUENCE_ROUTE_MISMATCH")
        manifest = json.loads(batch[7])
        check(batch[0] == mutation["import_lineage_id"] and manifest["manifest_hash"] == mutation["import_manifest_hash"], "IMPORT_LINEAGE_MISMATCH")
        check(batch[5] == "server_staging", "REFERENCE_IMPORT_TERMINAL_RANGE_REQUIRED")
        if operation in {"import_put", "import_delete"}:
            ordinal = mutation["import_item_ordinal"]
            check(sequence == batch[3] + ordinal + 1 and ordinal < manifest["total_item_count"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
            check(operation == "import_put", "REFERENCE_IMPORT_RECONCILIATION_REQUIRED")
            capacity = self._item_capacity_result(db, device, generation, mutation, receipt, manifest, hook)
            if capacity is not None:
                return capacity
            db.execute("INSERT INTO import_stage_items VALUES(?,?,?,?,?,?)", (batch_id, ordinal, mutation["target_type"], mutation["target_id"], payload_hash, encode(mutation)))
            checkpoint(hook, "import_staged_item")
            return staged
        check(operation == "import_commit" and sequence == batch[4] and mutation["target_id"] == batch_id and mutation["payload"]["manifest"] == manifest,
            "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(mutation["base_entity_version"] == batch[6], "IMPORT_VERSION_CONFLICT")
        rows = db.execute("SELECT ordinal,payload FROM import_stage_items WHERE batch=? ORDER BY ordinal", (batch_id,)).fetchall()
        staged_items = [json.loads(row[1]) for row in rows]
        try:
            check([row[0] for row in rows] == list(range(manifest["total_item_count"])), "IMPORT_REFERENCE_INVALID")
            validate_manifest(manifest, staged_items)
            records = [{"target_type": item["target_type"], "target_id": item["target_id"], "fact": item["payload"]["fact"]} for item in staged_items]
            for record in records:
                validate_fact(record)
            existing = [(target, entity, raw) for target, entity, raw in db.execute("SELECT target,id,fact FROM facts WHERE fact IS NOT NULL")]
            check(not {(row[0], row[1]) for row in existing} & {(row["target_type"], row["target_id"]) for row in records}, "IMPORT_DUPLICATE_IDENTITY")
            validate_graph([*records, *[{"target_type": target, "target_id": entity, "fact": json.loads(raw)} for target, entity, raw in existing]])
        except ValueError as error:
            db.execute("UPDATE import_batches SET stage='repair_required',revision=revision+1 WHERE id=?", (batch_id,))
            return {"receipt": receipt, "per_key_results": [], "import_batch_id": batch_id, "status": "rejected", "effect": None,
                "conflict_ids": [], "import_stage": "repair_required", "import_disposition": "repair_required",
                "error": {"code": str(error), "context": None}, "next_revision": batch[6] + 1}
        first = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0] + 1
        images = []
        for item, record in zip(staged_items, records):
            key = record["target_type"], record["target_id"]
            check(record["fact"].get("deleted_at") is None, "REFERENCE_IMPORT_TOMBSTONE_REQUIRED")
            provenance = {"import_lineage_id": batch[0], "source_workspace_id": manifest["source_workspace_id"], "source_epoch": manifest["source_epoch"],
                "source_target_type": key[0], "source_id": item["payload"]["source_id"]}
            db.execute("INSERT INTO facts VALUES(?,?,1,?,0,0,NULL)", (*key, encode(record["fact"])))
            for name in typed_definition(key[0], record["fact"])["merge_groups"]:
                db.execute("INSERT INTO fields VALUES(?,?,?,1)", (*key, name))
            db.execute("INSERT INTO import_mapping VALUES(?,?,?,?)", (batch[0], key[0], item["payload"]["source_id"], key[1]))
            db.execute("INSERT INTO import_provenance VALUES(?,?,?)", (*key, encode(provenance)))
            images.append(self.image(db, *key))
            checkpoint(hook, "import_canonical_fact:" + key[0])
        group_id = str(uuid.uuid4())
        lines = publication({"import_lineage_id": batch[0], "import_batch_id": batch_id, **manifest}, images, first, group_id)
        commit_sequence = lines[-1]["commit_server_sequence"]
        db.executemany("INSERT INTO import_publication_lines VALUES(?,?,?)", ((line["server_sequence"], group_id, encode(line)) for line in lines))
        db.execute("INSERT INTO groups VALUES(?,?,?)", (group_id, commit_sequence, encode(lines)))
        db.execute("UPDATE account SET sequence=? WHERE singleton=1", (commit_sequence,))
        db.executemany("UPDATE facts SET last_group=? WHERE target=? AND id=?", ((group_id, image["target_type"], image["target_id"]) for image in images))
        metadata = {name: lines[0][name] for name in lines[0] if name not in {"kind", "server_sequence"}}
        db.execute("INSERT INTO import_published_markers VALUES(?,?)", (batch_id, encode(metadata)))
        db.execute("UPDATE import_batches SET stage='server_confirmed',revision=revision+1,publication=? WHERE id=?", (encode(metadata), batch_id))
        checkpoint(hook, "import_publication_and_marker")
        return {"receipt": receipt, "per_key_results": [], "import_batch_id": batch_id, "status": "accepted",
            "effect": {"effect_change_group_id": group_id, "effect_group_last_server_sequence": commit_sequence}, "conflict_ids": [],
            "import_stage": "server_confirmed", "import_disposition": "server_confirmed", "error": None, "publish_group_id": group_id,
            "commit_server_sequence": commit_sequence, "canonical_digest": metadata["publish_digest"], "import_revision": batch[6] + 1}

    def bootstrap_markers(self):
        with self.connect() as db:
            images = [self.image(db, target, identifier) for target, identifier in db.execute("SELECT target,id FROM facts")]
            result = []
            for raw, in db.execute("SELECT payload FROM import_published_markers"):
                marker = {"kind": "import_publish_marker", **json.loads(raw)}
                entries = provenance_entries(images, marker)
                result.append({**marker, "snapshot_provenance_count": len(entries), "snapshot_provenance_digest": digest(entries)})
            return result
