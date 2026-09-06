#!/usr/bin/env python3
"""Rebuild pinned native C sources and test synthetic databases; no product changes.

Existing CMake, NDK, MinGW, WSL/make and QEMU are required. QEMU-user execution
of NDK/Bionic binaries is recorded separately from actual Android OS execution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tarfile
import time
import urllib.request
import uuid
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCES = {
    "sqlcipher": ("63697beb0fafcb61faa7a3e6fd267036548ab11b", "31951158488fa3542f1037ff26cb203513075e793f0739975a9a9da22294a305"),
    "libtomcrypt": ("476a9579ae94f32b9ea9e2747bfb04b302370259", "d4c18f3ad1acb4c13ebde0f0956e792465f0c9cbd5d4862a327e5f0926f523fb"),
}
OLD_RNG = b"#ifdef ANSI_RNG\n   x = _rng_ansic"
NEW_RNG = b"#if defined(ANSI_RNG) && !defined(EXCELLENT_CALENDAR_REQUIRE_OS_RNG)\n   x = _rng_ansic"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def wsl_path(path: Path) -> str:
    value = path.resolve().as_posix()
    if value[1:3] != ":/":
        raise ValueError("Expected an absolute Windows scratch path")
    return "/mnt/" + value[0].lower() + value[2:]


def command(argv: list[str], *, killed: bool = False, timeout: int = 300) -> dict:
    result = subprocess.run(argv, capture_output=True, timeout=timeout)
    out = result.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n")
    err = result.stderr.decode("utf-8", errors="replace").replace("\r\n", "\n")
    # WSL propagates SIGKILL as 9; native POSIX subprocess uses -9 and shells 137.
    allowed = (86, -9, 9, 137) if killed else (0,)
    if result.returncode not in allowed or (killed and "KILL_POINT_REACHED" not in out):
        raise RuntimeError(f"Command failed ({result.returncode}): {argv}\n{out[-1500:]}\n{err[-1500:]}")
    if "SYNC_SYNTHETIC_RECOVERY_PAYLOAD" in out + err:
        raise RuntimeError("Synthetic business payload leaked to probe logs")
    return {"argv": argv, "exit_code": result.returncode, "stdout": out, "stderr": err,
            "stdout_sha256": sha(out.encode()), "stderr_sha256": sha(err.encode())}


def verified_source(scratch: Path, name: str) -> dict:
    commit, digest = SOURCES[name]
    archive = scratch / (name + ".tar.gz")
    url = f"https://codeload.github.com/sqlcipher/{name}/tar.gz/{commit}"
    if not archive.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "ExcellentCalendar-contract-spike"})
        with urllib.request.urlopen(request, timeout=120) as response:
            archive.write_bytes(response.read())
    if sha(archive.read_bytes()) != digest:
        raise ValueError("Pinned archive hash differs: " + name)
    tree = scratch / name
    tree.mkdir(exist_ok=True)
    selected = {}
    with tarfile.open(archive) as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or member.issym() or member.islnk():
                raise ValueError("Unsafe source archive member")
            if not member.isfile():
                continue
            relative = Path(*path.parts[1:])
            target = tree / relative
            data = source.extractfile(member).read()
            if name == "libtomcrypt" and relative.as_posix() == "src/prngs/rng_get_bytes.c":
                if data.count(OLD_RNG) != 1:
                    raise ValueError("Pinned entropy patch context changed")
                data = data.replace(OLD_RNG, NEW_RNG)
            if target.exists():
                if target.read_bytes() != data:
                    raise ValueError("Modified upstream source: " + str(target))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            if relative.suffix in {".c", ".h"} or "LICENSE" in relative.name:
                selected[relative.as_posix()] = sha(data)
    return {"commit": commit, "url": url, "archive_sha256": digest,
            "source_file_hashes": selected, "source_tree_verified_against_archive": True}


def exercise(prefix: list[str], binary_dir: str, database_dir: str, extension: str) -> list[dict]:
    evidence = []
    probe = binary_dir + "/cipher_recovery_probe" + extension
    evidence.append(command(prefix + [binary_dir + "/rng_failure_probe" + extension]))
    evidence.append(command(prefix + [binary_dir + "/cipher_probe" + extension, database_dir + "/capacity.sqlite"]))
    evidence.append(command(prefix + [probe, "binary-key", database_dir + "/binary-key.sqlite"]))
    cases = [("keys", "0"), ("full", "0"), ("temp", "20000"),
             ("kill-before-commit", "0"), ("kill-during-wal-sync", "either"),
             ("kill-after-commit", "20000"), ("kill-during-checkpoint", "20000")]
    for mode, expected in cases:
        print("  " + mode, flush=True)
        path = database_dir + "/" + mode + ".sqlite"
        evidence.append(command(prefix + [probe, "init", path]))
        evidence.append(command(prefix + [probe, mode, path], killed=mode.startswith("kill-")))
        evidence.append(command(prefix + [probe, "verify", path, expected]))
    return evidence


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--scratch", type=Path, required=True)
    p.add_argument("--cmake", required=True)
    p.add_argument("--ninja", required=True)
    p.add_argument("--gcc", required=True)
    p.add_argument("--gxx", required=True)
    p.add_argument("--ndk", type=Path, required=True)
    p.add_argument("--wsl", default="wsl.exe")
    p.add_argument("--wsl-distro", default="Ubuntu")
    p.add_argument("--adb", required=True)
    p.add_argument("--serial", required=True)
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=True)
    report = {"spike_version": 1, "passed": False, "product_dependency_changed": False,
              "android_three_os_device_matrix_verified": False,
              "limits": ["QEMU-user is ABI execution, not a complete Android OS/device test",
                         "SQLITE_FULL is injected through a real-file VFS; no user disk was filled",
                         "Process kill does not simulate sudden storage power loss",
                         "20000 synthetic rows are cipher feasibility, not a full sync entity-graph capacity test",
                         "Keystore, backup policy and production v5-v6 migration are separate evidence"],
              "source_hashes": {}, "sources": {}, "builds": {}, "consumers": {},
              "errors": [], "cleanup_errors": []}
    for name in ("run_cipher_source_spike.py", "cipher_source_build/CMakeLists.txt", "sqlcipher_probe.cpp",
                 "cipher_recovery_probe.cpp", "rng_failure_probe.c", "require_os_rng.patch"):
        report["source_hashes"][name] = sha((HERE / name).read_text(encoding="utf-8").encode())
    wsl = [args.wsl, "-d", args.wsl_distro]
    run_id = uuid.uuid4().hex
    device_dir = "/data/local/tmp/excellent-calendar-cipher-" + run_id
    adb = [args.adb, "-s", args.serial]
    created_device_directories = []
    try:
        for name in SOURCES:
            print("Verify pinned source: " + name, flush=True)
            report["sources"][name] = verified_source(args.scratch, name)
        core = args.scratch / "sqlcipher"
        print("Generate amalgamation with existing WSL/make", flush=True)
        previous = {name: (sha((core / name).read_bytes()), (core / name).stat())
                    for name in ("sqlite3.c", "sqlite3.h") if (core / name).is_file()}
        report["generation"] = [command(wsl + ["--cd", wsl_path(core), "--", "sh", "./configure", "--with-tempstore=yes", "--disable-tcl"]),
                                command(wsl + ["--cd", wsl_path(core), "--", "make", "sqlite3.c"])]
        report["amalgamation_hashes"] = {name: sha((core / name).read_bytes()) for name in ("sqlite3.c", "sqlite3.h")}
        for name, (digest, stat) in previous.items():
            if report["amalgamation_hashes"][name] == digest:
                os.utime(core / name, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        environments = [("windows", None), ("arm64-v8a", "qemu-aarch64-static"),
                        ("armeabi-v7a", "qemu-arm-static"), ("x86_64", "qemu-x86_64-static")]
        for env, emulator in environments:
            print("Build and execute: " + env, flush=True)
            build = args.scratch / ("build-" + env)
            configure = [args.cmake, "-S", (HERE / "cipher_source_build").as_posix(), "-B", build.as_posix(), "-G", "Ninja",
                         "-DCMAKE_MAKE_PROGRAM=" + args.ninja, "-DCMAKE_BUILD_TYPE=Release",
                         "-DSQLCIPHER_SOURCE=" + core.as_posix(), "-DLTC_SOURCE_DIR=" + (args.scratch / "libtomcrypt").as_posix()]
            if emulator:
                configure += ["-DCMAKE_TOOLCHAIN_FILE=" + (args.ndk / "build/cmake/android.toolchain.cmake").as_posix(),
                              "-DANDROID_ABI=" + env, "-DANDROID_PLATFORM=android-23", "-DANDROID_STL=c++_static", "-DSYNC_SPIKE_STATIC_ANDROID=ON"]
            else:
                configure += ["-DCMAKE_C_COMPILER=" + args.gcc, "-DCMAKE_CXX_COMPILER=" + args.gxx]
            report["builds"][env] = [command(configure), command([args.cmake, "--build", build.as_posix(), "--parallel", "12"], timeout=600)]
            extension = "" if emulator else ".exe"
            binary_hashes = {name: sha((build / (name + extension)).read_bytes())
                             for name in ("cipher_probe", "cipher_recovery_probe", "rng_failure_probe")}
            data_dir = args.scratch / ("run-" + run_id) / env
            data_dir.mkdir(parents=True)
            started = time.monotonic()
            prefix = wsl + ["--", emulator] if emulator else []
            evidence = exercise(prefix, wsl_path(build) if emulator else build.as_posix(),
                                wsl_path(data_dir) if emulator else data_dir.as_posix(), "" if emulator else ".exe")
            report["consumers"][env] = {"passed": True, "execution": "bionic_static_qemu_user" if emulator else "windows_native",
                                         "elapsed_seconds": round(time.monotonic() - started, 3), "binary_sha256": binary_hashes, "steps": evidence}
        print("Execute actual Android arm64 device", flush=True)
        report["device"] = {"abi": command(adb + ["shell", "getprop", "ro.product.cpu.abilist"])["stdout"].strip(),
                            "model": command(adb + ["shell", "getprop", "ro.product.model"])["stdout"].strip(),
                            "sdk": command(adb + ["shell", "getprop", "ro.build.version.sdk"])["stdout"].strip()}
        if "arm64-v8a" not in report["device"]["abi"].split(","):
            raise ValueError("Connected device cannot execute arm64 probe")
        device_abis = [("arm64-v8a", "android_device_arm64")]
        if "armeabi-v7a" in report["device"]["abi"].split(","):
            device_abis.append(("armeabi-v7a", "android_device_arm32"))
        for abi, label in device_abis:
            current_dir = device_dir + "-" + abi
            command(adb + ["shell", "mkdir", current_dir])
            created_device_directories.append(current_dir)
            for name in ("cipher_probe", "cipher_recovery_probe", "rng_failure_probe"):
                command(adb + ["push", str(args.scratch / ("build-" + abi) / name), current_dir + "/" + name])
                command(adb + ["shell", "chmod", "700", current_dir + "/" + name])
            started = time.monotonic()
            # shell v2 propagates the child's exit code; exec-out reports transport
            # success (0) even when a remotely executed process was killed.
            evidence = exercise(adb + ["shell", "-T"], current_dir, current_dir, "")
            report["consumers"][label] = {"passed": True, "execution": "android_os_device_bionic_static",
                "elapsed_seconds": round(time.monotonic() - started, 3),
                "binary_sha256": report["consumers"][abi]["binary_sha256"], "steps": evidence}
        report["passed"] = True
    except Exception as error:
        report["errors"].append(str(error))
        print(str(error), flush=True)
    finally:
        for current_dir in created_device_directories:
            try:
                # Only our random synthetic directory; never a product path or recursive delete.
                names = ["cipher_probe", "cipher_recovery_probe", "rng_failure_probe"]
                for name in ["capacity", "binary-key", "keys", "full", "temp", "kill-before-commit", "kill-during-wal-sync", "kill-after-commit", "kill-during-checkpoint"]:
                    names.extend(name + ".sqlite" + suffix for suffix in ("", "-wal", "-shm", "-journal"))
                command(adb + ["shell", "rm", "-f"] + [current_dir + "/" + name for name in names])
                command(adb + ["shell", "rmdir", current_dir])
            except Exception as error:
                report["cleanup_errors"].append(str(error)); report["passed"] = False
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "consumers": list(report["consumers"]), "errors": report["errors"]}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
