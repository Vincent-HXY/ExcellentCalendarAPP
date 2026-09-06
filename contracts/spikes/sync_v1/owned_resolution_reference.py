"""Owned conflict candidates and immutable revision preparation Contract oracle.

All facts and device receipts are synthetic SQLite data. Public choices are
expanded into a frozen transport candidate before the Backend transaction.
"""
import copy
import json
import uuid

from bootstrap_reference import checkpoint
from counter_reference import MAXIMUM
from domain_reference import check, validate_fact, validate_graph, validate_schema
from owned_sequence_reference import OwnedSequenceStore, qualified_key
from protocol_reference import digest, encode, mutation_hash, mutation_keys, typed_definition, validate_terminal_for_mutation
from resolution_contract_reference import choose_resolution, validate_resolution, validate_resolution_fields

INVALID = "SYNC_RESOLUTION_CANDIDATE_INVALID"


def identity(record):
    return record["target_type"], record["target_id"]


def changed_keys(target, old, candidate):
    return {name for name, fields in typed_definition(target, candidate)["merge_groups"].items()
        if old is None or any(old[field] != candidate[field] for field in fields)}


def child_nodes(mutation):
    return [{**row, "client_sequence": mutation["client_sequence"],
        "payload": {"fact" if row["operation_type"] == "create" else "patch": row["payload"]}}
        for row in mutation["payload"]["prepared_owned_dependencies"]]


def compose_resolution(detail, graph, choice, dependencies, *, root_baseline=None):
    """Verify the prepared values against choices, then validate the whole graph.

    A new immutable identity changes the owner's pointer in this same candidate;
    the old revision is retained for occurrence/history readers. Prepared child
    values cannot introduce edits unrelated to the reviewed conflict candidate.
    """
    root = identity(detail)
    old_root = graph.get(root)
    baseline = root_baseline or ({"kind": "deleted_entity_anchor"} if old_root is None else {
        "kind": "tombstone" if old_root["fact"].get("deleted_at") else "fact_after_image", "fact": old_root["fact"]})
    selections = {digest(row["key"]): row["source"] for row in choice["group_choices"]}
    if choice["mode"] == "per_field":
        check(len(selections) == len(choice["group_choices"]) and
            set(selections) == {digest(row["key"]) for row in detail["conflicting_groups"]}, INVALID)
    root_detail = copy.deepcopy(detail)
    root_detail["conflicting_groups"] = [row for row in detail["conflicting_groups"] if identity(row["key"]) == root]
    root_choice = copy.deepcopy(choice)
    if choice["mode"] == "per_field":
        root_choice["group_choices"] = [row for row in choice["group_choices"] if identity(row["key"]) == root]
    if not root_detail["conflicting_groups"] and choice["mode"] != "manual_edit":
        candidate = copy.deepcopy(baseline.get("fact"))
    else:
        candidate = choose_resolution(root_detail, baseline, root_choice)
    check(candidate is not None, INVALID)  # Root deletion anchors use the root-only owner.
    prepared = {row["target_type"]: row for row in dependencies}
    check(len(prepared) == len(dependencies) and [identity(row) for row in dependencies] == sorted({identity(row) for row in dependencies}), INVALID)
    children = {}
    for row in detail["conflicting_groups"]:
        if identity(row["key"]) != root:
            children.setdefault(identity(row["key"]), []).append(row)
    check(set(prepared) <= {key[0] for key in children}, INVALID)
    output = copy.deepcopy(graph)
    changes, used = {}, set()
    for key, rows in children.items():
        target = key[0]
        old = graph.get(key)
        selected = []
        for row in rows:
            source = selections[digest(row["key"])] if choice["mode"] == "per_field" else (
                "remote" if choice["mode"] == "keep_remote" else "local")
            selected.append(row["local_candidate" if source == "local" else "server_candidate"])
        if any(row["kind"] == "absent" for row in selected):
            check(all(row["kind"] == "absent" for row in selected) and old is None and target not in prepared, INVALID)
            continue
        check(all(row["kind"] == "value" for row in selected), INVALID)
        dependency = prepared.get(target)
        check(old is not None or dependency is not None, INVALID)
        expected = copy.deepcopy(old["fact"] if old else dependency["payload"])
        for row in selected:
            expected.update(row["projection"]["value"])
        if choice["mode"] == "manual_edit" and target == "event_recurrence":
            # Event timing has one owner. Its matching recurrence start is
            # derived from the full manual root candidate, never independently.
            expected.update({name: candidate[name] for name in ("start_at", "start_date", "timezone")})
        touched = changed_keys(target, old["fact"] if old else None, expected)
        if not touched:
            check(dependency is None, INVALID)
            continue
        check(dependency is not None, INVALID)
        used.add(target)
        next_key = identity(dependency)
        definition = typed_definition(target, expected)
        if definition["immutable_fact"]:
            check(dependency["operation_type"] == "create" and dependency["base_entity_version"] == 0 and next_key not in graph, INVALID)
            actual = copy.deepcopy(dependency["payload"])
            check(all(actual[name] == expected[name] for name, field in definition["fields"].items()
                if field["role"] not in {"identity", "audit"}), INVALID)
            if target == "event_recurrence":
                recurrence_id = expected["recurrence_id"]
                revisions = [record["fact"]["revision"] for child_key, record in graph.items()
                    if child_key[0] == target and record["fact"]["recurrence_id"] == recurrence_id]
                maximum = max(revisions, default=0)
                check(maximum < MAXIMUM, "RECURRENCE_RULE_INVALID")
                check(actual["recurrence_id"] == recurrence_id and actual["revision"] == maximum + 1 and
                    root[0] == "event" and candidate["recurrence_id"] == recurrence_id, INVALID)
                candidate["recurrence_revision"] = actual["revision"]
            elif target in {"anniversary_recurrence", "habit_recurrence"}:
                check(root[0] == target.removesuffix("_recurrence"), INVALID)
                candidate["recurrence_id"] = actual["recurrence_id" if target == "anniversary_recurrence" else "id"]
            else:
                raise ValueError(INVALID)
        else:
            check(next_key == key, INVALID)
            operation = dependency["operation_type"]
            check(operation == ("create" if old is None else "update"), INVALID)
            actual = copy.deepcopy(dependency["payload"] if old is None else {**old["fact"], **dependency["payload"]})
            check(actual == expected, INVALID)
            if old:
                validate_resolution_fields(target, old["fact"], actual)
        record = {"target_type": target, "target_id": next_key[1], "fact": actual}
        validate_fact(record)
        output[next_key] = record
        changes[next_key] = changed_keys(target, graph.get(next_key, {}).get("fact"), actual)
    check(used == set(prepared), INVALID)
    validate_resolution_fields(root[0], baseline.get("fact") or detail["recovery_snapshot"]["fact"], candidate,
        manual=choice["mode"] == "manual_edit")
    output[root] = {"target_type": root[0], "target_id": root[1], "fact": candidate}
    changes[root] = changed_keys(root[0], baseline.get("fact"), candidate)
    try:
        validate_graph(list(output.values()))
    except ValueError as error:
        if str(error).startswith("IMPORT_"):
            raise ValueError(INVALID) from None
        raise
    return output, changes


