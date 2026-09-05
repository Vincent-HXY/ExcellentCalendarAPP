#!/usr/bin/env python3
"""Run Sync CT0 checks with the repository's existing isolated validation cache.

Default exits 2 until full freeze evidence/validation is implemented. Use
--stage ct0 explicitly for the limited pre-freeze audit.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CONTRACTS = Path(__file__).resolve().parent


def main() -> int:
    requirements = CONTRACTS / "requirements-validation.txt"
    fingerprint = hashlib.sha256(requirements.read_text(encoding="utf-8").encode()).hexdigest()
    cache = Path(tempfile.gettempdir()) / f"excellent-calendar-contract-validation-py{sys.version_info.major}{sys.version_info.minor}"
    stamp = cache / ".requirements.sha256"
    if not stamp.is_file() or stamp.read_text(encoding="ascii").strip() != fingerprint:
        cache.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
                        "--no-warn-script-location", "--upgrade", "--target", str(cache),
                        "--requirement", str(requirements)], check=True)
        stamp.write_text(fingerprint, encoding="ascii")
    environment = os.environ.copy()
    environment["PYTHONPATH"] = str(cache) + (os.pathsep + environment["PYTHONPATH"] if environment.get("PYTHONPATH") else "")
    return subprocess.run([sys.executable, str(CONTRACTS / "validate_sync_v1.py"), *sys.argv[1:]],
                          env=environment, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
