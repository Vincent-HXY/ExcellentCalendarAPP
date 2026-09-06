"""Private record/TTL Contract oracle, with actual JCE AEAD and atomic files.

The caller represents the trusted lifecycle owner. Recording a final receipt is
not evidence of Android key destruction; that OS primitive has separate evidence.
"""
import json
import os
from pathlib import Path
import subprocess

from domain_reference import check, validate_schema
from protocol_reference import canonical, digest

JDK = Path("A:/Android/AndroidStudio/jbr/bin")


class ProtectedRecords:
    def __init__(self, path, *, classes, key, installation_id, account_id, workspace_id):
        self.path, self.classes, self.key = Path(path), classes, key
        self.identity = dict(installation_id=installation_id, account_id=account_id, workspace_id=workspace_id)
        self.path.mkdir(parents=True, exist_ok=True)

    def crypt(self, mode, kind, raw):
        aad = canonical({"record_kind": kind, "schema_version": 1, **self.identity})
        process = subprocess.run([str(JDK / "java.exe"), "-cp", str(self.classes), "PrivateRecordProbe", mode,
            self.key.hex(), aad.hex(), raw.hex()], capture_output=True, text=True, timeout=20)
        check(process.returncode == 0, "PRIVATE_RECORD_AUTHENTICATION_FAILED")
        return bytes.fromhex(process.stdout)

    def save(self, kind, value):
        schema = {"crypto_destroy_final": "workspace/private/crypto_destroy_final_receipt.schema.json",
                  "remote_device_snapshot": "device/private/remote_snapshot_cache.schema.json"}[kind]
        validate_schema(schema, value)
        check(all(value[key] == self.identity[key] for key in ("account_id", "workspace_id")), "WORKSPACE_BINDING_MISMATCH")
        identifier = digest(value)
        target = self.path / (identifier + ".record")
        if target.exists():
            check(self.load(kind, identifier) == value, "PRIVATE_RECORD_AUTHENTICATION_FAILED")
            return identifier
        encrypted = self.crypt("seal", kind, canonical(value))
        temporary = target.with_suffix(".pending")
        with temporary.open("xb") as output:
            output.write(encrypted)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, target)
        return identifier

    def load(self, kind, identifier):
        check(len(identifier) == 64 and all(c in "0123456789abcdef" for c in identifier), "PRIVATE_RECORD_AUTHENTICATION_FAILED")
        target = self.path / (identifier + ".record")
        check(target.is_file(), "PRIVATE_RECORD_AUTHENTICATION_FAILED")
        value = json.loads(self.crypt("open", kind, target.read_bytes()))
        check(digest(value) == identifier, "PRIVATE_RECORD_AUTHENTICATION_FAILED")
        return value


def diagnostic_expired(journal, *, boot_id, elapsed_ms, share_completed=False):
    validate_schema("sync/private/diagnostic_export_journal.schema.json", journal)
    return share_completed or boot_id != journal["boot_id"] or elapsed_ms < journal["created_elapsed_ms"] or \
        elapsed_ms - journal["created_elapsed_ms"] >= journal["ttl_seconds"] * 1000


def cached_remote_snapshot(records, identifier, *, active_account_id, active_workspace_id, device_id):
    check(active_account_id == records.identity["account_id"] and active_workspace_id == records.identity["workspace_id"], "WORKSPACE_BINDING_MISMATCH")
    if identifier is None:
        return {"remote_snapshot_state": "unavailable", "remote_snapshot_at": None, "devices": []}
    value = records.load("remote_device_snapshot", identifier)
    validate_schema("device/private/remote_snapshot_cache.schema.json", value)
    check(value["device_id"] == device_id, "WORKSPACE_BINDING_MISMATCH")
    return {"remote_snapshot_state": "stale", "remote_snapshot_at": value["captured_at"], "devices": value["snapshot"]["devices"]}
