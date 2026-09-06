"""Real process exit within the range transaction and actual signing port."""
import json
import os
from pathlib import Path
import sys

from import_proof_authority import ImportProofAuthority
from import_range_reference import ImportRangeStore

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
authority = ImportProofAuthority(data["binary"])
store = ImportRangeStore(data["path"], authority=authority, account_id=data["account"])


def crash(point):
    if point == data["point"]:
        print("KILL_POINT_REACHED:" + point, flush=True)
        os._exit(79)


getattr(store, data["method"])(data["request"], hook=crash)
authority.close()
raise SystemExit("Requested crash point was not reached")
