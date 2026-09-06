"""Exit without unwinding a real resolution SQLite transaction."""
import json
import os
from pathlib import Path
import sys

from conflict_resolution_reference import ConflictStore
from protocol_reference import mutation_hash


def main():
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    server = ConflictStore(value["path"])
    def hook(point):
        if point == value["point"]:
            os._exit(79)
    server.resolve(value["device"], 0, value["mutation"], mutation_hash(value["mutation"]), hook=hook)
    raise AssertionError("resolution crash checkpoint not reached")


if __name__ == "__main__":
    main()
