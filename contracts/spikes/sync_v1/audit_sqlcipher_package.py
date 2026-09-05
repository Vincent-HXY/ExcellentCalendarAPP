#!/usr/bin/env python3
"""Inspect a previously downloaded candidate AAR and link a scratch C API probe.

Does not install dependencies, edit build files, run an APK, or touch user data.
Three ABI link success is not source build, licensing approval or runtime proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aar", type=Path, required=True)
    parser.add_argument("--upstream-sha256", type=Path, required=True)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    actual_hash = hashlib.sha256(args.aar.read_bytes()).hexdigest()
    if actual_hash != args.upstream_sha256.read_text(encoding="ascii").strip():
        raise SystemExit("Candidate artifact checksum mismatch")
    required = {"sqlite3_key", "sqlite3_key_v2"}
    for source in (ROOT / "cpp_core/src/storage/sqlite").glob("*.cpp"):
        required.update(re.findall(r"\b(sqlite3_\w+)\s*\(", source.read_text(encoding="utf-8")))
    report = {"audit_version": 1, "coordinate": "net.zetetic:sqlcipher-android:4.18.0",
              "source_url": "https://repo.maven.apache.org/maven2/net/zetetic/sqlcipher-android/4.18.0/sqlcipher-android-4.18.0.aar",
              "aar_sha256": actual_hash, "upstream_checksum_matches": True,
              "product_dependency_changed": False, "encryption_spike_passed": False,
              "source_build_verified": False, "abis": {}}
    report["source_sha256"] = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_text(encoding="utf-8").encode()).hexdigest()
                               for p in (Path(__file__), HERE / "sqlcipher_probe.cpp", ROOT / "cpp_core/third_party/sqlite/sqlite3.h")}
    bin_dir = args.ndk / "toolchains/llvm/prebuilt/windows-x86_64/bin"
    with tempfile.TemporaryDirectory(prefix="excellent-calendar-cipher-link-") as tmp, zipfile.ZipFile(args.aar) as archive:
        report["aar_metadata"] = archive.read("META-INF/com/android/build/gradle/aar-metadata.properties").decode()
        targets = {"arm64-v8a": "aarch64-linux-android23", "armeabi-v7a": "armv7a-linux-androideabi23", "x86_64": "x86_64-linux-android23"}
        for abi, target in targets.items():
            library = Path(tmp) / abi / "libsqlcipher.so"
            library.parent.mkdir()
            library.write_bytes(archive.read(f"jni/{abi}/libsqlcipher.so"))
            output = subprocess.check_output([str(bin_dir / "llvm-readelf.exe"), "--dyn-syms", "--wide", str(library)], text=True)
            exported = set(re.findall(r"\b(sqlite3_\w+)(?:\s|$)", output))
            missing = sorted(required - exported)
            if missing:
                raise SystemExit(f"Required C API symbols missing on {abi}: {missing}")
            subprocess.run([str(bin_dir / "clang++.exe"), "--target=" + target, "-std=c++17", "-O2", "-static-libstdc++",
                            "-I" + str(ROOT / "cpp_core/third_party/sqlite"), str(HERE / "sqlcipher_probe.cpp"), str(library),
                            "-Wl,-rpath,$ORIGIN", "-o", str(Path(tmp) / ("cipher-probe-" + abi))], check=True, capture_output=True, timeout=120)
            report["abis"][abi] = {"sha256": hashlib.sha256(library.read_bytes()).hexdigest(), "required_native_symbols": sorted(required),
                                   "missing_native_symbols": [], "probe_linked_with_current_ndk": True, "probe_executed": False}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"aar_sha256": actual_hash, "linked_abis": list(report["abis"]), "encryption_spike_passed": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
