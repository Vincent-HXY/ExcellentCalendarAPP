"""Durable full-graph import preparation in an isolated SQLite contract model.

Assignments are allocated once in a transaction and are reused by every batch in
the same epoch. Only identity fields and declared references are rewritten.
"""
import copy
import json
import uuid

from bootstrap_reference import CAPS, checkpoint
from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_graph, validate_schema
from identity_reference import canonical_uuid, check_in_id, lineage_id, occurrence_key, reminder_intent_id
from import_contract_reference import make_manifest, utf16_key
from protocol_reference import digest, encode
from sqlite_reference import connect

ROOT_TYPES = {"category", "event", "anniversary", "anniversary_recurrence", "habit", "habit_recurrence"}


def freeze_batch(account, source, epoch, items, *, source_hash, begin_sequence, batch_id,
                 predecessor=None, revision=0, takeover_reason=None, proof_id=None,
                 versions=None, created_at="2026-09-06T07:00:00Z"):
    items = sorted(copy.deepcopy(items), key=utf16_key)
    manifest = make_manifest(source, epoch, source_hash, items)
    check(manifest["total_item_count"] <= CAPS["import_batch_items"] and
          manifest["total_canonical_bytes"] <= CAPS["import_batch_canonical_bytes"], "SYNC_IMPORT_CAPACITY_EXCEEDED")
    integer(begin_sequence)
    integer(revision)
    check(1 <= begin_sequence <= MAXIMUM - len(items) - 1, "SYNC_CLIENT_SEQUENCE_EXHAUSTED")
    check(revision < MAXIMUM, "IMPORT_VERSION_CONFLICT")
    check((predecessor is None) == (revision == 0), "IMPORT_VERSION_CONFLICT")
    check((takeover_reason is None) == (proof_id is None), "IMPORT_REFERENCE_INVALID")
    lineage = lineage_id(account, source, epoch)
    envelope = {"protocol_version": 1, "causal_predecessors": [], "import_lineage_id": lineage,
        "import_batch_id": batch_id, "import_source_workspace_id": source, "import_source_epoch": epoch,
        "import_manifest_hash": manifest["manifest_hash"], "predecessor_batch_id": predecessor,
        "conflict_recovery_snapshot": None, "created_at": created_at}
    messages = []
    for offset in range(len(items) + 2):
        control = offset in {0, len(items) + 1}
        body = {"target_type": "workspace_import", "target_id": batch_id,
            "operation_type": "import_begin" if offset == 0 else "import_commit",
            "payload": {"manifest": manifest, "takeover_reason": takeover_reason, "range_close_proof_id": proof_id}} if control else items[offset - 1]
        version = revision + int(offset != 0) if control else (versions or {}).get((body["target_type"], body["target_id"]), 0)
        mutation = {**envelope, **body, "mutation_id": str(uuid.uuid4()), "client_sequence": begin_sequence + offset,
            "base_entity_version": version, "import_item_ordinal": None if control else offset - 1}
        validate_schema("sync/sync_mutation.schema.json", mutation)
        messages.append(mutation)
    return messages


