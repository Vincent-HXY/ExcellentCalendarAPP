"""Abrupt process death inside notice + download/finalize/claim transactions."""
import json
import os
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parents[2] / "contracts"), str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from notice_projection_reference import NoticeLocalStore


if __name__ == "__main__":
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    store = NoticeLocalStore(Path(value["path"]), device_id=value["device_id"])
    def stop(point):
        if point == value["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(79)
    getattr(store, value["method"])(**value["arguments"], hook=stop)
    raise RuntimeError("Expected process-death boundary was not reached")
