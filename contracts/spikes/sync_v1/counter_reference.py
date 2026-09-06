"""Executable Contract model, backed by real SQLite transactions, never product code.

This isolates counter/receipt/CAS semantics. It does not simulate the existence
of the actual workspace, Backend, Broker, import proof verifier or Outbox.
"""
from __future__ import annotations

import json
import math
import sqlite3
from pathlib import Path
from sqlite_reference import connect

MAXIMUM = 9007199254740991


def integer(value: object) -> int:
    # JSON Schema's integer is mathematical: 1, 1.0 and 1e0 describe the same
    # safe integer after the RFC 8785 binary64 parse. Booleans are never numbers.
    if type(value) not in (int, float) or not 0 <= value <= MAXIMUM or not math.isfinite(value) or value != int(value):
        raise ValueError("COUNTER_VALUE_INVALID")
    return int(value)


class CounterStore:
    def __init__(self, path: Path, kind: str, policy: dict, initial: int | None = None):
        self.path, self.kind, self.policy = path, kind, policy
        if initial is not None:
            if path.exists():
                raise ValueError("Refusing to overwrite a counter fixture database")
            with connect(path) as db:
                db.executescript("""
                    PRAGMA journal_mode=WAL;
                    CREATE TABLE state(value INTEGER NOT NULL CHECK(value BETWEEN 0 AND 9007199254740991),
                      terminal INTEGER NOT NULL CHECK(terminal IN(0,1)), facts INTEGER NOT NULL);
                    CREATE TABLE receipts(operation_id TEXT PRIMARY KEY, request TEXT NOT NULL, result TEXT NOT NULL);
                """)
                db.execute("INSERT INTO state VALUES (?,0,0)", (integer(initial),))

    def snapshot(self) -> tuple[int, int, int]:
        with connect(self.path) as db:
            return db.execute("SELECT value,terminal,facts FROM state").fetchone()

    def allocate(self, operation_id: str, input_value: str, expected: int | None = None,
                 *, rollback_before_commit: bool = False) -> dict:
        if expected is not None:
            expected = integer(expected)
        request = json.dumps([self.kind, input_value, expected], ensure_ascii=False, separators=(",", ":"))
        with connect(self.path, timeout=30) as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            receipt = db.execute("SELECT request,result FROM receipts WHERE operation_id=?", (operation_id,)).fetchone()
            if receipt:
                if receipt[0] != request:
                    return {"disposition": "replay_mismatch", "write": False}
                return {**json.loads(receipt[1]), "disposition": "duplicate", "write": False}
            value, terminal, facts = db.execute("SELECT value,terminal,facts FROM state").fetchone()
            if expected is not None and expected != value:
                return {"disposition": "stale_cas", "write": False, "value": value}
            if value == MAXIMUM:
                return {"disposition": "exhausted", "write": False, "value": value,
                        "error": self.policy["error"], "context": {"counter_kind": self.kind},
                        "action": self.policy["at_max"]}
            result_value = value + 1
            blocked = result_value == MAXIMUM and self.policy["at_last_increment"] == "publish_durable_blocked_instead_of_requested_action"
            notice_end = result_value == MAXIMUM and self.policy["at_last_increment"] == "commit_last_notice_and_mark_exhausted"
            result = {"disposition": "blocked" if blocked else "committed", "write": True,
                      "value": result_value, "business_effect": not blocked,
                      "terminal": blocked or notice_end, "error": self.policy["error"] if blocked else None}
            db.execute("UPDATE state SET value=?,terminal=?,facts=?", (result_value, int(result["terminal"]), facts + int(not blocked)))
            db.execute("INSERT INTO receipts VALUES (?,?,?)", (operation_id, request, json.dumps(result, separators=(",", ":"))))
            if rollback_before_commit:
                db.rollback()
                return {"disposition": "injected_rollback", "write": False, "value": value}
            return result
