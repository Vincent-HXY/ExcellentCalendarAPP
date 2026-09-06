"""Exit at an observed real local import transaction boundary."""
import json
import os
from pathlib import Path
import sys

from import_download_reference import ImportDownloadStore

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
store = ImportDownloadStore(data["path"], device_id=data["device"])


def crash(point):
    if point == data["point"]:
        print("KILL_POINT_REACHED:" + point, flush=True)
        os._exit(79)


store.apply_download(data["response"], request_id=data["request"], hook=crash)
raise SystemExit("Requested crash point was not reached")
