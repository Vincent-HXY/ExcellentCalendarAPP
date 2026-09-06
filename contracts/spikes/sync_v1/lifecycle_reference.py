"""Contract-only lifecycle decision oracle; OS/Keystore evidence is a separate spike."""
from datetime import datetime, timedelta, timezone
from functools import lru_cache
import math
from pathlib import Path
import re
import sqlite3
import uuid

from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_schema
from sqlite_reference import connect

UTC = timezone.utc
DAY_30 = timedelta(days=30)
UNREGISTERED = {"auth.token.refresh", "auth.logout", "user.get_current", "device.register"}
PENDING = UNREGISTERED | {"device.list", "auth.reauthenticate", "device.revoke"}


@lru_cache(maxsize=1)
def session_capabilities():
    from build_sync_domain_contracts import CONTRACTS, yaml
    return yaml.safe_load((CONTRACTS / "backend_sync_v1/session_capabilities.yaml").read_text(encoding="utf-8"))["account_operations"]


def backend_capability(registration_state, operation, *, same_installation=True):
    check(registration_state in {"unregistered", "pending_registration", "registered"}, "API_FORBIDDEN")
    capability = session_capabilities().get(operation)
    return bool(capability and capability[registration_state] and (registration_state != "pending_registration"
        or not capability["pending_installation_match_required"] or same_installation))


def device_name(manufacturer, model):
    def normalize(value):
        check(isinstance(value, str), "DEVICE_DISPLAY_NAME_INVALID")
        value.encode("utf-8", "strict")
        return " ".join(value.split())
    maker, device = normalize(manufacturer), normalize(model)
    result = device if maker and device.casefold().startswith(maker.casefold()) else " ".join(x for x in (maker, device) if x)
    return (result or "Android 设备")[:64]


def sync_phase(*, workspace_kind, identity_valid=True, globally_blocked=False, rebuilding=False,
               running=False, logout_authorized_queued=False, enabled=True, pending=0, online=True,
               ordinary_queued=False, recoverable_failure=False):
    check(workspace_kind in {"local", "account"}, "WORKSPACE_NOT_FOUND")
    integer(pending)
    for condition, phase in (
        (workspace_kind == "local", "local_only"), (not identity_valid, "auth_required"),
        (globally_blocked, "blocked"), (rebuilding, "rebuilding"), (running, "syncing"),
        (logout_authorized_queued, "queued"), (not enabled, "paused"), (pending > 0 and not online, "offline_pending"),
        (online and ordinary_queued, "queued"), (recoverable_failure, "failed"), (True, "idle")):
        if condition:
            return phase


def retry_delay(attempt, jitter_fraction, *, retry_after=None, retry_after_header=None):
    attempt = integer(attempt)
    check(attempt < 8, "RETRY_BUDGET_EXHAUSTED")
    check(type(jitter_fraction) in {int, float} and math.isfinite(jitter_fraction) and 0 <= jitter_fraction <= 1,
          "RETRY_RANDOM_INVALID")
    if retry_after is not None:
        check(type(retry_after) is int and 1 <= retry_after <= 86400, "SYNC_PAYLOAD_INVALID")
    if retry_after_header is not None:
        check(type(retry_after_header) is int and retry_after == retry_after_header, "SYNC_PAYLOAD_INVALID")
    jitter = jitter_fraction * min(900, 5 * 2 ** attempt)
    return min(86400, max(jitter, retry_after or 0))


