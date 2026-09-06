"""Device-local notice journals composed with real reference apply transactions.

The journal accepts only the authoritative unresolved set supplied by the apply
owner. It never invents conflicts from pending drafts or upload acknowledgments.
"""
import json
import uuid

from bootstrap_reference import checkpoint
from counter_reference import MAXIMUM, integer
from domain_reference import check
from identity_reference import canonical_uuid
from local_intent_reference import LocalIntentStore
from sqlite_reference import connect


class NoticeJournal:
    @staticmethod
    def initialize(db):
        db.executescript("""
            CREATE TABLE IF NOT EXISTS notice_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                next_sequence INTEGER,last_claimed INTEGER NOT NULL,exhausted INTEGER NOT NULL,
                revision INTEGER NOT NULL,diagnostic TEXT);
            INSERT OR IGNORE INTO notice_state VALUES(1,1,0,0,0,NULL);
            CREATE TABLE IF NOT EXISTS notice_window(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                kind TEXT NOT NULL,generation INTEGER NOT NULL,upper_bound INTEGER NOT NULL,identity TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS notice_discovery(id TEXT PRIMARY KEY,was_known INTEGER NOT NULL,
                seen_created INTEGER NOT NULL,seen_resolved INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS notice_queue(sequence INTEGER PRIMARY KEY,id TEXT UNIQUE NOT NULL,
                generation INTEGER NOT NULL,upper_bound INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS notice_members(sequence INTEGER NOT NULL,id TEXT NOT NULL,PRIMARY KEY(sequence,id));
        """)

    @staticmethod
    def begin(db, *, kind, generation, upper_bound, identity, unresolved):
        integer(generation); integer(upper_bound)
        check(kind in {"download", "bootstrap"}, "SYNC_APPLY_FAILED")
        binding = kind, generation, upper_bound, identity
        previous = db.execute("SELECT kind,generation,upper_bound,identity FROM notice_window").fetchone()
        if previous == binding:
            return
        carried = set()
        if previous:
            check(kind == "bootstrap", "SYNC_APPLY_FAILED")
            carried = {row[0] for row in db.execute("SELECT id FROM notice_discovery WHERE was_known=0 AND seen_created=1 AND seen_resolved=0")}
        db.execute("DELETE FROM notice_discovery")
        db.execute("INSERT OR REPLACE INTO notice_window VALUES(1,?,?,?,?)", binding)
        # Previously visible but still unnotified deltas remain part of the
        # interrupted logical discovery until an authoritative terminal page.
        db.executemany("INSERT INTO notice_discovery VALUES(?,?,?,0)",
            ((identifier, int(identifier not in carried), int(identifier in carried)) for identifier in sorted(set(unresolved))))

    @staticmethod
    def observe(db, identifier, *, resolved):
        canonical_uuid(identifier, 4)
        check(db.execute("SELECT 1 FROM notice_window").fetchone() is not None, "SYNC_APPLY_FAILED")
        db.execute("INSERT OR IGNORE INTO notice_discovery VALUES(?,0,0,0)", (identifier,))
        db.execute("UPDATE notice_discovery SET " + ("seen_resolved" if resolved else "seen_created") + "=1 WHERE id=?", (identifier,))

    @staticmethod
    def _advance_revision(db):
        revision = db.execute("SELECT revision FROM notice_state").fetchone()[0]
        check(revision < MAXIMUM, "SYNC_COUNTER_EXHAUSTED")
        db.execute("UPDATE notice_state SET revision=?", (revision + 1,))

    @classmethod
    def terminal(cls, db, unresolved, *, hook=None):
        window = db.execute("SELECT generation,upper_bound FROM notice_window").fetchone()
        if window is None:
            return None
        current = set(unresolved)
        members = [row[0] for row in db.execute("SELECT id FROM notice_discovery WHERE was_known=0 AND seen_created=1 AND seen_resolved=0 ORDER BY id")
            if row[0] in current]
        next_sequence, exhausted = db.execute("SELECT next_sequence,exhausted FROM notice_state").fetchone()
        notice = None
        if members and not exhausted:
            integer(next_sequence)
            check(next_sequence >= 1, "SYNC_APPLY_FAILED")
            notice = next_sequence, str(uuid.uuid4())
            db.execute("INSERT INTO notice_queue VALUES(?,?,?,?)", (*notice, *window))
            db.executemany("INSERT INTO notice_members VALUES(?,?)", ((next_sequence, identifier) for identifier in members))
            checkpoint(hook, "notice_queue_members")
            exhausted = next_sequence == MAXIMUM
            db.execute("UPDATE notice_state SET next_sequence=?,exhausted=?,diagnostic=?",
                (None if exhausted else next_sequence + 1, int(exhausted), "SYNC_NOTICE_SEQUENCE_EXHAUSTED" if exhausted else None))
            cls._advance_revision(db)
            checkpoint(hook, "notice_sequence_state")
        db.execute("DELETE FROM notice_discovery")
        db.execute("DELETE FROM notice_window")
        checkpoint(hook, "notice_terminal_journal_cleanup")
        return notice

    @classmethod
    def claim(cls, db, sequence, identifier, unresolved, *, hook=None):
        integer(sequence); canonical_uuid(identifier, 4)
        check(sequence >= 1, "SYNC_NOTICE_HEAD_MISMATCH")
        watermark = db.execute("SELECT last_claimed FROM notice_state").fetchone()[0]
        if sequence <= watermark:
            return {"disposition": "no_longer_actionable", "count": 0}
        head = db.execute("SELECT sequence,id FROM notice_queue ORDER BY sequence LIMIT 1").fetchone()
        check(head == (sequence, identifier), "SYNC_NOTICE_HEAD_MISMATCH")
        current = set(unresolved)
        count = sum(row[0] in current for row in db.execute("SELECT id FROM notice_members WHERE sequence=?", (sequence,)))
        db.execute("UPDATE notice_state SET last_claimed=?", (sequence,))
        checkpoint(hook, "notice_claim_watermark")
        db.execute("DELETE FROM notice_members WHERE sequence=?", (sequence,))
        db.execute("DELETE FROM notice_queue WHERE sequence=?", (sequence,))
        checkpoint(hook, "notice_claim_head_cleanup")
        cls._advance_revision(db)
        checkpoint(hook, "notice_claim_revision")
        return {"disposition": "claimed" if count else "no_longer_actionable", "count": count}

    @staticmethod
    def maintenance(db, *, limit=256):
        check(type(limit) is int and 1 <= limit <= 1000, "SYNC_PAYLOAD_INVALID")
        watermark = db.execute("SELECT last_claimed FROM notice_state").fetchone()[0]
        head = db.execute("SELECT MIN(sequence) FROM notice_queue WHERE sequence>?", (watermark,)).fetchone()[0]
        prefix = db.execute("SELECT sequence FROM notice_queue WHERE sequence<=? AND (? IS NULL OR sequence<>?) ORDER BY sequence LIMIT ?",
            (watermark, head, head, limit)).fetchall()
        db.executemany("DELETE FROM notice_members WHERE sequence=?", prefix)
        db.executemany("DELETE FROM notice_queue WHERE sequence=?", prefix)
        return len(prefix)


