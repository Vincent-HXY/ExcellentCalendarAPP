"""Sync identity/reference-graph oracle, separate from Native v2 identity-array rules.

The mapping ledger is an isolated SQLite model, not a production workspace implementation.
UUIDv4 mappings are allocated once and persisted; only lineage/derived logical identities use
UUIDv5. Hash-derived bytes are never mislabeled as a randomly generated UUIDv4.
"""
from __future__ import annotations

import json
import re
import sqlite3
import uuid
from pathlib import Path
from typing import Callable
from counter_reference import integer

MAX_SAFE_INTEGER = 9007199254740991
NAMESPACES = {name: uuid.uuid5(uuid.NAMESPACE_DNS, "excellent-calendar.local/sync-protocol-v1/" + name)
              for name in ("import-lineage", "habit-check-in", "reminder-intent")}
OCCURRENCE_NAMESPACE = uuid.UUID("2fa8ebd0-958e-5eae-83d1-1aa5da893415")
MAPPABLE = {"category", "event", "event_recurrence_family", "anniversary",
            "anniversary_recurrence", "habit", "habit_recurrence"}


def canonical_uuid(value: str, version: int | None = None) -> str:
    if not isinstance(value, str):
        raise ValueError("IDENTITY_INVALID")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ValueError("IDENTITY_INVALID") from None
    if str(parsed) != value or parsed.variant != uuid.RFC_4122 or version is not None and parsed.version != version:
        raise ValueError("IDENTITY_INVALID")
    return value


def checked_epoch(value: int) -> int:
    try:
        return integer(value)
    except ValueError:
        raise ValueError("IMPORT_SOURCE_EPOCH_INVALID")