def prepare_resolution(detail, graph, versions, choice, sequence, *, created_at, mutation_id=None):
    """Expand a typed UI choice using a transaction's authoritative local graph.

    No Backend version is allocated here. UUID/revision candidates and the whole
    mutation must be persisted with Outbox once; retries reuse those exact bytes.
    """
    root = identity(detail)
    selections = {digest(row["key"]): row["source"] for row in choice["group_choices"]}
    children = {}
    for row in detail["conflicting_groups"]:
        if identity(row["key"]) != root:
            children.setdefault(identity(row["key"]), []).append(row)
    dependencies = []
    for key, rows in children.items():
        selected = [row["server_candidate" if (selections.get(digest(row["key"]), "local") == "remote" if choice["mode"] == "per_field"
            else choice["mode"] == "keep_remote") else "local_candidate"] for row in rows]
        if all(row["kind"] == "absent" for row in selected):
            continue
        check(all(row["kind"] == "value" for row in selected), INVALID)
        old = graph.get(key)
        candidate = copy.deepcopy(old["fact"] if old else {})
        for row in selected:
            candidate.update(row["projection"]["value"])
        if key[0] == "reminder_intent" and old is None:
            candidate.update(owner_type=root[0], owner_id=root[1])
        if choice["mode"] == "manual_edit" and key[0] == "event_recurrence":
            candidate.update({name: choice["manual_candidate"]["fact"][name] for name in ("start_at", "start_date", "timezone")})
        if old and candidate == old["fact"]:
            continue
        definition = typed_definition(key[0], candidate)
        identifier = key[1]
        creating = old is None or definition["immutable_fact"]
        if key[0] == "event_recurrence":
            recurrence_id = key[1].split("#")[0]
            maximum = max((record["fact"]["revision"] for child_key, record in graph.items()
                if child_key[0] == key[0] and record["fact"]["recurrence_id"] == recurrence_id), default=0)
            check(maximum < MAXIMUM, "RECURRENCE_RULE_INVALID")
            candidate.update(recurrence_id=recurrence_id, revision=maximum + 1)
            identifier = recurrence_id + "#" + str(maximum + 1)
        elif key[0] in {"anniversary_recurrence", "habit_recurrence"}:
            identifier = str(uuid.uuid4())
            candidate["recurrence_id" if key[0] == "anniversary_recurrence" else "id"] = identifier
        if creating:
            for name, field in definition["fields"].items():
                if field["role"] == "audit":
                    check(name in {"created_at", "updated_at"}, INVALID)
                    candidate[name] = created_at
            patch, keys = candidate, set(definition["merge_groups"])
        else:
            keys = changed_keys(key[0], old["fact"], candidate)
            patch = {name: candidate[name] for merge in keys for name in definition["merge_groups"][merge]}
        dependencies.append({"target_type": key[0], "target_id": identifier, "operation_type": "create" if creating else "update",
            "base_entity_version": 0 if creating else versions[key], "causal_predecessors": [{"merge_key": name, "client_sequence": None} for name in sorted(keys)],
            "payload": copy.deepcopy(patch), "conflict_recovery_snapshot": None if creating else candidate})
    dependencies.sort(key=identity)
    output, changes = compose_resolution(detail, graph, choice, dependencies)
    keys = changes[root] | {row["key"]["merge_key"] for row in detail["conflicting_groups"] if identity(row["key"]) == root}
    mutation = {"protocol_version": 1, "mutation_id": mutation_id or str(uuid.uuid4()), "client_sequence": sequence,
        "target_type": root[0], "target_id": root[1], "operation_type": "resolve_conflict", "base_entity_version": versions[root],
        "causal_predecessors": [{"merge_key": key, "client_sequence": None} for key in sorted(keys)],
        "import_lineage_id": None, "import_batch_id": None, "import_source_workspace_id": None, "import_source_epoch": None,
        "import_item_ordinal": None, "import_manifest_hash": None, "predecessor_batch_id": None,
        "payload": {"conflict_id": detail["conflict_id"], "expected_conflict_version": detail["conflict_version"],
            "resolution": copy.deepcopy(choice), "prepared_owned_dependencies": dependencies},
        "conflict_recovery_snapshot": copy.deepcopy(graph[root]), "created_at": created_at}
    validate_resolution(mutation, mutation_hash(mutation))
    return mutation


