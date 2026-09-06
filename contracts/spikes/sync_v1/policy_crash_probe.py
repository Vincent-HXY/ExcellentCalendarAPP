"""Actual subprocess termination inside isolated policy and GC transactions."""
import json
import os
from pathlib import Path
import sys

from policy_maintenance_reference import PolicyMaintenanceStore


def main():
    request = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))
    store = PolicyMaintenanceStore(Path(request["path"]), workspace_id=request["workspace_id"],
        runtime_id=request["runtime_id"], device_id=request["device_id"])

    def hook(point):
        if point == request["point"]:
            print("KILL_POINT_REACHED:" + point, flush=True)
            os._exit(81)

    if request["method"] not in {"set_enabled", "apply_download", "finalize", "maintenance"}:
        raise ValueError("Unknown test operation")
    getattr(store, request["method"])(**request["arguments"], hook=hook)
    raise RuntimeError("Requested process-death boundary was not reached")


if __name__ == "__main__":
    main()
