"""C0 fixture-preparation checks; these do not certify a sync implementation."""
import hashlib
import unittest

from contract_input import FIXTURES, ROOT, FrozenFixtureInputs, read_json, text_hash


class ContractFixturePreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = FrozenFixtureInputs()

    def test_every_fixture_reference_resolves_with_an_expected_result(self):
        for entry in self.inputs.manifest["cases"]:
            with self.subTest(case=entry["id"]):
                case = self.inputs.case(entry["id"])
                self.assertTrue(entry["rule_anchor"])
                self.assertEqual(entry["id"], case["id"])
                name = entry["input_file"]
                if name == "jcs_boundary_vectors.json":
                    expected = ({"reject": True} if case["expected_error"] else {
                        "canonical_utf8_hex": case["canonical_utf8_hex"], "sha256": case["sha256"]})
                elif name == "target_vectors.json":
                    expected = {"error": case["expected_error"]}
                elif name == "native_v3_anniversary_vectors.json":
                    expected = {"v2_valid": case["v2_valid"], "v3_valid": case["v3_valid"]}
                elif name == "postgres_vectors.json":
                    expected = {"sqlstate": case["sqlstate"]}
                    if "scalar" in case:
                        expected["scalar"] = case["scalar"]
                else:
                    expected = case["expected"]
                self.assertEqual(entry["expected"], expected)

    def test_fixture_manifest_matches_all_four_consumer_locks(self):
        lock = read_json(ROOT / "contracts/sync/sync_v1_revision_lock.json")
        self.assertEqual(text_hash(FIXTURES / "manifest.json"), lock["fixture_manifest_sha256"])
        self.assertEqual(set(lock["consumers"]), {
            "03_cpp_sqlite", "04_cloud_backend", "05_kotlin_android", "06_flutter"})
        for consumer in lock["consumers"].values():
            self.assertEqual(consumer["contract_sha256"], lock["contract_sha256"])
            self.assertEqual(consumer["fixture_manifest_sha256"], lock["fixture_manifest_sha256"])

    def test_fixture_copies_cannot_change_a_retry_or_other_consumer(self):
        identity = "FX-RUN-ack-only-empty-valid"
        first = self.inputs.case(identity)
        original = self.inputs.case(identity)
        first["input"]["cursor"] = "deliberately-invalid-test-cursor"
        first["expected"]["valid"] = False
        self.assertEqual(self.inputs.case(identity), original)
        self.assertIsNone(original["input"]["cursor"])
        self.assertEqual(original["input"]["upload_mutations"], [])
        self.assertEqual(original["input"]["download_limit"], 0)

    def test_unknown_fixture_is_not_synthesized_as_success(self):
        with self.assertRaises(KeyError):
            self.inputs.case("not-a-declared-fixture")

    def test_canonical_expected_bytes_have_the_declared_sha256(self):
        count = 0
        for case in read_json(FIXTURES / "jcs_boundary_vectors.json")["cases"]:
            expected = case
            if "canonical_utf8_hex" in expected:
                count += 1
                self.assertEqual(hashlib.sha256(bytes.fromhex(
                    expected["canonical_utf8_hex"])).hexdigest(), expected["sha256"])
        self.assertGreater(count, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
