"""Build and exercise a disposable no-network APK; never touches the product app.

Only the random package first installed by this invocation can be uninstalled.
No backup transport is invoked and no device-wide setting is changed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
import xml.etree.ElementTree as ET

from build_android_key_contract import derive, BASE, DEVICE

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROBE = HERE / "android_key_probe"


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--cipher-scratch", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, default=Path("A:/Android/AndroidStudio/jbr"))
    parser.add_argument("--ndk", type=Path, default=Path("A:/Android/sdk/ndk/28.2.13676358"))
    parser.add_argument("--sdk", type=Path, default=Path("A:/Android/sdk"))
    parser.add_argument("--build-only", action="store_true", help="verify APK assembly without installing a package")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report_path = args.report or HERE / ("android_key_build_result.json" if args.build_only else "android_key_spike_result.json")
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-android-keystore-"))
    package = "com.excellentcalendar.contractspike.sync.s" + uuid.uuid4().hex[:16]
    component = package + "/com.excellentcalendar.contractspike.SyncStorageInstrumentation"
    env = {**os.environ, "JAVA_HOME": str(args.jdk)}
    sdk_bin = args.sdk / "build-tools/36.0.0"
    adb = [args.sdk / "platform-tools/adb.exe", "-s", args.serial]
    def run(command, *, input=None, binary=False, timeout=180):
        result = subprocess.run([str(item) for item in command], env=env, input=input, capture_output=True,
            **({} if binary else {"encoding": "utf-8", "errors": "replace"}), timeout=timeout)
        if result.returncode:
            message = (result.stdout + result.stderr).decode("utf-8", errors="replace") if binary else result.stdout + result.stderr
            raise RuntimeError(Path(str(command[0])).name + " failed: " + message[-1800:])
        return result.stdout if binary else result.stdout.strip()
    report = {"spike_version": 1, "passed": False, "scope": "disposable Android APK Keystore/JNI/native SQLCipher and packaged backup configuration",
        "product_package_touched": False, "production_manifest_activated": False, "full_v6_account_migration_verified": False,
        "actual_cloud_backup_or_restore_executed": False, "actual_device_to_device_transfer_executed": False,
        "api23_os_executed": False, "api24_os_executed": False, "android_x86_os_executed": False,
        "source_sha256": {}, "builds": {}, "consumers": {}, "errors": [], "cleanup_errors": []}
    try:
        from build_sync_domain_contracts import yaml
        for path, expected in derive().items():
            text = path.read_text(encoding="utf-8")
            if (yaml.safe_load(text) if path.suffix == ".yaml" else text) != expected: raise ValueError("key/backup definition drift")
        for resource, domains in (("xml/backup_rules.xml", BASE), ("xml-v24/backup_rules.xml", BASE + DEVICE)):
            document = ET.parse(PROBE / "res" / resource).getroot()
            if document.tag != "full-backup-content" or [(row.tag, row.attrib) for row in document] != [("exclude", {"domain": value, "path": "."}) for value in domains]:
                raise ValueError("legacy backup domain coverage")
        document = ET.parse(PROBE / "res/xml/data_extraction_rules.xml").getroot()
        if [row.tag for row in document] != ["cloud-backup", "device-transfer"]: raise ValueError("modern backup branches")
        for branch in document:
            if [(row.tag, row.attrib) for row in branch] != [("exclude", {"domain": value, "path": "."}) for value in BASE + DEVICE]: raise ValueError("modern backup domains")
        report["backup_resource_matrix"] = {"api23_domains": len(BASE), "api24_domains": len(BASE + DEVICE), "api31_cloud_domains": 9, "api31_transfer_domains": 9}
        clang = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/clang++.exe"
        libraries = {}
        for abi, triple in (("arm64-v8a", "aarch64-linux-android23"), ("armeabi-v7a", "armv7a-linux-androideabi23"), ("x86_64", "x86_64-linux-android23")):
            build = args.cipher_scratch / ("build-" + abi)
            if not (build / "libsync_spike_sqlcipher.a").is_file() or not (build / "libsync_spike_ltc.a").is_file(): raise ValueError("pinned cipher build absent")
            library = scratch / abi / "libsync_keystore.so"; library.parent.mkdir()
            run([clang, "--target=" + triple, "-std=c++17", "-O2", "-fPIC", "-shared", "-static-libstdc++", "-Wl,-z,max-page-size=16384",
                 "-I", build / "generated_include", PROBE / "keystore_cipher_jni.cpp", build / "libsync_spike_sqlcipher.a", build / "libsync_spike_ltc.a", "-o", library])
            libraries[abi] = library
            report["builds"][abi] = {"jni_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
                "sqlcipher_archive_sha256": hashlib.sha256((build / "libsync_spike_sqlcipher.a").read_bytes()).hexdigest(),
                "ltc_archive_sha256": hashlib.sha256((build / "libsync_spike_ltc.a").read_bytes()).hexdigest()}
        classes = scratch / "classes"; classes.mkdir()
        android_jar = args.sdk / "platforms/android-36/android.jar"
        run([args.jdk / "bin/javac.exe", "-encoding", "UTF-8", "-source", "8", "-target", "8", "-Xlint:-options", "-cp", android_jar, "-d", classes, PROBE / "SyncStorageInstrumentation.java"])
        jar = scratch / "probe.jar"; run([args.jdk / "bin/jar.exe", "--create", "--file", jar, "-C", classes, "."])
        dex_dir = scratch / "dex"; dex_dir.mkdir()
        run([sdk_bin / "d8.bat", "--min-api", "23", "--lib", android_jar, "--output", dex_dir, jar])
        resources = scratch / "resources.zip"; run([sdk_bin / "aapt2.exe", "compile", "--dir", PROBE / "res", "-o", resources])
        assets = scratch / "assets/licenses"; assets.mkdir(parents=True)
        for license_file in sorted((HERE / "licenses").glob("*.txt")): shutil.copyfile(license_file, assets / license_file.name)
        signing = scratch / "synthetic-apk-signing.p12"
        # Disposable debug-only certificate; no production signer or credential.
        run([args.jdk / "bin/keytool.exe", "-genkeypair", "-keystore", signing, "-storetype", "PKCS12", "-storepass", "isolated-spike-only",
             "-keypass", "isolated-spike-only", "-alias", "spike", "-keyalg", "RSA", "-keysize", "2048", "-validity", "2", "-dname", "CN=Isolated Contract Spike", "-noprompt"])
        apks = {}
        for version in (1, 2):
            manifest = scratch / ("AndroidManifest-" + str(version) + ".xml")
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="' + package + '" android:versionCode="' + str(version) + '" android:versionName="spike-' + str(version) + '">'
                '<uses-sdk android:minSdkVersion="23" android:targetSdkVersion="36"/>'
                '<application android:label="Isolated Sync Contract Test" android:debuggable="true" android:allowBackup="false" android:fullBackupContent="@xml/backup_rules" android:dataExtractionRules="@xml/data_extraction_rules" android:extractNativeLibs="true"/>'
                '<instrumentation android:name="com.excellentcalendar.contractspike.SyncStorageInstrumentation" android:targetPackage="' + package + '" android:functionalTest="true"/></manifest>', encoding="utf-8")
            linked = scratch / ("linked-" + str(version) + ".apk")
            run([sdk_bin / "aapt2.exe", "link", "-o", linked, "--manifest", manifest, "-I", android_jar, "-A", assets.parent, resources])
            with zipfile.ZipFile(linked, "a", compression=zipfile.ZIP_DEFLATED) as apk:
                apk.write(dex_dir / "classes.dex", "classes.dex")
                for abi, library in libraries.items(): apk.write(library, "lib/" + abi + "/libsync_keystore.so")
            aligned = scratch / ("aligned-" + str(version) + ".apk")
            run([sdk_bin / "zipalign.exe", "-P", "16", "-f", "4", linked, aligned])
            signed = scratch / ("keystore-spike-" + str(version) + ".apk")
            run([sdk_bin / "apksigner.bat", "sign", "--ks", signing, "--ks-pass", "pass:isolated-spike-only", "--out", signed, aligned])
            run([sdk_bin / "apksigner.bat", "verify", "--verbose", signed])
            badging = run([sdk_bin / "aapt2.exe", "dump", "badging", signed])
            if "package: name='" + package + "'" not in badging or "uses-permission:" in badging: raise ValueError("packaged manifest identity/permissions differ")
            manifest_tree = run([sdk_bin / "aapt2.exe", "dump", "xmltree", "--file", "AndroidManifest.xml", signed])
            for field in ("allowBackup", "fullBackupContent", "dataExtractionRules"):
                if field not in manifest_tree: raise ValueError("missing packaged backup attribute")
            if not re.search(r"allowBackup.*(?:false|0x0|0x00000000)", manifest_tree): raise ValueError("packaged allowBackup is not false")
            compiled_resources = {}
            for resource in ("res/xml/backup_rules.xml", "res/xml-v24/backup_rules.xml", "res/xml/data_extraction_rules.xml"):
                tree = run([sdk_bin / "aapt2.exe", "dump", "xmltree", "--file", resource, signed])
                if "exclude" not in tree or 'path' not in tree: raise ValueError("backup XML missing from final APK")
                compiled_resources[resource] = hashlib.sha256(tree.encode()).hexdigest()
            report["builds"]["apk_" + str(version)] = {"sha256": hashlib.sha256(signed.read_bytes()).hexdigest(), "compiled_backup_resources": compiled_resources,
                "manifest_sha256": hashlib.sha256(manifest_tree.encode()).hexdigest(), "no_internet_permission": True, "allow_backup": False}
            apks[version] = signed
        from build_android_abi_apks import build as build_abi_apks
        build_abi_apks(scratch, report, args.sdk, args.jdk)
        report["device"] = {"abi": run(adb + ["shell", "getprop", "ro.product.cpu.abilist"]), "sdk": run(adb + ["shell", "getprop", "ro.build.version.sdk"]),
                             "model": run(adb + ["shell", "getprop", "ro.product.model"])}
        report["scope"] = "build-only APK assembly; device lifecycle is recorded by the resumable phase runner"
        report["build_only"] = True
        report["passed"] = True
    except Exception as error:
        report["errors"].append(str(error))
    finally:
        # APKs/test signing material stay only in this isolated local temp path.
        report["scratch"] = str(scratch)
        sources = [Path(__file__), HERE / "build_android_abi_apks.py", HERE / "build_android_key_contract.py", *sorted(PROBE.rglob("*")),
                   ROOT / "contracts/storage/account_key_wrapping_v1.yaml", ROOT / "contracts/workspace/android_backup_policy_v1.yaml",
                   ROOT / "contracts/sync/proof/proof_key_revocation_record.schema.json", *sorted((HERE / "licenses").glob("*.txt"))]
        report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in sources if path.is_file()}
        report["pinned_cipher_evidence_sha256"] = hashlib.sha256((HERE / "cipher_source_spike_result.json").read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if report["passed"] and not args.build_only:
        checkpoint = {"package": package, "serial": args.serial, "consumers": {}}
        (scratch / "device_phase_checkpoint.json").write_text(json.dumps(checkpoint, indent=2) + "\n", encoding="utf-8")
        return subprocess.run([sys.executable, "-X", "utf8", str(HERE / "resume_android_key_spike.py"),
            "--serial", args.serial, "--scratch", str(scratch), "--sdk", str(args.sdk), "--report", str(report_path)], check=False).returncode
    print(json.dumps({"passed": report["passed"], "consumers": list(report["consumers"]), "errors": report["errors"], "cleanup_errors": report["cleanup_errors"], "scratch": str(scratch)}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
