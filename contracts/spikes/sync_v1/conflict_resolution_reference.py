"""Typed root conflict lifecycle composed with real device/receipt transactions.

An isolated Contract oracle. Owned recurrence revision allocation, imports and
production HTTP/Core owners remain separate; unsupported composition fails closed.
"""
import copy
import json
import uuid

from bootstrap_reference import CAPS, checkpoint, epoch
from counter_reference import MAXIMUM, integer
from domain_reference import check, definitions, validate_fact, validate_graph, validate_schema
from local_download_reference import group_hash
from protocol_reference import ProtocolStore, canonical, digest, encode, mutation_hash, typed_definition
from resolution_contract_reference import choose_resolution, validate_resolution, validate_resolution_fields


class ConflictStore(ProtocolStore):
    def __init__(self, path, *, server_time="2026-09-06T01:00:00Z", hook=None):
        super().__init__(path)
        self.server_time, self.hook = server_time, hook
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS typed_groups(id TEXT PRIMARY KEY,sequence INTEGER UNIQUE,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS typed_conflicts(id TEXT PRIMARY KEY,version INTEGER NOT NULL,status TEXT NOT NULL,
                    detail TEXT NOT NULL,resolution TEXT,effect TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS resolution_metadata(device TEXT,sequence INTEGER,payload TEXT NOT NULL,PRIMARY KEY(device,sequence));
                CREATE TABLE IF NOT EXISTS deletion_sequences(target TEXT,id TEXT,sequence INTEGER NOT NULL,PRIMARY KEY(target,id));
            """)

    @staticmethod
    def image(db, target, identifier):
        row = db.execute("SELECT version,fact,deleted,delete_version,last_group FROM facts WHERE target=? AND id=?", (target, identifier)).fetchone()
        check(row is not None, "SYNC_APPLY_FAILED")
        version, raw, deleted, delete_version, last_group = row
        record = {"target_type": target, "target_id": identifier, "entity_version": version, "import_provenance": None}
        if raw is None:
            sequence = db.execute("SELECT sequence FROM deletion_sequences WHERE target=? AND id=?", (target, identifier)).fetchone()
            check(deleted and sequence is not None, "SYNC_APPLY_FAILED")
            return {"kind": "deleted_entity_anchor", **record, "delete_server_sequence": sequence[0]}
        fact = json.loads(raw)
        key = {"target_type": target, "target_id": identifier}
        if target == "reminder_intent":
            key["owner_type"] = fact["owner_type"]
        result = {"kind": "tombstone" if deleted else "fact_after_image", **record, "fact": fact,
            "field_versions": [{"key": {**key, "merge_key": name}, "field_version": value}
                for name, value in db.execute("SELECT key,version FROM fields WHERE target=? AND id=? ORDER BY key", (target, identifier))]}
        if deleted:
            effect = db.execute("SELECT sequence FROM deletion_sequences WHERE target=? AND id=?", (target, identifier)).fetchone()
            check(effect is not None, "SYNC_APPLY_FAILED")
            result.update(deleted_at=fact["deleted_at"], delete_server_sequence=effect[0])
        return result

    def _persist_group(self, db, identifier, sequence, entities, deltas):
        group = {"kind": "change_group", "change_group_id": identifier, "server_sequence": sequence,
            "entity_changes": entities, "conflict_deltas": deltas}
        group["payload_hash"] = group_hash(group)
        validate_schema("sync/sync_change_group.schema.json", group)
        check(len(canonical(group)) <= CAPS["ordinary_group_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        db.execute("INSERT INTO typed_groups VALUES(?,?,?)", (identifier, sequence, encode(group)))
        return group

    def _apply(self, db, device, mutation, payload_hash):
        result = super()._apply(db, device, mutation, payload_hash)
        effect = result["effect"]
        if effect is None or db.execute("SELECT 1 FROM typed_groups WHERE id=?", (effect["effect_change_group_id"],)).fetchone():
            return result
        if mutation["operation_type"] == "delete" and any(row["causal_disposition"] == "applied" for row in result["per_key_results"]):
            db.execute("INSERT OR REPLACE INTO deletion_sequences VALUES(?,?,?)", (mutation["target_type"], mutation["target_id"], effect["effect_group_last_server_sequence"]))
        image = self.image(db, mutation["target_type"], mutation["target_id"])
        deltas = []
        for identifier in result["conflict_ids"]:
            raw = json.loads(db.execute("SELECT payload FROM conflicts WHERE id=?", (identifier,)).fetchone()[0])
            key = {"target_type": mutation["target_type"], "target_id": mutation["target_id"]}
            detail = {"conflict_id": identifier, "conflict_version": 1, **key, "status": "unresolved",
                "source_device_id": device, "received_at": self.server_time, "conflicting_groups": [], "auto_merged_groups": [],
                "recovery_snapshot": None if mutation["conflict_recovery_snapshot"] is None else {**key, "fact": mutation["conflict_recovery_snapshot"]}}
            for row in raw["conflicting_groups"]:
                merge_key = {**key, "merge_key": row["merge_key"]}
                remote = ({"kind": "deleted", "entity_version": image["entity_version"], "delete_server_sequence": image["delete_server_sequence"]}
                    if image["kind"] != "fact_after_image" else {"kind": "value", "projection": {**merge_key, "value": row["server"]}})
                detail["conflicting_groups"].append({"key": merge_key, "server_candidate": remote,
                    "local_candidate": {"kind": "value", "projection": {**merge_key, "value": row["local"]}}})
            detail["auto_merged_groups"] = [{"projection": {**key, "merge_key": row["merge_key"], "value": row["value"]},
                "resulting_entity_version": row["resulting_version"], "resulting_field_version": row["resulting_version"]}
                for row in raw["auto_merged_groups"]]
            validate_schema("sync/sync_conflict_detail.schema.json", detail)
            db.execute("INSERT INTO typed_conflicts VALUES(?,1,'unresolved',?,NULL,?)", (identifier, encode(detail), encode(effect)))
            deltas.append({"kind": "created", "conflict": detail})
        self._persist_group(db, effect["effect_change_group_id"], effect["effect_group_last_server_sequence"], [image], deltas)
        checkpoint(self.hook, "conflict_created_group")
        return result

    @staticmethod
    def _current(row, identifier):
        if row is None:
            return {"kind": "missing"}
        if row[1] == "unresolved":
            return {"kind": "unresolved", "conflict_id": identifier, "conflict_version": row[0]}
        return {"kind": "resolved", "conflict_id": identifier, "conflict_version": row[0],
            "resolved_at": json.loads(row[3])["resolved_at"], **json.loads(row[4])}

    def _validate_resolution_scope(self, mutation):
        check(not mutation["payload"]["prepared_owned_dependencies"], "REFERENCE_RESOLUTION_OWNED_REQUIRED")
        check(mutation["target_type"] in {"category", "event", "anniversary", "habit"}, "REFERENCE_RESOLUTION_TARGET_REQUIRED")

    def resolve(self, device, generation, mutation, payload_hash, *, hook=None):
        validate_resolution(mutation, payload_hash)
        integer(generation)
        self._validate_resolution_scope(mutation)
        sequence = mutation["client_sequence"]
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            state = db.execute("SELECT highest,generation,blocked FROM devices WHERE id=?", (device,)).fetchone()
            check(state is not None, "DEVICE_NOT_REGISTERED")
            check(state[1] == generation, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(not state[2], "SYNC_SEQUENCE_REPLAY_MISMATCH")
            old = db.execute("SELECT device,sequence,mutation,hash,result FROM receipts WHERE (device=? AND sequence=?) OR mutation=?",
                (device, sequence, mutation["mutation_id"])).fetchall()
            if old:
                if len(old) != 1 or old[0][:4] != (device, sequence, mutation["mutation_id"], payload_hash):
                    db.execute("UPDATE devices SET blocked=1 WHERE id=?", (device,))
                    db.commit()
                    raise ValueError("SYNC_SEQUENCE_REPLAY_MISMATCH")
                metadata = db.execute("SELECT payload FROM resolution_metadata WHERE device=? AND sequence=?", (device, sequence)).fetchone()
                check(metadata is not None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
                result = json.loads(old[0][4])
                return {"protocol_version": 1, "device_id": device, "sync_transport_generation": generation,
                    "result": {"status": "duplicate", "original_status": result["status"], "client_sequence": sequence,
                        "mutation_id": mutation["mutation_id"], "payload_hash": payload_hash, "original_result": result},
                    "current_conflict": json.loads(metadata[0])}
            check(sequence == state[0] + 1, "SYNC_CLIENT_SEQUENCE_GAP")
            result, current = self._resolve_business(db, device, mutation, payload_hash, hook)
            response = {"protocol_version": 1, "device_id": device, "sync_transport_generation": generation,
                "result": result, "current_conflict": current}
            validate_schema("sync/backend_sync_conflict_resolution_response.schema.json", response)
            db.execute("INSERT INTO receipts VALUES(?,?,?,?,?)", (device, sequence, mutation["mutation_id"], payload_hash, encode(result)))
            db.execute("INSERT INTO resolution_metadata VALUES(?,?,?)", (device, sequence, encode(current)))
            checkpoint(hook, "resolution_receipt")
            db.execute("UPDATE devices SET highest=? WHERE id=?", (sequence, device))
            checkpoint(hook, "resolution_device_sequence")
            return response

    def _resolve_business(self, db, device, m, payload_hash, hook):
        p = m["payload"]
        identifier = p["conflict_id"]
        row = db.execute("SELECT version,status,detail,resolution,effect FROM typed_conflicts WHERE id=?", (identifier,)).fetchone()
        current = self._current(row, identifier)
        key = {"target_type": m["target_type"], "target_id": m["target_id"]}
        keys = [item["merge_key"] for item in m["causal_predecessors"]]
        result = {"status": "rejected", "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
            "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": payload_hash},
            "effect": json.loads(row[4]) if row else None, "per_key_results": [], "conflict_ids": [identifier] if row and row[1] == "unresolved" else [],
            "failure_code": None, "failure_context": None, "import_batch_id": None, "import_stage": None}
        for name in keys:
            prior, version = self._baseline(db, device, m, name)
            result["per_key_results"].append({"key": {**key, "merge_key": name}, "causal_disposition": "no_effect",
                "resulting_field_version": None, "effective_prior_sequence": prior, "effective_prior_version": version})
        if row is None:
            result["failure_code"] = "SYNC_CONFLICT_NOT_FOUND"
            return result, current
        detail = json.loads(row[2])
        check(all(detail[name] == m[name] for name in key), "SYNC_IDENTITY_MISMATCH")
        if row[1] == "resolved":
            result["failure_code"] = "SYNC_CONFLICT_ALREADY_RESOLVED"
            return result, current
        if row[0] != p["expected_conflict_version"]:
            result.update(failure_code="SYNC_CONFLICT_VERSION_MISMATCH", failure_context={"conflict_id": identifier, "current_conflict_version": row[0]})
            return result, current
        baseline = self.image(db, m["target_type"], m["target_id"])
        check(m["base_entity_version"] <= baseline["entity_version"], "SYNC_CAUSAL_PREDECESSOR_INVALID")
        definition = typed_definition(m["target_type"], baseline.get("fact") or detail["recovery_snapshot"]["fact"])
        try:
            candidate = choose_resolution(detail, baseline, p["resolution"])
            if candidate is not None:
                validate_fact({**key, "fact": candidate})
                validate_resolution_fields(m["target_type"], baseline.get("fact") or detail["recovery_snapshot"]["fact"], candidate,
                    manual=p["resolution"]["mode"] == "manual_edit")
            graph = [{"target_type": target, "target_id": entity, "fact": json.loads(raw)}
                for target, entity, raw in db.execute("SELECT target,id,fact FROM facts WHERE fact IS NOT NULL") if (target, entity) != (m["target_type"], m["target_id"])]
            validate_graph([*graph, *([{**key, "fact": candidate}] if candidate is not None else [])])
        except ValueError as failure:
            result["failure_code"] = str(failure)
            return result, current
        changed = [] if candidate is None else [name for name, fields in definition["merge_groups"].items()
            if baseline.get("fact") is None or any(baseline["fact"][field] != candidate[field] for field in fields)]
        expected_keys = {item["key"]["merge_key"] for item in detail["conflicting_groups"]} | set(changed)
        check(set(keys) == expected_keys, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        check(row[0] < MAXIMUM and baseline["entity_version"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
        last_sequence = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0]
        check(last_sequence < MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
        version, conflict_version = baseline["entity_version"] + 1, row[0] + 1
        group_id, server_sequence = str(uuid.uuid4()), last_sequence + 1
        effect = {"effect_change_group_id": group_id, "effect_group_last_server_sequence": server_sequence}
        deleted = candidate is None or candidate.get("deleted_at") is not None
        if candidate is not None and deleted and (baseline["kind"] == "fact_after_image" or candidate["deleted_at"] != baseline.get("fact", {}).get("deleted_at")):
            db.execute("INSERT OR REPLACE INTO deletion_sequences VALUES(?,?,?)", (m["target_type"], m["target_id"], server_sequence))
        db.execute("UPDATE facts SET version=?,fact=?,deleted=?,delete_version=?,last_group=? WHERE target=? AND id=?",
            (version, encode(candidate) if candidate is not None else None, int(deleted), version if deleted else 0, group_id, m["target_type"], m["target_id"]))
        for name in changed:
            db.execute("UPDATE fields SET version=? WHERE target=? AND id=? AND key=?", (version, m["target_type"], m["target_id"], name))
            db.execute("INSERT OR REPLACE INTO anchors VALUES(?,?,?,?,?,?)", (device, m["target_type"], m["target_id"], name, m["client_sequence"], version))
            entry = next(item for item in result["per_key_results"] if item["key"]["merge_key"] == name)
            entry.update(causal_disposition="applied", resulting_field_version=version)
        checkpoint(hook, "resolution_fact_and_fields")
        resolved = {"kind": "resolved", "conflict_id": identifier, "conflict_version": conflict_version,
            "resolved_at": self.server_time, "resolution_mode": p["resolution"]["mode"], "resulting_entity_version": version,
            "resolution_receipt": result["receipt"]}
        db.execute("INSERT INTO groups VALUES(?,?,?)", (group_id, server_sequence, encode(resolved)))
        db.execute("UPDATE account SET sequence=? WHERE singleton=1", (server_sequence,))
        db.execute("UPDATE typed_conflicts SET version=?,status='resolved',resolution=?,effect=? WHERE id=?",
            (conflict_version, encode(resolved), encode(effect), identifier))
        db.execute("UPDATE conflicts SET status='resolved' WHERE id=?", (identifier,))
        checkpoint(hook, "resolution_conflict_lifecycle")
        self._persist_group(db, group_id, server_sequence, [self.image(db, m["target_type"], m["target_id"])], [resolved])
        checkpoint(hook, "resolution_change_group")
        result.update(status="accepted", effect=effect, conflict_ids=[])
        return result, {"kind": "resolved", "conflict_id": identifier, "conflict_version": conflict_version, "resolved_at": self.server_time, **effect}

    def snapshot(self):
        result = super().snapshot()
        with self.connect() as db:
            for name in ("typed_groups", "typed_conflicts", "resolution_metadata", "deletion_sequences"):
                result[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return result

    def retire_tombstone_payload(self, target, identifier, *, retention_floor):
        """Synthetic Backend maintenance under authenticated server watermarks.

        The timestamp belongs to this Backend oracle; no client-supplied clock
        can choose the age. Permanent deletion identity and sequence are retained.
        """
        integer(retention_floor)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            check(retention_floor <= db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0], "SYNC_PAYLOAD_INVALID")
            image = self.image(db, target, identifier)
            if image["kind"] != "tombstone" or image["delete_server_sequence"] > retention_floor:
                return False
            now = epoch(self.server_time)
            if epoch(image["deleted_at"]) + 180 * 86400 > now:
                return False
            for status, detail, resolved in db.execute("SELECT status,detail,resolution FROM typed_conflicts"):
                detail = json.loads(detail)
                if (detail["target_type"], detail["target_id"]) == (target, identifier):
                    if status == "unresolved" or epoch(json.loads(resolved)["resolved_at"]) + 30 * 86400 > now:
                        return False
            db.execute("UPDATE facts SET fact=NULL WHERE target=? AND id=?", (target, identifier))
            return True
