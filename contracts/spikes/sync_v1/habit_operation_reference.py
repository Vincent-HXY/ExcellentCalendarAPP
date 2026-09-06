"""Synthetic-account Habit operations composed with real sequence/receipt SQLite.

This Contract oracle does not implement a production Backend or Core writer.
It shares the existing ordering and per-key receipt verifier; operation identity
outlives a transport attempt. C++ local-date validation is a separate function.
"""
from __future__ import annotations

import copy
from datetime import datetime
import json
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import uuid

from counter_reference import MAXIMUM
from domain_reference import check, validate_fact
from identity_reference import check_in_id
from protocol_reference import ProtocolStore, digest, encode, mutation_keys, typed_definition


def operation_hash(mutation):
    return digest({name: mutation[name] for name in
                   ("protocol_version", "target_type", "target_id", "operation_type", "payload")})


def validate_local_date(habit, check_date, *, timezone, now):
    try:
        current = datetime.fromisoformat(now.replace("Z", "+00:00"))
        check(current.tzinfo is not None, "SYNC_PAYLOAD_INVALID")
        today = current.astimezone(ZoneInfo(timezone)).date().isoformat()
    except (ZoneInfoNotFoundError, KeyError):
        raise ValueError("SYNC_TIMEZONE_INVALID") from None
    check(habit["deleted_at"] is None, "HABIT_TARGET_DELETED")
    check(habit["is_active"] and habit["ended_date"] is None, "HABIT_ALREADY_ENDED")
    check(habit["start_date"] <= check_date <= habit["end_date"], "HABIT_CHECK_IN_DATE_OUT_OF_RANGE")
    check(check_date <= today, "HABIT_CHECK_IN_FUTURE_DATE")


