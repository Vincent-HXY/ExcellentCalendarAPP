"""Terminate a real process at the fresh import recovery transaction boundaries."""
import json
import os
from pathlib import Path
import sys

from import_client_reference import FullGraphGuestImport
from import_fresh_reference import FreshImportAccount
from import_proof_authority import ImportProofVerifier


def main():
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    directory = Path(request["directory"])
    guest = FullGraphGuestImport(directory / "guest.db", workspace_id=request["source"])
    account = FreshImportAccount(directory / "fresh.db", account_id=request["account"], device_id=request["device"],
        transport=request["fence"]["recovery"]["sync_transport_generation"], installation_key=bytes(range(32)))
    verifier = ImportProofVerifier(request["binary"], request["trust"])

    def hook(point):
        if point == request["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(80)

    if request["point"] == "import_fresh_ready":
        account.finish_recovery(hook=hook)
    else:
        account.recover(guest, request["fence"], request["status"], authority=verifier, proof=request["proof"], hook=hook)
    raise RuntimeError("Requested process-death boundary was not reached")


if __name__ == "__main__":
    main()
