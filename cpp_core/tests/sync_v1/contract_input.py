"""Read-only Plan 03 inputs. Test fixtures are not a production sync provider."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "contracts/fixtures/sync/v1"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def text_hash(path: Path) -> str:
    # Same newline-normalized UTF-8 domain as the frozen Contract validator.
    return hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest()


def source_drift() -> list[dict[str, str]]:
    lock = read_json(ROOT / "contracts/sync/sync_v1_revision_lock.json")
    differences = []
    for relative, expected in lock["sources_sha256"].items():
        path = ROOT / relative
        actual = text_hash(path) if path.is_file() else "MISSING"
        if actual != expected:
            differences.append({"path": relative, "expected": expected, "actual": actual})
    return differences


class FrozenFixtureInputs:
    """Copies authoritative test data; implements no Backend or Core rules.

    A test can retain a returned response to inject delayed delivery, mutate its
    copy for a negative case, or replay it after reopening the real Core. This
    class cannot acknowledge an upload, advance a cursor, or write business data.
    """

    def __init__(self):
        self.manifest = read_json(FIXTURES / "manifest.json")
        self._entries = {entry["id"]: entry for entry in self.manifest["cases"]}
        if len(self._entries) != len(self.manifest["cases"]):
            raise ValueError("duplicate fixture identity")
        self._files = {}

    def case(self, identity: str) -> dict:
        entry = self._entries[identity]  # Unknown identities must fail loudly.
        name = entry["input_file"]
        path = (FIXTURES / name).resolve()
        if not path.is_relative_to(FIXTURES.resolve()):
            raise ValueError("fixture path escapes fixture directory")
        if name not in self._files:
            self._files[name] = read_json(path)
        value = self._files[name]
        for token in entry["case_pointer"].split("/")[1:]:
            token = token.replace("~1", "/").replace("~0", "~")
            value = value[int(token)] if isinstance(value, list) else value[token]
        return copy.deepcopy(value)

    def identities(self):
        return tuple(self._entries)
