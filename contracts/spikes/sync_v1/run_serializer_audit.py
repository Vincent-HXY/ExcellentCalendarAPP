#!/usr/bin/env python3
"""Probe existing encoders; a mismatch is evidence against reuse, not a JCS pass.

Uses only existing compilers/libraries, synthetic input and a temporary build
directory. Explicit --report persists the measured audit, never build artifacts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
VECTORS = ROOT / "contracts/fixtures/sync/v1/canonical_vectors.json"


def run(command: list[str], payload: bytes | None = None) -> bytes:
    result = subprocess.run(command, input=payload, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command[0]}\n{result.stderr.decode('utf-8', errors='replace')}")
    return result.stdout


def classify(output: bytes, vectors: list[dict]) -> dict:
    lines = output.decode().splitlines()
    if len(lines) != len(vectors):
        raise AssertionError("Probe did not return exactly one result per input")
    results = []
    for vector, actual in zip(vectors, lines):
        expected = "ERROR" if vector.get("expected_error") else "OK\t" + vector["canonical_utf8_hex"]
        results.append({"id": vector["id"], "matches_jcs": actual == expected, "actual": actual})
    return {"status": "compatible_sample_only" if all(r["matches_jcs"] for r in results) else "not_jcs", "cases": results}


def measure(command: list[str], vectors: list[dict]) -> dict:
    return classify(run(command, ("\n".join(v["input_json"] for v in vectors) + "\n").encode()), vectors)


def device_file_input(adb: str, remote: str, build: Path, body: bytes, argument: str = "") -> bytes:
    # adb exec-out does not reliably propagate pipe EOF to a read-until-EOF
    # native process. A synthetic file gives the process a real EOF.
    local = build / "android-probe-input.txt"
    local.write_bytes(body)
    run([adb, "push", str(local), remote + ".input"])
    return run([adb, "exec-out", f"{remote} {argument} < {remote}.input"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpp-compiler", required=True)
    parser.add_argument("--java-classpath", required=True)
    parser.add_argument("--javac", default="javac")
    parser.add_argument("--java", default="java")
    parser.add_argument("--dart", required=True)
    parser.add_argument("--ndk")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--android-device", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    vectors = json.loads(VECTORS.read_text(encoding="utf-8"))["cases"]
    report = {"audit_version": 1, "kind": "existing_serializer_reuse_audit", "jcs_spike_passed": False,
              "fixture_sha256": hashlib.sha256(VECTORS.read_text(encoding="utf-8").encode()).hexdigest(), "consumers": {}, "android_builds": {},
              "execution_errors": [], "cleanup_pending": []}
    source_paths = [HERE / name for name in ("run_serializer_audit.py", "serializer_probe.cpp", "SerializerProbe.java", "serializer_probe.dart")]
    source_paths += [ROOT / "cpp_core/src/common/search_token_crypto.cpp", ROOT / "cpp_core/third_party/picojson/picojson.h"]
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_text(encoding="utf-8").encode()).hexdigest() for p in source_paths}
    with tempfile.TemporaryDirectory(prefix="excellent-calendar-sync-ct0-") as tmp:
        build = Path(tmp)
        executable = build / ("probe.exe" if os.name == "nt" else "probe")
        flags = ["-std=c++17", "-O2", "-I" + str(ROOT / "cpp_core/include"),
                 "-I" + str(ROOT / "cpp_core/src"), "-I" + str(ROOT / "cpp_core/third_party")]
        command = [args.cpp_compiler, *flags, str(HERE / "serializer_probe.cpp"), "-o", str(executable)]
        if os.name == "nt":
            command += ["-static", "-lbcrypt"]
        run(command)
        report["consumers"]["cpp_host"] = measure([str(executable)], vectors)
        # Independent hashlib oracle, including padding edges and multi-block input.
        messages = ["", "abc", "a" * 55, "a" * 56, "a" * 63, "a" * 64, "a" * 65, "a" * 1000000]
        hashes = run([str(executable), "--sha256"], ("\n".join(messages) + "\n").encode()).decode().splitlines()
        expected_hashes = [hashlib.sha256(m.encode()).hexdigest() for m in messages]
        if hashes != expected_hashes:
            raise AssertionError("Existing private SHA-256 failed independent KAT")
        report["sha256_host_kat"] = {"passed": True, "lengths": [len(m) for m in messages], "hashes": hashes,
                                     "production_extraction_and_reuse_approved": False}
        run([args.javac, "-encoding", "UTF-8", "-cp", args.java_classpath, "-d", str(build), str(HERE / "SerializerProbe.java")])
        report["consumers"]["java_jackson"] = measure([args.java, "-cp", str(build) + os.pathsep + args.java_classpath, "SerializerProbe"], vectors)
        report["consumers"]["dart_json"] = measure([args.dart, str(HERE / "serializer_probe.dart")], vectors)
        if args.ndk:
            ndk_bin = Path(args.ndk) / "toolchains/llvm/prebuilt" / ("windows-x86_64" if os.name == "nt" else "linux-x86_64") / "bin"
            compiler = ndk_bin / ("clang++.exe" if os.name == "nt" else "clang++")
            targets = {"arm64-v8a": "aarch64-linux-android23", "armeabi-v7a": "armv7a-linux-androideabi23", "x86_64": "x86_64-linux-android23"}
            supported = []
            if args.android_device:
                try:
                    supported = run([args.adb, "shell", "getprop", "ro.product.cpu.abilist"]).decode().strip().split(",")
                except RuntimeError:
                    report["execution_errors"].append("Requested Android device unavailable; runtime audit not executed")
            for abi, target in targets.items():
                binary = build / ("probe-" + abi)
                run([str(compiler), "--target=" + target, *flags, "-static-libstdc++", str(HERE / "serializer_probe.cpp"), "-o", str(binary)])
                report["android_builds"][abi] = {"compiled": True, "executed": False}
                if abi not in supported:
                    continue
                remote = "/data/local/tmp/excellent-calendar-sync-ct0-" + abi
                try:
                    run([args.adb, "push", str(binary), remote])
                    run([args.adb, "shell", "chmod", "700", remote])
                    body = ("\n".join(v["input_json"] for v in vectors) + "\n").encode()
                    report["consumers"]["android_" + abi] = classify(device_file_input(args.adb, remote, build, body), vectors)
                    android_hashes = device_file_input(args.adb, remote, build, ("\n".join(messages) + "\n").encode(), "--sha256").decode().splitlines()
                    if android_hashes != expected_hashes:
                        raise AssertionError(f"SHA-256 KAT failed on {abi}")
                    report["android_builds"][abi].update(executed=True, sha256_kat_passed=True)
                except (RuntimeError, AssertionError, subprocess.TimeoutExpired) as error:
                    report["execution_errors"].append(f"Android {abi} probe incomplete: {type(error).__name__}")
                finally:
                    try:
                        run([args.adb, "shell", "rm", "-f", remote, remote + ".input"])
                    except (RuntimeError, subprocess.TimeoutExpired):
                        report["cleanup_pending"].append(remote)
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"consumers": {k: v["status"] for k, v in report["consumers"].items()},
                      "sha256_host_kat": True, "android_builds": report["android_builds"], "jcs_spike_passed": False,
                      "execution_errors": report["execution_errors"], "cleanup_pending": report["cleanup_pending"]}))
    # Exit 0 means the audit ran. It deliberately never signifies JCS conformance.
    return 1 if report["execution_errors"] or report["cleanup_pending"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
