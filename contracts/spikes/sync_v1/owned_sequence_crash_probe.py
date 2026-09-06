"""Abrupt exits inside the real shared device/owned-graph transaction."""
import json
import os
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parents[2] / "contracts"), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from owned_sequence_reference import OwnedSequenceStore


if __name__ == "__main__":
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    def stop(point):
        if point == value["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(79)
    store = OwnedSequenceStore(Path(value["path"]), hook=stop)
    store.exchange(value["device"], value["generation"], value["items"])
    raise RuntimeError("Expected owned transaction exit was not reached")
