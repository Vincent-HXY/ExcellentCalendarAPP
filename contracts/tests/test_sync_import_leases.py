"""Actual guest/account transactions, exclusive owner and recoverable network gate."""
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "contracts/spikes/sync_v1"))
from bootstrap_reference import BootstrapServer, page_set_digest
from build_bootstrap_fixtures import KEY, KEY_ID, NOW
from build_owned_graph_fixtures import derive
from import_lease_reference import AccountImportJournal, GuestImportSource

A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
S = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
D = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
W = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
CRASH_POINTS = []


class ImportLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="excellent-calendar-import-lease-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.records = derive()["cases"][2]["input"]["seed"]
        self.guest, self.account = self.pair("initial")

    def account_store(self, name, *, owner=A):
        account = AccountImportJournal(self.path / (name + ".db"), account_id=owner, device_id=D, installation_key=bytes(range(32)))
        server = BootstrapServer(self.path / (name + "-bootstrap.db"), account_id=owner, device_id=D, keys={KEY_ID: KEY}, key_id=KEY_ID)
        server.seed([], highest=0, confirmed=0, upper_bound=0)
        page = server.begin(now=NOW)
        account.begin(page)
        account.stage(page, request_cursor=None)
        account.finalize(expected_page_set_digest=page_set_digest([page]), final_cursor=page["terminal_sync_cursor"])
        return account

    def pair(self, name):
        guest = GuestImportSource(self.path / (name + "-guest.db"), workspace_id=S)
        guest.seed(self.records)
        return guest, self.account_store(name + "-account")

    def test_preview_has_no_lease_or_account_writes_then_commit_freezes_exact_once(self):
        before = self.account.snapshot()
        preview = self.guest.preview(self.account, target_workspace_id=W)
        self.assertEqual(self.account.snapshot(), before)
        self.assertFalse(self.guest.snapshot()["guest_import_source_leases"])
        receipt = self.guest.commit(self.account, preview["preview_token"])
        self.assertEqual(receipt["manifest"], preview["manifest"])
        self.assertEqual(receipt["batch_id"], preview["proposed_import_batch_id"])
        self.assertEqual((receipt["begin_client_sequence"], receipt["terminal_client_sequence"]), (1, 5))
        self.assertEqual(len(self.account.snapshot()["local_import_outbox"]), 5)
        self.assertFalse(self.account.snapshot()["live"])
        self.assertFalse(self.account.snapshot()["presentation"])
        account, guest = self.account.snapshot(), self.guest.snapshot()
        self.assertEqual(self.guest.commit(self.account, preview["preview_token"]), receipt)
        self.assertEqual((self.account.snapshot(), self.guest.snapshot()), (account, guest))
        self.assertEqual(len(self.account.prepare_import(self.guest, receipt["operation_id"])), 5)
        self.assertNotIn(A, json.dumps(self.guest.snapshot(), ensure_ascii=False))

    def test_same_value_guest_version_change_invalidates_the_old_preview(self):
        preview = self.guest.preview(self.account, target_workspace_id=W)
        self.guest.write(copy.deepcopy(self.records[0]))
        before_guest, before_account = self.guest.snapshot(), self.account.snapshot()
        with self.assertRaisesRegex(ValueError, "IMPORT_REFERENCE_INVALID"):
            self.guest.commit(self.account, preview["preview_token"])
        self.assertEqual((self.guest.snapshot(), self.account.snapshot()), (before_guest, before_account))
        fresh = self.guest.preview(self.account, target_workspace_id=W)
        self.assertNotEqual(fresh["manifest"]["source_snapshot_hash"], preview["manifest"]["source_snapshot_hash"])

    def test_two_real_account_writers_cannot_both_own_the_same_guest_source(self):
        other = self.account_store("second-account", owner=B)
        left = self.guest.preview(self.account, target_workspace_id=W)
        right = self.guest.preview(other, target_workspace_id=W)

        def commit(account, preview):
            try:
                return self.guest.commit(account, preview["preview_token"])
            except ValueError as error:
                return str(error)

        with ThreadPoolExecutor(max_workers=2) as pool:
            one = pool.submit(commit, self.account, left)
            two = pool.submit(commit, other, right)
            results = [one.result(), two.result()]
        self.assertEqual(sum(isinstance(row, dict) for row in results), 1)
        self.assertIn("IMPORT_SOURCE_OWNED", results)
        self.assertEqual(sorted(len(account.snapshot()["local_import_outbox"]) for account in (self.account, other)), [0, 5])
        self.assertEqual(len(self.guest.snapshot()["guest_import_source_leases"]), 1)
        self.assertEqual(len(self.guest.snapshot()["guest_import_source_facts"]), 3)

    def test_actual_process_death_recovers_each_committed_phase_without_early_network(self):
        points = [("import_guest_reserved", False, False), ("import_guest_reserved_committed", True, False),
            ("import_account_outbox", True, False), ("import_account_operation_receipt", True, False), ("import_account_allocator", True, False),
            ("import_account_receipt_committed", True, True), ("import_guest_active", True, True)]
        for index, (point, reserved, received) in enumerate(points):
            guest, account = self.pair("kill-" + str(index))
            preview = guest.preview(account, target_workspace_id=W)
            original = guest.snapshot()["guest_import_source_facts"]
            path = self.path / "kill.json"
            path.write_text(json.dumps({"guest": str(guest.path), "account": str(account.path), "source": S, "account_id": A,
                "device": D, "token": preview["preview_token"], "point": point}), encoding="utf8")
            process = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "contracts/spikes/sync_v1/import_lease_crash_probe.py"), str(path)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(process.returncode, 79, process.stdout + process.stderr)
            self.assertIn("KILL_POINT_REACHED:" + point, process.stdout)
            guest = GuestImportSource(guest.path, workspace_id=S)
            account = AccountImportJournal(account.path, account_id=A, device_id=D, installation_key=bytes(range(32)))
            self.assertEqual(bool(guest.snapshot()["guest_import_source_leases"]), reserved, point)
            self.assertEqual(bool(account.snapshot()["local_import_operations"]), received, point)
            self.assertEqual(guest.snapshot()["guest_import_source_facts"], original)
            self.assertFalse(account.snapshot()["live"])
            operation = guest.snapshot()["guest_import_previews"][0][1]
            with self.assertRaises(ValueError):
                account.prepare_import(guest, operation)
            self.assertFalse(any(row[4] for row in account.snapshot()["local_import_outbox"]))
            if reserved:
                self.assertEqual(guest.recover_reserved(account), "active" if received else "released_never_active")
            receipt = guest.commit(account, preview["preview_token"])
            self.assertEqual(len(account.prepare_import(guest, receipt["operation_id"])), 5)
            self.assertEqual(json.loads(account.snapshot()["state"][0][0])["next_sequence"], 6)
            self.assertEqual(len(account.snapshot()["local_import_outbox"]), 5)
            CRASH_POINTS.append(point)


if __name__ == "__main__":
    unittest.main()
