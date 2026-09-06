"""Combined synthetic local journal, exact ack and atomic bootstrap rebase.

No production Native owner or import lifecycle is provided. The inherited
bootstrap validates complete pages before this component changes any live row.
"""
import copy
import json
import uuid

from bootstrap_reference import BootstrapLocal, checkpoint, item_key
from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_schema
from identity_reference import canonical_uuid
from local_download_reference import OrdinaryDownload
from local_projection_reference import project_local_intents, target_key
from protocol_reference import digest, encode, mutation_hash, mutation_keys, mutation_dependencies, validate_mutation, unwrap_terminal, validate_terminal_for_mutation
from sqlite_reference import connect


def qualified_keys(mutation):
    result = set()
    for node in [mutation] + [{**row, "payload": {"fact" if row["operation_type"] == "create" else "patch": row["payload"]}}
                             for row in mutation_dependencies(mutation)]:
        result.update((*target_key(node), name) for name in mutation_keys(node))
    return result


class LocalIntentStore(OrdinaryDownload, BootstrapLocal):
    def __init__(self, path, *, device_id, transport=0):
        super().__init__(path, device_id=device_id, transport=transport)
        with connect(path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS frozen_intents(sequence INTEGER PRIMARY KEY,hash TEXT NOT NULL,mutation_id TEXT NOT NULL UNIQUE);
                CREATE TABLE IF NOT EXISTS prepared_intents(id TEXT PRIMARY KEY,sequence INTEGER NOT NULL,generation INTEGER NOT NULL,transport INTEGER NOT NULL,hash TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS terminals(sequence INTEGER PRIMARY KEY,mutation TEXT NOT NULL,result TEXT NOT NULL,generation INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS applied_groups(id TEXT PRIMARY KEY,generation INTEGER NOT NULL,sequence INTEGER NOT NULL,hash TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS bootstrap_coverage(id TEXT PRIMARY KEY,generation INTEGER NOT NULL,upper_bound INTEGER NOT NULL,highest INTEGER NOT NULL,hash TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_anchors(identity TEXT PRIMARY KEY,sequence INTEGER NOT NULL,version INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS presentation(identity TEXT PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS retained_drafts(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS uncertain_pending(sequence INTEGER PRIMARY KEY);
            """)
        self._initialize_download()
        with connect(path) as db:
            self._validate_local_intents(db)

    @staticmethod
    def _state(db):
        return json.loads(db.execute("SELECT payload FROM state").fetchone()[0])

    @staticmethod
    def _save_state(db, state):
        db.execute("UPDATE state SET payload=?", (encode(state),))

    @staticmethod
    def _stored_mutation(db, sequence, raw):
        m = json.loads(raw)
        frozen = db.execute("SELECT hash,mutation_id FROM frozen_intents WHERE sequence=?", (sequence,)).fetchone()
        check(frozen is not None and m.get("client_sequence") == sequence and m.get("mutation_id") == frozen[1], "SYNC_OUTBOX_CORRUPTED")
        validate_mutation(m, frozen[0])
        return m, frozen[0]

    def _validate_local_intents(self, db):
        state = self._state(db)
        if state["fresh"]:
            check(sum(db.execute("SELECT count(*) FROM " + table).fetchone()[0] for table in ("pending", "failed", "effect_gates")) == 0,
                  "SYNC_OUTBOX_CORRUPTED")
        for sequence, raw in db.execute("SELECT * FROM pending"):
            self._stored_mutation(db, sequence, raw)
        for sequence, raw in db.execute("SELECT * FROM failed"):
            entry = json.loads(raw)
            check(set(entry) == {"id", "revision", "mutation", "failure", "state", "superseding_sequence"}, "SYNC_OUTBOX_CORRUPTED")
            canonical_uuid(entry["id"], 4)
            self._stored_mutation(db, sequence, encode(entry["mutation"]))
            check(entry["state"] in {"active", "superseded_pending"} and integer(entry["revision"]) >= 1, "SYNC_OUTBOX_CORRUPTED")
            check((entry["state"] == "active") == (entry["superseding_sequence"] is None), "SYNC_OUTBOX_CORRUPTED")
            if entry["superseding_sequence"] is not None:
                check(integer(entry["superseding_sequence"]) > sequence and db.execute("SELECT 1 FROM frozen_intents WHERE sequence=?",
                    (entry["superseding_sequence"],)).fetchone() is not None, "SYNC_OUTBOX_CORRUPTED")
            terminal = db.execute("SELECT result FROM terminals WHERE sequence=?", (sequence,)).fetchone()
            check(terminal is not None, "SYNC_OUTBOX_CORRUPTED")
            terminal = json.loads(terminal[0])
            check(terminal["status"] == "rejected" and entry["failure"] == {"code": terminal["failure_code"], "context": terminal["failure_context"]},
                "SYNC_OUTBOX_CORRUPTED")
        for sequence, raw, result, generation in db.execute("SELECT * FROM terminals"):
            m, _ = self._stored_mutation(db, sequence, raw)
            terminal = validate_terminal_for_mutation(json.loads(result), m)
            check(terminal["receipt"]["device_id"] == self.device_id and integer(generation) >= 0 and
                db.execute("SELECT 1 FROM pending WHERE sequence=?", (sequence,)).fetchone() is None, "SYNC_OUTBOX_CORRUPTED")
        for sequence, in db.execute("SELECT * FROM effect_gates"):
            check(db.execute("SELECT 1 FROM terminals WHERE sequence=?", (sequence,)).fetchone() is not None, "SYNC_OUTBOX_CORRUPTED")
        for sequence, in db.execute("SELECT * FROM uncertain_pending"):
            check(db.execute("SELECT 1 FROM pending WHERE sequence=?", (sequence,)).fetchone() is not None and
                db.execute("SELECT 1 FROM prepared_intents WHERE sequence=?", (sequence,)).fetchone() is not None, "SYNC_OUTBOX_CORRUPTED")

    @staticmethod
    def _covered(db, terminal, generation):
        effect = terminal["effect"]
        if effect is None:
            return True
        sequence = terminal["receipt"]["client_sequence"]
        existing = db.execute("SELECT generation,sequence FROM applied_groups WHERE id=?", (effect["effect_change_group_id"],)).fetchone()
        if existing:
            check(existing[1] == effect["effect_group_last_server_sequence"], "SYNC_APPLY_FAILED")
            if existing[0] == generation:
                return True
        covered = db.execute("SELECT 1 FROM bootstrap_coverage WHERE highest>=? AND "
            "(generation>? OR (generation=? AND upper_bound>=?))", (sequence, generation, generation,
            effect["effect_group_last_server_sequence"])).fetchone() is not None
        check(existing is None or covered, "SYNC_APPLY_FAILED")
        return covered

    def _cleanup_replacements(self, db, sequence, terminal, generation):
        if terminal["status"] not in {"accepted", "partially_merged"} or not self._covered(db, terminal, generation):
            return
        applied = {(*target_key(row["key"]), row["key"]["merge_key"]) for row in terminal["per_key_results"] if row["causal_disposition"] == "applied"}
        if not applied:
            return
        queue = [sequence]
        while queue:
            replacement = queue.pop()
            for old_sequence, raw in db.execute("SELECT * FROM failed").fetchall():
                entry = json.loads(raw)
                if entry["superseding_sequence"] == replacement and qualified_keys(entry["mutation"]) <= applied:
                    db.execute("DELETE FROM failed WHERE sequence=?", (old_sequence,))
                    queue.append(old_sequence)

    def _advance_ack(self, db, state):
        pins = set()
        for _, raw in db.execute("SELECT * FROM pending"):
            m = json.loads(raw)
            pins.update(row["client_sequence"] for node in [m] + mutation_dependencies(m)
                        for row in node["causal_predecessors"] if row["client_sequence"] is not None)
        current = state["local_ack"]
        while current < MAXIMUM and current + 1 not in pins:
            row = db.execute("SELECT result,generation FROM terminals WHERE sequence=?", (current + 1,)).fetchone()
            if row is None or not self._covered(db, json.loads(row[0]), row[1]):
                break
            current += 1
        state["local_ack"] = current

    def _rebuild(self, db, state):
        items = [json.loads(row[0]) for row in db.execute("SELECT payload FROM live")]
        intents, failed_sequences = [], set()
        for sequence, raw in db.execute("SELECT * FROM pending"):
            m, h = self._stored_mutation(db, sequence, raw)
            unknown = db.execute("SELECT 1 FROM uncertain_pending WHERE sequence=?", (sequence,)).fetchone() is not None
            intents.append({"kind": "receipt_unknown" if unknown else "pending", "state": "active", "mutation": m, "payload_hash": h})
        for sequence, raw in db.execute("SELECT * FROM failed"):
            entry = json.loads(raw)
            m, h = self._stored_mutation(db, sequence, encode(entry["mutation"]))
            intents.append({"kind": "failed", "state": entry["state"], "mutation": m, "payload_hash": h})
            failed_sequences.add(sequence)
        for sequence, raw in db.execute("SELECT t.sequence,t.mutation FROM terminals t JOIN effect_gates g ON g.sequence=t.sequence"):
            if sequence not in failed_sequences:
                m, h = self._stored_mutation(db, sequence, raw)
                intents.append({"kind": "awaiting_effect", "state": "active", "mutation": m, "payload_hash": h})
        projected = project_local_intents(items, intents, server_highest=state.get("baseline_device_highest", 0))
        db.execute("DELETE FROM presentation")
        db.execute("DELETE FROM retained_drafts")
        db.executemany("INSERT INTO presentation VALUES(?,?)", [(encode(target_key(record)), encode(record)) for record in projected["facts"]])
        db.executemany("INSERT INTO retained_drafts VALUES(?,?)", [(row["client_sequence"], encode(row)) for row in projected["retained_drafts"]])
        return projected

    def _finalize_local_intents(self, db, state, metadata, hook):
        db.execute("INSERT INTO bootstrap_coverage VALUES(?,?,?,?,?)", (metadata["bootstrap_id"], metadata["account_generation"],
            metadata["snapshot_upper_bound"], metadata["device_highest_client_sequence_at_snapshot"], digest(metadata)))
        state["baseline_device_highest"] = metadata["device_highest_client_sequence_at_snapshot"]
        state["download_upper"] = None
        db.execute("DELETE FROM uncertain_pending")
        for raw, in db.execute("SELECT payload FROM live").fetchall():
            item = json.loads(raw)
            if item["kind"] == "unresolved_conflict":
                old = db.execute("SELECT status FROM conflict_history WHERE id=?", (item["conflict"]["conflict_id"],)).fetchone()
                check(old is None or old[0] != "resolved", "SYNC_BOOTSTRAP_INCOMPLETE")
                self._conflict_delta(db, {"kind": "created", "conflict": item["conflict"]})
            elif item["kind"] == "requesting_device_causal_anchor":
                old = db.execute("SELECT sequence,version FROM local_anchors WHERE identity=?", (encode(item["key"]),)).fetchone()
                binding = item["client_sequence"], item["resulting_field_version"]
                if old is None or old[0] < binding[0]:
                    db.execute("INSERT OR REPLACE INTO local_anchors VALUES(?,?,?)", (encode(item["key"]), *binding))
                elif old[0] == binding[0]:
                    check(old == binding, "SYNC_OUTBOX_CORRUPTED")
        for sequence, raw, generation in db.execute("SELECT sequence,result,generation FROM terminals").fetchall():
            terminal = json.loads(raw)
            if self._covered(db, terminal, generation):
                db.execute("DELETE FROM effect_gates WHERE sequence=?", (sequence,))
                self._cleanup_replacements(db, sequence, terminal, generation)
        self._advance_ack(db, state)
        checkpoint(hook, "local_intent_effect_coverage")
        self._rebuild(db, state)
        checkpoint(hook, "local_intent_projection")

    def enqueue(self, mutation, *, replaces=None, expected_failed_revision=None, hook=None):
        validate_mutation(mutation, mutation_hash(mutation))
        check(not mutation["operation_type"].startswith("import_"), "REFERENCE_IMPORT_ACK_NOT_IMPLEMENTED")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            self._validate_local_intents(db)
            state = self._state(db)
            check(not state["fresh"], "SYNC_BOOTSTRAP_INCOMPLETE")
            check(state["next_sequence"] is not None, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
            check(mutation["client_sequence"] == state["next_sequence"], "SYNC_CLIENT_SEQUENCE_GAP")
            check(db.execute("SELECT 1 FROM frozen_intents WHERE mutation_id=?", (mutation["mutation_id"],)).fetchone() is None,
                "SYNC_SEQUENCE_REPLAY_MISMATCH")
            keys = {target_key(mutation)} | {target_key(row) for row in mutation_dependencies(mutation)}
            resolving = mutation["operation_type"] == "resolve_conflict"
            matching_conflict = False
            for raw, in db.execute("SELECT payload FROM live"):
                item = json.loads(raw)
                if item["kind"] == "unresolved_conflict" and target_key(item["conflict"]) in keys:
                    check(resolving, "SYNC_ENTITY_CONFLICT_BLOCKED")
                    if item["conflict"]["conflict_id"] == mutation["payload"]["conflict_id"]:
                        check(item["conflict"]["conflict_version"] == mutation["payload"]["expected_conflict_version"], "SYNC_CONFLICT_VERSION_MISMATCH")
                        matching_conflict = True
            check(not resolving or matching_conflict, "SYNC_CONFLICT_NOT_FOUND")
            for raw, in db.execute("SELECT mutation FROM terminals t JOIN effect_gates g ON g.sequence=t.sequence"):
                m = json.loads(raw)
                check(not keys & ({target_key(m)} | {target_key(row) for row in mutation_dependencies(m)}), "SYNC_ENTITY_SYNC_EFFECT_PENDING")
            for _, raw in db.execute("SELECT * FROM pending"):
                m = json.loads(raw)
                if m["client_sequence"] <= state.get("baseline_device_highest", 0) or db.execute(
                        "SELECT 1 FROM uncertain_pending WHERE sequence=?", (m["client_sequence"],)).fetchone() is not None:
                    check(not keys & ({target_key(m)} | {target_key(row) for row in mutation_dependencies(m)}), "SYNC_ENTITY_SYNC_EFFECT_PENDING")
            if replaces is not None:
                row = db.execute("SELECT payload FROM failed WHERE sequence=?", (replaces,)).fetchone()
                check(row is not None, "SYNC_FAILED_CHANGE_NOT_FOUND")
                old = json.loads(row[0])
                check(old["revision"] == expected_failed_revision, "SYNC_FAILED_CHANGE_VERSION_CONFLICT")
                check(old["revision"] < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
                check(qualified_keys(old["mutation"]) <= qualified_keys(mutation), "SYNC_PAYLOAD_INVALID")
                old.update(state="superseded_pending", revision=old["revision"] + 1, superseding_sequence=mutation["client_sequence"])
                db.execute("UPDATE failed SET payload=? WHERE sequence=?", (encode(old), replaces))
            db.execute("INSERT INTO pending VALUES(?,?)", (mutation["client_sequence"], encode(mutation)))
            db.execute("INSERT INTO frozen_intents VALUES(?,?,?)", (mutation["client_sequence"], mutation_hash(mutation), mutation["mutation_id"]))
            state["next_sequence"] = None if mutation["client_sequence"] == MAXIMUM else mutation["client_sequence"] + 1
            state["exhausted"] = state["next_sequence"] is None
            projected = self._rebuild(db, state)
            new_draft = next((row for row in projected["retained_drafts"] if row["client_sequence"] == mutation["client_sequence"]), None)
            if new_draft is not None:
                raise ValueError(new_draft["error"] or "SYNC_ENTITY_CONFLICT_BLOCKED")
            self._save_state(db, state)
            checkpoint(hook, "local_intent_enqueue")

    def prepare(self, sequence):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            row = db.execute("SELECT payload FROM pending WHERE sequence=?", (sequence,)).fetchone()
            check(row is not None, "SYNC_SEQUENCE_REPLAY_MISMATCH")
            _, h = self._stored_mutation(db, sequence, row[0])
            request_id = str(uuid.uuid4())
            db.execute("INSERT INTO prepared_intents VALUES(?,?,?,?,?)", (request_id, sequence, self._state(db)["generation"], self.transport, h))
            return request_id

    def acknowledge(self, result, *, request_id, hook=None):
        terminal = unwrap_terminal(result)
        check(terminal["receipt"]["device_id"] == self.device_id, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        sequence = terminal["receipt"]["client_sequence"]
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            prepared = db.execute("SELECT sequence,generation,transport,hash FROM prepared_intents WHERE id=?", (request_id,)).fetchone()
            check(prepared is not None and prepared[0] == sequence and prepared[2] == self.transport and
                  prepared[3] == terminal["receipt"]["payload_hash"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
            generation = prepared[1]
            old = db.execute("SELECT result,generation FROM terminals WHERE sequence=?", (sequence,)).fetchone()
            if old:
                check(json.loads(old[0]) == terminal, "SYNC_SEQUENCE_REPLAY_MISMATCH")
                return
            row = db.execute("SELECT payload FROM pending WHERE sequence=?", (sequence,)).fetchone()
            check(row is not None, "SYNC_SEQUENCE_REPLAY_MISMATCH")
            m, _ = self._stored_mutation(db, sequence, row[0])
            validate_terminal_for_mutation(result, m)
            db.execute("INSERT INTO terminals VALUES(?,?,?,?)", (sequence, encode(m), encode(terminal), integer(generation)))
            db.execute("DELETE FROM pending WHERE sequence=?", (sequence,))
            db.execute("DELETE FROM uncertain_pending WHERE sequence=?", (sequence,))
            if not self._covered(db, terminal, generation):
                db.execute("INSERT INTO effect_gates VALUES(?)", (sequence,))
            if terminal["status"] == "rejected":
                db.execute("INSERT INTO failed VALUES(?,?)", (sequence, encode({"id": str(uuid.uuid4()), "revision": 1,
                    "mutation": m, "failure": {"code": terminal["failure_code"], "context": terminal["failure_context"]},
                    "state": "active", "superseding_sequence": None})))
            for row in terminal["per_key_results"]:
                if row["causal_disposition"] == "applied":
                    identity = encode(row["key"])
                    old = db.execute("SELECT sequence FROM local_anchors WHERE identity=?", (identity,)).fetchone()
                    if old is None or old[0] < sequence:
                        db.execute("INSERT OR REPLACE INTO local_anchors VALUES(?,?,?)", (identity, sequence, row["resulting_field_version"]))
            self._cleanup_replacements(db, sequence, terminal, generation)
            state = self._state(db)
            self._advance_ack(db, state)
            self._rebuild(db, state)
            self._save_state(db, state)
            checkpoint(hook, "local_intent_ack")

    def discard(self, sequence, *, expected_revision, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT payload FROM failed WHERE sequence=?", (sequence,)).fetchone()
            check(row is not None, "SYNC_FAILED_CHANGE_NOT_FOUND")
            check(json.loads(row[0])["revision"] == expected_revision, "SYNC_FAILED_CHANGE_VERSION_CONFLICT")
            db.execute("DELETE FROM failed WHERE sequence=?", (sequence,))
            self._rebuild(db, self._state(db))
            checkpoint(hook, "local_intent_discard")

    def snapshot(self):
        result = super().snapshot()
        with connect(self.path) as db:
            for name in ("frozen_intents", "prepared_intents", "terminals", "applied_groups", "bootstrap_coverage", "local_anchors", "presentation", "retained_drafts",
                         "prepared_pages", "applied_pages", "conflict_history", "uncertain_pending"):
                result[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
        return result