class NoticeLocalStore(LocalIntentStore):
    def __init__(self, path, *, device_id, transport=0):
        super().__init__(path, device_id=device_id, transport=transport)
        with connect(path) as db:
            NoticeJournal.initialize(db)

    @staticmethod
    def _unresolved(db):
        return {item["conflict"]["conflict_id"] for row in db.execute("SELECT payload FROM live")
            if (item := json.loads(row[0]))["kind"] == "unresolved_conflict"}

    def _begin_download_discovery(self, db, generation, upper_bound, hook):
        NoticeJournal.begin(db, kind="download", generation=generation, upper_bound=upper_bound,
            identity=str(upper_bound), unresolved=self._unresolved(db))
        checkpoint(hook, "notice_download_window")

    def _conflict_delta(self, db, delta):
        super()._conflict_delta(db, delta)
        NoticeJournal.observe(db, delta["conflict"]["conflict_id"] if delta["kind"] == "created" else delta["conflict_id"],
            resolved=delta["kind"] == "resolved")

    def _finish_download_discovery(self, db, response, hook):
        if not response["has_more"]:
            NoticeJournal.terminal(db, self._unresolved(db), hook=hook)

    def _begin_bootstrap_discovery(self, db, metadata):
        NoticeJournal.begin(db, kind="bootstrap", generation=metadata["account_generation"], upper_bound=metadata["snapshot_upper_bound"],
            identity=metadata["bootstrap_id"], unresolved=self._unresolved(db))

    def _finish_bootstrap_discovery(self, db, metadata, hook):
        current = self._unresolved(db)
        for identifier in sorted(current):
            NoticeJournal.observe(db, identifier, resolved=False)
        NoticeJournal.terminal(db, current, hook=hook)

    def claim_notice(self, sequence, identifier, *, hook=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            return NoticeJournal.claim(db, sequence, identifier, self._unresolved(db), hook=hook)

    def notice_status(self):
        with connect(self.path) as db:
            head = db.execute("SELECT sequence,id FROM notice_queue ORDER BY sequence LIMIT 1").fetchone()
            state = db.execute("SELECT next_sequence,last_claimed,exhausted,revision,diagnostic FROM notice_state").fetchone()
            return {"unresolved_conflict_count": len(self._unresolved(db)),
                "unclaimed_conflict_notice_count": db.execute("SELECT count(*) FROM notice_queue").fetchone()[0],
                "next_conflict_notice_id": head[1] if head else None, "next_conflict_notice_sequence": head[0] if head else None,
                "next_conflict_notice_count": db.execute("SELECT count(*) FROM notice_members WHERE sequence=?", (head[0],)).fetchone()[0] if head else 0,
                "next_sequence": state[0], "last_claimed": state[1], "exhausted": bool(state[2]), "revision": state[3], "diagnostic": state[4]}

    def snapshot(self):
        result = super().snapshot()
        with connect(self.path) as db:
            for name in ("notice_state", "notice_window", "notice_discovery", "notice_queue", "notice_members"):
                result[name] = db.execute("SELECT * FROM " + name + " ORDER BY 1,2").fetchall()
        return result
