"""Typed proof binding and atomic acceptance oracle over disposable SQLite.

All signature decisions come from the real compiled C++ capsule consumer. This
is isolated protocol evidence, not the production v6 migration or lifecycle.
"""
import copy
import json
import subprocess

from counter_reference import MAXIMUM, integer
from domain_reference import check, validate_schema
from identity_reference import lineage_id
from protocol_reference import canonical, digest
from sqlite_reference import connect


def authenticate(binary, requests):
    completed = subprocess.run([str(binary), "--verify-lines"], input="\n".join(json.dumps(value, ensure_ascii=False, separators=(",", ":")) for value in requests) + "\n",
        capture_output=True, encoding="utf-8", timeout=30, check=True)
    lines = completed.stdout.splitlines()
    check(len(lines) == len(requests) and all(line in {"VALID", "REJECT"} for line in lines), "AUTHENTICATOR_FAILED")
    return [line == "VALID" for line in lines]


def validate_recovery(value):
    validate_schema("sync/sync_sequence_recovery_bundle.schema.json", value)
    highest = integer(value["highest_client_sequence"])
    check(integer(value["client_confirmed_through"]) <= highest, "SYNC_PAYLOAD_INVALID")
    check(value["next_client_sequence"] == (None if highest == MAXIMUM else highest + 1), "SYNC_PAYLOAD_INVALID")


