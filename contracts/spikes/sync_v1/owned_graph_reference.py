"""Contract oracle for owned graph coherence, with real SQLite atomic publication.

Sequence/transport and causal-chain adjudication are separate proven components.
This oracle accepts only null predecessors; it never treats unverified causal
evidence as permission. No product database or network is used.
"""
import copy
import json
from pathlib import Path

from build_sync_protocol_contracts import OWNED
from counter_reference import MAXIMUM
from domain_reference import check, validate_fact, validate_graph, validate_patch
from protocol_reference import canonical, digest, mutation_keys, typed_definition, validate_mutation
from sqlite_reference import connect


def key(record):
    return record["target_type"], record["target_id"]


def projected_record(node, existing):
    operation = node["operation_type"]
    if operation in {"create", "restore"}:
        fact = node["payload"]["fact"]
    else:
        check(existing is not None, "RECURRENCE_TARGET_INVALID")
        validate_patch(node["target_type"], node["payload"]["patch"], existing,
                       variant=existing["fact"]["owner_type"] if node["target_type"] == "reminder_intent" else "default")
        fact = {**existing["fact"], **node["payload"]["patch"]}
    result = {"target_type": node["target_type"], "target_id": node["target_id"], "fact": copy.deepcopy(fact)}
    validate_fact(result)
    return result


