"""Ordinary typed download transactions for the combined local-intent oracle.

Inputs represent an already authenticated HTTP boundary. Cursors remain opaque;
this component neither issues them nor pretends to implement an import publisher.
"""
import json
import uuid

from bootstrap_reference import CAPS, checkpoint, epoch, item_key, validate_snapshot
from domain_reference import check, validate_schema
from local_projection_reference import target_key
from protocol_reference import canonical, digest, encode, mutation_dependencies
from sqlite_reference import connect


def group_hash(group):
    return digest({key: value for key, value in group.items() if key != "payload_hash"})


def live_identity(item):
    return encode([part.hex() for part in item_key(item)])


class OrdinaryDownload:
    def _finish_download_control(self, db, response, prepared, hook):
        """Optional durable policy gate joins this exact prepared apply."""

    def _begin_download_discovery(self, db, generation, upper_bound, hook):
        """The optional notice component joins the existing apply transaction."""

    def _finish_download_discovery(self, db, response, hook):
        """The plain download component does not certify notice delivery."""

    def _initialize_download(self):
        with connect(self.path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS prepared_pages(id TEXT PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS applied_pages(id TEXT PRIMARY KEY,hash TEXT NOT NULL,cursor TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS conflict_history(id TEXT PRIMARY KEY,version INTEGER NOT NULL,status TEXT NOT NULL,payload TEXT NOT NULL);
                CREATE UNIQUE INDEX IF NOT EXISTS applied_group_sequence ON applied_groups(generation,sequence);
            """)

    @staticmethod
    def _not_rebuilding(db):
        session = db.execute("SELECT identity FROM session").fetchone()
        check(session is None or db.execute("SELECT 1 FROM finalized WHERE id=?",
            (json.loads(session[0])["bootstrap_id"],)).fetchone() is not None, "SYNC_BOOTSTRAP_INCOMPLETE")

    def prepare_download(self):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            state = self._state(db)
            check(not state["fresh"] and state["cursor"] is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            prepared = {"generation": state["generation"], "transport": self.transport, "cursor": state["cursor"],
                "position": state["upper_bound"], "fixed_upper": state.get("download_upper"), "reported_ack": state["server_ack"]}
            request_id = str(uuid.uuid4())
            db.execute("INSERT INTO prepared_pages VALUES(?,?)", (request_id, encode(prepared)))
            return request_id

    @staticmethod
    def _conflict_delta(db, delta):
        created = delta["kind"] == "created"
        payload = delta["conflict"] if created else delta
        conflict_id, version = payload["conflict_id"], payload["conflict_version"]
        previous = db.execute("SELECT version,status,payload FROM conflict_history WHERE id=?", (conflict_id,)).fetchone()
        if previous:
            if previous[1] == "resolved" and created:
                check(version <= previous[0], "SYNC_APPLY_FAILED")
                return  # A late created delta cannot reopen a resolved identity.
            if version < previous[0]:
                return
            if version == previous[0]:
                check(previous[1] == ("unresolved" if created else "resolved") and
                    json.loads(previous[2]) == payload, "SYNC_APPLY_FAILED")
                return
        for identity, raw in db.execute("SELECT * FROM live").fetchall():
            item = json.loads(raw)
            if item["kind"] == "unresolved_conflict" and item["conflict"]["conflict_id"] == conflict_id:
                check(version >= item["conflict"]["conflict_version"], "SYNC_APPLY_FAILED")
                db.execute("DELETE FROM live WHERE identity=?", (identity,))
        if created:
            item = {"kind": "unresolved_conflict", "conflict": payload}
            db.execute("INSERT INTO live VALUES(?,?)", (live_identity(item), encode(item)))
        db.execute("INSERT OR REPLACE INTO conflict_history VALUES(?,?,?,?)",
            (conflict_id, version, "unresolved" if created else "resolved", encode(payload)))

    def _apply_entity_image(self, db, item):
        """Identical after-image rules for ordinary and import publication."""
        key = target_key(item)
        for sequence, raw in db.execute("SELECT p.sequence,p.payload FROM pending p WHERE EXISTS "
                "(SELECT 1 FROM prepared_intents r WHERE r.sequence=p.sequence)").fetchall():
            mutation = json.loads(raw)
            if key in ({target_key(mutation)} | {target_key(node) for node in mutation_dependencies(mutation)}):
                db.execute("INSERT OR IGNORE INTO uncertain_pending VALUES(?)", (sequence,))
        identities = [live_identity({"kind": kind, "target_type": key[0], "target_id": key[1]})
            for kind in ("fact_after_image", "tombstone", "deleted_entity_anchor")]
        for identity, raw in db.execute("SELECT * FROM live WHERE identity IN (?,?,?)", identities).fetchall():
            current = json.loads(raw)
            if current["kind"] in {"fact_after_image", "tombstone", "deleted_entity_anchor"} and target_key(current) == key:
                check(item["entity_version"] >= current["entity_version"], "SYNC_APPLY_FAILED")
                if item["entity_version"] == current["entity_version"]:
                    check(item == current, "SYNC_APPLY_FAILED")
                check(item["import_provenance"] == current["import_provenance"], "SYNC_APPLY_FAILED")
                if "field_versions" in item and "field_versions" in current:
                    old_fields = {digest(row["key"]): row["field_version"] for row in current["field_versions"]}
                    new_fields = {digest(row["key"]): row["field_version"] for row in item["field_versions"]}
                    check(old_fields.keys() == new_fields.keys() and all(new_fields[key] >= value for key, value in old_fields.items()), "SYNC_APPLY_FAILED")
                db.execute("DELETE FROM live WHERE identity=?", (identity,))
        db.execute("INSERT INTO live VALUES(?,?)", (live_identity(item), encode(item)))

    def _apply_ordinary_group(self, db, group, generation, hook):
        check(group_hash(group) == group["payload_hash"], "SYNC_PAYLOAD_HASH_MISMATCH")
        check(len(canonical(group)) <= CAPS["ordinary_group_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        old = db.execute("SELECT generation,sequence,hash FROM applied_groups WHERE id=?", (group["change_group_id"],)).fetchone()
        binding = generation, group["server_sequence"], group["payload_hash"]
        if old:
            check(old == binding, "SYNC_APPLY_FAILED")
            return
        check(db.execute("SELECT 1 FROM applied_groups WHERE generation=? AND sequence=?", binding[:2]).fetchone() is None,
            "SYNC_APPLY_FAILED")
        seen = set()
        for item in group["entity_changes"]:
            key = target_key(item)
            check(key not in seen, "SYNC_APPLY_FAILED")
            seen.add(key)
            # An after-image alone cannot say whether an unacknowledged sent
            # increment was included. Preserve its exact draft until its receipt
            # (or a complete bootstrap device watermark) resolves that ambiguity.
            self._apply_entity_image(db, item)
        checkpoint(hook, "download_entities")
        identifiers = [row.get("conflict_id", row.get("conflict", {}).get("conflict_id")) for row in group["conflict_deltas"]]
        check(len(identifiers) == len(set(identifiers)), "SYNC_APPLY_FAILED")
        for delta in group["conflict_deltas"]:
            self._conflict_delta(db, delta)
        checkpoint(hook, "download_conflicts")
        db.execute("INSERT INTO applied_groups VALUES(?,?,?,?)", (group["change_group_id"], *binding))
        checkpoint(hook, "download_group_receipt")

    def apply_download(self, response, *, request_id, hook=None):
        validate_schema("sync/sync_exchange_response.schema.json", response)
        check(response["mode"] == "normal", "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(response["device_id"] == self.device_id and response["sync_transport_generation"] == self.transport,
            "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(not response["results"], "REFERENCE_DOWNLOAD_ONLY_PREPARATION")
        check(all(row["kind"] == "change_group" for row in response["changes"]), "REFERENCE_IMPORT_PUBLISH_NOT_IMPLEMENTED")
        check(len(canonical(response)) <= CAPS["response_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            prepared = db.execute("SELECT payload FROM prepared_pages WHERE id=?", (request_id,)).fetchone()
            check(prepared is not None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            prepared = json.loads(prepared[0])
            check(prepared["transport"] == self.transport and response["account_generation"] == prepared["generation"],
                "SYNC_CURSOR_GENERATION_MISMATCH")
            old = db.execute("SELECT hash,cursor FROM applied_pages WHERE id=?", (request_id,)).fetchone()
            if old:
                check(old == (digest(response), response["next_cursor"]), "SYNC_APPLY_FAILED")
                return old[1]
            self._not_rebuilding(db)
            self._validate_local_intents(db)
            state = self._state(db)
            check(state["generation"] == prepared["generation"] and state["cursor"] == prepared["cursor"] and
                state["upper_bound"] == prepared["position"], "SYNC_APPLY_FAILED")
            upper = response["snapshot_upper_bound"]
            check(upper >= state["upper_bound"] and (prepared["fixed_upper"] is None or prepared["fixed_upper"] == upper),
                "SYNC_APPLY_FAILED")
            check(response["accepted_client_sequence_through"] == prepared["reported_ack"], "SYNC_APPLY_FAILED")
            self._begin_download_discovery(db, state["generation"], upper, hook)
            position = state["upper_bound"]
            for group in response["changes"]:
                check(position < group["server_sequence"] <= upper, "SYNC_APPLY_FAILED")
                self._apply_ordinary_group(db, group, state["generation"], hook)
                position = group["server_sequence"]
                group_items = sorted([json.loads(row[0]) for row in db.execute("SELECT payload FROM live")], key=item_key)
                validate_snapshot(group_items, upper_bound=position, highest=max(state.get("baseline_device_highest", 0), state["local_ack"]))
            check(not response["has_more"] or position < upper, "SYNC_APPLY_FAILED")
            check(not (response["changes"] or response["has_more"] or upper > prepared["position"]) or
                response["next_cursor"] != prepared["cursor"], "SYNC_APPLY_FAILED")
            items = sorted([json.loads(row[0]) for row in db.execute("SELECT payload FROM live")], key=item_key)
            # The complete graph is validated before publication, including
            # dependencies affected by another member of this atomic page.
            validate_snapshot(items, upper_bound=upper, highest=max(state.get("baseline_device_highest", 0), state["local_ack"]))
            for sequence, raw, generation in db.execute("SELECT sequence,result,generation FROM terminals").fetchall():
                terminal = json.loads(raw)
                if self._covered(db, terminal, generation):
                    db.execute("DELETE FROM effect_gates WHERE sequence=?", (sequence,))
                    self._cleanup_replacements(db, sequence, terminal, generation)
            checkpoint(hook, "download_effect_coverage")
            self._advance_ack(db, state)
            self._rebuild(db, state)
            checkpoint(hook, "download_projection")
            self._finish_download_discovery(db, response, hook)
            self._finish_download_control(db, response, prepared, hook)
            floor, cleanup = response["retention_floor_server_sequence"], epoch(response["resolved_conflict_cleanup_before"])
            if state["floor"] <= floor <= upper and cleanup >= state["cleanup"]:
                state.update(floor=floor, cleanup=cleanup)
            state.update(cursor=response["next_cursor"], upper_bound=position if response["has_more"] else upper,
                download_upper=upper if response["has_more"] else None)
            self._save_state(db, state)
            checkpoint(hook, "download_cursor")
            db.execute("INSERT INTO applied_pages VALUES(?,?,?)", (request_id, digest(response), response["next_cursor"]))
            checkpoint(hook, "download_page_receipt")
            return response["next_cursor"]
