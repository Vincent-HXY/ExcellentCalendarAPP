"""Seal a reviewed Contract revision after all required evidence checks pass.

This records an automated engineering acceptance under the user's authorization,
not a human signature or an assertion that downstream product owners exist.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACTS = ROOT / "contracts"
GATE = CONTRACTS / "sync/ct0_gate_status.json"
LOCK = CONTRACTS / "sync/sync_v1_revision_lock.json"
EXCLUDED = {GATE, LOCK}


def sha(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def revision():
    paths = [path for path in CONTRACTS.rglob("*") if path.is_file() and path not in EXCLUDED and
        path.suffix in {".json", ".yaml", ".sql", ".py"} and not any(part in {"spikes", "tests", "__pycache__"} for part in path.relative_to(CONTRACTS).parts)]
    hashes = {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(paths)}
    encoded = json.dumps(hashes, sort_keys=True, separators=(",", ":")).encode()
    return hashes, hashlib.sha256(encoded).hexdigest()


def validate_lock(lock):
    hashes, digest = revision()
    assert lock["revision"] == "cloud-sync-v1-contracts-2026-09-06", "Contract revision identity differs"
    assert lock["contract_sha256"] == digest and lock["sources_sha256"] == hashes, "Contract revision lock is stale"
    manifest = CONTRACTS / "fixtures/sync/v1/manifest.json"
    assert lock["fixture_manifest_sha256"] == sha(manifest), "Fixture manifest lock differs"
    assert set(lock["consumers"]) == {"03_cpp_sqlite", "04_cloud_backend", "05_kotlin_android", "06_flutter"}, "Downstream revision lock is incomplete"
    expected = {"03_cpp_sqlite": "cpp_windows", "04_cloud_backend": "java21", "05_kotlin_android": "kotlin_jvm_2_2_20", "06_flutter": "dart"}
    report_path = CONTRACTS / "spikes/sync_v1/cross_language_schema_spike_result.json"
    report = json.loads(report_path.read_text(encoding="utf8"))
    assert report["passed"] and report["all_fixed_fixture_transport_verified"], "Four-language fixture evidence missing"
    for owner, name in expected.items():
        consumer = lock["consumers"][owner]
        assert consumer == {"contract_sha256": digest, "fixture_manifest_sha256": sha(manifest), "parser": name,
            "parser_evidence_sha256": sha(report_path), "result_sha256": report["consumers"][name]["output_sha256"],
            "implementation_status": "planned", "release_status": "planned"}, "Consumer revision/evidence mismatch: " + owner
    assert lock["acceptance"] == {"reviewer": "Codex", "kind": "automated_engineering_review",
        "authority": "User explicitly authorized Plan 02 development and autonomous reversible Contract decisions; encryption and Native v3 directions were explicitly accepted",
        "accepted_contract_sha256": digest, "production_integration_claimed": False}, "Engineering acceptance is missing or overstated"


def seal():
    from validate_sync_v1 import validate_audit
    gates = json.loads(GATE.read_text(encoding="utf8"))
    assert all(gate["id"] == "CT0-CONCURRENT-APPEARANCE" for gate in gates["open_gates"]), "Unresolved Contract design gate cannot be moved into integration notes"
    # Report hashes are refreshed only as indexes; validate_audit below checks
    # each actual result and its unchanged source hashes before sealing anything.
    for name in ("import_saga", "import_capacity", "cross_language_schema", "client_recovery"):
        gates["evidence"]["contracts/spikes/sync_v1/" + name + "_spike_result.json"] = ""
    gates["evidence"] = {name: sha(ROOT / name) for name in gates["evidence"]}
    GATE.write_text(json.dumps(gates, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    validate_audit()
    hashes, digest = revision()
    manifest = CONTRACTS / "fixtures/sync/v1/manifest.json"
    report_path = CONTRACTS / "spikes/sync_v1/cross_language_schema_spike_result.json"
    report = json.loads(report_path.read_text(encoding="utf8"))
    lock = {"revision": "cloud-sync-v1-contracts-2026-09-06", "contract_sha256": digest,
        "fixture_manifest_sha256": sha(manifest), "sources_sha256": hashes, "consumers": {},
        "acceptance": {"reviewer": "Codex", "kind": "automated_engineering_review",
            "authority": "User explicitly authorized Plan 02 development and autonomous reversible Contract decisions; encryption and Native v3 directions were explicitly accepted",
            "accepted_contract_sha256": digest, "production_integration_claimed": False}}
    for owner, name in {"03_cpp_sqlite": "cpp_windows", "04_cloud_backend": "java21", "05_kotlin_android": "kotlin_jvm_2_2_20", "06_flutter": "dart"}.items():
        lock["consumers"][owner] = {"contract_sha256": digest, "fixture_manifest_sha256": sha(manifest), "parser": name,
            "parser_evidence_sha256": sha(report_path), "result_sha256": report["consumers"][name]["output_sha256"],
            "implementation_status": "planned", "release_status": "planned"}
    validate_lock(lock)
    LOCK.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    gates.update(contract_status="CONTRACT FROZEN", implementation_allowed=True,
        stages={"CT" + str(n): "passed" for n in range(5)}, revision_lock="contracts/sync/sync_v1_revision_lock.json")
    gates["integration_notes"] = gates.pop("integration_notes", []) + gates["open_gates"]
    gates["open_gates"] = []
    gates["freeze_scope"] = "Plan 02 design and machine Contract only. All new product capabilities remain planned; the separate font worktree is not included in this revision."
    GATE.write_text(json.dumps(gates, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"status": "CONTRACT FROZEN", "revision": lock["revision"], "sha256": digest, "files": len(hashes)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--seal", action="store_true")
    args = parser.parse_args()
    if args.seal:
        seal()
    else:
        validate_lock(json.loads(LOCK.read_text(encoding="utf8")))
        print("Contract revision lock passed")
