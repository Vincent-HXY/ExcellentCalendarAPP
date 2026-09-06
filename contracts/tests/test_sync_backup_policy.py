"""Backup policy branches, missing exclusion regressions and two-destination restore isolation."""
import copy
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

from backup_policy_reference import RESOURCES, exclusions, export_projection, restore_decision
from build_backup_policy_fixtures import derive, files, OLD_INSTALL, OLD_GUEST, CATEGORIES

OBSERVED = []


def execute_case(case):
    request = copy.deepcopy(case["input"])
    operation = request.pop("operation")
    if operation == "export_projection":
        exported = export_projection(**request)
        guests = {row["id"] for row in request["files"] if row["category"].startswith("guest")}
        return {"exported_entries": exported, "guest_entries_exported": len(guests & set(exported))}
    destinations = request.pop("destinations")
    outputs = [restore_decision(**request, **destination) for destination in destinations]
    return {"distinct_new_installations": len({row["installation_id"] for row in outputs}) == 2,
        "distinct_new_guests": len({row["guest_workspace_id"] for row in outputs}) == 2,
        "active_restored_entries": sum(len(row["active_restored_entries"]) for row in outputs),
        "restored_account_or_broker_or_lease_or_lineage_allowed": any(row[field] for row in outputs for field in
            ("restored_account_open_allowed", "restored_broker_session_allowed", "restored_source_lease_allowed", "restored_lineage_allowed")),
        "guest_rehome_performed": any(row["guest_rehome_performed"] for row in outputs)}


class BackupPolicyTests(unittest.TestCase):
    def test_all_fixed_export_and_two_destination_cases(self):
        for case in derive()["cases"]:
            with self.subTest(case=case["id"]):
                actual = execute_case(case)
                OBSERVED.append({"id": case["id"], "actual": actual, "passed": actual == case["expected"]})
                self.assertEqual(actual, case["expected"])

    def test_missing_each_api31_domain_would_export_synthetic_data_even_with_manifest_disabled(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw) / "res"; shutil.copytree(RESOURCES, root)
            path = root / "xml/data_extraction_rules.xml"
            original = path.read_bytes()
            for transport, tag in (("cloud", "cloud-backup"), ("device_transfer", "device-transfer")):
                for domain, _ in exclusions(33, transport):
                    tree = ET.fromstring(original)
                    branch = tree.find(tag)
                    branch.remove(next(row for row in branch if row.attrib["domain"] == domain))
                    path.write_bytes(ET.tostring(tree))
                    exported = export_projection(files(33), api_level=33, transport=transport, resources=root)
                    self.assertEqual(set(exported), {row["id"] for row in files(33) if row["domain"] == domain})
                    self.assertTrue(any("guest_db" in name for name in exported))

    def test_api23_parser_gets_no_device_protected_domains(self):
        self.assertEqual(len(exclusions(23, "cloud")), 5)
        self.assertEqual(len(exclusions(24, "cloud")), 9)
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            export_projection([{"id": "wrong", "category": "guest_db", "domain": "device_file", "path": "guest/db"}], api_level=23, transport="cloud")

    def test_old_identity_or_unapproved_guest_rehome_is_refused(self):
        case = derive()["cases"][-1]["input"]
        request = {name: case[name] for name in ("restored_files", "previous_installation_id", "previous_guest_workspace_id")}
        valid = {**request, **case["destinations"][0]}
        for field, value in (("new_installation_id", OLD_INSTALL), ("new_guest_workspace_id", OLD_GUEST), ("direct_transfer_authorized", True)):
            with self.assertRaisesRegex(ValueError, "WORKSPACE_LOCKED"): restore_decision(**{**valid, field: value})
        result = restore_decision(**valid)
        self.assertEqual(len(result["quarantined_entries"]), len(request["restored_files"]))


if __name__ == "__main__": unittest.main()
