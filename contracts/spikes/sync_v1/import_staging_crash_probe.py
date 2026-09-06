"""Actual process exits inside an initial import commit on generated data."""
import json
import os
from pathlib import Path
import sys

from import_staging_reference import ImportStagingStore
from protocol_reference import mutation_hash


if __name__ == "__main__":
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    def stop(point):
        if point == value["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(79)
    store = ImportStagingStore(Path(value["path"]), account_id=value["account"])
    store.exchange(value["device"], 0, [{"mutation": value["mutation"], "payload_hash": mutation_hash(value["mutation"])}], hook=stop)
    raise RuntimeError("Expected import transaction exit was not reached")
