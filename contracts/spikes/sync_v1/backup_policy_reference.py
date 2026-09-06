"""Read-only Contract policy interpreter; never invokes an Android backup transport."""
from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ET

from domain_reference import check
from identity_reference import canonical_uuid

RESOURCES = Path(__file__).resolve().parent / "android_key_probe/res"
BASE = {"root", "file", "database", "sharedpref", "external"}
DEVICE = {"device_root", "device_file", "device_database", "device_sharedpref"}


def exclusions(api_level, transport, *, resources=RESOURCES):
    check(type(api_level) is int and api_level >= 23 and transport in {"cloud", "device_transfer"}, "SYNC_PAYLOAD_INVALID")
    if api_level >= 31:
        root = ET.parse(resources / "xml/data_extraction_rules.xml").getroot()
        check(root.tag == "data-extraction-rules", "SYNC_PAYLOAD_INVALID")
        branch = root.find("cloud-backup" if transport == "cloud" else "device-transfer")
        check(branch is not None, "SYNC_PAYLOAD_INVALID")
    else:
        branch = ET.parse(resources / ("xml-v24" if api_level >= 24 else "xml") / "backup_rules.xml").getroot()
        check(branch.tag == "full-backup-content", "SYNC_PAYLOAD_INVALID")
    supported = BASE | (DEVICE if api_level >= 24 else set())
    rows = list(branch)
    check(all(row.tag == "exclude" and set(row.attrib) == {"domain", "path"} and row.attrib["domain"] in supported for row in rows), "SYNC_PAYLOAD_INVALID")
    check(len({(row.attrib["domain"], row.attrib["path"]) for row in rows}) == len(rows), "SYNC_PAYLOAD_INVALID")
    return [(row.attrib["domain"], row.attrib["path"]) for row in rows]


def export_projection(files, *, api_level, transport, resources=RESOURCES):
    """Evaluate explicit XML even when allowBackup=false, including OEM D2D fallback."""
    rules = exclusions(api_level, transport, resources=resources)
    supported = BASE | (DEVICE if api_level >= 24 else set())
    exported = []
    for item in files:
        check(set(item) == {"id", "category", "domain", "path"} and item["domain"] in supported, "SYNC_PAYLOAD_INVALID")
        relative = PurePosixPath(item["path"])
        check(not relative.is_absolute() and ".." not in relative.parts and "\\" not in item["path"] and bool(relative.parts), "SYNC_PAYLOAD_INVALID")
        if not any(domain == item["domain"] and (path == "." or relative == PurePosixPath(path) or PurePosixPath(path) in relative.parents) for domain, path in rules):
            exported.append(item["id"])
    return exported


def restore_decision(restored_files, *, previous_installation_id, previous_guest_workspace_id,
                     new_installation_id, new_guest_workspace_id, direct_transfer_authorized=False):
    """A policy decision only: excluded bytes never become an active restored workspace."""
    for value in (previous_installation_id, previous_guest_workspace_id, new_installation_id, new_guest_workspace_id): canonical_uuid(value, 4)
    check(not direct_transfer_authorized, "WORKSPACE_LOCKED")
    check(len({previous_installation_id, previous_guest_workspace_id, new_installation_id, new_guest_workspace_id}) == 4, "WORKSPACE_LOCKED")
    return {"installation_id": new_installation_id, "guest_workspace_id": new_guest_workspace_id, "guest_source_epoch": 0,
        "active_restored_entries": [], "quarantined_entries": sorted(item["id"] for item in restored_files),
        "restored_account_open_allowed": False, "restored_broker_session_allowed": False,
        "restored_source_lease_allowed": False, "restored_lineage_allowed": False, "guest_rehome_performed": False}
