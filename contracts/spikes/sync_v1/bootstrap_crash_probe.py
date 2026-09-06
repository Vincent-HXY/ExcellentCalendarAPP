"""Child process exits without closing SQLite at a named synthetic write boundary."""
import json
import os
from pathlib import Path
import sys

from bootstrap_reference import BootstrapLocal, BootstrapServer
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW


def main():
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    def crash(name):
        if name == request["checkpoint"]: os._exit(79)
    if request["mode"] == "server_begin":
        server = BootstrapServer(Path(request["path"]), account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        server.begin(now=NOW, download_limit=2, hook=crash)
    else:
        local = BootstrapLocal(Path(request["path"]), device_id=D)
        if request["mode"] == "stage": local.stage(request["page"], request_cursor=None, hook=crash)
        else: local.finalize(expected_page_set_digest=request["digest"], final_cursor=request["cursor"], hook=crash)
    raise RuntimeError("requested crash boundary was not reached")


if __name__ == "__main__": main()