def instant(value):
    check(isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value) is not None,
          "RETENTION_TIME_INVALID")
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def wire_time(value):
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def observe_boot(record, *, boot_count, elapsed_ms, aad_verified, process_continues=False, uuid_factory=uuid.uuid4):
    """Use only verified decrypted input. This function does not authenticate AAD.

    No observation can authorize a previous deadline merely by generating a new ID.
    """
    elapsed_ms = integer(elapsed_ms)
    check(boot_count is None or type(boot_count) is int and 0 <= boot_count <= 2147483647, "BOOT_IDENTITY_UNTRUSTED")
    if record is not None:
        validate_schema("auth/private/boot_epoch_record.schema.json", record)
        check(aad_verified, "BOOT_IDENTITY_UNTRUSTED")
        if record["source"] == "global_boot_count" and boot_count is not None:
            check(boot_count >= record["observed_boot_count"], "BOOT_IDENTITY_UNTRUSTED")
            if boot_count == record["observed_boot_count"]:
                check(elapsed_ms >= record["last_elapsed_realtime_ms"], "BOOT_IDENTITY_UNTRUSTED")
                return {**record, "last_elapsed_realtime_ms": elapsed_ms}, True
        elif record["source"] == "process_only" and boot_count is None and process_continues:
            check(elapsed_ms >= record["last_elapsed_realtime_ms"], "BOOT_IDENTITY_UNTRUSTED")
            return {**record, "last_elapsed_realtime_ms": elapsed_ms}, True
    new_id = str(uuid_factory())
    check(record is None or new_id != record["boot_id"], "BOOT_IDENTITY_UNTRUSTED")
    result = {"schema_version": 1, "source": "process_only" if boot_count is None else "global_boot_count",
        "boot_id": new_id, "last_elapsed_realtime_ms": elapsed_ms}
    if boot_count is not None:
        result["observed_boot_count"] = boot_count
    validate_schema("auth/private/boot_epoch_record.schema.json", result)
    return result, False


def begin_retention(*, policy, lifecycle_revision, server_time=None, same_boot_anchor=None, boot_id=None, elapsed_ms=None):
    integer(lifecycle_revision)
    check(policy in {"retain_30d", "destroy_now"}, "SYNC_PAYLOAD_INVALID")
    if policy == "destroy_now":
        return {"cache_action": "destroyed", "retained_until": None, "retention_clock_state": "destroyed", "lifecycle_revision": lifecycle_revision}
    if server_time is not None:
        start = instant(server_time)
    elif same_boot_anchor is not None:
        check(boot_id == same_boot_anchor["boot_id"] and elapsed_ms is not None and
              integer(elapsed_ms) >= same_boot_anchor["elapsed_realtime_at_anchor"], "RETENTION_TRUSTED_TIME_REQUIRED")
        start = instant(same_boot_anchor["server_time_anchor"]) + timedelta(milliseconds=elapsed_ms - same_boot_anchor["elapsed_realtime_at_anchor"])
    else:
        raise ValueError("RETENTION_TRUSTED_TIME_REQUIRED")
    # Second-granularity truncation can only shorten the window conservatively.
    start = start.replace(microsecond=0)
    result = {"retention_started_at": wire_time(start), "retained_until": wire_time(start + DAY_30),
        "server_time_anchor": wire_time(start), "elapsed_realtime_at_anchor": integer(elapsed_ms),
        "boot_id": boot_id, "retention_clock_state": "trusted", "lifecycle_revision": lifecycle_revision}
    validate_schema("auth/private/retention_deadline_record.schema.json", result)
    return result


def retention_due(record, *, current_boot_id=None, elapsed_ms=None, https_time_lower_bound=None):
    validate_schema("auth/private/retention_deadline_record.schema.json", record)
    if record["retention_clock_state"] in {"destroyed", "not_applicable"}:
        return False
    start, end = instant(record["retention_started_at"]), instant(record["retained_until"])
    check(end - start == DAY_30, "RETENTION_TIME_INVALID")
    lower_bound = None
    if https_time_lower_bound is not None:
        lower_bound = instant(https_time_lower_bound)
        check(lower_bound >= start, "RETENTION_TIME_INVALID")
    elif (record["retention_clock_state"] == "trusted" and current_boot_id == record["boot_id"] and elapsed_ms is not None):
        check(integer(elapsed_ms) >= record["elapsed_realtime_at_anchor"], "BOOT_IDENTITY_UNTRUSTED")
        lower_bound = instant(record["server_time_anchor"]) + timedelta(milliseconds=elapsed_ms - record["elapsed_realtime_at_anchor"])
    return lower_bound is not None and lower_bound >= end


