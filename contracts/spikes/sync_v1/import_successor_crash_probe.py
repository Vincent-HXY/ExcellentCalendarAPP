"""Exit inside a real successor transaction; never intercept the DB writer."""
import json
import os
from pathlib import Path
import sys

from import_graph_reference import ImportGraphPlanner
from import_successor_reference import ImportSuccessorServer
from protocol_reference import mutation_hash


request = json.loads(Path(sys.argv[1]).read_text(encoding="utf8"))


def die(point):
    if point == request["point"]:
        print("KILL_POINT_REACHED:" + point, flush=True)
        os._exit(79)


if request["mode"] == "planner":
    ImportGraphPlanner(Path(request["path"])).prepare(request["account"], request["source"], 0, request["records"], hook=die)
else:
    server = ImportSuccessorServer(Path(request["path"]), account_id=request["account"], authority=None, staging_ttl_seconds=60)
    server.exchange(request["device"], 0, [{"mutation": row, "payload_hash": mutation_hash(row)} for row in request["messages"]], hook=die)
raise SystemExit("Requested crash point was not reached")
