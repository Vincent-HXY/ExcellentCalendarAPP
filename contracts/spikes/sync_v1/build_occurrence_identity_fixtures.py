"""Identity migration cases with independent fixed civil/instant expectations."""
import argparse
import copy
import json
from pathlib import Path
import uuid

HERE=Path(__file__).resolve().parent
FIXTURE=HERE.parents[1]/"fixtures/sync/v1/occurrence_identity_vectors.json"
SOURCE="11111111-1111-4111-8111-111111111111"
TARGET="22222222-2222-4222-8222-222222222222"
NAMESPACE=uuid.UUID("2fa8ebd0-958e-5eae-83d1-1aa5da893415")


def key(event,revision,wall):
    return str(uuid.uuid5(NAMESPACE,json.dumps([event,revision,wall],separators=(",",":"),ensure_ascii=False)))


def derive():
    cases=[]
    def timed(name,start,end,zone,index,original,instant,reconverted,frequency="daily",same=1,source=SOURCE,revision=1):
        request={"source_event_id":source,"target_event_id":TARGET,"start_at":start,"end_at":end,"start_date":None,"end_date":None,
                 "is_all_day":False,"timezone":zone,"frequency":frequency,"revision":revision,"index":index,"stored_override":None}
        result={"original_local_start":original,"occurrence_start_at":instant,"occurrence_start_date":None,"utc_reconverted_wall":reconverted,
                "source_occurrence_key":key(source,revision,original),"target_occurrence_key":key(TARGET,revision,original),"same_instant_candidates":same}
        cases.append({"id":"FX-IDENTITY-"+name,"family":"FX-TARGET","rule_anchor":"cloud-sync-02/4.2,7.1,7.6","input":request,"expected":{"result":result}})
    timed("london-gap","2026-03-28T01:30:00Z","2026-03-28T02:30:00Z","Europe/London",1,"2026-03-29T01:30:00","2026-03-29T01:00:00Z","2026-03-29T02:00:00")
    timed("london-fold","2026-10-24T00:30:00Z","2026-10-24T01:30:00Z","Europe/London",1,"2026-10-25T01:30:00","2026-10-25T00:30:00Z","2026-10-25T01:30:00")
    timed("new-york-gap","2026-03-07T07:30:00Z","2026-03-07T08:30:00Z","America/New_York",1,"2026-03-08T02:30:00","2026-03-08T07:00:00Z","2026-03-08T03:00:00")
    timed("new-york-fold","2026-10-31T05:30:00Z","2026-10-31T06:30:00Z","America/New_York",1,"2026-11-01T01:30:00","2026-11-01T05:30:00Z","2026-11-01T01:30:00")
    timed("lord-howe-half-hour-gap","2026-10-02T15:45:00Z","2026-10-02T16:45:00Z","Australia/Lord_Howe",1,"2026-10-04T02:15:00","2026-10-03T15:30:00Z","2026-10-04T02:30:00")
    for index,wall in ((1,"2011-12-30T00:00:00"),(2,"2011-12-31T00:00:00")):
        timed("apia-colliding-instant-"+str(index),"2011-12-29T10:00:00Z","2011-12-29T11:00:00Z","Pacific/Apia",index,wall,
              "2011-12-30T10:00:00Z","2011-12-31T00:00:00",same=2)
    timed("monthly-clamp","2026-01-31T09:00:00Z","2026-01-31T10:00:00Z","Europe/London",1,"2026-02-28T09:00:00","2026-02-28T09:00:00Z","2026-02-28T09:00:00",frequency="monthly")
    timed("uppercase-source-lexeme","2026-03-28T01:30:00Z","2026-03-28T02:30:00Z","Europe/London",1,
          "2026-03-29T01:30:00","2026-03-29T01:00:00Z","2026-03-29T02:00:00",source="AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",revision=2147483647)
    all_day=copy.deepcopy(cases[0]); all_day["id"]="FX-IDENTITY-all-day-leap-month"
    all_day["input"].update(start_at=None,end_at=None,start_date="2024-01-31",end_date="2024-02-01",is_all_day=True,timezone="Asia/Shanghai",frequency="monthly",index=1)
    all_day["expected"]["result"]={"original_local_start":"2024-02-29","occurrence_start_at":None,"occurrence_start_date":"2024-02-29","utc_reconverted_wall":"2024-02-29",
        "source_occurrence_key":key(SOURCE,1,"2024-02-29"),"target_occurrence_key":key(TARGET,1,"2024-02-29"),"same_instant_candidates":1}
    cases.append(all_day)
    for name,patch in (("unknown-source-key",{"stored_override":{"occurrence_key":TARGET}}),
                       ("wrong-stored-instant",{"stored_override":{"occurrence_start_at":"2026-03-29T01:00:01Z"}}),
                       ("v2-cannot-truncate-wide-revision",{"revision":2147483648}),
                       ("v2-cannot-coerce-fraction",{"revision":1.5}), ("v2-yearly-unsupported",{"frequency":"yearly"})):
        case=copy.deepcopy(cases[0]); case["id"]="FX-IDENTITY-"+name; case["input"].update(patch); case["expected"]={"result":None}; cases.append(case)
    return {"fixture_version":1,"scope":"unchanged Core v2/TZDB original-civil lookup and import identity remap, not a v6 writer", "cases":cases}


if __name__=="__main__":
    parser=argparse.ArgumentParser(__doc__); parser.add_argument("--check",action="store_true"); args=parser.parse_args(); value=derive()
    if args.check:
        if json.loads(FIXTURE.read_text(encoding="utf-8"))!=value: raise ValueError("occurrence identity fixture drift")
    else: FIXTURE.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Original-civil identity cases:",len(value["cases"]))
