#!/usr/bin/env python3
"""Build and exercise actual standalone consumers using existing tools only.

Records Bionic/QEMU-user ABI execution separately from Android device execution.
Uses synthetic input files on the device so adb pipe EOF cannot stall the probe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import struct
import subprocess
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FIXTURES = ROOT / "contracts/fixtures/sync/v1/jcs_boundary_vectors.json"


def run(args: list[str], data: bytes | None = None, timeout: int = 120) -> bytes:
    result = subprocess.run(args, input=data, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{args[0]} exited {result.returncode}: {result.stderr.decode('utf-8', errors='replace')[-2000:]}")
    return result.stdout


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def wsl_path(path: Path) -> str:
    resolved = path.resolve().as_posix()
    if len(resolved) < 3 or resolved[1:3] != ":/":
        raise ValueError("Expected an absolute Windows scratch path")
    return "/mnt/" + resolved[0].lower() + resolved[2:]


def expected(case: dict) -> str:
    if case["expected_error"]:
        return "ERROR"
    raw = bytes.fromhex(case["canonical_utf8_hex"])
    if sha(raw) != case["sha256"]:
        raise ValueError("Boundary fixture byte/hash mismatch")
    return "OK\t" + raw.hex() + "\t" + sha(raw)


def numeric_inputs(count: int, seed: int) -> list[str]:
    rng = random.Random(seed)
    values = []
    while len(values) < count:
        value = struct.unpack(">d", rng.getrandbits(64).to_bytes(8, "big"))[0]
        if math.isfinite(value):
            values.append(format(value, ".17g"))
    return values


def numeric_edges() -> list[str]:
    values = set()
    for exponent in range(-1074, 1024):
        value = math.ldexp(1.0, exponent)
        for neighbour in (value, math.nextafter(value, 0), math.nextafter(value, math.inf)):
            if math.isfinite(neighbour):
                values.update((neighbour, -neighbour))
    for exponent in range(-323, 309):
        for coefficient in (1, 3, 5, 7, 9):
            value = float(str(coefficient) + "e" + str(exponent))
            if not math.isfinite(value):
                continue
            for neighbour in (value, math.nextafter(value, 0), math.nextafter(value, math.inf)):
                if math.isfinite(neighbour):
                    values.update((neighbour, -neighbour))
    return [format(value, ".17g") for value in sorted(values)]


@contextmanager
def persist_evidence(report: dict, path: Path):
    try:
        yield
    except Exception as error:
        report["jcs_spike_passed"] = False
        report["errors"].append(str(error))
        print(str(error), flush=True)
    finally:
        path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpp-compiler", required=True)
    parser.add_argument("--java", required=True)
    parser.add_argument("--javac", required=True)
    parser.add_argument("--node", required=True)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--wsl", default="wsl.exe")
    parser.add_argument("--wsl-distro", default="Ubuntu")
    parser.add_argument("--adb")
    parser.add_argument("--serial")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    fixtures = json.loads(FIXTURES.read_text(encoding="utf-8"))
    cases = fixtures["cases"]
    fuzz = numeric_inputs(fixtures["random_numeric_oracle"]["finite_ieee754_samples"], 8785)
    edges = numeric_edges()
    if len(edges) != fixtures["systematic_numeric_oracle"]["case_count"]:
        raise ValueError("Systematic IEEE edge generator drift")
    numeric = fuzz + edges
    oracle = run([args.node, str(HERE / "jcs_numeric_oracle.cjs")], ("\n".join(numeric) + "\n").encode()).decode().splitlines()
    if len(oracle) != len(numeric):
        raise ValueError("Numeric oracle omitted results")
    inputs = [case["input_json"] for case in cases] + numeric
    body = ("\n".join(inputs) + "\n").encode()
    answers = [expected(case) for case in cases] + ["OK\t" + v.encode().hex() + "\t" + sha(v.encode()) for v in oracle]
    report = {"spike_version": 1, "kind": "jcs_bytes_and_sha256_feasibility", "jcs_spike_passed": False,
              "android_three_os_device_matrix_verified": False, "product_dependency_changed": False,
              "input_sha256": sha(body), "expected_output_sha256": sha(("\n".join(answers) + "\n").encode()),
              "fixture_sha256": sha(FIXTURES.read_text(encoding="utf-8").encode()),
              "numeric_oracle_version": run([args.node, "--version"]).decode().strip(),
              "consumers": {}, "errors": [], "cleanup_pending": []}
    sources = [Path(__file__), HERE / "jcs_probe.cpp", HERE / "JcsProbe.java", HERE / "sha256_probe.hpp", HERE / "jcs_numeric_oracle.cjs"]
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): sha(p.read_text(encoding="utf-8").encode()) for p in sources}
    with persist_evidence(report, args.report), tempfile.TemporaryDirectory(prefix="excellent-calendar-jcs-") as tmp:
        build = Path(tmp)

        def measure(name, invoke, executable: Path | None = None, environment: str = "host"):
            output = invoke(body)
            actual = output.decode("utf-8", errors="strict").splitlines()
            if len(actual) != len(answers):
                raise AssertionError(f"{name}: result count {len(actual)} != {len(answers)}")
            mismatches = [{"index": i, "input": inputs[i], "expected": e, "actual": a}
                          for i, (a, e) in enumerate(zip(actual, answers)) if a != e]
            for invalid in fixtures["malformed_utf8"]:
                raw = bytes.fromhex(invalid["input_utf8_hex"]) + b"\n"
                if invoke(raw).decode().splitlines() != ["ERROR"]:
                    mismatches.append({"id": invalid["id"], "reason": "malformed UTF-8 accepted"})
            result = {"environment": environment, "boundary_cases": len(cases), "numeric_cases": len(fuzz),
                      "systematic_numeric_cases": len(edges),
                      "malformed_utf8_cases": len(fixtures["malformed_utf8"]), "passed": not mismatches,
                      "actual_output_sha256": sha(("\n".join(actual) + "\n").encode()), "mismatches": mismatches[:20]}
            if executable:
                result["executable_sha256"] = sha(executable.read_bytes())
            report["consumers"][name] = result
            print(json.dumps({"consumer": name, "passed": not mismatches}), flush=True)
            if mismatches:
                raise AssertionError(f"{name}: {len(mismatches)} canonicalization mismatches")

        host = build / "jcs.exe"
        run([args.cpp_compiler, "-std=c++17", "-O2", "-static", str(HERE / "jcs_probe.cpp"), "-o", str(host)])
        measure("windows_cpp", lambda data: run([str(host)], data), host)
        messages = ["", "abc", "a" * 55, "a" * 56, "a" * 63, "a" * 64, "a" * 65, "a" * 1000000, "中文😀"]
        kat_body = ("\n".join(messages) + "\n").encode()
        kat_expected = [sha(value.encode()) for value in messages]
        if run([str(host), "--sha256"], kat_body).decode().splitlines() != kat_expected:
            raise AssertionError("Extracted SHA-256 host KAT failed")
        report["extracted_sha256_kat"] = {"passed": True, "byte_lengths": [len(v.encode()) for v in messages], "hashes": kat_expected,
                                           "counter_width": 64, "production_core_unchanged": True}
        run([args.javac, "-encoding", "UTF-8", "-d", str(build), str(HERE / "JcsProbe.java")])
        measure("java", lambda data: run([args.java, "-cp", str(build), "JcsProbe"], data))
        ndk_bin = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
        targets = {"arm64-v8a": ("aarch64-linux-android23", "qemu-aarch64-static"),
                   "armeabi-v7a": ("armv7a-linux-androideabi23", "qemu-arm-static"),
                   "x86_64": ("x86_64-linux-android23", "qemu-x86_64-static")}
        report["ndk_revision"] = (args.ndk / "source.properties").read_text(encoding="utf-8").strip()
        for abi, (target, emulator) in targets.items():
            binary = build / ("jcs-" + abi)
            run([str(ndk_bin / "clang++.exe"), "--target=" + target, "-std=c++17", "-O2", "-static", str(HERE / "jcs_probe.cpp"), "-o", str(binary)])
            command = [args.wsl, "-d", args.wsl_distro, "--", emulator, wsl_path(binary)]
            measure("ndk_bionic_" + abi, lambda data, cmd=command: run(cmd, data), binary,
                    "Android NDK Bionic static executable under existing QEMU-user on WSL2; not a full Android OS")
            if run(command + ["--sha256"], kat_body).decode().splitlines() != kat_expected:
                raise AssertionError(f"Extracted SHA-256 {abi} KAT failed")
            report["consumers"]["ndk_bionic_" + abi]["sha256_kat_passed"] = True
        if args.adb and args.serial:
            adb = [args.adb, "-s", args.serial]
            abi = run(adb + ["shell", "getprop", "ro.product.cpu.abi"], timeout=20).decode().strip()
            if abi not in targets:
                raise RuntimeError("Connected device has no audited ABI")
            binary = build / "jcs-device"
            run([str(ndk_bin / "clang++.exe"), "--target=" + targets[abi][0], "-std=c++17", "-O2", "-static-libstdc++", str(HERE / "jcs_probe.cpp"), "-o", str(binary)])
            remote = "/data/local/tmp/excellent-calendar-jcs-" + uuid.uuid4().hex
            try:
                run(adb + ["push", str(binary), remote], timeout=20)
                run(adb + ["shell", "chmod", "700", remote], timeout=20)

                def device_invoke(data, argument=""):
                    local = build / "device-input.jsonl"
                    local.write_bytes(data)
                    run(adb + ["push", str(local), remote + ".input"], timeout=20)
                    return run(adb + ["exec-out", f"{remote} {argument} < {remote}.input"], timeout=60)

                measure("android_device_" + abi, device_invoke, binary, "Connected Android device; system Bionic")
                if device_invoke(kat_body, "--sha256").decode().splitlines() != kat_expected:
                    raise AssertionError("Device SHA-256 KAT failed")
                report["consumers"]["android_device_" + abi]["sha256_kat_passed"] = True
            finally:
                try:
                    run(adb + ["shell", "rm", "-f", remote, remote + ".input"], timeout=20)
                except Exception:
                    report["cleanup_pending"] += [remote, remote + ".input"]
        report["jcs_spike_passed"] = all(v["passed"] for v in report["consumers"].values()) and not report["cleanup_pending"]
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if report["jcs_spike_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