class ImportGraphPlanner:
    def __init__(self, path, *, factory=None):
        self.path = path
        self.factory = factory or (lambda: str(uuid.uuid4()))
        with connect(path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS graph_mapping(lineage TEXT,kind TEXT,source TEXT,target TEXT,
                    PRIMARY KEY(lineage,kind,source),UNIQUE(kind,target));
                CREATE TABLE IF NOT EXISTS graph_batches(batch TEXT PRIMARY KEY,input_hash TEXT NOT NULL,payload TEXT NOT NULL);
            """)

    def snapshot(self):
        with connect(self.path) as db:
            return {table: db.execute("SELECT * FROM " + table + " ORDER BY 1,2,3").fetchall()
                    for table in ("graph_mapping", "graph_batches")}

    def prepare(self, account, source, epoch, records, *, occupied=(), portable_color=None,
                begin_sequence=1, batch_id=None, predecessor=None, revision=0, versions=None,
                takeover_reason=None, proof_id=None, source_snapshot_hash=None, hook=None):
        validate_graph(records)
        check(all(row["target_type"] not in {"user_preferences", "account_profile"} for row in records), "SYNC_TARGET_UNSUPPORTED")
        batch_id = canonical_uuid(batch_id or str(uuid.uuid4()), 4)
        lineage = lineage_id(account, source, epoch)
        occupied = set(occupied)
        occupied.update(("event_recurrence_family", identifier.split("#", 1)[0])
                        for kind, identifier in list(occupied) if kind == "event_recurrence")
        identity = {"account": account, "source": source, "epoch": epoch, "records": records,
            "portable_color": portable_color, "begin": begin_sequence, "predecessor": predecessor,
            "revision": revision, "versions": sorted([*key, value] for key, value in (versions or {}).items()),
            "takeover_reason": takeover_reason, "proof_id": proof_id, "source_snapshot_hash": source_snapshot_hash}
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            replay = db.execute("SELECT input_hash,payload FROM graph_batches WHERE batch=?", (batch_id,)).fetchone()
            if replay:
                check(replay[0] == digest(identity), "IMPORT_LINEAGE_MISMATCH")
                return json.loads(replay[1])
            mapping = {(kind, old): new for kind, old, new in db.execute(
                "SELECT kind,source,target FROM graph_mapping WHERE lineage=?", (lineage,))}

            def allocate(kind, old, derived=None):
                key = kind, old
                if key in mapping:
                    check(derived is None or derived == mapping[key], "IMPORT_LINEAGE_MISMATCH")
                    return mapping[key]
                candidate = derived or old
                if derived is None:
                    try:
                        canonical_uuid(candidate, 4)
                    except ValueError:
                        candidate = canonical_uuid(self.factory(), 4)
                for attempt in range(65):
                    taken = (kind, candidate) in occupied or db.execute(
                        "SELECT 1 FROM graph_mapping WHERE kind=? AND target=?", (kind, candidate)).fetchone()
                    if not taken:
                        break
                    check(derived is None and attempt < 64, "IMPORT_DUPLICATE_IDENTITY")
                    candidate = canonical_uuid(self.factory(), 4)
                db.execute("INSERT INTO graph_mapping VALUES(?,?,?,?)", (lineage, kind, old, candidate))
                mapping[key] = candidate
                return candidate

            # Roots and recurrence families precede all dependent identities.
            for row in sorted(records, key=lambda value: (value["target_type"], value["target_id"])):
                kind, old, fact = row["target_type"], row["target_id"], row["fact"]
                if kind in ROOT_TYPES:
                    allocate(kind, old)
                elif kind == "event_recurrence":
                    allocate("event_recurrence_family", fact["recurrence_id"])

            def strong(kind, old):
                check((kind, old) in mapping, "IMPORT_REFERENCE_INVALID")
                return mapping[kind, old]

            result = []
            for row in records:
                kind, old, fact = row["target_type"], row["target_id"], copy.deepcopy(row["fact"])
                if kind in ROOT_TYPES:
                    new = strong(kind, old)
                    fact["recurrence_id" if kind == "anniversary_recurrence" else "id"] = new
                elif kind == "event_recurrence":
                    fact["recurrence_id"] = strong("event_recurrence_family", fact["recurrence_id"])
                    new = allocate(kind, old, fact["recurrence_id"] + "#" + str(fact["revision"]))
                elif kind == "habit_check_in":
                    fact["habit_id"] = strong("habit", fact["habit_id"])
                    new = allocate(kind, old, check_in_id(fact["habit_id"], fact["check_date"]))
                elif kind == "event_occurrence_state":
                    fact["event_id"] = strong("event", fact["event_id"])
                    new = allocate(kind, old, occurrence_key(fact["event_id"], fact["recurrence_revision"], fact["original_local_start"]))
                    fact["occurrence_key"] = new
                else:
                    check(kind == "reminder_intent", "SYNC_TARGET_UNSUPPORTED")
                    fact["owner_id"] = strong(fact["owner_type"], fact["owner_id"])
                    new = allocate(kind, old, reminder_intent_id(fact["owner_type"], fact["owner_id"]))
                if kind in {"event", "anniversary", "habit"}:
                    fact["category_id"] = mapping.get(("category", fact["category_id"]), fact["category_id"])
                    if fact["recurrence_id"] is not None:
                        fact["recurrence_id"] = strong("event_recurrence_family" if kind == "event" else kind + "_recurrence", fact["recurrence_id"])
                result.append({"target_type": kind, "target_id": new, "operation_type": "import_put", "payload": {"source_id": old, "fact": fact}})
            validate_graph([{"target_type": row["target_type"], "target_id": row["target_id"], "fact": row["payload"]["fact"]} for row in result])
            live = {(row["target_type"], row["target_id"]) for row in records}
            historical = [(kind, old, new) for (kind, old), new in mapping.items()
                          if kind != "event_recurrence_family" and (kind, old) not in live]
            result.extend({"target_type": kind, "target_id": new, "operation_type": "import_delete",
                "payload": {"source_id": old, "deleted_at": "2026-09-06T07:00:00Z"}} for kind, old, new in historical)
            if portable_color is not None:
                result.append({"target_type": "user_preferences", "target_id": account, "operation_type": "import_put",
                    "payload": {"habit_progress_color": portable_color}})
            batch = freeze_batch(account, source, epoch, result, source_hash=source_snapshot_hash or digest(records),
                begin_sequence=begin_sequence, batch_id=batch_id, predecessor=predecessor, revision=revision, versions=versions,
                takeover_reason=takeover_reason, proof_id=proof_id)
            checkpoint(hook, "import_graph_mapping")
            db.execute("INSERT INTO graph_batches VALUES(?,?,?)", (batch_id, digest(identity), encode(batch)))
            checkpoint(hook, "import_graph_frozen_batch")
            return batch
