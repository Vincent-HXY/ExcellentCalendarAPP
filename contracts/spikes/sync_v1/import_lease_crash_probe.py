"""Exit inside one phase of the actual two-database source lease saga."""
import json
import os
from pathlib import Path
import sys

from import_lease_reference import AccountImportJournal, GuestImportSource

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
guest = GuestImportSource(data["guest"], workspace_id=data["source"])
account = AccountImportJournal(data["account"], account_id=data["account_id"], device_id=data["device"], installation_key=bytes(range(32)))


def crash(point):
    if point == data["point"]:
        print("KILL_POINT_REACHED:" + point, flush=True)
        os._exit(79)


guest.commit(account, data["token"], hook=crash)
raise SystemExit("Requested crash point was not reached")