def nodes_for(mutation, graph, *, require_null_predecessors=True):
    """The dependency union's shape is broader than each root's legal ownership."""
    root_key = key(mutation)
    root = projected_record(mutation, graph.get(root_key))
    rows = [(mutation, root)]
    dependencies = mutation["payload"].get("owned_dependencies", [])
    identities = [key(row) for row in dependencies]
    check(identities == sorted(set(identities)) and root_key not in identities, "SYNC_PAYLOAD_INVALID")
    for dependency in dependencies:
        child_type, child_id = key(dependency)
        check(child_type in OWNED.get(root_key[0], []), "SYNC_PAYLOAD_INVALID")
        node = {**dependency, "client_sequence": mutation["client_sequence"],
                "payload": {"fact" if dependency["operation_type"] == "create" else "patch": dependency["payload"]}}
        record = projected_record(node, graph.get(key(node)))
        if child_type == "reminder_intent":
            check((record["fact"]["owner_type"], record["fact"]["owner_id"]) == root_key, "REMINDER_TARGET_NOT_FOUND")
        elif root_key[0] == "reminder_intent":
            check(root["fact"]["owner_type"] == "event", "RECURRENCE_TARGET_INVALID")
            if child_type == "event":
                check(child_id == root["fact"]["owner_id"], "RECURRENCE_TARGET_INVALID")
        elif child_type.endswith("recurrence"):
            expected = root["fact"]["recurrence_id"]
            if child_type == "event_recurrence": expected = str(expected) + "#" + str(root["fact"]["recurrence_revision"])
            check(child_id == expected, "RECURRENCE_TARGET_INVALID")
        rows.append((node, record))
    if root_key[0] == "reminder_intent":
        parent = next((record for _, record in rows[1:] if record["target_type"] == "event"), graph.get(("event", root["fact"]["owner_id"])))
        check(parent is not None, "REMINDER_TARGET_NOT_FOUND")
        for _, record in rows[1:]:
            if record["target_type"] == "event_recurrence":
                expected = str(parent["fact"]["recurrence_id"]) + "#" + str(parent["fact"]["recurrence_revision"])
                check(record["target_id"] == expected, "RECURRENCE_TARGET_INVALID")
    for node, record in rows:
        predecessors = node["causal_predecessors"]
        expected = mutation_keys({**node, "conflict_recovery_snapshot": record["fact"]})
        check([row["merge_key"] for row in predecessors] == expected, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        if require_null_predecessors:
            check(all(row["client_sequence"] is None for row in predecessors), "REFERENCE_CAUSAL_EVIDENCE_REQUIRED")
        else:
            # Presentation can interpret a frozen local command without
            # adjudicating it. No successful anchor or server fact is created.
            check(all(row["client_sequence"] is None or row["client_sequence"] < mutation["client_sequence"] for row in predecessors),
                  "SYNC_CAUSAL_PREDECESSOR_INVALID")
    return rows


def adjudicate(graph, field_versions, mutation, *, causal_baselines=None):
    validate_mutation(mutation, digest({name: value for name, value in mutation.items() if name != "created_at"}))
    check(mutation["operation_type"] in {"create", "update", "restore"}, "REFERENCE_OPERATION_NOT_IMPLEMENTED")
    check(mutation["target_type"] in {"category", "event", "anniversary", "habit", "reminder_intent"}, "RECURRENCE_TARGET_INVALID")
    rows = nodes_for(mutation, graph, require_null_predecessors=causal_baselines is None)
    proposed = {**graph, **{key(record): record for _, record in rows}}
    validate_graph(list(proposed.values()))
    # Every newly proposed revision must have a real root; retained old Event
    # revisions may be referenced by existing occurrence states.
    candidates, applied, conflicting = {}, set(), set()
    root_key = key(mutation)
    component = set()
    root_component = {"category": None, "event": {"timing", "recurrence_link"}, "anniversary": {"date_rule"},
                      "habit": set() if mutation["operation_type"] == "update" else None,
                      "reminder_intent": {"schedule"}}[root_key[0]]
    for node, record in rows:
        identity = key(record); old = graph.get(identity)
        definition = typed_definition(identity[0], record["fact"])
        touched = mutation_keys({**node, "conflict_recovery_snapshot": record["fact"]})
        immutable_collision = definition["immutable_fact"] and old is not None and old["fact"] != record["fact"]
        for name in touched:
            qualified = (*identity, name)
            candidate = {field: record["fact"][field] for field in definition["merge_groups"][name]}
            current = None if old is None else {field: old["fact"][field] for field in candidate}
            candidates[qualified] = candidate
            if identity != root_key or root_component is None or name in root_component:
                component.add(qualified)
            prior, baseline = (None, node["base_entity_version"]) if causal_baselines is None else causal_baselines[qualified]
            current_version = field_versions.get(qualified, 0)
            newer = current_version != baseline if prior is not None else current_version > baseline
            if immutable_collision or current != candidate and newer:
                conflicting.add(qualified)
            elif current != candidate:
                applied.add(qualified)
    if conflicting & component:
        conflicting |= component
        applied -= component
    merged = copy.deepcopy(graph)
    changed = sorted({row[:2] for row in applied})
    for identity in changed:
        record = copy.deepcopy(graph.get(identity) or proposed[identity])
        for qualified in applied:
            if qualified[:2] == identity: record["fact"].update(candidates[qualified])
        merged[identity] = record
    validate_graph(list(merged.values()))
    return {"status": "partially_merged" if applied and conflicting else "conflict" if conflicting else "accepted",
            "applied": sorted(applied), "conflicting": sorted(conflicting), "changed": changed,
            "candidates": candidates, "graph": merged}


class OwnedGraphStore:
    def __init__(self, path: Path):
        self.path = path
        with connect(path) as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS facts(target TEXT,id TEXT,version INTEGER NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(target,id));
                CREATE TABLE IF NOT EXISTS fields(target TEXT,id TEXT,name TEXT,version INTEGER NOT NULL,PRIMARY KEY(target,id,name));
                CREATE TABLE IF NOT EXISTS receipts(mutation_id TEXT PRIMARY KEY,hash TEXT NOT NULL,result TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS conflicts(mutation_id TEXT PRIMARY KEY,payload TEXT NOT NULL);
            """)

    def seed(self, records, version=1):
        validate_graph(records)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            for record in records:
                identity = key(record)
                db.execute("INSERT INTO facts VALUES(?,?,?,?)", (*identity, version, canonical(record).decode()))
                for name in typed_definition(identity[0], record["fact"])["merge_groups"]:
                    db.execute("INSERT INTO fields VALUES(?,?,?,?)", (*identity, name, version))

    def apply(self, mutation, *, fail_after=None):
        content_hash = digest({name: value for name, value in mutation.items() if name != "created_at"})
        validate_mutation(mutation, content_hash)
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL"); db.execute("BEGIN IMMEDIATE")
            prior = db.execute("SELECT hash,result FROM receipts WHERE mutation_id=?", (mutation["mutation_id"],)).fetchone()
            if prior:
                check(prior[0] == content_hash, "SYNC_SEQUENCE_REPLAY_MISMATCH")
                return json.loads(prior[1])
            graph = {(t, i): json.loads(payload) for t, i, payload in db.execute("SELECT target,id,payload FROM facts")}
            fields = {(t, i, name): version for t, i, name, version in db.execute("SELECT * FROM fields")}
            decision = adjudicate(graph, fields, mutation)
            for index, identity in enumerate(decision["changed"]):
                row = db.execute("SELECT version FROM facts WHERE target=? AND id=?", identity).fetchone()
                version = row[0] if row else 0
                check(version < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
                version += 1
                db.execute("INSERT OR REPLACE INTO facts VALUES(?,?,?,?)", (*identity, version, canonical(decision["graph"][identity]).decode()))
                for qualified in decision["applied"]:
                    if qualified[:2] == identity: db.execute("INSERT OR REPLACE INTO fields VALUES(?,?,?,?)", (*qualified, version))
                if fail_after == index: raise RuntimeError("injected_owned_graph_rollback")
            result = {name: [list(row) for row in decision[name]] for name in ("applied", "conflicting", "changed")}
            result["status"] = decision["status"]
            if decision["conflicting"]:
                db.execute("INSERT INTO conflicts VALUES(?,?)", (mutation["mutation_id"], canonical([
                    {"key": list(q), "candidate": decision["candidates"][q]} for q in decision["conflicting"]]).decode()))
            db.execute("INSERT INTO receipts VALUES(?,?,?)", (mutation["mutation_id"], content_hash, canonical(result).decode()))
            if fail_after == "receipt": raise RuntimeError("injected_owned_graph_rollback")
            return result

    def snapshot(self):
        with connect(self.path) as db:
            return {name: db.execute("SELECT * FROM " + name + " ORDER BY 1,2").fetchall() for name in ("facts", "fields", "receipts", "conflicts")}
