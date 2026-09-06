"""Full import batches, permanent mappings and lineage CAS in disposable stores.

The production PostgreSQL implementation remains a downstream task. This oracle
uses actual SQLite transactions, typed publications and the existing proof owner.
"""
import copy
from datetime import datetime, timedelta, timezone
import json
import uuid

from bootstrap_reference import checkpoint, epoch
from counter_reference import MAXIMUM
from domain_reference import check, validate_graph, validate_schema
from identity_reference import lineage_id
from import_contract_reference import mapping_rows, publication, validate_manifest
from import_status_reference import ImportStatusServer
from protocol_reference import encode, typed_definition


class ImportSuccessorServer(ImportStatusServer):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS import_lineage_heads(lineage TEXT PRIMARY KEY,source TEXT NOT NULL,
                    epoch INTEGER NOT NULL,head TEXT NOT NULL,revision INTEGER NOT NULL,UNIQUE(source,epoch));
                CREATE TABLE IF NOT EXISTS import_reserved_mapping(lineage TEXT,target TEXT,source TEXT,id TEXT,
                    PRIMARY KEY(lineage,target,source),UNIQUE(target,id));
                CREATE TABLE IF NOT EXISTS import_control_inputs(batch TEXT PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TRIGGER IF NOT EXISTS import_completed_head AFTER UPDATE OF stage ON import_batches
                    WHEN NEW.stage='completed'
                    BEGIN UPDATE import_lineage_heads SET revision=NEW.revision WHERE head=NEW.id; END;
            """)

    @staticmethod
    def _head(db, lineage):
        return db.execute("SELECT head,revision FROM import_lineage_heads WHERE lineage=?", (lineage,)).fetchone()

    def _publication(self, db, batch):
        value = super()._publication(db, batch)
        if value is not None:
            lineage = db.execute("SELECT lineage FROM import_batches WHERE id=?", (batch,)).fetchone()[0]
            head = self._head(db, lineage)
            if head:
                value["current_head"] = {"current_head_batch_id": head[0], "current_import_revision": head[1]}
        return value

    def _status(self, db, batch, caller):
        value = super()._status(db, batch, caller)
        if value["disposition"] == "found":
            head = self._head(db, value["import_lineage_id"])
            check(head is not None, "IMPORT_REFERENCE_INVALID")
            value["current_head"] = {"current_head_batch_id": head[0], "current_import_revision": head[1]}
            if value["stage"] == "repair_required" and value["range_close_proof"] is None:
                row = db.execute("SELECT result FROM receipts WHERE device=? AND sequence=?",
                    (value["origin_device_id"], value["terminal_client_sequence"])).fetchone()
                if row is not None:
                    terminal = json.loads(row[0])
                    if terminal.get("import_batch_id") == batch and terminal.get("import_stage") == "repair_required":
                        value["resume_disposition"] = "create_successor"
            validate_schema("sync/import_status_response.schema.json", value)
        return value

    def _close(self, db, binding, previous, reason, **kwargs):
        head = self._head(db, binding["import_lineage_id"])
        fence = self._fence(db, binding["import_batch_id"])
        if fence and fence["proof"] is not None:
            return fence["proof"]
        check(head is None or head == (binding["import_batch_id"], previous), "IMPORT_VERSION_CONFLICT")
        proof = super()._close(db, binding, previous, reason, **kwargs)
        db.execute("INSERT INTO import_lineage_heads VALUES(?,?,?,?,?) ON CONFLICT(lineage) DO UPDATE SET revision=excluded.revision",
            (binding["import_lineage_id"], binding["source_workspace_id"], binding["source_epoch"], binding["import_batch_id"], proof["resulting_import_revision"]))
        return proof

    def _validate_close_context(self, db, request, takeover):
        if takeover:
            return
        row = db.execute("SELECT predecessor FROM import_status_metadata WHERE batch=?", (request["import_batch_id"],)).fetchone()
        if row:
            check(request["predecessor_batch_id"] == row[0], "IMPORT_LINEAGE_MISMATCH")
        if self._publication(db, request["import_batch_id"]) is not None:
            return
        published_before = db.execute("SELECT 1 FROM import_batches WHERE lineage=? AND publication IS NOT NULL",
                                     (request["import_lineage_id"],)).fetchone() is not None
        if published_before:
            check(request["reason"] == "privacy_destroy", "IMPORT_SOURCE_OWNED")

    def snapshot(self):
        value = super().snapshot()
        with self.connect() as db:
            for table in ("import_lineage_heads", "import_reserved_mapping", "import_control_inputs"):
                value[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return value

    def _import_apply(self, db, device, generation, mutation, payload_hash, hook):
        operation = mutation["operation_type"]
        if not operation.startswith("import_"):
            return super()._import_apply(db, device, generation, mutation, payload_hash, hook)
        batch, lineage, sequence = mutation["import_batch_id"], mutation["import_lineage_id"], mutation["client_sequence"]
        check(lineage == lineage_id(self.account_id, mutation["import_source_workspace_id"], mutation["import_source_epoch"]), "IMPORT_LINEAGE_MISMATCH")
        receipt = {"receipt_id": str(uuid.uuid4()), "device_id": device, "client_sequence": sequence,
            "mutation_id": mutation["mutation_id"], "payload_hash": payload_hash}
        staged = {"status": "staged", "receipt": receipt, "effect": None, "per_key_results": [], "conflict_ids": [],
            "failure_code": None, "failure_context": None, "import_batch_id": batch, "import_stage": "server_staging"}
        if operation == "import_begin":
            manifest, control = mutation["payload"]["manifest"], mutation["payload"]
            check(mutation["target_id"] == batch and all(manifest[a] == mutation[b] for a, b in
                (("source_workspace_id", "import_source_workspace_id"), ("source_epoch", "import_source_epoch"),
                 ("manifest_hash", "import_manifest_hash"))), "IMPORT_LINEAGE_MISMATCH")
            head = self._head(db, lineage)
            predecessor = mutation["predecessor_batch_id"]
            check((head is None and predecessor is None and mutation["base_entity_version"] == 0) or
                  (head is not None and head == (predecessor, mutation["base_entity_version"])), "IMPORT_VERSION_CONFLICT")
            check(mutation["base_entity_version"] < MAXIMUM, "IMPORT_VERSION_CONFLICT")
            if predecessor is not None:
                old = db.execute("SELECT stage,publication,origin,terminal_sequence FROM import_batches WHERE id=?", (predecessor,)).fetchone()
                check(old is not None and old[0] != "completed", "IMPORT_SOURCE_OWNED")
                if control["takeover_reason"] is None:
                    fence = self._fence(db, predecessor)
                    proof = fence["proof"] if fence else None
                    closed_capacity = proof is not None and proof["reason"] == "capacity_rejected" and \
                        proof["resulting_import_revision"] == head[1] and proof["origin_device_id"] == device and \
                        proof["origin_sync_transport_generation"] == generation
                    check(old[1] is not None or old[0] == "repair_required" and (closed_capacity or db.execute(
                        "SELECT 1 FROM receipts WHERE device=? AND sequence=?", (old[2], old[3])).fetchone() is not None), "IMPORT_SOURCE_OWNED")
                    if closed_capacity:
                        check(self._recovery(db, device)["client_confirmed_through"] >= old[3], "SYNC_ACK_WATERMARK_INVALID")
                else:
                    fence = self._fence(db, predecessor)
                    proof = fence["proof"] if fence else None
                    check(proof is not None and proof["proof_id"] == control["range_close_proof_id"] and
                          proof["resulting_import_revision"] == head[1], "IMPORT_REFERENCE_INVALID")
                    reason = control["takeover_reason"]
                    if reason == "origin_unavailable":
                        check(db.execute("SELECT 1 FROM import_revoked_devices WHERE device=?", (old[2],)).fetchone() is not None, "IMPORT_SOURCE_OWNED")
                    elif reason == "local_evidence_lost":
                        check(device == old[2] and generation > proof["origin_sync_transport_generation"], "IMPORT_SOURCE_OWNED")
                    else:
                        check(reason == "ttl_payload_reclaimed" and proof["reason"] == "ttl_payload_reclaimed", "IMPORT_SOURCE_OWNED")
                    if old[2] == device and proof["kind"] == "seen_range_closed":
                        check(self._recovery(db, device)["client_confirmed_through"] >= old[3], "SYNC_ACK_WATERMARK_INVALID")
                check(db.execute("SELECT 1 FROM import_batches WHERE lineage=? AND stage='server_staging'", (lineage,)).fetchone() is None,
                      "IMPORT_SOURCE_OWNED")
            count = manifest["total_item_count"]
            check(count == sum(manifest["target_counts"].values()) + manifest["portable_preferences_count"], "IMPORT_REFERENCE_INVALID")
            check(sequence <= MAXIMUM - count - 1, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
            check(db.execute("SELECT 1 FROM import_batches WHERE origin=? AND stage='server_staging' AND ?<=terminal_sequence AND ?>=begin_sequence",
                (device, sequence, sequence + count + 1)).fetchone() is None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            capacity = self._begin_capacity_result(db, device, generation, mutation, receipt, hook)
            if capacity is not None:
                return capacity
            revision = mutation["base_entity_version"] + 1
            db.execute("INSERT INTO import_batches VALUES(?,?,?,?,?,?,'server_staging',?,?,NULL)",
                (batch, lineage, device, generation, sequence, sequence + count + 1, revision, encode(manifest)))
            db.execute("INSERT INTO import_lineage_heads VALUES(?,?,?,?,?) ON CONFLICT(lineage) DO UPDATE SET head=excluded.head,revision=excluded.revision",
                (lineage, manifest["source_workspace_id"], manifest["source_epoch"], batch, revision))
            expires = datetime.fromtimestamp(epoch(self.clock()), timezone.utc) + timedelta(seconds=self.staging_ttl_seconds)
            db.execute("INSERT INTO import_status_metadata VALUES(?,?,?,0)", (batch, predecessor, expires.strftime("%Y-%m-%dT%H:%M:%SZ")))
            db.execute("INSERT INTO import_control_inputs VALUES(?,?)", (batch, encode(control)))
            checkpoint(hook, "import_successor_begin_head")
            return staged
        binding = self._batch_binding(db, batch)
        check(binding is not None and binding["origin_device_id"] == device and
              binding["origin_sync_transport_generation"] == generation, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        manifest = binding["manifest"]
        check(binding["import_lineage_id"] == lineage and manifest["manifest_hash"] == mutation["import_manifest_hash"], "IMPORT_LINEAGE_MISMATCH")
        head = self._head(db, lineage)
        stage, revision = db.execute("SELECT stage,revision FROM import_batches WHERE id=?", (batch,)).fetchone()
        check(head == (batch, revision) and stage == "server_staging", "IMPORT_BATCH_SUPERSEDED")
        predecessor = db.execute("SELECT predecessor FROM import_status_metadata WHERE batch=?", (batch,)).fetchone()[0]
        check(predecessor == mutation["predecessor_batch_id"], "IMPORT_LINEAGE_MISMATCH")
        if operation in {"import_put", "import_delete"}:
            ordinal = mutation["import_item_ordinal"]
            check(ordinal < manifest["total_item_count"] and sequence == binding["begin_client_sequence"] + ordinal + 1, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            capacity = self._item_capacity_result(db, device, generation, mutation, receipt, manifest, hook)
            if capacity is not None:
                return capacity
            if mutation["target_type"] != "user_preferences":
                key = lineage, mutation["target_type"], mutation["payload"]["source_id"]
                old = db.execute("SELECT id FROM import_reserved_mapping WHERE lineage=? AND target=? AND source=?", key).fetchone()
                check(old is None or old[0] == mutation["target_id"], "IMPORT_LINEAGE_MISMATCH")
                collision = db.execute("SELECT lineage,source FROM import_reserved_mapping WHERE target=? AND id=?",
                    (mutation["target_type"], mutation["target_id"])).fetchone()
                check(collision is None or collision == (lineage, mutation["payload"]["source_id"]), "IMPORT_DUPLICATE_IDENTITY")
                db.execute("INSERT OR IGNORE INTO import_reserved_mapping VALUES(?,?,?,?)", (*key, mutation["target_id"]))
            db.execute("INSERT INTO import_stage_items VALUES(?,?,?,?,?,?)", (batch, ordinal, mutation["target_type"], mutation["target_id"], payload_hash, encode(mutation)))
            checkpoint(hook, "import_successor_staged_mapping")
            return staged
        check(operation == "import_commit" and sequence == binding["terminal_client_sequence"] and mutation["target_id"] == batch and
              mutation["payload"] == json.loads(db.execute("SELECT payload FROM import_control_inputs WHERE batch=?", (batch,)).fetchone()[0]), "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(mutation["base_entity_version"] == revision and revision < MAXIMUM, "IMPORT_VERSION_CONFLICT")
        rows = db.execute("SELECT ordinal,payload FROM import_stage_items WHERE batch=? ORDER BY ordinal", (batch,)).fetchall()
        items = [json.loads(row[1]) for row in rows]
        db.execute("SAVEPOINT import_publication")
        try:
            check([row[0] for row in rows] == list(range(manifest["total_item_count"])), "IMPORT_REFERENCE_INVALID")
            validate_manifest(manifest, items)
            expected = {(target, source, identifier) for target, source, identifier in db.execute(
                "SELECT target,source,id FROM import_reserved_mapping WHERE lineage=?", (lineage,))}
            actual = {(row["target_type"], row["source_id"], row["target_id"]) for row in mapping_rows(items)}
            check(actual == expected, "IMPORT_REFERENCE_INVALID")
            result = self._publish_graph(db, device, mutation, receipt, manifest, items, revision, hook)
        except ValueError as error:
            db.execute("ROLLBACK TO import_publication")
            db.execute("RELEASE import_publication")
            db.execute("UPDATE import_batches SET stage='repair_required',revision=revision+1 WHERE id=?", (batch,))
            db.execute("UPDATE import_lineage_heads SET revision=revision+1 WHERE lineage=?", (lineage,))
            return {"receipt": receipt, "per_key_results": [], "import_batch_id": batch, "status": "rejected", "effect": None,
                "conflict_ids": [], "import_stage": "repair_required", "import_disposition": "repair_required",
                "error": {"code": str(error), "context": None}, "next_revision": revision + 1}
        db.execute("RELEASE import_publication")
        return result

    def _publish_graph(self, db, device, mutation, receipt, manifest, items, revision, hook):
        lineage, batch = mutation["import_lineage_id"], mutation["import_batch_id"]
        existing = {(target, identifier): (version, json.loads(raw) if raw else None, deleted)
                    for target, identifier, version, raw, deleted in db.execute("SELECT target,id,version,fact,deleted FROM facts")}
        affected = {(item["target_type"], item["target_id"]) for item in items}
        for raw, in db.execute("SELECT detail FROM typed_conflicts WHERE status='unresolved'"):
            detail = json.loads(raw)
            blocked = {(detail["target_type"], detail["target_id"])} | {
                (row["key"]["target_type"], row["key"]["target_id"]) for row in detail["conflicting_groups"]}
            check(not affected & blocked, "SYNC_ENTITY_CONFLICT_BLOCKED")
        proposed = {key: {"target_type": key[0], "target_id": key[1], "fact": copy.deepcopy(value[1])}
                    for key, value in existing.items() if value[1] is not None and not value[2]}
        decisions, conflicts = [], []
        for item in items:
            key = item["target_type"], item["target_id"]
            old_version, old, deleted = existing.get(key, (0, None, 0))
            check(item["base_entity_version"] <= old_version, "SYNC_CAUSAL_PREDECESSOR_INVALID")
            if key[0] != "user_preferences" and old_version:
                provenance = db.execute("SELECT payload FROM import_provenance WHERE target=? AND id=?", key).fetchone()
                check(provenance is not None and json.loads(provenance[0])["import_lineage_id"] == lineage and
                      json.loads(provenance[0])["source_id"] == item["payload"]["source_id"], "IMPORT_DUPLICATE_IDENTITY")
            elif key[0] == "user_preferences":
                check(key[1] == self.account_id and old is not None, "IMPORT_REFERENCE_INVALID")
            removing = item["operation_type"] == "import_delete"
            if removing:
                proposed.pop(key, None)
                candidate = {**old, "deleted_at": item["payload"]["deleted_at"]} if old and "deleted_at" in old else None
            else:
                candidate = {**old, **item["payload"]} if key[0] == "user_preferences" else copy.deepcopy(item["payload"]["fact"])
                if key[0] == "habit" and old is not None and old["first_check_in_at"] is not None:
                    check(candidate["first_check_in_at"] is not None and all(candidate[field] == old[field] for field in
                        ("target_count_hundredths", "unit", "start_date")), "HABIT_HISTORY_IMMUTABLE")
                proposed[key] = {"target_type": key[0], "target_id": key[1], "fact": candidate}
            decisions.append({"key": key, "item": item, "old": old, "old_version": old_version, "deleted": deleted,
                "candidate": candidate, "remove": removing, "applied": [], "conflicting": [], "final": copy.deepcopy(candidate)})
        validate_graph(list(proposed.values()))
        # Compare every merge key against the source device's frozen baseline.
        merged = {key: {"target_type": key[0], "target_id": key[1], "fact": copy.deepcopy(value[1])}
                  for key, value in existing.items() if value[1] is not None and not value[2]}
        for row in decisions:
            key, item, old, candidate = row["key"], row["item"], row["old"], row["candidate"]
            definition = typed_definition(key[0], candidate or old) if candidate is not None or old is not None else None
            groups = definition["merge_groups"] if definition else {}
            fields = dict(db.execute("SELECT key,version FROM fields WHERE target=? AND id=?", key))
            if row["remove"]:
                if row["old_version"] > item["base_entity_version"] and not row["deleted"]:
                    row["conflicting"] = list(groups)
                    row["final"] = copy.deepcopy(old)
                else:
                    row["applied"] = list(groups)
                    merged.pop(key, None)
            else:
                final = copy.deepcopy(old or candidate)
                for name, names in groups.items():
                    local = {field: candidate[field] for field in names}
                    remote = None if old is None else {field: old[field] for field in names}
                    if remote != local:
                        if old is not None and (row["deleted"] or fields.get(name, 0) > item["base_entity_version"] or definition["immutable_fact"]):
                            row["conflicting"].append(name)
                        else:
                            row["applied"].append(name)
                            final.update(local)
                row["final"] = final
                if not row["deleted"] or not row["conflicting"]:
                    merged[key] = {"target_type": key[0], "target_id": key[1], "fact": final}
            row["groups"] = groups
        # A mixed projection must still be a complete valid domain graph.
        validate_graph(list(merged.values()))
        first = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0] + 1
        check(first <= MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
        for row in decisions:
            key, item = row["key"], row["item"]
            deleting = (row["remove"] and not row["conflicting"]) or (
                row["final"] is not None and row["final"].get("deleted_at") is not None) or (
                row["final"] is None and bool(row["deleted"]))
            changed = row["old_version"] == 0 or row["final"] != row["old"] or deleting != bool(row["deleted"])
            version = row["old_version"] + int(changed)
            check(version <= MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            row["version"] = version
            if changed:
                fact = row["final"]
                previous_delete = db.execute("SELECT delete_version FROM facts WHERE target=? AND id=?", key).fetchone()
                db.execute("INSERT INTO facts VALUES(?,?,?,?,?,?,NULL) ON CONFLICT(target,id) DO UPDATE SET version=excluded.version,fact=excluded.fact,deleted=excluded.deleted,delete_version=excluded.delete_version",
                    (*key, version, encode(fact) if fact is not None else None, int(deleting), version if deleting else previous_delete[0] if previous_delete else 0))
                if fact is not None:
                    for name in row["groups"] if row["old_version"] == 0 else row["applied"]:
                        db.execute("INSERT INTO fields VALUES(?,?,?,?) ON CONFLICT(target,id,key) DO UPDATE SET version=excluded.version", (*key, name, version))
                if deleting:
                    db.execute("INSERT INTO deletion_sequences VALUES(?,?,?) ON CONFLICT(target,id) DO UPDATE SET sequence=excluded.sequence", (*key, first))
            if key[0] != "user_preferences":
                provenance = {"import_lineage_id": lineage, "source_workspace_id": manifest["source_workspace_id"], "source_epoch": manifest["source_epoch"],
                    "source_target_type": key[0], "source_id": item["payload"]["source_id"]}
                db.execute("INSERT OR IGNORE INTO import_mapping VALUES(?,?,?,?)", (lineage, key[0], item["payload"]["source_id"], key[1]))
                db.execute("INSERT OR IGNORE INTO import_provenance VALUES(?,?,?)", (*key, encode(provenance)))
            if row["conflicting"]:
                detail = {"conflict_id": str(uuid.uuid4()), "conflict_version": 1, "target_type": key[0], "target_id": key[1],
                    "status": "unresolved", "source_device_id": device, "received_at": self.clock(), "conflicting_groups": [],
                    "auto_merged_groups": [], "recovery_snapshot": None if row["remove"] else {"target_type": key[0], "target_id": key[1], "fact": row["candidate"]}}
                for name in row["conflicting"]:
                    typed_key = {"target_type": key[0], "target_id": key[1], "merge_key": name}
                    if key[0] == "reminder_intent":
                        typed_key["owner_type"] = row["old"]["owner_type"]
                    remote = {"kind": "deleted"} if row["deleted"] else {"kind": "value", "projection": {**typed_key,
                        "value": {field: row["old"][field] for field in row["groups"][name]}}}
                    local = {"kind": "deleted"} if row["remove"] else {"kind": "value", "projection": {**typed_key,
                        "value": {field: row["candidate"][field] for field in row["groups"][name]}}}
                    detail["conflicting_groups"].append({"key": typed_key, "server_candidate": remote, "local_candidate": local})
                for name in row["applied"]:
                    typed_key = {"target_type": key[0], "target_id": key[1], "merge_key": name}
                    if key[0] == "reminder_intent":
                        typed_key["owner_type"] = row["candidate"]["owner_type"]
                    detail["auto_merged_groups"].append({"projection": {**typed_key,
                        "value": {field: row["candidate"][field] for field in row["groups"][name]}},
                        "resulting_entity_version": version, "resulting_field_version": version})
                validate_schema("sync/sync_conflict_detail.schema.json", detail)
                conflicts.append({"kind": "created", "conflict": detail})
                db.execute("INSERT INTO conflicts VALUES(?,?,?,'unresolved',?)", (detail["conflict_id"], *key, encode(detail)))
            checkpoint(hook, "import_successor_canonical:" + key[0])
        images = [self.image(db, *row["key"]) for row in decisions]
        group = str(uuid.uuid4())
        lines = publication({"import_lineage_id": lineage, "import_batch_id": batch, **manifest}, [*images, *conflicts], first, group)
        last = lines[-1]["commit_server_sequence"]
        effect = {"effect_change_group_id": group, "effect_group_last_server_sequence": last}
        for delta in conflicts:
            detail = delta["conflict"]
            db.execute("INSERT INTO typed_conflicts VALUES(?,1,'unresolved',?,NULL,?)", (detail["conflict_id"], encode(detail), encode(effect)))
        db.executemany("INSERT INTO import_publication_lines VALUES(?,?,?)", ((line["server_sequence"], group, encode(line)) for line in lines))
        db.execute("INSERT INTO groups VALUES(?,?,?)", (group, last, encode(lines)))
        db.execute("UPDATE account SET sequence=? WHERE singleton=1", (last,))
        db.executemany("UPDATE facts SET last_group=? WHERE target=? AND id=?", ((group, *row["key"]) for row in decisions))
        metadata = {name: value for name, value in lines[0].items() if name not in {"kind", "server_sequence"}}
        db.execute("INSERT INTO import_published_markers VALUES(?,?)", (batch, encode(metadata)))
        db.execute("INSERT INTO import_publication_times VALUES(?,?)", (batch, self.clock()))
        predecessor = mutation["predecessor_batch_id"]
        if predecessor is not None:
            db.execute("UPDATE import_batches SET stage='superseded' WHERE id=? AND publication IS NULL", (predecessor,))
        db.execute("UPDATE import_batches SET stage='server_confirmed',revision=?,publication=? WHERE id=?", (revision + 1, encode(metadata), batch))
        db.execute("UPDATE import_lineage_heads SET revision=? WHERE lineage=?", (revision + 1, lineage))
        checkpoint(hook, "import_successor_publication_head")
        return {"receipt": receipt, "per_key_results": [], "import_batch_id": batch, "status": "accepted", "effect": effect,
            "conflict_ids": [row["conflict"]["conflict_id"] for row in conflicts], "import_stage": "server_confirmed",
            "import_disposition": "server_confirmed", "error": None, "publish_group_id": group, "commit_server_sequence": last,
            "canonical_digest": metadata["publish_digest"], "import_revision": revision + 1}
