#!/usr/bin/env python3
"""Record license/provenance evidence for the exact isolated native candidate."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--scratch", type=Path, required=True)
    p.add_argument("--report", type=Path, required=True)
    args = p.parse_args()
    from run_cipher_source_spike import verified_source
    sources = {name: verified_source(args.scratch, name) for name in ("sqlcipher", "libtomcrypt")}
    cmake = (HERE / "cipher_source_build/CMakeLists.txt").read_text(encoding="utf-8")
    if "LTC_NOTHING" not in cmake or "LTC_BLAKE2" in cmake:
        raise ValueError("Re-audit provider algorithm selection")
    report = {"audit_version": 1, "scope": "exact_native_sqlcipher_ltc_runtime_candidate",
              "runtime_source_license_inventory_complete": True,
              "product_notice_ui_delivered": False,
              "build_helpers_redistributed": False,
              "android_wrapper_or_aar_included": False,
              "source_commits": {name: row["commit"] for name, row in sources.items()},
              "reviewed_file_count": 0, "files": {}, "notices": {},
              "distribution_requirements": [
                  "Preserve exact SQLCipher BSD-style copyright, three conditions and disclaimer with source and binary distribution",
                  "Preserve the full provider LICENSE; select its public-domain option for the included provider",
                  "Preserve AES Rijndael attribution and the upstream per-file headers",
                  "If distributing the unused BLAKE2 source, preserve its three-option notice and use the CC0 option",
                  "Bundle these notices offline with the future APK and provide an accessible third-party notices entry",
                  "Audit build-helper redistribution separately if source packages include autosetup/autoconf/Jim; this spike does not redistribute them"
              ]}
    notices = HERE / "licenses"
    notices.mkdir(exist_ok=True)
    for component, source, output in (
        ("sqlcipher", "LICENSE.md", "SQLCipher-LICENSE.txt"),
        ("sqlcipher", "SQLITE_LICENSE.md", "SQLite-LICENSE.txt"),
        ("libtomcrypt", "LICENSE", "LibTomCrypt-LICENSE.txt"),
    ):
        data = (args.scratch / component / source).read_bytes()
        (notices / output).write_bytes(data)
        report["notices"][output] = {"sha256": sha(data), "source": component + "/" + source}
    for path in sorted((args.scratch / "libtomcrypt/src").rglob("*")):
        if path.suffix not in (".c", ".h"):
            continue
        data = path.read_bytes(); text = data.decode("utf-8")
        head = "\n".join(text.splitlines()[:20])
        if "free for all purposes" not in head:
            raise ValueError("Unreviewed provider header: " + str(path))
        relative = path.relative_to(args.scratch).as_posix()
        special = path.name in ("blake2b.c", "blake2s.c")
        if re.search(r"copyright|redistribut|permission is hereby|all rights reserved|gpl|lesser general|apache", text, re.I) and not special:
            raise ValueError("Unreviewed per-file license term: " + relative)
        report["files"][relative] = {"sha256": sha(data), "header_sha256": sha(head.encode()),
                                     "license": "CC0_option; algorithm disabled" if special else "LibTomCrypt_public_domain_option"}
        if path.name in ("aes.c", "blake2b.c", "blake2s.c"):
            # Preserve complete leading attribution/comment blocks, not a paraphrase.
            prefix = text.split('#include "tomcrypt.h"', 1)[0]
            output = path.name + "-NOTICE.txt"
            (notices / output).write_bytes(prefix.encode("utf-8"))
            report["notices"][output] = {"sha256": sha(prefix.encode()), "source": relative}
    for name in ("sqlite3.c", "sqlite3.h"):
        data = (args.scratch / "sqlcipher" / name).read_bytes()
        report["files"]["sqlcipher/" + name] = {"sha256": sha(data), "license": "SQLCipher_BSD_style_and_SQLite_public_domain"}
    report["reviewed_file_count"] = len(report["files"])
    report["source_hashes"] = {name: sha((HERE / name).read_text(encoding="utf-8").encode())
                                for name in ("audit_cipher_sources.py", "run_cipher_source_spike.py", "require_os_rng.patch", "cipher_source_build/CMakeLists.txt")}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"reviewed_runtime_files": len(report["files"]), "preserved_notices": len(report["notices"]), "product_ui_delivered": False}))


if __name__ == "__main__":
    main()