class HabitOperationStore(ProtocolStore):
    def __init__(self, path, *, checkpoint=None):
        super().__init__(path)
        self.checkpoint = checkpoint or (lambda name: None)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS habit_operations(operation TEXT PRIMARY KEY,
                    hash TEXT NOT NULL, applied INTEGER NOT NULL DEFAULT 0,
                    effect_group TEXT, effect_sequence INTEGER, effect_version INTEGER);
                CREATE TABLE IF NOT EXISTS habit_barriers(entity TEXT PRIMARY KEY,version INTEGER NOT NULL);
            """)

    def seed(self, record, version=1):
        super().seed(record, version)
        if record["target_type"] == "habit_check_in":
            with self.connect() as db:
                db.execute("INSERT INTO habit_barriers VALUES(?,?)", (record["target_id"], version))
                if record["fact"]["deleted_at"] is not None:
                    db.execute("UPDATE facts SET deleted=1,delete_version=? WHERE target='habit_check_in' AND id=?",
                               (version, record["target_id"]))

    def snapshot(self):
        result = super().snapshot()
        with self.connect() as db:
            for name in ("habit_operations", "habit_barriers", "account"):
                result[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return result

    def _apply(self, db, device, m, payload_hash):
        if m["target_type"] != "habit_check_in":
            return super()._apply(db, device, m, payload_hash)
        target, identifier, operation, payload = (m[name] for name in
            ("target_type", "target_id", "operation_type", "payload"))
        keys = mutation_keys(m)
        baseline = {key: self._baseline(db, device, m, key) for key in keys}
        result = {"status": "accepted", "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
            "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": payload_hash},
            "effect": None, "per_key_results": [{"key": {"target_type": target, "target_id": identifier, "merge_key": key},
                "causal_disposition": "no_effect", "resulting_field_version": None,
                "effective_prior_sequence": baseline[key][0], "effective_prior_version": baseline[key][1]} for key in keys],
            "conflict_ids": [], "failure_code": None, "failure_context": None,
            "import_batch_id": None, "import_stage": None}

        def reject(code):
            result.update(status="rejected", failure_code=code)
            return result

        op_id, op_hash = payload["operation_id"], operation_hash(m)
        previous = db.execute("SELECT hash,applied,effect_group,effect_sequence FROM habit_operations WHERE operation=?", (op_id,)).fetchone()
        if previous:
            if previous[0] != op_hash:
                result["failure_context"] = {"operation_id": op_id}
                return reject("SYNC_HABIT_OPERATION_ID_REUSED")
            if previous[1]:
                current = db.execute("SELECT version FROM facts WHERE target=? AND id=?", (target, identifier)).fetchone()
                check(m["base_entity_version"] <= (current[0] if current else 0), "SYNC_CAUSAL_PREDECESSOR_INVALID")
                if previous[2]:
                    result["effect"] = {"effect_change_group_id": previous[2], "effect_group_last_server_sequence": previous[3]}
                return result
        else:
            db.execute("INSERT INTO habit_operations(operation,hash) VALUES(?,?)", (op_id, op_hash))
        self.checkpoint("operation_binding")
        check(identifier == check_in_id(payload["habit_id"], payload["check_date"]), "SYNC_IDENTITY_MISMATCH")
        parent_row = db.execute("SELECT version,fact FROM facts WHERE target='habit' AND id=?", (payload["habit_id"],)).fetchone()
        if parent_row is None:
            return reject("HABIT_NOT_FOUND")
        parent_version, parent = parent_row[0], json.loads(parent_row[1])
        if parent["deleted_at"] is not None:
            return reject("HABIT_TARGET_DELETED")
        if not parent["is_active"] or parent["ended_date"] is not None:
            return reject("HABIT_ALREADY_ENDED")
        if not parent["start_date"] <= payload["check_date"] <= parent["end_date"]:
            return reject("HABIT_CHECK_IN_DATE_OUT_OF_RANGE")
        unresolved = db.execute("SELECT id,target,entity FROM conflicts WHERE status='unresolved' AND "
            "((target=? AND entity=?) OR (target='habit' AND entity=?))", (target, identifier, payload["habit_id"])).fetchall()
        if unresolved:
            result["conflict_ids"] = [row[0] for row in unresolved]
            effects = []
            for _, owner, entity in unresolved:
                group = db.execute("SELECT last_group FROM facts WHERE target=? AND id=?", (owner, entity)).fetchone()
                check(group is not None and group[0] is not None, "REFERENCE_CONFLICT_EFFECT_REQUIRED")
                effects.append(self._effect(db, group[0]))
            result["effect"] = max(effects, key=lambda row: row["effect_group_last_server_sequence"])
            return reject("SYNC_ENTITY_CONFLICT_BLOCKED")
        row = db.execute("SELECT version,fact,deleted,delete_version,last_group FROM facts WHERE target=? AND id=?",
                         (target, identifier)).fetchone()
        version, old, deleted, delete_version, last_group = (row[0], json.loads(row[1]), *row[2:]) if row else (0, None, 0, 0, None)
        check(m["base_entity_version"] <= version, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        definition = typed_definition(target, old or {})
        field_versions = dict(db.execute("SELECT key,version FROM fields WHERE target=? AND id=?", (target, identifier)))
        for key in keys:
            check(baseline[key][1] <= version, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        barrier = db.execute("SELECT version FROM habit_barriers WHERE entity=?", (identifier,)).fetchone()
        if operation in {"increment", "decrement"}:
            competes = (barrier[0] if barrier else 0) > baseline["completion"][1]
        else:
            competes = any(field_versions.get(key, 0) > baseline[key][1] for key in keys)
        competes |= bool(deleted and delete_version > baseline["deleted_at"][1])
        try:
            candidate = self._candidate(parent, old, m)
        except ValueError as error:
            if competes and str(error) == "HABIT_CHECK_IN_STATE_INVALID":
                # A decrement valid against its frozen local baseline may be
                # invalid after an unseen clear. That is a competing intent.
                candidate = copy.deepcopy(m["conflict_recovery_snapshot"])
            else:
                return reject(str(error))
        # Diagnostic source/updated_at do not turn the same business value into
        # a new operation effect. An accepted no-op is still deduplicated forever.
        equal = candidate is None or (old is not None and all(candidate[f] == old[f]
                     for key in keys for f in definition["merge_groups"][key]))
        if equal:
            if last_group:
                result["effect"] = self._effect(db, last_group)
            db.execute("UPDATE habit_operations SET applied=1,effect_group=?,effect_sequence=?,effect_version=? WHERE operation=?",
                       (last_group, result["effect"]["effect_group_last_server_sequence"] if result["effect"] else None, version, op_id))
            return result
        if competes:
            conflict_id = str(uuid.uuid4())
            payload_value = {"conflict_id": conflict_id, "target_type": target, "target_id": identifier,
                "operation_id": op_id, "operation_type": operation,
                "server": old, "local": m["conflict_recovery_snapshot"],
                "conflicting_keys": keys, "recovery_snapshot": m["conflict_recovery_snapshot"]}
            db.execute("INSERT INTO conflicts VALUES(?,?,?,'unresolved',?)", (conflict_id, target, identifier, encode(payload_value)))
            result.update(status="conflict", conflict_ids=[conflict_id])
            group_id = self._group(db, m, version, old, result["conflict_ids"], None)
            db.execute("UPDATE facts SET last_group=? WHERE target=? AND id=?", (group_id, target, identifier))
            result["effect"] = self._effect(db, group_id)
            return result
        check(version < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
        next_version = version + 1
        changed = [key for key in keys if old is None or any(old[f] != candidate[f] for f in definition["merge_groups"][key])]
        if operation == "clear" and "completion" not in changed:
            changed.append("completion")
        db.execute("INSERT OR REPLACE INTO facts VALUES(?,?,?,?,?,?,?)", (target, identifier, next_version, encode(candidate),
            int(candidate["deleted_at"] is not None), next_version if operation == "clear" else delete_version, last_group))
        for key in definition["merge_groups"]:
            db.execute("INSERT OR IGNORE INTO fields VALUES(?,?,?,0)", (target, identifier, key))
        for key in changed:
            db.execute("UPDATE fields SET version=? WHERE target=? AND id=? AND key=?", (next_version, target, identifier, key))
            db.execute("INSERT OR REPLACE INTO anchors VALUES(?,?,?,?,?,?)", (device, target, identifier, key, m["client_sequence"], next_version))
            entry = next(entry for entry in result["per_key_results"] if entry["key"]["merge_key"] == key)
            entry.update(causal_disposition="applied", resulting_field_version=next_version)
        if operation in {"clear", "replace_total"}:
            db.execute("INSERT OR REPLACE INTO habit_barriers VALUES(?,?)", (identifier, next_version))
        self.checkpoint("check_in_fact")
        parent_image = None
        if parent["first_check_in_at"] is None:
            check(parent_version < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
            parent["first_check_in_at"] = payload["occurred_at"]
            db.execute("UPDATE facts SET version=?,fact=? WHERE target='habit' AND id=?", (parent_version + 1, encode(parent), payload["habit_id"]))
            db.execute("UPDATE fields SET version=? WHERE target='habit' AND id=? AND key='history_guard'", (parent_version + 1, payload["habit_id"]))
            parent_image = {"target_type": "habit", "target_id": payload["habit_id"], "version": parent_version + 1, "fact": parent}
        self.checkpoint("parent_history_guard")
        group_id = self._group(db, m, next_version, candidate, [], parent_image)
        db.execute("UPDATE facts SET last_group=? WHERE target=? AND id=?", (group_id, target, identifier))
        if parent_image:
            db.execute("UPDATE facts SET last_group=? WHERE target='habit' AND id=?", (group_id, payload["habit_id"]))
        self.checkpoint("change_group")
        result["effect"] = self._effect(db, group_id)
        db.execute("UPDATE habit_operations SET applied=1,effect_group=?,effect_sequence=?,effect_version=? WHERE operation=?",
                   (group_id, result["effect"]["effect_group_last_server_sequence"], next_version, op_id))
        self.checkpoint("operation_effect")
        return result

    @staticmethod
    def _candidate(parent, old, mutation):
        p, operation = mutation["payload"], mutation["operation_type"]
        if operation == "clear":
            return old if old is None or old["deleted_at"] is not None else {**old, "deleted_at": p["deleted_at"], "updated_at": p["occurred_at"]}
        if operation == "replace_total":
            fact = copy.deepcopy(p["fact"])
            check(fact["habit_id"] == p["habit_id"] and fact["check_date"] == p["check_date"] and fact["source"] == p["source"]
                  and fact["deleted_at"] is None, "SYNC_IDENTITY_MISMATCH")
            if old:
                check(fact["created_at"] == old["created_at"], "HABIT_HISTORY_IMMUTABLE")
            if fact["status"] != "skipped":
                check(fact["target_count_snapshot_hundredths"] == parent["target_count_hundredths"] and
                      fact["unit_snapshot"] == parent["unit"], "HABIT_HISTORY_IMMUTABLE")
        else:
            snapshot = p["snapshot"]
            check(snapshot["target_count_snapshot_hundredths"] is not None and parent["target_count_hundredths"] is not None,
                  "HABIT_CHECK_IN_STATE_INVALID")
            check(snapshot["target_count_snapshot_hundredths"] == parent["target_count_hundredths"] and
                  snapshot["unit_snapshot"] == parent["unit"], "HABIT_HISTORY_IMMUTABLE")
            start = old["completed_count_hundredths"] if old and old["deleted_at"] is None and old["completed_count_hundredths"] is not None else 0
            total = start + p["delta_hundredths"] * (1 if operation == "increment" else -1)
            check(1 <= total <= MAXIMUM, "HABIT_CHECK_IN_STATE_INVALID")
            fact = {**(old or {}), "habit_id": p["habit_id"], "check_date": p["check_date"],
                "status": "done" if total >= snapshot["target_count_snapshot_hundredths"] else "partial",
                "completed_count_hundredths": total, **snapshot, "completed_at": p["occurred_at"],
                "note": old["note"] if old else None, "source": p["source"],
                "created_at": old["created_at"] if old else p["occurred_at"], "updated_at": p["occurred_at"], "deleted_at": None}
        validate_fact({"target_type": "habit_check_in", "target_id": mutation["target_id"], "fact": fact})
        return fact

    @staticmethod
    def _group(db, mutation, version, fact, conflicts, parent):
        sequence = db.execute("SELECT sequence FROM account").fetchone()[0]
        check(sequence < MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
        identifier = str(uuid.uuid4())
        group = {"target_type": "habit_check_in", "target_id": mutation["target_id"], "version": version,
            "fact": fact, "conflict_ids": conflicts, "source_mutation_id": mutation["mutation_id"], "owned_after_image": parent}
        db.execute("INSERT INTO groups VALUES(?,?,?)", (identifier, sequence + 1, encode(group)))
        db.execute("UPDATE account SET sequence=sequence+1")
        return identifier
