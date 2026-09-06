"""Deterministic transaction and connection lifetime for isolated SQLite evidence."""
from contextlib import contextmanager
import sqlite3


@contextmanager
def connect(path, *, timeout=30):
    db = sqlite3.connect(path, timeout=timeout)
    try:
        db.execute("PRAGMA synchronous=FULL")
        with db:
            yield db
    finally:
        # sqlite3.Connection.__exit__ commits/rolls back but does not close.
        # Keep file handles out of subsequent reopen/crash and Windows cleanup.
        db.close()