class OwnedResolutionStore(OwnedSequenceStore):
    def _validate_resolution_scope(self, mutation):
        check(mutation["target_type"] in {"category", "event", "anniversary", "habit", "reminder_intent"}, "REFERENCE_RESOLUTION_TARGET_REQUIRED")

    def _resolve_business(self, db, device, m, payload_hash, hook):
        identifier = m["payload"]["conflict_id"]
        row = db.execute("SELECT version,status,detail,resolution,effect FROM typed_conflicts WHERE id=?", (identifier,)).fetchone()
        if m["target_type"] != "reminder_intent" and not m["payload"]["prepared_owned_dependencies"] and (row is None or not any(
                identity(item["key"]) != identity(m) for item in json.loads(row[2])["conflicting_groups"])):
            return super()._resolve_business(db, device, m, payload_hash, hook)
        current = self._current(row, identifier)
        result = {"status": "rejected", "receipt": {"receipt_id": str(uuid.uuid4()), "device_id": device,
            "client_sequence": m["client_sequence"], "mutation_id": m["mutation_id"], "payload_hash": payload_hash},
            "effect": json.loads(row[4]) if row else None, "per_key_results": [],
            "conflict_ids": [identifier] if row and row[1] == "unresolved" else [],
            "failure_code": None, "failure_context": None, "import_batch_id": None, "import_stage": None}
        nodes = [m] + child_nodes(m)
        for node in nodes:
            keys = mutation_keys(node)
            check([r["merge_key"] for r in node["causal_predecessors"]] == keys and all(
                r["client_sequence"] is None or r["client_sequence"] < m["client_sequence"] for r in node["causal_predecessors"]), "SYNC_CAUSAL_PREDECESSOR_INVALID")
            existing = db.execute("SELECT version FROM facts WHERE target=? AND id=?", identity(node)).fetchone()
            check(node["base_entity_version"] <= (existing[0] if existing else 0), "SYNC_CAUSAL_PREDECESSOR_INVALID")
            for name in keys:
                prior, version = self._baseline(db, device, node, name)
                result["per_key_results"].append({"key": qualified_key(node, name), "causal_disposition": "no_effect",
                    "resulting_field_version": None, "effective_prior_sequence": prior, "effective_prior_version": version})
        if row is None:
            result["failure_code"] = "SYNC_CONFLICT_NOT_FOUND"
            return result, current
        detail = json.loads(row[2])
        check(identity(detail) == identity(m), "SYNC_IDENTITY_MISMATCH")
        if row[1] == "resolved":
            result["failure_code"] = "SYNC_CONFLICT_ALREADY_RESOLVED"
            return result, current
        if row[0] != m["payload"]["expected_conflict_version"]:
            result.update(failure_code="SYNC_CONFLICT_VERSION_MISMATCH", failure_context={"conflict_id": identifier, "current_conflict_version": row[0]})
            return result, current
        graph = {(target, entity): {"target_type": target, "target_id": entity, "fact": json.loads(raw)}
            for target, entity, raw in db.execute("SELECT target,id,fact FROM facts WHERE fact IS NOT NULL")}
        try:
            output, changes = compose_resolution(detail, graph, m["payload"]["resolution"], m["payload"]["prepared_owned_dependencies"],
                root_baseline=self.image(db, *identity(m)))
            check(all(output[identity(node)]["fact"].get("deleted_at") is None for node in nodes), INVALID)
        except ValueError as error:
            result["failure_code"] = str(error)
            return result, current
        expected_root = changes[identity(m)] | {item["key"]["merge_key"] for item in detail["conflicting_groups"] if identity(item["key"]) == identity(m)}
        check(set(mutation_keys(m)) == expected_root, "SYNC_CAUSAL_PREDECESSOR_INVALID")
        for node in nodes[1:]:
            check(set(mutation_keys(node)) == changes[identity(node)], "SYNC_CAUSAL_PREDECESSOR_INVALID")
        versions = {identity(node): (db.execute("SELECT version FROM facts WHERE target=? AND id=?", identity(node)).fetchone() or (0,))[0] for node in nodes}
        check(row[0] < MAXIMUM and all(version < MAXIMUM for version in versions.values()), "SYNC_COUNTER_EXHAUSTED")
        sequence = db.execute("SELECT sequence FROM account WHERE singleton=1").fetchone()[0]
        check(sequence < MAXIMUM, "SYNC_SERVER_SEQUENCE_EXHAUSTED")
        sequence += 1
        group_id = str(uuid.uuid4())
        effect = {"effect_change_group_id": group_id, "effect_group_last_server_sequence": sequence}
        for node in nodes:
            key = identity(node)
            version = versions[key] + 1
            fact = output[key]["fact"]
            db.execute("INSERT OR REPLACE INTO facts VALUES(?,?,?,?,0,0,?)", (*key, version, encode(fact), group_id))
            for name in changes[key]:
                db.execute("INSERT OR REPLACE INTO fields VALUES(?,?,?,?)", (*key, name, version))
                db.execute("INSERT OR REPLACE INTO anchors VALUES(?,?,?,?,?,?)", (device, *key, name, m["client_sequence"], version))
                entry = next(item for item in result["per_key_results"] if item["key"] == qualified_key(node, name))
                entry.update(causal_disposition="applied", resulting_field_version=version)
            checkpoint(hook, "owned_resolution_fact:" + key[0])
        resolved = {"kind": "resolved", "conflict_id": identifier, "conflict_version": row[0] + 1,
            "resolved_at": self.server_time, "resolution_mode": m["payload"]["resolution"]["mode"],
            "resulting_entity_version": versions[identity(m)] + 1, "resolution_receipt": result["receipt"]}
        db.execute("UPDATE typed_conflicts SET version=?,status='resolved',resolution=?,effect=? WHERE id=?",
            (row[0] + 1, encode(resolved), encode(effect), identifier))
        db.execute("UPDATE conflicts SET status='resolved' WHERE id=?", (identifier,))
        checkpoint(hook, "owned_resolution_conflict_lifecycle")
        group = self._persist_group(db, group_id, sequence, [self.image(db, *key) for key in sorted(versions)], [resolved])
        db.execute("INSERT INTO groups VALUES(?,?,?)", (group_id, sequence, encode(group)))
        db.execute("UPDATE account SET sequence=? WHERE singleton=1", (sequence,))
        checkpoint(hook, "owned_resolution_change_group")
        result.update(status="accepted", effect=effect, conflict_ids=[])
        validate_terminal_for_mutation(result, m)
        return result, {"kind": "resolved", "conflict_id": identifier, "conflict_version": row[0] + 1,
            "resolved_at": self.server_time, **effect}
