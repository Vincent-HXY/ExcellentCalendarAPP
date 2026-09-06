"""Abrupt child-process termination inside the combined SQLite transaction."""
import json
import os
from pathlib import Path
import sys

from local_intent_reference import LocalIntentStore


def main():
    operation = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    local = LocalIntentStore(operation["path"], device_id=operation["device_id"])
    def crash(point):
        if point == operation["point"]:
            os._exit(79)  # No finally/close/rollback callback runs.
    getattr(local, operation["method"])(**operation["arguments"], hook=crash)
    raise AssertionError("requested transaction point was not reached")


if __name__ == "__main__":
    main()
