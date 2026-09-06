"""Isolated key-wrap/backup definitions. No product Android Manifest edits."""
import argparse
from pathlib import Path
from build_sync_domain_contracts import CONTRACTS, yaml

HERE = Path(__file__).resolve().parent
BASE = ["root", "file", "database", "sharedpref", "external"]
DEVICE = ["device_root", "device_file", "device_database", "device_sharedpref"]


def xml(root, domains, indent="  "):
    return "<" + root + ">\n" + "".join(indent + '<exclude domain="' + value + '" path="."/>\n' for value in domains) + "</" + root + ">\n"


def derive():
    profile = {"version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/4.2,8.3,10",
        "dek": {"algorithm": "SQLCipher binary database key", "bytes": 32, "generation": "OS-backed cryptographic random per account workspace", "json_allowed": False},
        "kek": {"provider": "AndroidKeyStore", "algorithm": "AES", "bits": 256, "mode": "GCM", "padding": "NoPadding", "tag_bits": 128,
            "purposes": ["encrypt", "decrypt"], "randomized_encryption_required": True, "user_authentication_required": False,
            "user_auth_reason": "background sync/reminders must not depend on a per-use unlock prompt; session and workspace lifecycle remain independently enforced",
            "exportable": False, "hardware_security_level": "record actual KeyInfo; do not claim TEE/StrongBox without evidence", "minimum_android_api": 23},
        "binary_wrapper": {"bytes": 136, "byte_order": "big_endian", "uuid_encoding": "16 raw bytes, UUIDv4 RFC variant, no text/JSON encoding",
            "fields": [
                {"name": "magic", "offset": 0, "bytes": 8, "constant_ascii": "ECSKEY01"},
                {"name": "installation_id", "offset": 8, "bytes": 16}, {"name": "workspace_id", "offset": 24, "bytes": 16},
                {"name": "account_id", "offset": 40, "bytes": 16}, {"name": "storage_format_version", "offset": 56, "bytes": 4, "constant": 6},
                {"name": "wrapping_instance_id", "offset": 60, "bytes": 16}, {"name": "nonce", "offset": 76, "bytes": 12},
                {"name": "ciphertext_and_tag", "offset": 88, "bytes": 48}],
            "aad": "exact bytes [0,76), reconstructed with expected authenticated installation/workspace/account/storage binding and the validated wrapping UUID",
            "nonce": "obtained from initialized AndroidKeyStore Cipher; never caller selected or reused", "unknown_or_truncated_record": "reject without fallback"},
        "durability": {"location": "Kotlin private noBackupFilesDir, independently excluded from all backup/transfer domains",
            "write": "AtomicFile finishWrite including sync before a corresponding account open is authorized; failure leaves prior record or no committed open seed",
            "raw_material": "never in JSON, event, logs, ordinary cache, SQLite metadata or temp files; clear caller/JNI copies and close SQLCipher handles",
            "crypto_destroy": "durable lifecycle tombstone/fence policy first where required; delete this workspace's Keystore alias and wrapped material; ciphertext files may be removed later; key absence never triggers key recreation for that database",
            "reinstall": "fresh installation UUID and new registration; restored old wrapper/account files remain locked and cannot reuse a recreated alias",
            "retention": "retain_30d keeps the same wrapper/key only until the separately authenticated retention deadline; this format does not grant retention"},
        "evidence": {"runner": "spikes/sync_v1/run_android_key_spike.py", "report": "spikes/sync_v1/android_key_spike_result.json",
            "scope": "isolated APK plus native SQLCipher feasibility; production owners and final product APK are not implemented"},
        "primary_sources": ["https://developer.android.com/privacy-and-security/keystore", "https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder"]}
    backup = {"version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/4.1,4.2",
        "manifest": {"allowBackup": False, "fullBackupContent": "@xml/backup_rules", "dataExtractionRules": "@xml/data_extraction_rules"},
        "legacy_api23": {"excluded_domains": BASE, "path": "."}, "legacy_api24_to30": {"excluded_domains": BASE + DEVICE, "path": "."},
        "api31_plus": {"cloud_backup": {"excluded_domains": BASE + DEVICE, "path": "."}, "device_transfer": {"excluded_domains": BASE + DEVICE, "path": "."}},
        "rules": {"guest_and_account": "both excluded, including files-based DB/WAL/SHM and legacy JSON; do not rely only on database domain",
            "protected_material": "all registry, wrapped keys, Broker tokens, leases/seeds/journals, boot/retention/proof-revocation state and caches excluded",
            "api23_compatibility": "device-protected domains are introduced through resource qualifier xml-v24, not supplied to the API23 parser",
            "default_include": False, "direct_transfer_exception": False, "manufacturer_d2d": "verify actual device behavior separately; allowBackup false alone is insufficient"},
        "primary_sources": ["https://developer.android.com/identity/data/autobackup"],
        "product_manifest_activated": False}
    root = HERE / "android_key_probe/res"
    return {CONTRACTS / "storage/account_key_wrapping_v1.yaml": profile,
        CONTRACTS / "workspace/android_backup_policy_v1.yaml": backup,
        root / "xml/backup_rules.xml": xml("full-backup-content", BASE),
        root / "xml-v24/backup_rules.xml": xml("full-backup-content", BASE + DEVICE),
        root / "xml/data_extraction_rules.xml": "<data-extraction-rules>\n" + "\n".join("  " + line for section in ("cloud-backup", "device-transfer") for line in xml(section, BASE + DEVICE).rstrip().splitlines()) + "\n</data-extraction-rules>\n"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__); parser.add_argument("--check", action="store_true"); args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            actual = path.read_text(encoding="utf-8")
            if (yaml.safe_load(actual) if path.suffix == ".yaml" else actual) != value: raise ValueError("Android key/backup definition drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(value, allow_unicode=True, sort_keys=False) if path.suffix == ".yaml" else value, encoding="utf-8")
    print("Planned binary wrapper and isolated APK backup resources verified")
