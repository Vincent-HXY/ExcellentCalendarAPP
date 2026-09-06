"""Durable import pages composed with the actual local projection/notice oracle.

The input is an authenticated typed download boundary. Partial publications keep
their own cursor; no upload receipt or status response is treated as visibility.
"""
import json
import uuid

from bootstrap_reference import CAPS, checkpoint, epoch, item_key, provenance_entries, validate_snapshot
from domain_reference import check, validate_schema
from import_contract_reference import PUBLISH_FIELDS, validate_publication
from local_download_reference import live_identity
from notice_projection_reference import NoticeLocalStore
from protocol_reference import canonical, digest, encode
from sqlite_reference import connect


class ImportDownloadStore(NoticeLocalStore):
    def __init__(self, path, **kwargs):
        super().__init__(path, **kwargs)
        with connect(self.path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS local_import_stage(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    header TEXT NOT NULL,generation INTEGER NOT NULL,position INTEGER NOT NULL,cursor TEXT NOT NULL,upper_bound INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_lines(sequence INTEGER PRIMARY KEY,payload TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS local_import_applied(batch TEXT PRIMARY KEY,group_id TEXT NOT NULL,metadata TEXT NOT NULL,via TEXT NOT NULL);
            """)

    @staticmethod
    def _stage_state(db):
        row = db.execute("SELECT header,generation,position,cursor,upper_bound FROM local_import_stage").fetchone()
        return None if row is None else {"header": json.loads(row[0]), "generation": row[1], "position": row[2], "cursor": row[3], "upper": row[4]}

    def prepare_download(self):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            self._not_rebuilding(db)
            state, stage = self._state(db), self._stage_state(db)
            check(not state["fresh"] and state["cursor"] is not None, "SYNC_BOOTSTRAP_INCOMPLETE")
            prepared = {"generation": state["generation"], "transport": self.transport,
                "cursor": stage["cursor"] if stage else state["cursor"],
                "position": stage["position"] if stage else state["upper_bound"],
                "fixed_upper": stage["upper"] if stage else state.get("download_upper"),
                "reported_ack": state["server_ack"], "import_group": stage["header"]["import_publish_group_id"] if stage else None}
            request_id = str(uuid.uuid4())
            db.execute("INSERT INTO prepared_pages VALUES(?,?)", (request_id, encode(prepared)))
            return request_id

    def _install_publication(self, db, messages, state, hook):
        items = validate_publication(messages)
        header = messages[0]
        metadata = {name: header[name] for name in PUBLISH_FIELDS}
        seen = set()
        for item in items:
            if item["kind"] in {"created", "resolved"}:
                identifier = item["conflict"]["conflict_id"] if item["kind"] == "created" else item["conflict_id"]
                identity = "conflict", identifier
                check(identity not in seen, "SYNC_APPLY_FAILED")
                seen.add(identity)
                self._conflict_delta(db, item)
                checkpoint(hook, "import_download_conflict")
            else:
                identity = item["target_type"], item["target_id"]
                check(identity not in seen, "SYNC_APPLY_FAILED")
                seen.add(identity)
                self._apply_entity_image(db, item)
                checkpoint(hook, "import_download_fact:" + item["target_type"])
        images = [json.loads(row[0]) for row in db.execute("SELECT payload FROM live")]
        for index, previous in enumerate(images):
            if previous["kind"] != "import_publish_marker" or any(previous[name] != header[name] for name in
                    ("source_workspace_id", "source_epoch", "import_lineage_id")):
                continue
            # These two fields describe the current local snapshot. Immutable
            # publication metadata and the original applied receipt stay intact.
            previous_entries = provenance_entries(images, previous)
            refreshed = {**previous, "snapshot_provenance_count": len(previous_entries),
                         "snapshot_provenance_digest": digest(previous_entries)}
            db.execute("UPDATE live SET payload=? WHERE identity=?", (encode(refreshed), live_identity(previous)))
            images[index] = refreshed
        checkpoint(hook, "import_download_prior_snapshot_markers")
        entries = provenance_entries(images, metadata)
        marker = {"kind": "import_publish_marker", **metadata,
            "snapshot_provenance_count": len(entries), "snapshot_provenance_digest": digest(entries)}
        db.execute("INSERT INTO live VALUES(?,?)", (live_identity(marker), encode(marker)))
        validate_snapshot(sorted([*images, marker], key=item_key), upper_bound=header["commit_server_sequence"],
            highest=max(state.get("baseline_device_highest", 0), state["local_ack"]))
        db.execute("INSERT INTO applied_groups VALUES(?,?,?,?)", (header["import_publish_group_id"], state["generation"],
            header["commit_server_sequence"], header["publish_digest"]))
        db.execute("INSERT INTO local_import_applied VALUES(?,?,?,?)", (header["import_batch_id"],
            header["import_publish_group_id"], encode(metadata), "download"))
        checkpoint(hook, "import_download_marker")

    def apply_download(self, response, *, request_id, hook=None):
        # A mixed page could expose half of an atomic group; reject it before
        # allowing the ordinary apply owner to consume any member.
        validate_schema("sync/sync_exchange_response.schema.json", response)
        import_page = bool(response["changes"]) and response["changes"][0]["kind"].startswith("import_publish_")
        with connect(self.path) as db:
            pending = self._stage_state(db)
        if not import_page:
            check(pending is None and all(row["kind"] == "change_group" for row in response["changes"]), "IMPORT_PUBLISH_INCOMPLETE")
            return super().apply_download(response, request_id=request_id, hook=hook)
        check(response["mode"] == "normal" and not response["results"], "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(response["device_id"] == self.device_id and response["sync_transport_generation"] == self.transport, "SYNC_SEQUENCE_ROUTE_MISMATCH")
        check(all(row["kind"].startswith("import_publish_") for row in response["changes"]), "IMPORT_PUBLISH_INCOMPLETE")
        check(len(canonical(response)) <= CAPS["response_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            prepared = db.execute("SELECT payload FROM prepared_pages WHERE id=?", (request_id,)).fetchone()
            check(prepared is not None, "SYNC_SEQUENCE_ROUTE_MISMATCH")
            prepared = json.loads(prepared[0])
            check(prepared["transport"] == self.transport and response["account_generation"] == prepared["generation"], "SYNC_CURSOR_GENERATION_MISMATCH")
            old = db.execute("SELECT hash,cursor FROM applied_pages WHERE id=?", (request_id,)).fetchone()
            if old:
                check(old == (digest(response), response["next_cursor"]), "SYNC_APPLY_FAILED")
                return old[1]
            self._not_rebuilding(db)
            self._validate_local_intents(db)
            state, stage = self._state(db), self._stage_state(db)
            check(state["generation"] == prepared["generation"], "SYNC_CURSOR_GENERATION_MISMATCH")
            cursor = stage["cursor"] if stage else state["cursor"]
            position = stage["position"] if stage else state["upper_bound"]
            check(prepared["cursor"] == cursor and prepared["position"] == position and
                prepared["import_group"] == (stage["header"]["import_publish_group_id"] if stage else None), "SYNC_APPLY_FAILED")
            upper = response["snapshot_upper_bound"]
            check(upper >= position and (prepared["fixed_upper"] is None or prepared["fixed_upper"] == upper), "SYNC_APPLY_FAILED")
            check(response["accepted_client_sequence_through"] == prepared["reported_ack"], "SYNC_APPLY_FAILED")
            self._begin_download_discovery(db, state["generation"], upper, hook)
            committed = False
            for index, message in enumerate(response["changes"]):
                kind = message["kind"]
                if kind == "import_publish_begin":
                    check(index == 0 and stage is None and position < message["server_sequence"] == message["begin_server_sequence"], "IMPORT_PUBLISH_INCOMPLETE")
                    check(message["commit_server_sequence"] <= upper and
                        message["commit_server_sequence"] - message["begin_server_sequence"] == message["total_chunk_count"] + 1,
                        "IMPORT_PUBLISH_INCOMPLETE")
                    check(db.execute("SELECT 1 FROM local_import_applied WHERE batch=?", (message["import_batch_id"],)).fetchone() is None, "SYNC_APPLY_FAILED")
                    stage = {"header": message, "position": message["server_sequence"], "generation": state["generation"], "cursor": cursor, "upper": upper}
                    db.execute("INSERT INTO local_import_stage VALUES(1,?,?,?,?,?)", (encode(message), state["generation"], message["server_sequence"], cursor, upper))
                else:
                    check(stage is not None and message["import_publish_group_id"] == stage["header"]["import_publish_group_id"] and
                        message["server_sequence"] == position + 1 <= stage["header"]["commit_server_sequence"], "IMPORT_PUBLISH_INCOMPLETE")
                    if kind == "import_publish_chunk":
                        check(message["chunk_ordinal"] == message["server_sequence"] - stage["header"]["begin_server_sequence"] - 1, "IMPORT_PUBLISH_INCOMPLETE")
                        check(message["payload_hash"] == digest({name: value for name, value in message.items() if name != "payload_hash"}), "SYNC_PAYLOAD_HASH_MISMATCH")
                        check(len(canonical(message)) <= CAPS["import_chunk_hard_bytes"], "SYNC_CHANGE_GROUP_TOO_LARGE")
                    else:
                        check(kind == "import_publish_commit" and index == len(response["changes"]) - 1, "IMPORT_PUBLISH_INCOMPLETE")
                        committed = True
                position = message["server_sequence"]
                db.execute("INSERT INTO local_import_lines VALUES(?,?)", (position, encode(message)))
                checkpoint(hook, "import_download_staged_line")
            check(response["next_cursor"] != cursor and (committed or response["has_more"]) and
                (not response["has_more"] or position < upper), "IMPORT_PUBLISH_INCOMPLETE")
            if committed:
                messages = [json.loads(row[0]) for row in db.execute("SELECT payload FROM local_import_lines ORDER BY sequence")]
                self._install_publication(db, messages, state, hook)
                for sequence, raw, generation in db.execute("SELECT sequence,result,generation FROM terminals").fetchall():
                    terminal = json.loads(raw)
                    if self._covered(db, terminal, generation):
                        db.execute("DELETE FROM effect_gates WHERE sequence=?", (sequence,))
                        self._cleanup_replacements(db, sequence, terminal, generation)
                self._advance_ack(db, state)
                checkpoint(hook, "import_download_effect_coverage")
                self._rebuild(db, state)
                checkpoint(hook, "import_download_projection")
                self._finish_download_discovery(db, response, hook)
                floor, cleanup = response["retention_floor_server_sequence"], epoch(response["resolved_conflict_cleanup_before"])
                if state["floor"] <= floor <= upper and cleanup >= state["cleanup"]:
                    state.update(floor=floor, cleanup=cleanup)
                state.update(cursor=response["next_cursor"], upper_bound=position if response["has_more"] else upper,
                    download_upper=upper if response["has_more"] else None)
                self._save_state(db, state)
                db.execute("DELETE FROM local_import_stage")
                db.execute("DELETE FROM local_import_lines")
                checkpoint(hook, "import_download_visible_cursor")
            else:
                db.execute("UPDATE local_import_stage SET position=?,cursor=?", (position, response["next_cursor"]))
                checkpoint(hook, "import_download_staging_cursor")
            db.execute("INSERT INTO applied_pages VALUES(?,?,?)", (request_id, digest(response), response["next_cursor"]))
            checkpoint(hook, "import_download_page_receipt")
            return response["next_cursor"]

    def _finalize_local_intents(self, db, state, metadata, hook):
        # BootstrapLocal has already validated every page, marker and provenance
        # against the same snapshot before entering this transaction hook.
        stage = self._stage_state(db)
        markers = [json.loads(row[0]) for row in db.execute("SELECT payload FROM live") if json.loads(row[0])["kind"] == "import_publish_marker"]
        if stage:
            check(any(all(marker[name] == stage["header"][name] for name in PUBLISH_FIELDS) for marker in markers), "SYNC_BOOTSTRAP_INCOMPLETE")
        for marker in markers:
            value = {name: marker[name] for name in PUBLISH_FIELDS}
            old = db.execute("SELECT metadata FROM local_import_applied WHERE batch=?", (marker["import_batch_id"],)).fetchone()
            check(old is None or json.loads(old[0]) == value, "SYNC_BOOTSTRAP_INCOMPLETE")
            db.execute("INSERT OR IGNORE INTO local_import_applied VALUES(?,?,?,?)", (marker["import_batch_id"],
                marker["import_publish_group_id"], encode(value), "bootstrap"))
        db.execute("DELETE FROM local_import_stage")
        db.execute("DELETE FROM local_import_lines")
        checkpoint(hook, "import_download_bootstrap_coverage")
        super()._finalize_local_intents(db, state, metadata, hook)

    def snapshot(self):
        result = super().snapshot()
        with connect(self.path) as db:
            for table in ("local_import_stage", "local_import_lines", "local_import_applied"):
                result[table] = db.execute("SELECT * FROM " + table + " ORDER BY 1").fetchall()
        return result
