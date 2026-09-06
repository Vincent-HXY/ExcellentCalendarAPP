"""Cursor authentication, fixed snapshot boundaries and safe key retirement."""
import copy
import unittest
from pathlib import Path

from build_cursor_fixtures import derive, KEY, KEY_ID, A, D, BOOT
from cursor_reference import CursorCodec, KeyRetirementLedger, encode_claims
from validate_sync_v1 import read_yaml


def run_case(request):
    try:
        codec = CursorCodec({key: bytes.fromhex(value) for key, value in request["keys"].items()})
        if request["action"] == "issue": return "SIGNED\t" + codec.issue(request["claims"])
        codec.validate(request["token"], **request["context"])
        return "VALID"
    except ValueError as error:
        return str(error)


class CursorTests(unittest.TestCase):
    def test_machine_layout_matches_exact_authenticated_bytes(self):
        definition = read_yaml(Path(__file__).resolve().parents[1] / "sync/sync_cursor_protocol.yaml")
        encoding = definition["encoding"]
        self.assertEqual(encoding["byte_order"], "big_endian")
        cursor = 0
        for field in encoding["fields"]:
            self.assertEqual(field["offset"], cursor)
            cursor += field["bytes"]
        self.assertEqual(cursor, encoding["total_bytes"])
        self.assertEqual(len(encode_claims(derive()["claims"]["normal"])), encoding["claims_bytes"])
        self.assertEqual(encoding["total_bytes"] - encoding["claims_bytes"], 32)
        self.assertEqual(encoding["token_characters"], len(CursorCodec({KEY_ID: KEY}).issue(derive()["claims"]["normal"])))
        self.assertEqual(definition["authentication"]["domain_prefix_utf8"], "ExcellentCalendar.SyncCursor.v1\n")
        self.assertEqual(definition["authentication"]["key_bytes"], 32)

    def test_fixed_binary_and_failure_vectors(self):
        for case in derive()["cases"]:
            with self.subTest(case=case["id"]): self.assertEqual(run_case(case["input"]), case["expected"]["output"])

    def test_normal_rotation_keeps_old_authentication_until_all_ranges_and_sessions_expire(self):
        claims = derive()["claims"]
        ledger = KeyRetirementLedger()
        ledger.record(claims["normal"]); ledger.record(claims["bootstrap"])
        ledger.record({**claims["normal"], "account_id": BOOT, "snapshot_upper_bound": 100})
        self.assertFalse(ledger.can_retire(KEY_ID, {A: (3, 11)}, 1800000001))
        watermarks = {A: (3, 11), BOOT: (4, 0)}
        self.assertFalse(ledger.can_retire(KEY_ID, watermarks, 1799999999))
        self.assertTrue(ledger.can_retire(KEY_ID, watermarks, 1800000000))
        self.assertFalse(ledger.can_retire(KEY_ID, {A: (3, 10), BOOT: (4, 0)}, 1800000000))

    def test_fixed_upper_bound_cannot_be_rewritten_when_new_changes_arrive(self):
        claims = derive()["claims"]["normal"]
        codec = CursorCodec({KEY_ID: KEY})
        token = codec.issue(claims)
        newer = {**claims, "snapshot_upper_bound": 11}
        self.assertEqual(codec.authenticate(token)["snapshot_upper_bound"], 10)
        self.assertNotEqual(codec.issue(newer), token)
        with self.assertRaisesRegex(ValueError, "SYNC_CURSOR_INVALID"):
            codec.issue({**claims, "position": 11})


if __name__ == "__main__": unittest.main()
