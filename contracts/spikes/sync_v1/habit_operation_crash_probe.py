"""Abrupt exit in a synthetic Habit transaction: no connection close or cleanup."""
import json
import os
from pathlib import Path
import sys

from habit_operation_reference import HabitOperationStore
from protocol_reference import mutation_hash

path, point, request = sys.argv[1:]
step = json.loads(Path(request).read_text(encoding="utf8"))


def crash(name):
    if name == point:
        os._exit(79)


store = HabitOperationStore(Path(path), checkpoint=crash)
m = step["mutation"]
store.exchange(step["device"], 0, [{"mutation": m, "payload_hash": mutation_hash(m)}])
raise RuntimeError("Expected transaction checkpoint not reached")
