#!/usr/bin/env python3
"""Bootstrap isolated Contract verification dependencies and run Calendar View R1."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path


CONTRACTS = Path(__file__).resolve().parent
REQUIREMENTS = CONTRACTS / "requirements-validation.txt"
VALIDATOR = CONTRACTS / "validate_calendar_v1.py"


def main() -> int:
    requirements_text = REQUIREMENTS.read_text(encoding="utf-8")
    fingerprint = hashlib.sha256(requirements_text.encode("utf-8")).hexdigest()
    cache = Path(tempfile.gettempdir()) / (
        f"excellent-calendar-contract-validation-py{sys.version_info.major}{sys.version_info.minor}"
    )
    stamp = cache / ".requirements.sha256"
    if not stamp.is_file() or stamp.read_text(encoding="ascii").strip() != fingerprint:
        cache.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--no-warn-script-location",
                "--upgrade",
                "--target",
                str(cache),
                "--requirement",
                str(REQUIREMENTS),
            ],
            check=True,
        )
        stamp.write_text(fingerprint, encoding="ascii")
    environment = os.environ.copy()
    existing_pythonpath = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = str(cache) + (
        os.pathsep + existing_pythonpath if existing_pythonpath else ""
    )
    return subprocess.run(
        [sys.executable, str(VALIDATOR)], env=environment, check=False
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())