class NoticeStore:
    """Durable net-new discovery and at-most-once exact-head claim oracle."""
    def __init__(self, path: Path):
        self.path = path
        with connect(path) as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS state(next_sequence INTEGER,last_claimed INTEGER,exhausted INTEGER);
                INSERT INTO state SELECT 1,0,0 WHERE NOT EXISTS(SELECT 1 FROM state);
                CREATE TABLE IF NOT EXISTS conflicts(id TEXT PRIMARY KEY,version INTEGER NOT NULL,unresolved INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS windows(id TEXT PRIMARY KEY,upper_bound INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS discovered(window TEXT,id TEXT,PRIMARY KEY(window,id));
                CREATE TABLE IF NOT EXISTS notices(sequence INTEGER PRIMARY KEY,id TEXT UNIQUE NOT NULL);
                CREATE TABLE IF NOT EXISTS notice_members(sequence INTEGER,id TEXT,PRIMARY KEY(sequence,id));
            """)

    def begin(self, window, upper_bound):
        integer(upper_bound)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT upper_bound FROM windows WHERE id=?", (window,)).fetchone()
            check(old is None or old[0] == upper_bound, "SYNC_APPLY_FAILED")
            db.execute("INSERT OR IGNORE INTO windows VALUES(?,?)", (window, upper_bound))

    def delta(self, window, conflict_id, version, *, resolved=False):
        integer(version)
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            check(db.execute("SELECT 1 FROM windows WHERE id=?", (window,)).fetchone() is not None, "SYNC_APPLY_FAILED")
            old = db.execute("SELECT version,unresolved FROM conflicts WHERE id=?", (conflict_id,)).fetchone()
            if old and version <= old[0]:
                return
            check(not old or old[1] or resolved, "SYNC_APPLY_FAILED")
            db.execute("INSERT OR REPLACE INTO conflicts VALUES(?,?,?)", (conflict_id, version, int(not resolved)))
            if old is None and not resolved:
                db.execute("INSERT OR IGNORE INTO discovered VALUES(?,?)", (window, conflict_id))

    def terminal(self, window, *, rollback=False):
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            if not db.execute("SELECT 1 FROM windows WHERE id=?", (window,)).fetchone():
                return None
            members = db.execute("SELECT d.id FROM discovered d JOIN conflicts c ON c.id=d.id WHERE d.window=? AND c.unresolved=1 ORDER BY d.id", (window,)).fetchall()
            sequence, _, exhausted = db.execute("SELECT * FROM state").fetchone()
            notice = None
            if members and not exhausted:
                notice = (sequence, str(uuid.uuid4()))
                db.execute("INSERT INTO notices VALUES(?,?)", notice)
                db.executemany("INSERT INTO notice_members VALUES(?,?)", [(sequence, row[0]) for row in members])
                db.execute("UPDATE state SET next_sequence=?,exhausted=?", (sequence if sequence == MAXIMUM else sequence + 1, int(sequence == MAXIMUM)))
            db.execute("DELETE FROM discovered WHERE window=?", (window,))
            db.execute("DELETE FROM windows WHERE id=?", (window,))
            if rollback:
                raise RuntimeError("injected_notice_rollback")
            return notice

    def claim(self, sequence, notice_id):
        integer(sequence)
        with connect(self.path) as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            head = db.execute("SELECT sequence,id FROM notices ORDER BY sequence LIMIT 1").fetchone()
            watermark = db.execute("SELECT last_claimed FROM state").fetchone()[0]
            if sequence <= watermark:
                return {"disposition": "no_longer_actionable", "count": 0}
            check(head == (sequence, notice_id), "SYNC_NOTICE_HEAD_MISMATCH")
            count = db.execute("SELECT COUNT(*) FROM notice_members n JOIN conflicts c ON c.id=n.id WHERE n.sequence=? AND c.unresolved=1", (sequence,)).fetchone()[0]
            db.execute("UPDATE state SET last_claimed=?", (sequence,))
            db.execute("DELETE FROM notice_members WHERE sequence=?", (sequence,))
            db.execute("DELETE FROM notices WHERE sequence=?", (sequence,))
            return {"disposition": "claimed" if count else "no_longer_actionable", "count": count}

    def snapshot(self):
        with connect(self.path) as db:
            return {name: db.execute("SELECT * FROM " + name + " ORDER BY 1").fetchall()
                    for name in ("state", "conflicts", "windows", "discovered", "notices", "notice_members")}
