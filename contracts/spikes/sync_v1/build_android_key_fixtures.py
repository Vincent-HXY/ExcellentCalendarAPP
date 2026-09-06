"""Index the fixed assertions actually executed by the isolated Android APK."""
import json
from pathlib import Path

PREFIX = ["manifest-backup-disabled", "manifest-no-internet-permission"]
PHASES = {
    "initial": PREFIX + ["fresh-no-keystore-alias", "keystore-key-not-exportable", "keystore-aes256-gcm-background-policy",
        "randomized-wrap-no-iv-reuse", "wrapped-binary-layout-136", "unwrap-exact-binary-key", "reject-account-aad",
        "reject-workspace-aad", "reject-installation-aad", "reject-schema-aad", "reject-record-tamper-0", "reject-record-tamper-60",
        "reject-record-tamper-76", "reject-record-tamper-88", "reject-record-tamper-135", "reject-short-record", "jni-key-length-before-create",
        "keystore-jni-sqlcipher-20000-rows", "sqlcipher-wrong-key-rejected", "sqlcipher-wrong-owner-rejected",
        "sqlcipher-wrong-workspace-rejected", "revocation-record-initial"],
    "process_restart": PREFIX + ["reopen-keystore-jni-encrypted-rows", "revocation-survives-old-empty-trust"],
    "apk_upgrade": PREFIX + ["reopen-keystore-jni-encrypted-rows", "revocation-survives-old-empty-trust"],
    "crypto_destroy": PREFIX + ["crypto-destroy-alias-absent", "ciphertext-files-may-remain", "leftover-wrapper-cannot-recover-key"],
    "reinstall": PREFIX + ["reinstall-changes-installation", "reinstall-has-no-old-keystore-key", "reinstall-has-no-old-account-or-wrapper"],
    "restored_ciphertext": PREFIX + ["restored-wrapper-installation-rejected", "recreated-alias-cannot-decrypt-old-wrapper"],
}


def derive():
    return {"fixture_version": 1, "scope": "actual isolated Android Keystore/JNI lifecycle; synthetic ciphertext restore only",
        "cases": [{"id": "FX-RETENTION-NOTIFY-android-key-" + phase + "-" + name,
                   "rule_anchor": "cloud-sync-02/4.2,8.3,8.4", "input": {"phase": phase, "assertion": name}, "expected": {"passed": True}}
                  for phase, names in PHASES.items() for name in names]}


if __name__ == "__main__":
    path = Path(__file__).resolve().parents[2] / "fixtures/sync/v1/android_key_vectors.json"
    path.write_text(json.dumps(derive(), indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(derive()["cases"])}))
