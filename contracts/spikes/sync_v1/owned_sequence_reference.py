"""Owned graph writes composed with real device ordering and typed change feed.

Uses the same temporary SQLite device/receipt/anchor owner as root mutations.
It does not implement import or Android/Backend production services.
"""
import copy
from contextlib import contextmanager
import json
import uuid

from bootstrap_reference import checkpoint
from conflict_resolution_reference import ConflictStore
from counter_reference import MAXIMUM
from domain_reference import check, validate_schema
from owned_graph_reference import adjudicate
from protocol_reference import encode, mutation_keys, typed_definition, validate_terminal_for_mutation


def flattened(mutation):
    return [mutation] + [{**row, "client_sequence": mutation["client_sequence"],
        "payload": {"fact" if row["operation_type"] == "create" else "patch": row["payload"]}}
        for row in mutation["payload"].get("owned_dependencies", [])]


def qualified_key(node, name):
    result = {"target_type": node["target_type"], "target_id": node["target_id"], "merge_key": name}
    if node["target_type"] == "reminder_intent":
        fact = node["payload"].get("fact") or node["conflict_recovery_snapshot"]
        if node["operation_type"] == "resolve_conflict":
            fact = fact["fact"]
        result["owner_type"] = fact["owner_type"]
    return result


class OwnedSequenceStore(ConflictStore):
    @contextmanager
    def connect(self):
        with super().connect() as db:
            if getattr(self, "hook", None) is not None:
                # TEMP triggers inject a real exit after the underlying owner
                # writes its receipt/highest, without replacing that owner.
                db.create_function("owned_spike_checkpoint", 1, lambda point: checkpoint(self.hook, point))
                for table, trigger in (("receipts", "AFTER INSERT ON receipts"), ("devices", "AFTER UPDATE OF highest ON devices")):
                    if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone():
                        point = "owned_receipt" if table == "receipts" else "owned_device_sequence"
                        db.execute("CREATE TEMP TRIGGER owned_checkpoint_" + table + " " + trigger +
                            " BEGIN SELECT owned_spike_checkpoint('" + point + "'); END")
            yield db

    def snapshot(self):
        result = super().snapshot()
        with self.connect() as db:
            result["account"] = db.execute("SELECT * FROM account").fetchall()
            result["fences"] = db.execute("SELECT * FROM fences ORDER BY 1,2").fetchall()
        return result

    def _baseline(self, db, device, node, name):
        predecessor = next(row["client_sequence"] for row in node["causal_predecessors"] if row["merge_key"] == name)
        if predecessor is None:
            return None, node["base_entity_version"]
        anchor = db.execute("SELECT sequence,version FROM anchors WHERE device=? AND target=? AND id=? AND key=?",
            (device, node["target_type"], node["target_id"], name)).fetchone()
        if anchor and anchor[0] == predecessor:
            return anchor
        receipt = db.execute("SELECT result FROM receipts WHERE device=? AND sequence=?", (device, predecessor)).fetchone()
        check(receipt is not None, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        receipt = json.loads(receipt[0])
        check(receipt["status"] != "staged", "SYNC_CAUSAL_PREDECESSOR_INVALID")
        row = next((row for row in receipt["per_key_results"] if row["key"] == qualified_key(node, name)), None)
        check(row is not None, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        return (predecessor, row["resulting_field_version"]) if row["causal_disposition"] == "applied" else (
            row["effective_prior_sequence"], row["effective_prior_version"])

    def _apply(self, db, device, mutation, payload_hash):
        category_creation = mutation["target_type"] == "category" and mutation["operation_type"] in {"create", "restore"}
        if not category_creation and (mutation["target_type"] not in {"event", "anniversary", "habit", "reminder_intent"} or mutation["operation_type"] not in {"create", "update", "restore"}):
            return super()._apply(db, device, mutation, payload_hash)
        nodes = flattened(mutation)
        identities = [(row["target_type"], row["target_id"]) for row in nodes]
        check(len(identities) == len(set(identities)) and identities[1:] == sorted(identities[1:]), "SYNC_PAYLOAD_INVALID")
        versions = {(target, identifier): version for target, identifier, version in db.execute("SELECT target,id,version FROM facts")}
        baselines, by_key = {}, {}
        result = {"status": "accepted", "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
            "client_sequence": mutation["client_sequence"], "mutation_id": mutation["mutation_id"], "payload_hash": payload_hash},
            "effect": None, "per_key_results": [], "conflict_ids": [], "failure_code": None, "failure_context": None,
            "import_batch_id": None, "import_stage": None}
        for node, identity in zip(nodes, identities):
            keys = mutation_keys(node)
            check([row["merge_key"] for row in node["causal_predecessors"]] == keys and all(row["client_sequence"] is None or
                row["client_sequence"] < mutation["client_sequence"] for row in node["causal_predecessors"]), "SYNC_CAUSAL_PREDECESSOR_INVALID")
            check(node["base_entity_version"] <= versions.get(identity, 0), "SYNC_CAUSAL_PREDECESSOR_INVALID")
            for name in keys:
                qualified = (*identity, name)
                baselines[qualified] = self._baseline(db, device, node, name)
                prior, version = baselines[qualified]
                row = {"key": qualified_key(node, name), "causal_disposition": "no_effect", "resulting_field_version": None,
                    "effective_prior_sequence": prior, "effective_prior_version": version}
                result["per_key_results"].append(row)
                by_key[qualified] = row
        blocked = []
        for conflict_id, raw, effect in db.execute("SELECT id,detail,effect FROM typed_conflicts WHERE status='unresolved'"):
            detail = json.loads(raw)
            affected = {(detail["target_type"], detail["target_id"])} | {
                (row["key"]["target_type"], row["key"]["target_id"]) for row in detail["conflicting_groups"]}
            if affected & set(identities):
                blocked.append((conflict_id, json.loads(effect)))
        if blocked:
            result.update(status="rejected", failure_code="SYNC_ENTITY_CONFLICT_BLOCKED", conflict_ids=sorted(row[0] for row in blocked),
                effect=max((row[1] for row in blocked), key=lambda effect: effect["effect_group_last_server_sequence"]))
            validate_terminal_for_mutation(result, mutation)
            return result
        graph = {(target, identifier): {"target_type": target, "target_id": identifier, "fact": json.loads(raw)}
            for target, identifier, raw in db.execute("SELECT target,id,fact FROM facts WHERE fact IS NOT NULL")}
        fields = {(target, identifier, name): version for target, identifier, name, version in db.execute("SELECT * FROM fields")}
        try:
            decision = adjudicate(graph, fields, mutation, causal_baselines=baselines)
        except ValueError as error:
            if str(error) == "SYNC_CAUSAL_PREDECESSOR_INVALID":
                raise
            result.update(status="rejected", failure_code=str(error))
            validate_terminal_for_mutation(result, mutation)
            return result
        for identity in decision["changed"]:
            check(versions.get(identity, 0) < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
        if decision["changed"] or decision["conflicting"]:
            check(db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0] < MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
        for identity in decision["changed"]:
            version = versions.get(identity, 0) + 1
            record = decision["graph"][identity]
            old = db.execute("SELECT delete_version,last_group FROM facts WHERE target=? AND id=?", identity).fetchone()
            db.execute("INSERT OR REPLACE INTO facts VALUES(?,?,?,?,?,?,?)", (*identity, version, encode(record["fact"]),
                int(record["fact"].get("deleted_at") is not None), old[0] if old else 0, old[1] if old else None))
            for qualified in decision["applied"]:
                if qualified[:2] == identity:
                    db.execute("INSERT OR REPLACE INTO fields VALUES(?,?,?,?)", (*qualified, version))
                    db.execute("INSERT OR REPLACE INTO anchors VALUES(?,?,?,?,?,?)", (device, *qualified, mutation["client_sequence"], version))
                    by_key[qualified].update(causal_disposition="applied", resulting_field_version=version)
            checkpoint(self.hook, "owned_fact_and_fields:" + identity[0])
        result["status"] = decision["status"]
        deltas = []
        if decision["conflicting"]:
            detail = {"conflict_id": str(uuid.uuid4()), "conflict_version": 1, "target_type": mutation["target_type"],
                "target_id": mutation["target_id"], "status": "unresolved", "source_device_id": device, "received_at": self.server_time,
                "conflicting_groups": [], "auto_merged_groups": [], "recovery_snapshot": None if mutation["conflict_recovery_snapshot"] is None else {
                    "target_type": mutation["target_type"], "target_id": mutation["target_id"], "fact": mutation["conflict_recovery_snapshot"]}}
            for qualified in decision["conflicting"]:
                key = by_key[qualified]["key"]
                old = graph.get(qualified[:2])
                remote = {"kind": "absent"} if old is None else {"kind": "value", "projection": {**key,
                    "value": {name: old["fact"][name] for name in decision["candidates"][qualified]}}}
                detail["conflicting_groups"].append({"key": key, "server_candidate": remote,
                    "local_candidate": {"kind": "value", "projection": {**key, "value": decision["candidates"][qualified]}}})
            for qualified in decision["applied"]:
                version = by_key[qualified]["resulting_field_version"]
                detail["auto_merged_groups"].append({"projection": {**by_key[qualified]["key"], "value": decision["candidates"][qualified]},
                    "resulting_entity_version": version, "resulting_field_version": version})
            validate_schema("sync/sync_conflict_detail.schema.json", detail)
            db.execute("INSERT INTO conflicts VALUES(?,?,?,'unresolved',?)", (detail["conflict_id"], mutation["target_type"], mutation["target_id"], encode(detail)))
            result["conflict_ids"] = [detail["conflict_id"]]
            deltas = [{"kind": "created", "conflict": detail}]
            checkpoint(self.hook, "owned_conflict_lifecycle")
        if decision["changed"] or deltas:
            sequence = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0] + 1
            group_id = str(uuid.uuid4())
            effect = {"effect_change_group_id": group_id, "effect_group_last_server_sequence": sequence}
            entity_keys = sorted(set(decision["changed"]) | {identity for identity in identities if identity in graph})
            images = [self.image(db, *identity) for identity in entity_keys]
            group = self._persist_group(db, group_id, sequence, images, deltas)
            db.execute("INSERT INTO groups VALUES(?,?,?)", (group_id, sequence, encode(group)))
            db.execute("UPDATE account SET sequence=? WHERE singleton=1", (sequence,))
            db.executemany("UPDATE facts SET last_group=? WHERE target=? AND id=?", ((group_id, *identity) for identity in entity_keys))
            if deltas:
                detail = deltas[0]["conflict"]
                db.execute("INSERT INTO typed_conflicts VALUES(?,1,'unresolved',?,NULL,?)", (detail["conflict_id"], encode(detail), encode(effect)))
            result["effect"] = effect
            checkpoint(self.hook, "owned_typed_change_group")
        else:
            effects = [self._effect(db, row[0]) for identity in identities if (row := db.execute(
                "SELECT last_group FROM facts WHERE target=? AND id=?", identity).fetchone()) and row[0]]
            if effects:
                result["effect"] = max(effects, key=lambda effect: effect["effect_group_last_server_sequence"])
        validate_terminal_for_mutation(result, mutation)
        return result