def validate_typed_claims(request):
    """No signature shortcut: this function establishes domain validity only."""
    purpose, data = request["expected_purpose"], request["claim_data"]
    account = request["expected_account_id"]
    if purpose == "device_fence":
        wire = {**data, "fence_receipt": request["token"], "result_hash": request["claimed_hash"]}
        validate_schema("sync/sync_device_fence_response.schema.json", wire)
        validate_recovery(data["recovery"])
        previous = integer(data["previous_sync_transport_generation"])
        check(previous < MAXIMUM and data["recovery"]["sync_transport_generation"] == previous + 1, "SYNC_TRANSPORT_GENERATION_MISMATCH")
        identities = set()
        for proof in data["resolved_absent_import_fences"]:
            check(proof["kind"] == "never_visible_after_transport_fence", "SYNC_PAYLOAD_INVALID")
            check(proof["origin_device_id"] == data["device_id"] and proof["fence_operation_id"] == data["fence_operation_id"], "SYNC_PAYLOAD_INVALID")
            check(proof["origin_sync_transport_generation"] == previous and proof["recovery"] == data["recovery"], "SYNC_PAYLOAD_INVALID")
            check(proof["proof_id"] not in identities, "SYNC_PAYLOAD_INVALID"); identities.add(proof["proof_id"])
            nested = {**request, "expected_purpose": "import_range_close", "claim_data": {key: value for key, value in proof.items() if key not in {"proof_token", "proof_hash"}},
                      "token": proof["proof_token"], "claimed_hash": proof["proof_hash"]}
            validate_typed_claims(nested)
    elif purpose == "import_range_close":
        wire = {**data, "proof_token": request["token"], "proof_hash": request["claimed_hash"]}
        validate_schema("sync/import_range_close_proof.schema.json", wire)
        validate_recovery(data["recovery"])
        check(data["import_lineage_id"] == lineage_id(account, data["source_workspace_id"], data["source_epoch"]), "IMPORT_LINEAGE_MISMATCH")
        previous = integer(data["previous_import_revision"])
        check(previous < MAXIMUM and data["resulting_import_revision"] == previous + 1, "IMPORT_VERSION_CONFLICT")
        manifest = data["manifest"]
        check(manifest["source_workspace_id"] == data["source_workspace_id"] and manifest["source_epoch"] == data["source_epoch"], "IMPORT_LINEAGE_MISMATCH")
        check(sum(manifest["target_counts"].values()) + manifest["portable_preferences_count"] == manifest["total_item_count"], "SYNC_PAYLOAD_INVALID")
        # The signed claim binds the original declared manifest hash. A range
        # proof may exist before any items arrive, so its consumer cannot
        # reconstruct the item-content digest from manifest metadata alone.
        check(data["begin_client_sequence"] + manifest["total_item_count"] + 1 == data["terminal_client_sequence"], "SYNC_PAYLOAD_INVALID")
        if data["kind"] == "seen_range_closed":
            check(data["recovery"]["sync_transport_generation"] >= data["origin_sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(data["recovery"]["highest_client_sequence"] >= data["terminal_client_sequence"], "SYNC_PAYLOAD_INVALID")
        else:
            previous_generation = integer(data["origin_sync_transport_generation"])
            check(previous_generation < MAXIMUM and data["resulting_sync_transport_generation"] == previous_generation + 1, "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(data["recovery"]["sync_transport_generation"] == data["resulting_sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
    elif purpose == "account_deleted":
        validate_schema("sync/proof/account_deleted_claim_data.schema.json", data)
        check(data["account_id"] == account, "IMPORT_LINEAGE_MISMATCH")
    else:
        raise ValueError("SYNC_PAYLOAD_INVALID")


def authenticate_typed(binary, request):
    validate_typed_claims(request)
    requests = [request]
    if request["expected_purpose"] == "device_fence":
        for proof in request["claim_data"]["resolved_absent_import_fences"]:
            requests.append({**request, "expected_purpose": "import_range_close", "claim_data": {key: value for key, value in proof.items() if key not in {"proof_token", "proof_hash"}},
                             "token": proof["proof_token"], "claimed_hash": proof["proof_hash"]})
    check(all(authenticate(binary, requests)), "SYNC_PAYLOAD_INVALID")


class AcceptanceLedger:
    """Small transaction oracle; table names deliberately differ from v6 DDL."""
    def __init__(self, path, binary):
        self.path, self.binary = path, binary
        with connect(path) as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS proof_test_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    account_id TEXT NOT NULL, device_id TEXT NOT NULL, runtime_id TEXT NOT NULL, generation INTEGER NOT NULL,
                    highest INTEGER NOT NULL, acknowledged INTEGER NOT NULL, next_sequence INTEGER, exhausted INTEGER NOT NULL,
                    ack_dirty INTEGER NOT NULL, fresh INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS proof_test_imports(lineage TEXT PRIMARY KEY, reservation_json TEXT NOT NULL, revision INTEGER NOT NULL, closed INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS proof_test_receipts(purpose TEXT NOT NULL, receipt_id TEXT NOT NULL, token TEXT NOT NULL,
                    claim_hash TEXT NOT NULL, PRIMARY KEY(purpose,receipt_id));
                CREATE TABLE IF NOT EXISTS proof_test_revoked_keys(key_id TEXT PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS proof_test_guest_lease(source_id TEXT PRIMARY KEY, account_id TEXT NOT NULL, epoch INTEGER NOT NULL,
                    current_epoch INTEGER NOT NULL, cleanup_pending INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS proof_test_guest_epochs(source_id TEXT PRIMARY KEY, current_epoch INTEGER NOT NULL);
            """)

    def seed(self, *, account_id, device_id, runtime_id, generation=0, fresh=False):
        with connect(self.path) as db:
            db.execute("INSERT INTO proof_test_state VALUES(1,?,?,?,?,0,0,1,0,0,?)", (account_id, device_id, runtime_id, generation, int(fresh)))

    def reserve(self, data):
        with connect(self.path) as db:
            db.execute("INSERT INTO proof_test_imports VALUES(?,?,?,0)", (data["import_lineage_id"], canonical(data).decode(), data["previous_import_revision"]))

    def revoke(self, key_ids):
        # A verified APK contributes only a monotone union, never a replacement.
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            for key in key_ids:
                check(isinstance(key, str) and len(key) == 64 and set(key) <= set("0123456789abcdef"), "SYNC_PAYLOAD_INVALID")
                db.execute("INSERT OR IGNORE INTO proof_test_revoked_keys VALUES(?)", (key,))

    def accept(self, request, *, expected_runtime_id, expected_operation_id=None, source_workspace_id=None, fail_at=None):
        with connect(self.path) as db:
            db.execute("BEGIN IMMEDIATE")
            def checkpoint(name):
                if fail_at == name: raise RuntimeError("injected " + name)
            request = copy.deepcopy(request)
            request["locally_revoked_keys"] = sorted({*request["locally_revoked_keys"], *(row[0] for row in db.execute("SELECT key_id FROM proof_test_revoked_keys"))})
            authenticate_typed(self.binary, request)
            checkpoint("authenticated")
            row = db.execute("SELECT account_id,device_id,runtime_id,generation,highest,acknowledged,fresh FROM proof_test_state WHERE singleton=1").fetchone()
            check(row is not None and row[0] == request["expected_account_id"] and row[2] == expected_runtime_id, "WORKSPACE_RUNTIME_MISMATCH")
            purpose, data = request["expected_purpose"], request["claim_data"]
            if purpose == "account_deleted": check(isinstance(source_workspace_id, str), "IMPORT_LINEAGE_MISMATCH")
            receipt_id = data["fence_operation_id"] if purpose == "device_fence" else data["proof_id"] if purpose == "import_range_close" else data["account_id"] + ":" + source_workspace_id
            if purpose == "device_fence": check(receipt_id == expected_operation_id, "SYNC_PAYLOAD_INVALID")
            previous = db.execute("SELECT token,claim_hash FROM proof_test_receipts WHERE purpose=? AND receipt_id=?", (purpose, receipt_id)).fetchone()
            if previous:
                check(previous == (request["token"], request["claimed_hash"]), "SYNC_PAYLOAD_INVALID")
                return "duplicate"
            if purpose == "device_fence":
                check(data["device_id"] == row[1] and data["previous_sync_transport_generation"] == row[3], "SYNC_TRANSPORT_GENERATION_MISMATCH")
                self._apply_recovery(db, data["recovery"], row, ack_to=None)
            elif purpose == "import_range_close":
                reservation = db.execute("SELECT reservation_json,revision,closed FROM proof_test_imports WHERE lineage=?", (data["import_lineage_id"],)).fetchone()
                check(reservation is not None and not reservation[2], "IMPORT_LINEAGE_MISMATCH")
                local = json.loads(reservation[0])
                for key in ("import_lineage_id", "import_batch_id", "source_workspace_id", "source_epoch", "origin_device_id", "origin_sync_transport_generation",
                            "begin_client_sequence", "terminal_client_sequence", "manifest"):
                    check(data[key] == local[key], "IMPORT_LINEAGE_MISMATCH")
                check(data["previous_import_revision"] == reservation[1], "IMPORT_VERSION_CONFLICT")
                if data["origin_device_id"] == row[1]:
                    if data["kind"] == "never_visible_after_transport_fence":
                        check(bool(row[6]) and row[3] == data["resulting_sync_transport_generation"], "SYNC_TRANSPORT_GENERATION_MISMATCH")
                        fence = db.execute("SELECT claim_hash FROM proof_test_receipts WHERE purpose='device_fence' AND receipt_id=?", (data["fence_operation_id"],)).fetchone()
                        check(fence is not None, "SYNC_TRANSPORT_GENERATION_MISMATCH")
                        # Never-visible ranges do not acknowledge unconsumed sequences.
                        self._apply_recovery(db, data["recovery"], row, ack_to=None)
                    else:
                        check(row[3] == data["recovery"]["sync_transport_generation"] and
                            (row[3] == data["origin_sync_transport_generation"] or bool(row[6])), "SYNC_TRANSPORT_GENERATION_MISMATCH")
                        self._apply_recovery(db, data["recovery"], row, ack_to=data["terminal_client_sequence"])
                db.execute("UPDATE proof_test_imports SET revision=?,closed=1 WHERE lineage=?", (data["resulting_import_revision"], data["import_lineage_id"]))
            else:
                # Only a matching owner lease can be released; never modify a
                # later epoch's facts or rewind its already advanced epoch.
                count = db.execute("SELECT COUNT(*) FROM proof_test_guest_lease WHERE source_id=? AND account_id=?", (source_workspace_id, row[0])).fetchone()[0]
                check(count > 0, "IMPORT_LINEAGE_MISMATCH")
                db.execute("DELETE FROM proof_test_guest_lease WHERE source_id=? AND account_id=?", (source_workspace_id, row[0]))
            checkpoint("state_applied")
            db.execute("INSERT INTO proof_test_receipts VALUES(?,?,?,?)", (purpose, receipt_id, request["token"], request["claimed_hash"]))
            checkpoint("receipt_inserted")
            return "accepted"

    @staticmethod
    def _apply_recovery(db, recovery, row, *, ack_to):
        check(recovery["highest_client_sequence"] >= row[4], "SYNC_PAYLOAD_INVALID")
        acknowledged = max(row[5], recovery["client_confirmed_through"], ack_to or 0)
        check(acknowledged <= recovery["highest_client_sequence"], "SYNC_PAYLOAD_INVALID")
        db.execute("UPDATE proof_test_state SET generation=?,highest=?,acknowledged=?,next_sequence=?,exhausted=?,ack_dirty=? WHERE singleton=1",
                   (recovery["sync_transport_generation"], recovery["highest_client_sequence"], acknowledged, recovery["next_client_sequence"],
                    int(recovery["client_sequence_exhausted"]), int(acknowledged > recovery["client_confirmed_through"])))