def compact_array(values: list) -> str:
    # This is the explicit identity-array name, NOT the JCS object/hash domain.
    return json.dumps(values, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def lineage_id(account_id: str, source_workspace_id: str, source_epoch: int) -> str:
    name = canonical_uuid(account_id) + "\n" + canonical_uuid(source_workspace_id) + "\n" + str(checked_epoch(source_epoch))
    return str(uuid.uuid5(NAMESPACES["import-lineage"], name))


def check_in_id(habit_id: str, check_date: str) -> str:
    from datetime import date
    if not isinstance(check_date, str) or len(check_date) != 10 or date.fromisoformat(check_date).isoformat() != check_date:
        raise ValueError("CHECK_DATE_INVALID")
    return str(uuid.uuid5(NAMESPACES["habit-check-in"], compact_array([canonical_uuid(habit_id), check_date])))


def reminder_intent_id(owner_type: str, owner_id: str) -> str:
    if owner_type not in {"event", "anniversary", "habit"}:
        raise ValueError("REMINDER_OWNER_INVALID")
    return str(uuid.uuid5(NAMESPACES["reminder-intent"], compact_array([owner_type, canonical_uuid(owner_id)])))


def occurrence_key(event_id: str, revision: int, original_local_start: str) -> str:
    from datetime import date, datetime
    revision = integer(revision)
    if revision < 1:
        raise ValueError("RECURRENCE_REVISION_INVALID")
    if not isinstance(original_local_start, str):
        raise ValueError("OCCURRENCE_LOCAL_START_INVALID")
    if len(original_local_start) == 10:
        if date.fromisoformat(original_local_start).isoformat() != original_local_start:
            raise ValueError("OCCURRENCE_LOCAL_START_INVALID")
    elif len(original_local_start) == 19:
        if datetime.fromisoformat(original_local_start).isoformat(timespec="seconds") != original_local_start:
            raise ValueError("OCCURRENCE_LOCAL_START_INVALID")
    else:
        raise ValueError("OCCURRENCE_LOCAL_START_INVALID")
    return str(uuid.uuid5(OCCURRENCE_NAMESPACE, compact_array([canonical_uuid(event_id), revision, original_local_start])))


class MappingLedger:
    def __init__(self, path: Path, factory: Callable[[], str] = lambda: str(uuid.uuid4())):
        self.db = sqlite3.connect(path, timeout=10, isolation_level=None)
        self.factory = factory
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("""CREATE TABLE IF NOT EXISTS mapping(
            lineage_id TEXT NOT NULL, target_type TEXT NOT NULL, source_id TEXT NOT NULL,
            target_id TEXT NOT NULL, published INTEGER NOT NULL DEFAULT 0 CHECK(published IN (0,1)),
            PRIMARY KEY(lineage_id,target_type,source_id), UNIQUE(target_type,target_id))""")

    def close(self):
        self.db.close()

    def reserve(self, lineage: str, sources: list[tuple[str, str]], occupied: set[tuple[str, str]]) -> dict:
        canonical_uuid(lineage, 5)
        if len(set(sources)) != len(sources) or any(kind not in MAPPABLE for kind, _ in sources):
            raise ValueError("IMPORT_MAPPING_INVALID")
        # Only current typed source facts enter this oracle. Legacy v1 opaque entity payloads
        # need their own audited conversion; opaque *weak references* are handled below.
        for kind, source in sources:
            if not isinstance(source, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", source):
                raise ValueError("IMPORT_SOURCE_IDENTITY_INVALID")
            if kind in {"category", "habit", "habit_recurrence"}:
                canonical_uuid(source, 4)
        return self._reserve_validated(lineage, sources, occupied)

    def reserve_legacy_events(self, lineage: str, source_ids: list[str], occupied: set[tuple[str, str]]) -> dict:
        """Separate audited v1 namespace; a UUID-looking compatibility ID is still v1."""
        from legacy_identity_reference import legacy_source_id
        canonical_uuid(lineage, 5)
        sources = [("event", legacy_source_id(value)) for value in source_ids]
        if len(set(sources)) != len(sources):
            raise ValueError("IMPORT_DUPLICATE_IDENTITY")
        return self._reserve_validated(lineage, sources, occupied)

    def _reserve_validated(self, lineage, sources, occupied):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            result = {}
            for kind, source in sorted(sources):
                row = self.db.execute("SELECT target_id FROM mapping WHERE lineage_id=? AND target_type=? AND source_id=?",
                                      (lineage, kind, source)).fetchone()
                if row:
                    result[(kind, source)] = row[0]
                    continue
                candidate = source
                # The v5 Event/Anniversary UUID checker accepts uppercase and non-v4 UUID
                # lexemes. Preserve them as source keys, allocate a new v4 target instead of
                # case-folding or reinterpreting the identity in the existing guest graph.
                try:
                    canonical_uuid(candidate, 4)
                except ValueError:
                    candidate = canonical_uuid(self.factory(), 4)
                for attempt in range(65):
                    taken = (kind, candidate) in occupied or self.db.execute(
                        "SELECT 1 FROM mapping WHERE target_type=? AND target_id=?", (kind, candidate)).fetchone()
                    if not taken:
                        break
                    if attempt == 64:
                        raise ValueError("IMPORT_MAPPING_ALLOCATION_FAILED")
                    candidate = canonical_uuid(self.factory(), 4)
                self.db.execute("INSERT INTO mapping(lineage_id,target_type,source_id,target_id) VALUES(?,?,?,?)",
                                (lineage, kind, source, candidate))
                result[(kind, source)] = candidate
            self.db.execute("COMMIT")
            return result
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def mark_published(self, lineage: str):
        self.db.execute("UPDATE mapping SET published=1 WHERE lineage_id=?", (lineage,))

    def successor_deletes(self, lineage: str, live: set[tuple[str, str]]) -> list[dict]:
        return [{"target_type": kind, "source_id": source, "target_id": target}
                for kind, source, target in self.db.execute(
                    "SELECT target_type,source_id,target_id FROM mapping WHERE lineage_id=? AND target_type!='event_recurrence_family' ORDER BY target_type,source_id",
                    (lineage,)) if (kind, source) not in live]


def remap_weak_category(value: str | None, mapping: dict[tuple[str, str], str]) -> str | None:
    if value is not None and not isinstance(value, str):
        raise ValueError("CATEGORY_REFERENCE_INVALID")
    # Deliberately no trim, case fold, UUID parsing, Unicode normalization or synthesized row.
    return mapping.get(("category", value), value)


def remap_strong(target_type: str, value: str, mapping: dict[tuple[str, str], str]) -> str:
    if (target_type, value) not in mapping:
        raise ValueError("IMPORT_REFERENCE_MISSING")
    return mapping[target_type, value]
