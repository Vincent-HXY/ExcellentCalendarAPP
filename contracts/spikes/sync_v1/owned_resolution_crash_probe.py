"""Exit after a real owned resolution write in a temporary SQLite transaction."""
import json
import os
from pathlib import Path
import sys

from owned_resolution_reference import OwnedResolutionStore
from protocol_reference import mutation_hash


if __name__ == "__main__":
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    def stop(point):
        if point == value["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(79)
    store = OwnedResolutionStore(Path(value["path"]))
    store.resolve(value["device"], 0, value["mutation"], mutation_hash(value["mutation"]), hook=stop)
    raise RuntimeError("Expected owned resolution exit was not reached")
