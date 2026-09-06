"""Exit the real cleanup owner after its writes, before SQLite commit."""
import json
import os
from pathlib import Path
import sys

from import_cleanup_reference import AccountImportCleanup, GuestImportCleanup, ImportCleanupServer
from import_proof_authority import ImportProofAuthority

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
directory = Path(data["directory"])
guest = GuestImportCleanup(directory / "guest.db", workspace_id=data["source"])
account = AccountImportCleanup(directory / "account.db", account_id=data["account_id"], device_id=data["device"], installation_key=bytes(range(32)))


def crash(point):
    if point == data["point"]:
        print("KILL_POINT_REACHED:" + point, flush=True)
        os._exit(79)


phase = data["phase"]
if phase == "retire":
    guest.retire(account, data["operation"], now=data["now"], hook=crash)
elif phase == "observe":
    account.observe_retirement(guest, data["receipt"], operation=data["operation"], hook=crash)
elif phase == "confirm":
    authority = ImportProofAuthority(data["binary"])
    server = ImportCleanupServer(directory / "server.db", account_id=data["account_id"], authority=authority)
    server.cleanup_confirm(data["request"], hook=crash)
    authority.close()
elif phase == "accept":
    account.accept_cleanup(data["receipt"], data["response"], hook=crash)
elif phase == "release":
    guest.release_completed(account, data["completed"], hook=crash)
elif phase == "ack":
    account.accept_ack_only(data["identifier"], data["response"], hook=crash)
raise SystemExit("Requested crash point was not reached")
