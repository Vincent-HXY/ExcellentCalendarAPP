"""Produce signed, single-ABI variants of an already built isolated test APK."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent


def build(scratch, report, sdk, jdk):
    def run(command):
        result = subprocess.run([str(item) for item in command], capture_output=True, encoding="utf-8", errors="replace",
            timeout=60, env={**os.environ, "JAVA_HOME": str(jdk)})
        if result.returncode:
            raise ValueError("ABI APK build failed: " + result.stdout[-1000:] + result.stderr[-1000:])
    for version in (1, 2):
        for abi in ("arm64-v8a", "armeabi-v7a"):
            unsigned = scratch / (f"linked-{version}-{abi}.apk")
            original_path = scratch / f"linked-{version}.apk"
            with zipfile.ZipFile(original_path) as original, original_path.open("rb") as raw, zipfile.ZipFile(unsigned, "w", compression=zipfile.ZIP_DEFLATED) as target:
                for entry in original.infolist():
                    if entry.filename.startswith("lib/") and not entry.filename.startswith("lib/" + abi + "/"):
                        continue
                    # Windows aapt2 can encode a backslash in the local asset
                    # header while normalizing its central-directory name.
                    # Validate that this is the only difference, then use the
                    # original ZIP CRC/decompressor and emit consistent names.
                    raw.seek(entry.header_offset)
                    header = raw.read(30)
                    if header[:4] != b"PK\x03\x04":
                        raise ValueError("invalid local ZIP header")
                    name_length = struct.unpack_from("<H", header, 26)[0]
                    local_name = raw.read(name_length).decode("utf-8" if entry.flag_bits & 0x800 else "cp437")
                    if local_name.replace("\\", "/") != entry.filename:
                        raise ValueError("unexpected ZIP filename divergence")
                    adjusted = copy.copy(entry)
                    adjusted.orig_filename = local_name
                    # Keep resources.arsc stored, as required by target API 30+;
                    # zipalign below restores its four-byte alignment.
                    target.writestr(entry, original.read(adjusted))
            aligned = scratch / f"aligned-{version}-{abi}.apk"
            signed = scratch / f"keystore-spike-{version}-{abi}.apk"
            run([sdk / "build-tools/36.0.0/zipalign.exe", "-P", "16", "-f", "4", unsigned, aligned])
            run([sdk / "build-tools/36.0.0/apksigner.bat", "sign", "--ks", scratch / "synthetic-apk-signing.p12", "--ks-pass", "pass:isolated-spike-only", "--out", signed, aligned])
            run([sdk / "build-tools/36.0.0/apksigner.bat", "verify", "--verbose", signed])
            with zipfile.ZipFile(signed) as apk:
                libraries = [name for name in apk.namelist() if name.startswith("lib/")]
                if libraries != [f"lib/{abi}/libsync_keystore.so"]:
                    raise ValueError("single ABI packaging failed")
                for license_file in (HERE / "licenses").glob("*.txt"):
                    if apk.read("assets/licenses/" + license_file.name) != license_file.read_bytes():
                        raise ValueError("packaged license content differs")
            evidence = copy.deepcopy(report["builds"]["apk_" + str(version)])
            evidence.update(sha256=hashlib.sha256(signed.read_bytes()).hexdigest(), packaged_abis=[abi],
                packaged_license_contents_verified=True, derived_from_apk_sha256=report["builds"]["apk_" + str(version)]["sha256"])
            report["builds"][f"apk_{version}_{abi}"] = evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--scratch", type=Path, required=True)
    args = parser.parse_args()
    path = HERE / "android_key_spike_result.json"
    report = json.loads(path.read_text(encoding="utf-8"))
    if args.scratch.resolve() != Path(report["scratch"]).resolve():
        raise ValueError("scratch is not the recorded test build")
    build(args.scratch, report, Path("A:/Android/sdk"), Path("A:/Android/AndroidStudio/jbr"))
    report["source_sha256"]["contracts/spikes/sync_v1/build_android_abi_apks.py"] = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Verified single-ABI APKs, signatures and packaged license contents.")
