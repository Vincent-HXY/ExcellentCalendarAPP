"""Isolated immutable snapshot/page oracle. Uses only synthetic SQLite databases.

This is a Contract experiment, not a production Backend or Native implementation.
Pending local edits are explicitly gated until the overlay component is supplied.
"""
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import uuid

from counter_reference import MAXIMUM, integer
from cursor_reference import CursorCodec
from domain_reference import check, definitions, validate_fact, validate_graph, validate_schema
from identity_reference import canonical_uuid
from protocol_reference import canonical, digest, encode, typed_definition
from sqlite_reference import connect
from validate_sync_v1 import read_yaml

ROOT = Path(__file__).resolve().parents[3]
INVARIANTS = read_yaml(ROOT / "contracts/sync/sync_protocol_invariants.yaml")
CAPS = INVARIANTS["limits"]
RULES = read_yaml(ROOT / "contracts/sync/sync_bootstrap_protocol.yaml")
IDENTITY_FIELDS = ("protocol_version", "device_id", "sync_transport_generation", "bootstrap_id", "account_generation",
    "snapshot_upper_bound", "device_highest_client_sequence_at_snapshot", "device_client_confirmed_through_at_snapshot",
    "device_next_client_sequence_at_snapshot", "device_client_sequence_exhausted_at_snapshot", "retention_floor_server_sequence",
    "resolved_conflict_cleanup_before", "expires_at", "snapshot_item_count", "snapshot_items_hash", "total_page_count", "page_item_limit")


