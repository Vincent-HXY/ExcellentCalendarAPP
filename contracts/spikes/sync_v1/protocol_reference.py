"""Isolated SQLite oracle for Sync ordering, field merge and ack/apply semantics.

It is not a Backend, Native bridge or substitute for PostgreSQL/Android evidence.
Unimplemented import/owned-graph operations fail explicitly. No network or user DB
is accessed. Canonicalization here accepts only the Contract's safe-integer domain;
the separate C++/Java JCS spike covers the full binary64 number grammar.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import uuid

from counter_reference import MAXIMUM, integer
from domain_reference import check, definitions, validate_fact, validate_patch, validate_schema
from sqlite_reference import connect


def canonical(value) -> bytes:
    def encode(v):
        if v is None:
            return "null"
        if type(v) is bool:
            return "true" if v else "false"
        if type(v) in {int, float}:
            return str(integer(v))
        if isinstance(v, str):
            v.encode("utf-8", errors="strict")
            return json.dumps(v, ensure_ascii=False, separators=(",", ":"))
        if isinstance(v, list):
            return "[" + ",".join(encode(x) for x in v) + "]"
        if isinstance(v, dict) and all(isinstance(k, str) for k in v):
            return "{" + ",".join(encode(k) + ":" + encode(v[k]) for k in sorted(v, key=lambda s: s.encode("utf-16-be"))) + "}"
        raise ValueError("SYNC_PAYLOAD_INVALID")
    return encode(value).encode("utf-8")


def digest(value) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def mutation_hash(mutation: dict) -> str:
    return digest({key: value for key, value in mutation.items() if key != "created_at"})


def typed_definition(target: str, fact: dict):
    return definitions()[1]["targets"][target]["variants"][fact["owner_type"] if target == "reminder_intent" else "default"]


def mutation_keys(mutation: dict) -> list[str]:
    target, operation, payload = mutation["target_type"], mutation["operation_type"], mutation["payload"]
    if operation == "resolve_conflict":
        # The complete write set is frozen by the resolution writer. Its exact
        # relationship to the current conflict is checked by that route owner.
        return [row["merge_key"] for row in mutation["causal_predecessors"]]
    if operation.startswith("import_"):
        return []
    if target == "habit_check_in":
        from domain_reference import ROOT, read_yaml
        # The operation's semantic write set includes lifecycle barriers and
        # immutable snapshot checks, even when a member is ultimately no-effect.
        if not hasattr(mutation_keys, "habit_policy"):
            mutation_keys.habit_policy = read_yaml(ROOT / "contracts/sync/sync_habit_operation_protocol.yaml")
        check(operation in mutation_keys.habit_policy["operations"], "SYNC_OPERATION_UNSUPPORTED")
        return mutation_keys.habit_policy["operations"][operation]["merge_keys"][:]
    fact = payload.get("fact") or mutation["conflict_recovery_snapshot"] or {}
    definition = typed_definition(target, fact)
    if operation == "update":
        keys = {definition["fields"][name]["merge_key"] for name in payload["patch"]}
    elif operation in {"delete", "clear"}:
        keys = {"lifecycle" if operation == "delete" else "completion"}
    elif operation in {"increment", "decrement", "replace_total"}:
        keys = {"completion"}
    else:
        keys = set(definition["merge_groups"])
    return sorted(keys, key=lambda key: key.encode("utf-16-be"))


def mutation_dependencies(mutation):
    return mutation["payload"].get("prepared_owned_dependencies" if mutation["operation_type"] == "resolve_conflict" else "owned_dependencies", [])


def validate_mutation(mutation: dict, payload_hash: str):
    if mutation.get("operation_type") == "resolve_conflict":
        from resolution_contract_reference import validate_resolution
        return validate_resolution(mutation, payload_hash)
    validate_schema("sync/sync_mutation.schema.json", mutation)
    check(mutation_hash(mutation) == payload_hash, "SYNC_PAYLOAD_HASH_MISMATCH")
    expected = mutation_keys(mutation)
    actual = [row["merge_key"] for row in mutation["causal_predecessors"]]
    check(actual == expected, "SYNC_CAUSAL_PREDECESSOR_INVALID")
    for row in mutation["causal_predecessors"]:
        check(row["client_sequence"] is None or row["client_sequence"] < mutation["client_sequence"],
              "SYNC_CAUSAL_PREDECESSOR_INVALID")
    target, payload = mutation["target_type"], mutation["payload"]
    if target == "habit_check_in" and not mutation["operation_type"].startswith("import_"):
        from identity_reference import check_in_id
        check(mutation["target_id"] == check_in_id(payload["habit_id"], payload["check_date"]), "SYNC_IDENTITY_MISMATCH")
        if "fact" in payload:
            check(all(payload["fact"][name] == payload[name] for name in ("habit_id", "check_date", "source")), "SYNC_IDENTITY_MISMATCH")
    if "fact" in payload:
        validate_fact({"target_type": target, "target_id": mutation["target_id"], "fact": payload["fact"]})
    if mutation["conflict_recovery_snapshot"] is not None:
        validate_fact({"target_type": target, "target_id": mutation["target_id"], "fact": mutation["conflict_recovery_snapshot"]})


def unwrap_terminal(result: dict) -> dict:
    validate_schema("sync/sync_upload_result.schema.json", result)
    original = result["original_result"] if result["status"] == "duplicate" else result
    if result["status"] == "duplicate":
        check(all(result[name] == original["receipt"][name] for name in ("client_sequence", "mutation_id", "payload_hash")) and
              result["original_status"] == original["status"], "SYNC_SEQUENCE_REPLAY_MISMATCH")
    return original


def validate_terminal_for_mutation(result: dict, mutation: dict) -> dict:
    """Mandatory receipt/operation bindings that JSON Schema cannot compare."""
    original = unwrap_terminal(result)
    receipt = original["receipt"]
    expected = {"client_sequence": mutation["client_sequence"], "mutation_id": mutation["mutation_id"], "payload_hash": mutation_hash(mutation)}
    check(all(receipt[name] == value for name, value in expected.items()), "SYNC_SEQUENCE_REPLAY_MISMATCH")
    if result["status"] == "duplicate":
        check(all(result[name] == value for name, value in expected.items()) and result["original_status"] == original["status"],
              "SYNC_SEQUENCE_REPLAY_MISMATCH")
    imported = mutation["operation_type"].startswith("import_")
    if original.get("failure_code") == "SYNC_RESOLUTION_CANDIDATE_INVALID":
        check(mutation["operation_type"] == "resolve_conflict", "SYNC_SEQUENCE_ROUTE_MISMATCH")
    if original.get("failure_code") == "SYNC_HABIT_OPERATION_ID_REUSED":
        check(mutation["target_type"] == "habit_check_in" and mutation["operation_type"] in {"increment", "decrement", "replace_total", "clear"}
              and original["failure_context"] == {"operation_id": mutation["payload"]["operation_id"]}, "SYNC_SEQUENCE_ROUTE_MISMATCH")
    check(original["import_batch_id"] == mutation["import_batch_id"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
    fenced = original.get("failure_code") in {"IMPORT_BATCH_ABANDONED", "IMPORT_BATCH_SUPERSEDED"}
    if mutation["operation_type"] == "import_commit" and not fenced:
        validate_schema("sync/sync_import_commit_result.schema.json", original)
        if original["status"] == "accepted":
            check(original["effect"] == {"effect_change_group_id": original["publish_group_id"],
                "effect_group_last_server_sequence": original["commit_server_sequence"]}, "SYNC_PAYLOAD_INVALID")
        else:
            check(original["next_revision"] > mutation["base_entity_version"], "SYNC_PAYLOAD_INVALID")
    elif imported:
        check("import_disposition" not in original and original["status"] in {"staged", "rejected"}, "SYNC_SEQUENCE_ROUTE_MISMATCH")
    else:
        check("import_disposition" not in original and original["status"] != "staged", "SYNC_SEQUENCE_ROUTE_MISMATCH")
    expected_keys = set()
    if not imported:
        nodes = [mutation] + [{**row, "payload": {"fact" if row["operation_type"] == "create" else "patch": row["payload"]}}
                              for row in mutation_dependencies(mutation)]
        for node in nodes:
            fact = node["payload"].get("fact") or node["conflict_recovery_snapshot"] or {}
            if node.get("operation_type") == "resolve_conflict":
                fact = fact.get("fact", {})
            owner = fact.get("owner_type") if node["target_type"] == "reminder_intent" else None
            expected_keys.update((node["target_type"], node["target_id"], name, owner) for name in mutation_keys(node))
    keys = [(row["key"]["target_type"], row["key"]["target_id"], row["key"]["merge_key"], row["key"].get("owner_type")) for row in original["per_key_results"]]
    check(len(keys) == len(set(keys)) and set(keys) == expected_keys, "SYNC_CAUSAL_PREDECESSOR_INVALID")
    if original["status"] in {"rejected", "conflict", "staged"}:
        check(all(row["causal_disposition"] == "no_effect" for row in original["per_key_results"]), "SYNC_CAUSAL_PREDECESSOR_INVALID")
    if original["status"] == "partially_merged":
        check(any(row["causal_disposition"] == "applied" for row in original["per_key_results"]), "SYNC_CAUSAL_PREDECESSOR_INVALID")
    return original


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def decoded(row):
    return None if row is None else json.loads(row[0])


class ProtocolStore:
    """One synthetic account, multiple device sequences, real atomic persistence."""
    def __init__(self, path: Path):
        self.path = path
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS account(singleton INTEGER PRIMARY KEY CHECK(singleton=1), sequence INTEGER NOT NULL);
                INSERT OR IGNORE INTO account VALUES(1,0);
                CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, highest INTEGER NOT NULL DEFAULT 0,
                  generation INTEGER NOT NULL DEFAULT 0, confirmed INTEGER NOT NULL DEFAULT 0, blocked INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS facts(target TEXT, id TEXT, version INTEGER NOT NULL,
                  fact TEXT, deleted INTEGER NOT NULL, delete_version INTEGER NOT NULL, last_group TEXT,
                  PRIMARY KEY(target,id));
                CREATE TABLE IF NOT EXISTS fields(target TEXT,id TEXT,key TEXT,version INTEGER NOT NULL,PRIMARY KEY(target,id,key));
                CREATE TABLE IF NOT EXISTS anchors(device TEXT,target TEXT,id TEXT,key TEXT,sequence INTEGER NOT NULL,
                  version INTEGER NOT NULL,PRIMARY KEY(device,target,id,key));
                CREATE TABLE IF NOT EXISTS receipts(device TEXT,sequence INTEGER,mutation TEXT UNIQUE,hash TEXT,result TEXT,
                  PRIMARY KEY(device,sequence));
                CREATE TABLE IF NOT EXISTS conflicts(id TEXT PRIMARY KEY,target TEXT,entity TEXT,status TEXT,payload TEXT);
                CREATE TABLE IF NOT EXISTS groups(id TEXT PRIMARY KEY,sequence INTEGER UNIQUE,payload TEXT);
                CREATE TABLE IF NOT EXISTS fences(device TEXT,operation TEXT,request TEXT,result TEXT,PRIMARY KEY(device,operation));
            """)

    def connect(self):
        return connect(self.path)

    def register(self, device: str):
        with self.connect() as db:
            db.execute("INSERT OR IGNORE INTO devices(id) VALUES(?)", (device,))

    def seed(self, record: dict, version=1):
        validate_fact(record)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("INSERT INTO facts VALUES(?,?,?,?,0,0,NULL)", (record["target_type"], record["target_id"], version, encode(record["fact"])))
            for key in typed_definition(record["target_type"], record["fact"])["merge_groups"]:
                db.execute("INSERT INTO fields VALUES(?,?,?,?)", (record["target_type"], record["target_id"], key, version))

    def snapshot(self):
        with self.connect() as db:
            return {name: db.execute("SELECT * FROM " + name + " ORDER BY 1,2").fetchall()
                    for name in ("devices", "facts", "fields", "anchors", "receipts", "conflicts", "groups")}

    def fence(self, device, operation, expected):
        integer(expected)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            previous = db.execute("SELECT request,result FROM fences WHERE device=? AND operation=?", (device, operation)).fetchone()
            if previous:
                check(previous[0] == str(expected), "SYNC_SEQUENCE_REPLAY_MISMATCH")
                return json.loads(previous[1])
            state = db.execute("SELECT highest,generation,confirmed FROM devices WHERE id=?", (device,)).fetchone()
            check(state is not None, "DEVICE_NOT_REGISTERED")
            highest, generation, confirmed = state
            check(generation == expected, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(generation < MAXIMUM, "SYNC_TRANSPORT_GENERATION_EXHAUSTED")
            result = {"sync_transport_generation": generation + 1, "highest_client_sequence": highest,
                      "client_confirmed_through": confirmed, "next_client_sequence": None if highest == MAXIMUM else highest + 1,
                      "client_sequence_exhausted": highest == MAXIMUM}
            db.execute("UPDATE devices SET generation=generation+1 WHERE id=?", (device,))
            db.execute("INSERT INTO fences VALUES(?,?,?,?)", (device, operation, str(expected), encode(result)))
            return result

    def exchange(self, device, generation, items, *, confirmed=0, rollback_before_commit=False):
        integer(generation)
        integer(confirmed)
        check(len(items) <= 100, "SYNC_BATCH_TOO_LARGE")
        sequences = [integer(item["mutation"]["client_sequence"]) for item in items]
        check(sequences == sorted(set(sequences)), "SYNC_CLIENT_SEQUENCE_GAP")
        for item in items:
            check(set(item) == {"mutation", "payload_hash"}, "SYNC_PAYLOAD_INVALID")
            validate_mutation(item["mutation"], item["payload_hash"])
            check(item["mutation"]["operation_type"] != "resolve_conflict", "SYNC_SEQUENCE_ROUTE_MISMATCH")
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            state = db.execute("SELECT highest,generation,confirmed,blocked FROM devices WHERE id=?", (device,)).fetchone()
            check(state is not None, "DEVICE_NOT_REGISTERED")
            highest, current_generation, prior_confirmed, blocked = state
            check(current_generation == generation, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(not blocked, "SYNC_SEQUENCE_REPLAY_MISMATCH")
            check(prior_confirmed <= confirmed <= highest, "SYNC_ACK_WATERMARK_INVALID")
            # Preflight the whole sequence/replay envelope before touching facts.
            next_sequence = highest + 1
            for item in items:
                m, h = item["mutation"], item["payload_hash"]
                row = db.execute("SELECT device,sequence,mutation,hash FROM receipts WHERE (device=? AND sequence=?) OR mutation=?",
                                 (device, m["client_sequence"], m["mutation_id"])).fetchall()
                if row:
                    if len(row) != 1 or row[0] != (device, m["client_sequence"], m["mutation_id"], h):
                        db.execute("UPDATE devices SET blocked=1 WHERE id=?", (device,))
                        db.commit()
                        raise ValueError("SYNC_SEQUENCE_REPLAY_MISMATCH")
                else:
                    check(m["client_sequence"] == next_sequence, "SYNC_CLIENT_SEQUENCE_GAP")
                    next_sequence += 1
            results = []
            for item in items:
                m, h = item["mutation"], item["payload_hash"]
                old = decoded(db.execute("SELECT result FROM receipts WHERE device=? AND sequence=?", (device, m["client_sequence"])).fetchone())
                if old:
                    results.append({"status": "duplicate", "original_status": old["status"],
                        "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": h, "original_result": old})
                    continue
                result = self._apply(db, device, m, h)
                db.execute("INSERT INTO receipts VALUES(?,?,?,?,?)", (device, m["client_sequence"], m["mutation_id"], h, encode(result)))
                db.execute("UPDATE devices SET highest=? WHERE id=?", (m["client_sequence"], device))
                results.append(result)
            db.execute("UPDATE devices SET confirmed=? WHERE id=?", (confirmed, device))
            if rollback_before_commit:
                raise RuntimeError("injected_infrastructure_rollback")
            return results

    def _baseline(self, db, device, m, key):
        predecessor = next(row["client_sequence"] for row in m["causal_predecessors"] if row["merge_key"] == key)
        if predecessor is None:
            return None, m["base_entity_version"]
        anchor = db.execute("SELECT sequence,version FROM anchors WHERE device=? AND target=? AND id=? AND key=?",
                            (device, m["target_type"], m["target_id"], key)).fetchone()
        if anchor and anchor[0] == predecessor:
            return anchor
        receipt = decoded(db.execute("SELECT result FROM receipts WHERE device=? AND sequence=?", (device, predecessor)).fetchone())
        check(receipt is not None and receipt["status"] != "staged", "SYNC_CAUSAL_PREDECESSOR_INVALID")
        row = next((r for r in receipt["per_key_results"] if r["key"] == {"target_type": m["target_type"], "target_id": m["target_id"], "merge_key": key}), None)
        check(row is not None, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        if row["causal_disposition"] == "applied":
            return predecessor, row["resulting_field_version"]
        return row["effective_prior_sequence"], row["effective_prior_version"]

    def _apply(self, db, device, m, payload_hash):
        target, identifier, operation, payload = (m[key] for key in ("target_type", "target_id", "operation_type", "payload"))
        check(operation in {"update", "delete"} and target in {"category", "event", "anniversary", "habit", "user_preferences"},
              "REFERENCE_OPERATION_NOT_IMPLEMENTED")
        check(not payload.get("owned_dependencies"), "REFERENCE_OWNED_GRAPH_NOT_IMPLEMENTED")
        row = db.execute("SELECT version,fact,deleted,delete_version,last_group FROM facts WHERE target=? AND id=?", (target, identifier)).fetchone()
        check(row is not None, "REFERENCE_SEED_REQUIRED")
        version, raw, is_deleted, delete_version, last_group = row
        old_fact = json.loads(raw) if raw else None
        check(m["base_entity_version"] <= version, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        keys = mutation_keys(m)
        baselines = {key: self._baseline(db, device, m, key) for key in keys}
        result = {"status": "accepted", "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
            "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": payload_hash},
            "effect": None, "per_key_results": [], "conflict_ids": [], "failure_code": None, "failure_context": None,
            "import_batch_id": None, "import_stage": None}
        for key in keys:
            prior_sequence, prior_version = baselines[key]
            result["per_key_results"].append({"key": {"target_type": target, "target_id": identifier, "merge_key": key},
                "causal_disposition": "no_effect", "resulting_field_version": None,
                "effective_prior_sequence": prior_sequence, "effective_prior_version": prior_version})
        existing = db.execute("SELECT id FROM conflicts WHERE target=? AND entity=? AND status='unresolved'", (target, identifier)).fetchall()
        if existing:
            result.update(status="rejected", failure_code="SYNC_ENTITY_CONFLICT_BLOCKED", conflict_ids=[r[0] for r in existing])
            if last_group:
                result["effect"] = self._effect(db, last_group)
            return result
        definition = typed_definition(target, old_fact or m["conflict_recovery_snapshot"])
        if operation == "update":
            try:
                validate_patch(target, payload["patch"], {"target_type": target, "target_id": identifier,
                    "fact": old_fact or m["conflict_recovery_snapshot"]})
            except ValueError as error:
                result.update(status="rejected", failure_code=str(error))
                return result
            requested = {key: {field: payload["patch"][field] for field in definition["merge_groups"][key]} for key in keys}
        else:
            requested = {"lifecycle": {**{field: old_fact[field] for field in definition["merge_groups"]["lifecycle"]},
                                       "deleted_at": payload["deleted_at"]}}
        applied, concurrent, unchanged = [], [], []
        merged = copy.deepcopy(old_fact)
        for key in keys:
            current = db.execute("SELECT version FROM fields WHERE target=? AND id=? AND key=?", (target, identifier, key)).fetchone()[0]
            prior_sequence, baseline = baselines[key]
            current_values = {field: old_fact[field] for field in requested[key]} if old_fact else None
            if current_values == requested[key]:
                unchanged.append(key)
                continue
            # Delete competes with *all* intervening edits. Updating a deleted
            # entity never turns it into a create, even after payload cleanup.
            conflict = bool(is_deleted and operation == "update")
            if operation == "delete":
                latest = db.execute("SELECT MAX(version) FROM fields WHERE target=? AND id=?", (target, identifier)).fetchone()[0]
                conflict |= latest > baseline
            elif target != "user_preferences":
                conflict |= current != baseline if prior_sequence is not None else current > baseline
            if conflict:
                concurrent.append(key)
            else:
                applied.append(key)
                merged.update(requested[key])
        if applied:
            try:
                validate_fact({"target_type": target, "target_id": identifier, "fact": merged})
            except ValueError as error:
                result.update(status="rejected", failure_code=str(error))
                return result
            check(version < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            version += 1
            db.execute("UPDATE facts SET version=?,fact=?,deleted=?,delete_version=? WHERE target=? AND id=?",
                       (version, encode(merged), int(operation == "delete"), version if operation == "delete" else delete_version, target, identifier))
            for key in applied:
                db.execute("UPDATE fields SET version=? WHERE target=? AND id=? AND key=?", (version, target, identifier, key))
                db.execute("INSERT OR REPLACE INTO anchors VALUES(?,?,?,?,?,?)", (device, target, identifier, key, m["client_sequence"], version))
                per_key = next(row for row in result["per_key_results"] if row["key"]["merge_key"] == key)
                per_key.update(causal_disposition="applied", resulting_field_version=version)
        if concurrent:
            conflict_id = str(uuid.uuid4())
            conflict_payload = {"conflict_id": conflict_id, "target_type": target, "target_id": identifier,
                "conflicting_groups": [{"merge_key": key, "local": requested[key],
                    "server": {name: old_fact[name] for name in requested[key]} if old_fact else {"deleted_anchor": True}}
                    for key in concurrent],
                "auto_merged_groups": [{"merge_key": key, "value": requested[key], "resulting_version": version} for key in applied],
                "recovery_snapshot": m["conflict_recovery_snapshot"]}
            db.execute("INSERT INTO conflicts VALUES(?,?,?,'unresolved',?)", (conflict_id, target, identifier, encode(conflict_payload)))
            result.update(status="partially_merged" if applied else "conflict", conflict_ids=[conflict_id])
        if applied or concurrent:
            sequence = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0]
            check(sequence < MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
            group_id = str(uuid.uuid4())
            group_payload = {"target_type": target, "target_id": identifier, "version": version,
                "fact": merged if applied else old_fact, "conflict_ids": result["conflict_ids"], "source_mutation_id": m["mutation_id"]}
            db.execute("INSERT INTO groups VALUES(?,?,?)", (group_id, sequence + 1, encode(group_payload)))
            db.execute("UPDATE account SET sequence=sequence+1 WHERE singleton=1")
            db.execute("UPDATE facts SET last_group=? WHERE target=? AND id=?", (group_id, target, identifier))
            result["effect"] = {"effect_change_group_id": group_id, "effect_group_last_server_sequence": sequence + 1}
        elif last_group:
            result["effect"] = self._effect(db, last_group)
        return result

    @staticmethod
    def _effect(db, group_id):
        return {"effect_change_group_id": group_id,
                "effect_group_last_server_sequence": db.execute("SELECT sequence FROM groups WHERE id=?", (group_id,)).fetchone()[0]}


class ApplyStore:
    """Synthetic local ack/apply boundary with durable hidden gates and failed intent."""
    def __init__(self, path: Path, *, device_id: str):
        from identity_reference import canonical_uuid
        canonical_uuid(device_id, 4)
        self.path = path
        self.device_id = device_id
        with connect(path) as db:
            db.execute("CREATE TABLE IF NOT EXISTS binding(singleton INTEGER PRIMARY KEY CHECK(singleton=1),device_id TEXT NOT NULL)")
            db.execute("INSERT OR IGNORE INTO binding VALUES(1,?)", (device_id,))
            check(db.execute("SELECT device_id FROM binding WHERE singleton=1").fetchone()[0] == device_id, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS state(local_ack INTEGER,server_ack INTEGER,cursor INTEGER);
                INSERT INTO state SELECT 0,0,0 WHERE NOT EXISTS(SELECT 1 FROM state);
                CREATE TABLE IF NOT EXISTS outbox(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS receipts(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS gates(group_id TEXT,target TEXT,entity TEXT,PRIMARY KEY(group_id,target,entity));
                CREATE TABLE IF NOT EXISTS applied(group_id TEXT PRIMARY KEY,sequence INTEGER,hash TEXT,payload TEXT);
                CREATE TABLE IF NOT EXISTS failed(sequence INTEGER PRIMARY KEY,intent TEXT,failure TEXT);
            """)

    def enqueue(self, mutation):
        with connect(self.path) as db:
            for node in [mutation] + mutation["payload"].get("owned_dependencies", []):
                check(not db.execute("SELECT 1 FROM gates WHERE target=? AND entity=?", (node["target_type"], node["target_id"])).fetchone(), "SYNC_ENTITY_SYNC_EFFECT_PENDING")
            db.execute("INSERT INTO outbox VALUES(?,?)", (mutation["client_sequence"], encode(mutation)))

    def acknowledge(self, result, *, rollback=False):
        original = unwrap_terminal(result)
        check(original["receipt"]["device_id"] == self.device_id, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        sequence = original["receipt"]["client_sequence"]
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            receipt = decoded(db.execute("SELECT payload FROM receipts WHERE sequence=?", (sequence,)).fetchone())
            if receipt:
                check(receipt == original, "SYNC_SEQUENCE_REPLAY_MISMATCH")
                return
            mutation = decoded(db.execute("SELECT payload FROM outbox WHERE sequence=?", (sequence,)).fetchone())
            check(mutation is not None and mutation["mutation_id"] == original["receipt"]["mutation_id"] and
                  mutation_hash(mutation) == original["receipt"]["payload_hash"], "SYNC_SEQUENCE_REPLAY_MISMATCH")
            validate_terminal_for_mutation(result, mutation)
            check(not mutation["operation_type"].startswith("import_"), "REFERENCE_IMPORT_ACK_NOT_IMPLEMENTED")
            db.execute("INSERT INTO receipts VALUES(?,?)", (sequence, encode(original)))
            db.execute("DELETE FROM outbox WHERE sequence=?", (sequence,))
            effect = original["effect"]
            if effect:
                applied = db.execute("SELECT sequence FROM applied WHERE group_id=?", (effect["effect_change_group_id"],)).fetchone()
                check(applied is None or applied[0] == effect["effect_group_last_server_sequence"], "SYNC_APPLY_FAILED")
                if applied is None:
                    for node in [mutation] + mutation["payload"].get("owned_dependencies", []):
                        db.execute("INSERT OR IGNORE INTO gates VALUES(?,?,?)", (effect["effect_change_group_id"], node["target_type"], node["target_id"]))
            if original["status"] == "rejected":
                db.execute("INSERT INTO failed VALUES(?,?,?)", (sequence, encode(mutation),
                    encode({"code": original["failure_code"], "context": original["failure_context"]})))
            self._advance_ack(db)
            if rollback:
                raise RuntimeError("injected_ack_rollback")

    @staticmethod
    def _advance_ack(db):
        current = db.execute("SELECT local_ack FROM state").fetchone()[0]
        pending = [json.loads(row[0]) for row in db.execute("SELECT payload FROM outbox")]
        pinned = {p["client_sequence"] for mutation in pending
                  for node in [mutation] + mutation["payload"].get("owned_dependencies", [])
                  for p in node["causal_predecessors"] if p["client_sequence"] is not None}
        while current < MAXIMUM and current + 1 not in pinned:
            receipt = decoded(db.execute("SELECT payload FROM receipts WHERE sequence=?", (current + 1,)).fetchone())
            if receipt is None:
                break
            effect = receipt["effect"]
            if effect and not db.execute("SELECT 1 FROM applied WHERE group_id=? AND sequence=?",
                    (effect["effect_change_group_id"], effect["effect_group_last_server_sequence"])).fetchone():
                break
            current += 1
        db.execute("UPDATE state SET local_ack=?", (current,))

    def apply(self, group_id, sequence, group, *, rollback=False):
        check(integer(sequence) > 0, "SYNC_APPLY_FAILED")
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT sequence,hash FROM applied WHERE group_id=?", (group_id,)).fetchone()
            if old:
                check(old == (sequence, digest(group)), "SYNC_APPLY_FAILED")
                return
            check(sequence > db.execute("SELECT cursor FROM state").fetchone()[0], "SYNC_APPLY_FAILED")
            for row in db.execute("SELECT payload FROM receipts"):
                effect = json.loads(row[0])["effect"]
                if effect and effect["effect_change_group_id"] == group_id:
                    check(sequence == effect["effect_group_last_server_sequence"], "SYNC_APPLY_FAILED")
            db.execute("INSERT INTO applied VALUES(?,?,?,?)", (group_id, sequence, digest(group), encode(group)))
            db.execute("DELETE FROM gates WHERE group_id=?", (group_id,))
            db.execute("UPDATE state SET cursor=?", (sequence,))
            self._advance_ack(db)
            if rollback:
                raise RuntimeError("injected_apply_rollback")

    def flush_ack(self, reported, accepted):
        integer(reported)
        integer(accepted)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            local, server, _ = db.execute("SELECT * FROM state").fetchone()
            check(server <= accepted == reported <= local, "SYNC_ACK_WATERMARK_INVALID")
            db.execute("UPDATE state SET server_ack=?", (accepted,))

    def snapshot(self):
        with connect(self.path) as db:
            return {name: db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
                    for name in ("state", "outbox", "receipts", "gates", "applied", "failed")}
