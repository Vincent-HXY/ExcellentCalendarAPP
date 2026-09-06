"""Full capsule parsing/authentication: independent Java, Windows C++, Android C++/JNI."""
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
FIXTURE = ROOT / "contracts/fixtures/sync/v1/proof_capsule_vectors.json"


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--jdk", type=Path, default=Path("A:/Android/AndroidStudio/jbr"))
    parser.add_argument("--ndk", type=Path, default=Path("A:/Android/sdk/ndk/28.2.13676358"))
    parser.add_argument("--sdk", type=Path, default=Path("A:/Android/sdk"))
    parser.add_argument("--gxx", default="D:/mingw/mingw64/bin/g++.exe")
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-capsule-check-"))
    env = dict(os.environ, JAVA_HOME=str(args.jdk))
    def run(command, *, input=None, extra_env=None):
        result = subprocess.run([str(item) for item in command], env={**env, **(extra_env or {})}, input=input,
            capture_output=True, encoding="utf-8", errors="strict", timeout=180)
        if result.returncode:
            raise RuntimeError(Path(str(command[0])).name + " failed: " + result.stdout[-2200:] + result.stderr[-2200:])
        return result.stdout.strip(), result.stderr.strip()
    def verify_output(output):
        lines = output.splitlines()
        if lines != ["VALID" if case["expected"]["authenticated"] else "REJECT" for case in fixture["cases"]]:
            failures = [case["id"] for index, case in enumerate(fixture["cases"]) if index >= len(lines) or lines[index] != ("VALID" if case["expected"]["authenticated"] else "REJECT")]
            raise RuntimeError("Capsule case result/coverage differs: " + ",".join(failures))
        return {"passed": True, "cases": len(lines), "actual_output_sha256": hashlib.sha256(output.encode()).hexdigest()}
    report = {"spike_version": 1, "passed": False, "scope": "strict capsule authentication and isolated typed SQLite acceptance",
        "production_activated": False, "all_import_saga_crash_points_verified": False, "android_persistent_revocation_store_verified": False,
        "account_deletion_backend_producer_implemented": False, "android_x86_os_executed": False,
        "consumers": {}, "builds": {}, "errors": [], "cleanup_errors": []}
    adb = [args.sdk / "platform-tools/adb.exe", "-s", args.serial]
    device_dir = "/data/local/tmp/excellent-calendar-capsule-" + uuid.uuid4().hex
    device_created = False
    remote_files = []
    try:
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        if len(fixture["cases"]) != 49 or len({case["id"] for case in fixture["cases"]}) != 49: raise ValueError("fixture identity/count")
        raw = "\n".join(json.dumps(case["input"], ensure_ascii=False, separators=(",", ":")) for case in fixture["cases"]) + "\n"
        vectors = scratch / "requests.jsonl"; vectors.write_text(raw, encoding="utf-8")
        run([args.jdk / "bin/javac.exe", "-encoding", "UTF-8", "-d", scratch, HERE / "JcsProbe.java", HERE / "ProofSignatureProbe.java", HERE / "ProofCapsuleProbe.java"])
        report["consumers"]["java21"] = verify_output(run([args.jdk / "bin/java.exe", "-cp", scratch, "ProofCapsuleProbe", "--verify-lines"], input=raw)[0])
        binary = scratch / "proof_capsule_probe.exe"
        run([args.gxx, "-std=c++17", "-O2", HERE / "proof_capsule_probe.cpp", "-o", binary, "-lbcrypt"])
        report["consumers"]["windows_cng_cpp"] = verify_output(run([binary, "--verify-lines"], input=raw)[0])
        report["builds"]["windows_cng_cpp"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        import sys
        output, errors = run([sys.executable, "-X", "utf8", "-m", "unittest", "discover", "-s", ROOT / "contracts/tests", "-p", "test_sync_proofs.py"],
                             extra_env={"SYNC_PROOF_TEST_BINARY": str(binary)})
        if "Ran 12 tests" not in errors or not errors.endswith("OK"): raise ValueError("acceptance suite coverage")
        report["typed_atomic_acceptance"] = {"passed": True, "tests": 12, "fixed_cases": 45, "output_sha256": hashlib.sha256((output + errors).encode()).hexdigest()}
        clang = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin/clang++.exe"
        libraries = {}
        for abi, triple in (("arm64-v8a", "aarch64-linux-android23"), ("armeabi-v7a", "armv7a-linux-androideabi23"), ("x86_64", "x86_64-linux-android23")):
            library = scratch / ("libcapsule_" + abi + ".so")
            run([clang, "--target=" + triple, "-std=c++17", "-O2", "-fPIC", "-shared", "-static-libstdc++", HERE / "proof_capsule_probe.cpp", "-o", library])
            report["builds"][abi] = hashlib.sha256(library.read_bytes()).hexdigest(); libraries[abi] = library
        android_classes = scratch / "android_classes"; android_classes.mkdir()
        run([args.jdk / "bin/javac.exe", "-encoding", "UTF-8", "--release", "8", "-Xlint:-options", "-d", android_classes,
             HERE / "ProofSignatureProbe.java", HERE / "ProofCapsuleAndroidProbe.java"])
        jar = scratch / "android.jar"
        run([args.jdk / "bin/jar.exe", "--create", "--file", jar, "-C", android_classes, "."])
        dex = scratch / "classes.zip"
        run([args.sdk / "build-tools/36.0.0/d8.bat", "--min-api", "23", "--lib", args.sdk / "platforms/android-36/android.jar", "--output", dex, jar])
        report["dex_sha256"] = hashlib.sha256(dex.read_bytes()).hexdigest()
        report["device"] = {"abi": run(adb + ["shell", "getprop", "ro.product.cpu.abilist"])[0],
            "sdk": run(adb + ["shell", "getprop", "ro.build.version.sdk"])[0], "model": run(adb + ["shell", "getprop", "ro.product.model"])[0]}
        if "arm64-v8a" not in report["device"]["abi"].split(","): raise ValueError("Android arm64 device required")
        run(adb + ["shell", "mkdir", device_dir]); device_created = True
        for path in (dex, vectors, *libraries.values()):
            remote = device_dir + "/" + path.name; run(adb + ["push", path, remote]); remote_files.append(remote)
        base = adb + ["shell", "env", "CLASSPATH=" + device_dir + "/classes.zip"]
        for abi, process in (("arm64-v8a", "app_process64"), ("armeabi-v7a", "app_process32")):
            if abi not in report["device"]["abi"].split(","): continue
            command = base + ["/system/bin/" + process, "/system/bin", "ProofCapsuleAndroidProbe", device_dir + "/requests.jsonl", device_dir + "/" + libraries[abi].name]
            report["consumers"]["android_cpp_jni_" + abi] = verify_output(run(command)[0])
        report["passed"] = True
    except Exception as error:
        report["errors"].append(str(error))
    finally:
        if device_created:
            try:
                if remote_files: run(adb + ["shell", "rm", "-f"] + remote_files)
                run(adb + ["shell", "rmdir", device_dir])
            except Exception as error:
                report["cleanup_errors"].append(str(error)); report["passed"] = False
        source_paths = [Path(__file__), HERE / "proof_capsule_probe.cpp", HERE / "ProofCapsuleProbe.java", HERE / "ProofCapsuleAndroidProbe.java",
            HERE / "proof_signature_probe.cpp", HERE / "ProofSignatureProbe.java", HERE / "jcs_probe.cpp", HERE / "JcsProbe.java", HERE / "sha256_probe.hpp",
            HERE / "proof_reference.py", HERE / "build_proof_capsule_fixtures.py", HERE / "build_sync_proof_contracts.py", HERE / "sqlite_reference.py",
            HERE / "protocol_reference.py", HERE / "domain_reference.py", HERE / "schema_validation_reference.py", HERE / "identity_reference.py", HERE / "counter_reference.py",
            ROOT / "contracts/tests/test_sync_proofs.py", FIXTURE, FIXTURE.with_name("proof_capsule_seeds.json"),
            ROOT / "contracts/sync/sync_proof_protocol.yaml", ROOT / "contracts/sync/sync_device_fence_response.schema.json",
            ROOT / "contracts/sync/import_range_close_proof.schema.json", ROOT / "contracts/sync/sync_import_manifest.schema.json",
            ROOT / "contracts/sync/sync_sequence_recovery_bundle.schema.json", *sorted((ROOT / "contracts/sync/proof").glob("*.schema.json"))]
        source_paths += [HERE / name for name in ("import_contract_reference.py", "bootstrap_reference.py", "cursor_reference.py",
            "build_target_fixtures.py", "build_sync_domain_contracts.py")]
        source_paths.append(ROOT / "contracts/sync/sync_protocol_invariants.yaml")
        report["source_sha256"] = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest() for path in source_paths}
        (HERE / "proof_capsule_spike_result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("passed", "consumers", "errors", "cleanup_errors")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
