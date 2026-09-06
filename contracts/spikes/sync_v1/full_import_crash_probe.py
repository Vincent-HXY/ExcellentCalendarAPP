"""Actual process termination inside the dual-store successor operation."""
import json
import os
from pathlib import Path
import sys

from import_client_reference import FullGraphAccountImport, FullGraphGuestImport


def main():
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    directory = Path(request["directory"])
    guest = FullGraphGuestImport(directory / "guest.db", workspace_id=request["source"])
    account = FullGraphAccountImport(directory / "account.db", account_id=request["account"],
        device_id=request["device"], installation_key=bytes(range(32)))

    def hook(point):
        if point == request["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(79)

    guest.commit(account, request["token"], hook=hook)
    raise RuntimeError("Requested actual process-death boundary was not reached")


if __name__ == "__main__":
    main()
