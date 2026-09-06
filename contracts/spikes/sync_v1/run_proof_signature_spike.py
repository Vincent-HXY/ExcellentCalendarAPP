"""Verify fixed RSA-PSS vectors with Windows CNG, JDK and actual Android/JNI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/proof_signature_vectors.json"


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--jdk", type=Path, default=Path("A:/Android/AndroidStudio/jbr"))
    parser.add_argument("--ndk", type=Path, default=Path("A:/Android/sdk/ndk/28.2.13676358"))
    parser.add_argument("--sdk", type=Path, default=Path("A:/Android/sdk"))
    parser.add_argument("--gxx", default="D:/mingw/mingw64/bin/g++.exe")
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-signature-check-"))
    env = dict(os.environ, JAVA_HOME=str(args.jdk))
    def run(command):
        result = subprocess.run([str(item) for item in command], env=env, capture_output=True, encoding="utf-8", errors="replace", timeout=180)
        if result.returncode:
            raise RuntimeError(Path(str(command[0])).name + " failed: " + result.stdout[-1800:] + result.stderr[-1800:])
        return result.stdout.strip()
    def verify_output(output):
        lines = output.splitlines()
        expected = [case["id"] + "\tPASS" for case in fixture["cases"]] + ["PASS\t14"]
        if lines != expected:
            raise RuntimeError("Signature output case coverage differs")
        return {"passed": True, "cases": 14, "actual_output_sha256": hashlib.sha256(output.encode()).hexdigest()}
    report = {"spike_version": 1, "passed": False, "scope": "platform crypto primitive and JNI adapter only",
        "capsule_claim_authentication_verified": False, "key_rotation_verified": False, "product_dependency_changed": False,
        "android_x86_os_executed": False, "consumers": {}, "builds": {}, "errors": [], "cleanup_errors": []}
    adb = [args.sdk / "platform-tools/adb.exe", "-s", args.serial]
    device_dir = "/data/local/tmp/excellent-calendar-signature-" + uuid.uuid4().hex
    device_created = False
    remote_files = []
    try:
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        if len(fixture["cases"]) != 14 or len({case["id"] for case in fixture["cases"]}) != 14:
            raise ValueError("Signature fixture count/identity")
        vectors = scratch / "vectors.tsv"
        vectors.write_text("\n".join("\t".join((case["id"], case["modulus_hex"], case["message_hex"], case["signature_hex"],
            "1" if case["expected"]["signature_valid"] else "0")) for case in fixture["cases"]) + "\n", encoding="utf-8")
        run([args.jdk / "bin/javac.exe", "-encoding", "UTF-8", "--release", "8", "-Xlint:-options", "-d", scratch, HERE / "ProofSignatureProbe.java"])
        report["consumers"]["java21"] = verify_output(run([args.jdk / "bin/java.exe", "-cp", scratch, "ProofSignatureProbe", "verify", vectors]))
        binary = scratch / "proof_signature_probe.exe"
        run([args.gxx, "-std=c++17", "-O2", HERE / "proof_signature_probe.cpp", "-o", binary, "-lbcrypt"])
        report["consumers"]["windows_cng_cpp"] = verify_output(run([binary, vectors]))
        report["builds"]["windows_cng_cpp"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        clang = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/clang++.exe"
        libraries = {}
        for abi, triple in (("arm64-v8a", "aarch64-linux-android23"), ("armeabi-v7a", "armv7a-linux-androideabi23"), ("x86_64", "x86_64-linux-android23")):
            library = scratch / ("libproof_" + abi + ".so")
            run([clang, "--target=" + triple, "-std=c++17", "-O2", "-fPIC", "-shared", "-static-libstdc++", HERE / "proof_signature_probe.cpp", "-o", library])
            report["builds"][abi] = hashlib.sha256(library.read_bytes()).hexdigest()
            libraries[abi] = library
        jar = scratch / "probe.jar"
        run([args.jdk / "bin/jar.exe", "--create", "--file", jar, "-C", scratch, "ProofSignatureProbe.class"])
        dex = scratch / "classes.zip"
        run([args.sdk / "build-tools/36.0.0/d8.bat", "--min-api", "23", "--lib", args.sdk / "platforms/android-36/android.jar", "--output", dex, jar])
        report["dex_sha256"] = hashlib.sha256(dex.read_bytes()).hexdigest()
        report["device"] = {"abi": run(adb + ["shell", "getprop", "ro.product.cpu.abilist"]),
            "sdk": run(adb + ["shell", "getprop", "ro.build.version.sdk"]), "model": run(adb + ["shell", "getprop", "ro.product.model"])}
        if "arm64-v8a" not in report["device"]["abi"].split(","):
            raise ValueError("Android arm64 device required")
        run(adb + ["shell", "mkdir", device_dir]); device_created = True
        for path in (dex, vectors, *libraries.values()):
            remote = device_dir + "/" + path.name
            run(adb + ["push", path, remote]); remote_files.append(remote)
        base = adb + ["shell", "env", "CLASSPATH=" + device_dir + "/classes.zip"]
        for abi, process in (("arm64-v8a", "app_process64"), ("armeabi-v7a", "app_process32")):
            if abi not in report["device"]["abi"].split(","):
                continue
            command = base + ["/system/bin/" + process, "/system/bin", "ProofSignatureProbe", "verify", device_dir + "/vectors.tsv"]
            report["consumers"]["android_jca_" + abi] = verify_output(run(command))
            report["consumers"]["android_jni_" + abi] = verify_output(run(command + [device_dir + "/" + libraries[abi].name]))
        report["passed"] = True
    except Exception as error:
        report["errors"].append(str(error))
    finally:
        if device_created:
            try:
                if remote_files:
                    run(adb + ["shell", "rm", "-f"] + remote_files)
                run(adb + ["shell", "rmdir", device_dir])
            except Exception as error:
                report["cleanup_errors"].append(str(error)); report["passed"] = False
        report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
            for path in (Path(__file__), HERE / "ProofSignatureProbe.java", HERE / "proof_signature_probe.cpp", HERE / "sha256_probe.hpp", FIXTURE)}
        (HERE / "proof_signature_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "consumers", "errors", "cleanup_errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