def utc(seconds):
    return datetime.fromtimestamp(integer(seconds), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def epoch(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    check(parsed.tzinfo is not None and parsed.utcoffset().total_seconds() == 0, "SYNC_PAYLOAD_INVALID")
    return integer(int(parsed.timestamp()))


def identity(page):
    return {name: page[name] for name in IDENTITY_FIELDS}


def item_key(item):
    nested = item.get("conflict", item.get("key", item))
    if item["kind"] == "import_publish_marker":
        nested = {"target_type": "workspace_import", "target_id": item["import_batch_id"]}
    return tuple(str(value).encode("utf-16-be") for value in (item["kind"], nested.get("target_type", ""),
        nested.get("target_id", ""), nested.get("conflict_id", ""), nested.get("merge_key", "")))


def page_hash(page):
    return digest({name: value for name, value in page.items() if name != "page_hash"})


def page_set_digest(pages):
    return digest([{"page_ordinal": page["page_ordinal"], "page_hash": page["page_hash"]} for page in pages])


def provenance_entries(items, marker):
    values = []
    for item in items:
        provenance = item.get("import_provenance")
        if provenance and all(provenance[name] == marker[name] for name in ("source_workspace_id", "source_epoch", "import_lineage_id")):
            values.append({name: item[name] for name in ("target_type", "target_id", "import_provenance")})
    return sorted(values, key=lambda value: (value["target_type"].encode("utf-16-be"), value["target_id"].encode("utf-16-be")))


def validate_snapshot(items, *, upper_bound, highest):
    check(items == sorted(items, key=item_key), "SYNC_BOOTSTRAP_INCOMPLETE")
    check(len({item_key(item) for item in items}) == len(items), "SYNC_BOOTSTRAP_INCOMPLETE")
    entities, facts, anchors, conflicts, markers = {}, [], [], [], []
    for item in items:
        validate_schema("sync/sync_bootstrap_item.schema.json", item)
        check(len(canonical(item)) <= CAPS["bootstrap_item_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        kind = item["kind"]
        if kind in {"fact_after_image", "tombstone", "deleted_entity_anchor"}:
            key = item["target_type"], item["target_id"]
            check(key not in entities, "SYNC_BOOTSTRAP_INCOMPLETE")
            entities[key] = item
            if kind != "fact_after_image":
                check(item["delete_server_sequence"] <= upper_bound, "SYNC_BOOTSTRAP_INCOMPLETE")
            if kind != "deleted_entity_anchor":
                record = {name: item[name] for name in ("target_type", "target_id", "fact")}
                validate_fact(record)
                facts.append(record)
                groups = typed_definition(item["target_type"], item["fact"])["merge_groups"]
                keys = [row["key"] for row in item["field_versions"]]
                check(len(keys) == len(groups) and {key["merge_key"] for key in keys} == set(groups), "SYNC_BOOTSTRAP_INCOMPLETE")
                check(all((key["target_type"], key["target_id"]) == (item["target_type"], item["target_id"]) and
                          key.get("owner_type") == item["fact"].get("owner_type") for key in keys), "SYNC_BOOTSTRAP_INCOMPLETE")
                check(all(row["field_version"] <= item["entity_version"] for row in item["field_versions"]), "SYNC_BOOTSTRAP_INCOMPLETE")
                check((kind == "tombstone") == (item["fact"].get("deleted_at") is not None), "SYNC_BOOTSTRAP_INCOMPLETE")
                if kind == "tombstone": check(item["deleted_at"] == item["fact"]["deleted_at"], "SYNC_BOOTSTRAP_INCOMPLETE")
        elif kind == "requesting_device_causal_anchor": anchors.append(item)
        elif kind == "unresolved_conflict": conflicts.append(item["conflict"])
        else: markers.append(item)
    validate_graph(facts, deleted_anchors={key for key, value in entities.items() if value["kind"] == "deleted_entity_anchor"})
    for anchor in anchors:
        key = anchor["key"]
        row = entities.get((key["target_type"], key["target_id"]))
        check(row is not None and anchor["client_sequence"] <= highest and anchor["resulting_field_version"] <= row["entity_version"], "SYNC_BOOTSTRAP_INCOMPLETE")
        if row["kind"] != "deleted_entity_anchor":
            fields = {digest(value["key"]): value["field_version"] for value in row["field_versions"]}
            check(digest(key) in fields and anchor["resulting_field_version"] <= fields[digest(key)], "SYNC_BOOTSTRAP_INCOMPLETE")
    for conflict in conflicts:
        check((conflict["target_type"], conflict["target_id"]) in entities, "SYNC_BOOTSTRAP_INCOMPLETE")
        if conflict["recovery_snapshot"] is not None:
            validate_fact(conflict["recovery_snapshot"])
            check(all(conflict["recovery_snapshot"][name] == conflict[name] for name in ("target_type", "target_id")), "SYNC_BOOTSTRAP_INCOMPLETE")
    for marker in markers:
        check(marker["begin_server_sequence"] <= marker["commit_server_sequence"] <= upper_bound, "SYNC_BOOTSTRAP_INCOMPLETE")
        values = provenance_entries(items, marker)
        check(len(values) == marker["snapshot_provenance_count"] and digest(values) == marker["snapshot_provenance_digest"], "SYNC_BOOTSTRAP_INCOMPLETE")


def partition(items, limit):
    pages, current, size = [], [], RULES["pagination"]["page_envelope_reservation_bytes"]
    for item in items:
        item_bytes = len(canonical(item)) + 1
        check(item_bytes + RULES["pagination"]["page_envelope_reservation_bytes"] <= CAPS["response_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        if current and (len(current) == limit or size + item_bytes > CAPS["response_soft_bytes"]):
            pages.append(current); current = []; size = RULES["pagination"]["page_envelope_reservation_bytes"]
        current.append(item); size += item_bytes
    if current or not pages: pages.append(current)
    return pages


def checkpoint(hook, name):
    if hook is not None: hook(name)


class BootstrapServer:
    """One authenticated account/device, immutable pages in actual SQLite transactions."""
    def __init__(self, path, *, account_id, device_id, keys, key_id):
        canonical_uuid(account_id); canonical_uuid(device_id, 4)
        self.path, self.account_id, self.device_id, self.key_id = path, account_id, device_id, key_id
        self.codec = CursorCodec(keys)
        with connect(path) as db:
            db.executescript("""PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS binding(account_id TEXT,device_id TEXT);
                CREATE TABLE IF NOT EXISTS state(payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS live(identity TEXT PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY,reuse_hash TEXT,identity TEXT NOT NULL,superseded INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS pages(id TEXT,ordinal INTEGER,payload TEXT NOT NULL,PRIMARY KEY(id,ordinal));""")
            old = db.execute("SELECT * FROM binding").fetchone()
            if old is None: db.execute("INSERT INTO binding VALUES(?,?)", (account_id, device_id))
            else: check(old == (account_id, device_id), "SYNC_SEQUENCE_ROUTE_MISMATCH")

    def seed(self, items, *, generation=0, transport=0, upper_bound=100, highest=0, confirmed=0, floor=0, cleanup=1788483600):
        items = sorted(copy.deepcopy(items), key=item_key)
        for value in (generation, transport, upper_bound, highest, confirmed, floor, cleanup): integer(value)
        check(confirmed <= highest and floor <= upper_bound, "SYNC_PAYLOAD_INVALID")
        validate_snapshot(items, upper_bound=upper_bound, highest=highest)
        state = dict(generation=generation, transport=transport, upper_bound=upper_bound, highest=highest, confirmed=confirmed, floor=floor, cleanup=cleanup)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM state"); db.execute("INSERT INTO state VALUES(?)", (encode(state),))
            db.execute("DELETE FROM live")
            db.executemany("INSERT INTO live VALUES(?,?)", [(encode([part.hex() for part in item_key(item)]), encode(item)) for item in items])

    def _claims(self, metadata, *, position, bootstrap):
        return dict(kind="bootstrap" if bootstrap else "sync", key_id=self.key_id, account_id=self.account_id,
            device_id=self.device_id, protocol_version=1, account_generation=metadata["account_generation"],
            snapshot_upper_bound=metadata["snapshot_upper_bound"], position=position,
            bootstrap_id=metadata["bootstrap_id"] if bootstrap else None,
            sync_transport_generation=metadata["sync_transport_generation"] if bootstrap else 0,
            expires_at_epoch_seconds=epoch(metadata["expires_at"]) if bootstrap else 0,
            retention_floor_server_sequence=metadata["retention_floor_server_sequence"],
            resolved_cleanup_before_epoch_seconds=epoch(metadata["resolved_conflict_cleanup_before"]))

    def begin(self, *, now, download_limit=500, hook=None):
        integer(now); check(1 <= integer(download_limit) <= 500, "SYNC_PAYLOAD_INVALID")
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL"); db.execute("BEGIN IMMEDIATE")
            state = json.loads(db.execute("SELECT payload FROM state").fetchone()[0])
            reuse = digest({name: state[name] for name in ("generation", "transport", "highest", "confirmed")} | {"limit": download_limit})
            existing = db.execute("SELECT id,identity FROM sessions WHERE reuse_hash=? AND superseded=0", (reuse,)).fetchone()
            if existing and now < epoch(json.loads(existing[1])["expires_at"]):
                return json.loads(db.execute("SELECT payload FROM pages WHERE id=? AND ordinal=0", (existing[0],)).fetchone()[0])
            items = sorted([json.loads(row[0]) for row in db.execute("SELECT payload FROM live")], key=item_key)
            validate_snapshot(items, upper_bound=state["upper_bound"], highest=state["highest"])
            partitions = partition(items, download_limit)
            metadata = dict(protocol_version=1, device_id=self.device_id, sync_transport_generation=state["transport"],
                bootstrap_id=str(uuid.uuid4()), account_generation=state["generation"], snapshot_upper_bound=state["upper_bound"],
                device_highest_client_sequence_at_snapshot=state["highest"], device_client_confirmed_through_at_snapshot=state["confirmed"],
                device_next_client_sequence_at_snapshot=None if state["highest"] == MAXIMUM else state["highest"] + 1,
                device_client_sequence_exhausted_at_snapshot=state["highest"] == MAXIMUM, retention_floor_server_sequence=state["floor"],
                resolved_conflict_cleanup_before=utc(state["cleanup"]), expires_at=utc(now + INVARIANTS["bootstrap"]["ttl_seconds"]),
                snapshot_item_count=len(items), snapshot_items_hash=digest(items), total_page_count=len(partitions), page_item_limit=download_limit)
            pages = []
            for ordinal, content in enumerate(partitions):
                more = ordinal + 1 < len(partitions)
                page = {**metadata, "page_ordinal": ordinal, "page_hash": "0" * 64, "items": content, "has_more": more,
                    "next_bootstrap_cursor": self.codec.issue(self._claims(metadata, position=ordinal + 1, bootstrap=True)) if more else None,
                    "terminal_sync_cursor": None if more else self.codec.issue(self._claims(metadata, position=state["upper_bound"], bootstrap=False))}
                page["page_hash"] = page_hash(page)
                validate_schema("sync/sync_bootstrap_page_response.schema.json", page)
                check(len(canonical(page)) <= CAPS["response_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
                pages.append(page)
            db.execute("UPDATE sessions SET superseded=1 WHERE superseded=0"); checkpoint(hook, "server_supersede")
            db.execute("INSERT INTO sessions VALUES(?,?,?,0)", (metadata["bootstrap_id"], reuse, encode(metadata))); checkpoint(hook, "server_session")
            db.executemany("INSERT INTO pages VALUES(?,?,?)", [(metadata["bootstrap_id"], ordinal, encode(page)) for ordinal, page in enumerate(pages)])
            checkpoint(hook, "server_pages")
            return pages[0]

    def download(self, token, *, now, download_limit=500):
        with connect(self.path) as db:
            state = json.loads(db.execute("SELECT payload FROM state").fetchone()[0])
            claims = self.codec.validate(token, account_id=self.account_id, device_id=self.device_id,
                account_generation=state["generation"], sync_transport_generation=state["transport"],
                retention_floor_server_sequence=state["floor"], now_epoch_seconds=now)
            check(claims["kind"] == "bootstrap", "SYNC_CURSOR_INVALID")
            session = db.execute("SELECT identity,superseded FROM sessions WHERE id=?", (claims["bootstrap_id"],)).fetchone()
            check(session is not None and not session[1], "SYNC_BOOTSTRAP_EXPIRED")
            metadata = json.loads(session[0])
            check(download_limit == metadata["page_item_limit"], "SYNC_PAYLOAD_INVALID")
            expected = self._claims(metadata, position=claims["position"], bootstrap=True)
            expected["key_id"] = claims["key_id"]
            check(claims == expected and 0 < claims["position"] < metadata["total_page_count"], "SYNC_CURSOR_INVALID")
            return json.loads(db.execute("SELECT payload FROM pages WHERE id=? AND ordinal=?", (claims["bootstrap_id"], claims["position"])).fetchone()[0])


class BootstrapLocal:
    """Durable local staging/atomic baseline promotion; no implicit cursor decoding."""
    def _begin_bootstrap_discovery(self, db, metadata):
        """An optional notice component can freeze discovery with the session."""

    def _finish_bootstrap_discovery(self, db, metadata, hook):
        """The standalone snapshot component does not certify notice delivery."""

    def __init__(self, path, *, device_id, transport=0):
        canonical_uuid(device_id, 4); integer(transport)
        self.path, self.device_id, self.transport = path, device_id, transport
        with connect(path) as db:
            db.executescript("""PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS binding(device_id TEXT,transport INTEGER);
                CREATE TABLE IF NOT EXISTS state(payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS session(identity TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS pages(ordinal INTEGER PRIMARY KEY,request_cursor TEXT,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS live(identity TEXT PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS finalized(id TEXT PRIMARY KEY,receipt TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS pending(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS failed(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS effect_gates(sequence INTEGER PRIMARY KEY);""")
            old = db.execute("SELECT * FROM binding").fetchone()
            if old is None:
                db.execute("INSERT INTO binding VALUES(?,?)", (device_id, transport))
                db.execute("INSERT INTO state VALUES(?)", (encode(dict(generation=0, upper_bound=0, local_ack=0, server_ack=0, next_sequence=1,
                    exhausted=False, cursor=None, floor=0, cleanup=0, fresh=True)),))
            else: check(old == (device_id, transport), "SYNC_SEQUENCE_ROUTE_MISMATCH")

    def _validate_page(self, page):
        validate_schema("sync/sync_bootstrap_page_response.schema.json", page)
        check(page["device_id"] == self.device_id and page["sync_transport_generation"] == self.transport, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(page_hash(page) == page["page_hash"], "SYNC_BOOTSTRAP_INCOMPLETE")
        high = page["device_highest_client_sequence_at_snapshot"]
        check(page["device_client_confirmed_through_at_snapshot"] <= high and
              page["device_next_client_sequence_at_snapshot"] == (None if high == MAXIMUM else high + 1), "SYNC_BOOTSTRAP_INCOMPLETE")
        check(page["retention_floor_server_sequence"] <= page["snapshot_upper_bound"] and
              page["page_ordinal"] < page["total_page_count"] and len(page["items"]) <= page["page_item_limit"] and
              page["has_more"] == (page["page_ordinal"] + 1 < page["total_page_count"]), "SYNC_BOOTSTRAP_INCOMPLETE")
        check(len(canonical(page)) <= CAPS["response_hard_bytes"] and
              all(len(canonical(item)) <= CAPS["bootstrap_item_hard_bytes"] for item in page["items"]), "SYNC_CHANGE_GROUP_TOO_LARGE")

    def begin(self, first_page):
        self._validate_page(first_page)
        check(first_page["page_ordinal"] == 0, "SYNC_BOOTSTRAP_INCOMPLETE")
        metadata = identity(first_page)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT identity FROM session").fetchone()
            if old and json.loads(old[0])["bootstrap_id"] == metadata["bootstrap_id"]:
                check(json.loads(old[0]) == metadata, "SYNC_BOOTSTRAP_INCOMPLETE")
                return
            db.execute("DELETE FROM pages"); db.execute("DELETE FROM session")
            db.execute("INSERT INTO session VALUES(?)", (encode(metadata),))
            self._begin_bootstrap_discovery(db, metadata)

    def stage(self, page, *, request_cursor, hook=None):
        self._validate_page(page)
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL"); db.execute("BEGIN IMMEDIATE")
            session = db.execute("SELECT identity FROM session").fetchone()
            check(session is not None and json.loads(session[0]) == identity(page), "SYNC_BOOTSTRAP_INCOMPLETE")
            old = db.execute("SELECT request_cursor,payload FROM pages WHERE ordinal=?", (page["page_ordinal"],)).fetchone()
            if old:
                check(old == (request_cursor, encode(page)), "SYNC_BOOTSTRAP_INCOMPLETE")
                return
            count = db.execute("SELECT count(*) FROM pages").fetchone()[0]
            check(page["page_ordinal"] == count, "SYNC_BOOTSTRAP_INCOMPLETE")
            previous = None if count == 0 else json.loads(db.execute("SELECT payload FROM pages WHERE ordinal=?", (count - 1,)).fetchone()[0])
            check(request_cursor == (previous["next_bootstrap_cursor"] if previous else None), "SYNC_BOOTSTRAP_INCOMPLETE")
            if previous: check(previous["has_more"] and request_cursor is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            db.execute("INSERT INTO pages VALUES(?,?,?)", (count, request_cursor, encode(page)))
            checkpoint(hook, "local_page_receipt")

    def _validate_local_intents(self, db):
        # The standalone component remains strict; the combined local-intent
        # oracle overrides this with journal validation, never a success flag.
        for table in ("pending", "failed", "effect_gates"):
            check(db.execute("SELECT count(*) FROM " + table).fetchone()[0] == 0, "REFERENCE_BOOTSTRAP_REBASE_REQUIRED")

    def _finalize_local_intents(self, db, state, metadata, hook):
        self._validate_local_intents(db)

    def finalize(self, *, expected_page_set_digest, final_cursor, hook=None):
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL"); db.execute("BEGIN IMMEDIATE")
            session = db.execute("SELECT identity FROM session").fetchone()
            check(session is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            metadata = json.loads(session[0])
            stored_pages = db.execute("SELECT ordinal,request_cursor,payload FROM pages ORDER BY ordinal").fetchall()
            pages = [json.loads(row[2]) for row in stored_pages]
            check(len(pages) == metadata["total_page_count"] and pages and not pages[-1]["has_more"], "SYNC_BOOTSTRAP_INCOMPLETE")
            check(page_set_digest(pages) == expected_page_set_digest and pages[-1]["terminal_sync_cursor"] == final_cursor, "SYNC_BOOTSTRAP_INCOMPLETE")
            for ordinal, page in enumerate(pages):
                self._validate_page(page)
                check(stored_pages[ordinal][0] == page["page_ordinal"] == ordinal and identity(page) == metadata and
                      stored_pages[ordinal][1] == (pages[ordinal - 1]["next_bootstrap_cursor"] if ordinal else None), "SYNC_BOOTSTRAP_INCOMPLETE")
            items = [item for page in pages for item in page["items"]]
            check(len(items) == metadata["snapshot_item_count"] and digest(items) == metadata["snapshot_items_hash"], "SYNC_BOOTSTRAP_INCOMPLETE")
            validate_snapshot(items, upper_bound=metadata["snapshot_upper_bound"], highest=metadata["device_highest_client_sequence_at_snapshot"])
            receipt = dict(page_set_digest=expected_page_set_digest, cursor=final_cursor, snapshot_items_hash=metadata["snapshot_items_hash"])
            previous = db.execute("SELECT receipt FROM finalized WHERE id=?", (metadata["bootstrap_id"],)).fetchone()
            if previous:
                check(json.loads(previous[0]) == receipt, "SYNC_BOOTSTRAP_INCOMPLETE")
                return
            self._validate_local_intents(db)
            state = json.loads(db.execute("SELECT payload FROM state").fetchone()[0])
            high, confirmed = metadata["device_highest_client_sequence_at_snapshot"], metadata["device_client_confirmed_through_at_snapshot"]
            check(high >= state["local_ack"] and confirmed >= state["server_ack"], "SYNC_BOOTSTRAP_INCOMPLETE")
            check(state["fresh"] or confirmed <= state["local_ack"], "SYNC_BOOTSTRAP_INCOMPLETE")
            if metadata["account_generation"] == state["generation"]:
                check(metadata["snapshot_upper_bound"] >= state["upper_bound"], "SYNC_BOOTSTRAP_INCOMPLETE")
            else: check(metadata["account_generation"] > state["generation"], "SYNC_BOOTSTRAP_INCOMPLETE")
            db.execute("DELETE FROM live"); checkpoint(hook, "local_clear_baseline")
            for kind_set, point in (({"fact_after_image", "tombstone", "deleted_entity_anchor"}, "local_entities"),
                    ({"unresolved_conflict", "requesting_device_causal_anchor"}, "local_conflicts_anchors"),
                    ({"import_publish_marker"}, "local_import_markers")):
                db.executemany("INSERT INTO live VALUES(?,?)", [(encode([part.hex() for part in item_key(item)]), encode(item)) for item in items if item["kind"] in kind_set])
                checkpoint(hook, point)
            same_generation = state["generation"] == metadata["account_generation"]
            floor, cleanup = metadata["retention_floor_server_sequence"], epoch(metadata["resolved_conflict_cleanup_before"])
            if same_generation and (floor < state["floor"] or cleanup < state["cleanup"]):
                floor, cleanup = state["floor"], state["cleanup"]
            state.update(generation=metadata["account_generation"], upper_bound=metadata["snapshot_upper_bound"], cursor=final_cursor,
                local_ack=high if state["fresh"] else state["local_ack"], server_ack=confirmed,
                next_sequence=None if high == MAXIMUM or state["exhausted"] else max(state["next_sequence"], high + 1),
                exhausted=state["exhausted"] or high == MAXIMUM, floor=floor, cleanup=cleanup, fresh=False)
            self._finalize_local_intents(db, state, metadata, hook)
            self._finish_bootstrap_discovery(db, metadata, hook)
            db.execute("UPDATE state SET payload=?", (encode(state),)); checkpoint(hook, "local_confirmation_cursor")
            db.execute("INSERT INTO finalized VALUES(?,?)", (metadata["bootstrap_id"], encode(receipt))); checkpoint(hook, "local_finalize_receipt")

    def snapshot(self):
        with connect(self.path) as db:
            return {table: db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
                    for table in ("state", "live", "session", "pages", "finalized", "pending", "failed", "effect_gates")}
