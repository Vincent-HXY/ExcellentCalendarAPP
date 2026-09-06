"""Execute frozen histories and collect actual durable outcomes for the report."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts/tests")]
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import A, D, KEY, KEY_ID, NOW, after_image
from build_local_intent_fixtures import derive, FIXTURE
from local_intent_reference import LocalIntentStore
from protocol_reference import mutation_hash
from test_sync_local_intents import terminal
from test_sync_local_download import group, revised

OBSERVED = []


class LocalIntentFixtureTests(unittest.TestCase):
    def test_all_fixed_histories_across_real_reopen(self):
        vectors = json.loads(FIXTURE.read_text(encoding="utf8"))
        self.assertEqual(vectors, derive())
        OBSERVED.clear()
        for case in vectors["cases"]:
            with self.subTest(fixture=case["id"]), tempfile.TemporaryDirectory(prefix="excellent-calendar-local-history-") as scratch:
                root = Path(scratch)
                local = LocalIntentStore(root / "local.db", device_id=D)
                server = BootstrapServer(root / "server.db", account_id=A, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
                scenario, sample, m, replacement = (case["input"][key] for key in ("scenario", "baseline", "original", "replacement"))
                def bootstrap(item, high, upper, now):
                    server.seed([item], highest=high, upper_bound=upper)
                    page = server.begin(now=now, download_limit=5)
                    local.begin(page)
                    local.stage(page, request_cursor=None)
                    local.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
                bootstrap(after_image(sample), 0, 0, NOW)
                local.enqueue(m)
                request = local.prepare(1)
                error = None
                if scenario not in {"missing_receipt_bootstrap", "pending_above_snapshot"}:
                    local.acknowledge(terminal(m), request_id=request)
                if scenario in {"no_effect_replacement", "discard_failed_replacement", "stale_failed_revision", "failed_then_pending"}:
                    try:
                        local.enqueue(replacement, **({} if scenario == "failed_then_pending" else
                            {"replaces": 1, "expected_failed_revision": 2 if scenario == "stale_failed_revision" else 1}))
                    except ValueError as failure:
                        error = str(failure)
                    if scenario in {"no_effect_replacement", "discard_failed_replacement"}:
                        request2 = local.prepare(2)
                        local.acknowledge(terminal(replacement, status="accepted" if scenario == "no_effect_replacement" else "rejected"), request_id=request2)
                        if scenario == "discard_failed_replacement":
                            local.discard(2, expected_revision=1)
                if scenario in {"pending_above_snapshot", "failed_then_pending", "missing_receipt_bootstrap"}:
                    item = revised(sample, **({"name": "远端名字"} if scenario == "missing_receipt_bootstrap" else {"description": "远端备注"}))
                    bootstrap(item, 0 if scenario == "pending_above_snapshot" else 1, 1, NOW + 86400)
                elif scenario == "rejected_download":
                    request = local.prepare_download()
                    response = {"protocol_version": 1, "device_id": D, "sync_transport_generation": 0, "mode": "normal", "results": [],
                        "changes": [group(revised(sample, description="远端备注"))], "account_generation": 0, "snapshot_upper_bound": 1,
                        "next_cursor": "YWFhYWFhYWFhYWFhYWFhYQ", "has_more": False, "accepted_client_sequence_through": 0,
                        "retention_floor_server_sequence": 0, "resolved_conflict_cleanup_before": "2026-09-05T01:00:00Z"}
                    local.apply_download(response, request_id=request)
                local = LocalIntentStore(local.path, device_id=D)
                state = local.snapshot()
                fact = json.loads(state["presentation"][0][1])["fact"]
                counters = json.loads(state["state"][0][0])
                actual = {"name": fact["name"], "description": fact["description"], "pending": len(state["pending"]),
                    "failed": len(state["failed"]), "drafts": len(state["retained_drafts"]), "effects": len(state["effect_gates"]),
                    "local_ack": counters["local_ack"], "next_sequence": counters["next_sequence"], "error": error}
                self.assertEqual(actual, case["expected"])
                OBSERVED.append({"id": case["id"], "actual": actual})
