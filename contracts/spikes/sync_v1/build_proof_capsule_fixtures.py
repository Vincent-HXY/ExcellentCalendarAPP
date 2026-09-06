"""Reproducible capsule mutations over fixed public signed seeds.

--generate-seeds is an explicit one-shot maintenance step. It creates ephemeral
JDK keys in memory; no private key is returned, committed, logged or persisted.
Ordinary validation only consumes the committed public evidence.
"""
import argparse
import base64
import copy
import json
from pathlib import Path
import subprocess
import tempfile

from protocol_reference import canonical, digest
from identity_reference import lineage_id
from build_target_fixtures import build as target_examples
from import_contract_reference import make_manifest

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parents[1] / "fixtures/sync/v1"
A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"
C = "33333333-3333-4333-8333-333333333333"
D = "44444444-4444-4444-8444-444444444444"
E = "55555555-5555-4555-8555-555555555555"
MAXIMUM = 9007199254740991


def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def recovery(generation=1, highest=0):
    return {"sync_transport_generation": generation, "highest_client_sequence": highest,
            "next_client_sequence": None if highest == MAXIMUM else highest + 1,
            "client_confirmed_through": 0, "client_sequence_exhausted": highest == MAXIMUM}


def templates():
    fence = {"protocol_version": 1, "device_id": B, "fence_operation_id": C,
             "previous_sync_transport_generation": 0, "recovery": recovery(), "resolved_absent_import_fences": []}
    event = target_examples()["samples"]["event"]
    item = {"target_type": "event", "target_id": event["target_id"], "operation_type": "import_put",
        "payload": {"source_id": event["target_id"], "fact": event["fact"]}}
    manifest = make_manifest(D, 0, digest([event]), [item])
    seen = {"import_lineage_id": lineage_id(A, D, 0), "import_batch_id": C, "source_workspace_id": D, "source_epoch": 0,
            "origin_device_id": B, "origin_sync_transport_generation": 0, "begin_client_sequence": 1, "terminal_client_sequence": 3,
            "manifest": manifest, "proof_id": E, "previous_import_revision": 0, "resulting_import_revision": 1,
            "resulting_head_batch_id": C, "issued_at": "2026-09-05T01:00:00Z", "recovery": recovery(0, 3),
            "kind": "seen_range_closed", "sequence_advanced": True, "reason": "abandoned", "fence_operation_id": None,
            "lineage_ever_published": False}
    never = {**seen, "kind": "never_visible_after_transport_fence", "sequence_advanced": False, "reason": "abandoned",
             "fence_operation_id": C, "resulting_sync_transport_generation": 1, "recovery": recovery()}
    values = [("fence", "device_fence", fence, 0), ("fence-max", "device_fence", {**fence, "recovery": recovery(1, MAXIMUM)}, 0),
              ("range-seen", "import_range_close", seen, 0), ("range-never", "import_range_close", never, 0),
              ("range-published-lineage", "import_range_close", {**seen, "lineage_ever_published": True}, 0),
              ("deleted", "account_deleted", {"account_id": A, "state": "deleted"}, 0),
              ("rotated", "device_fence", fence, 1)]
    # Sign malformed domain claims too: a valid RSA signature never excuses a
    # broken schema, allocator bundle, lineage identity or adjacent revision.
    values.extend((name, purpose, data, 0) for name, purpose, data in [
        ("bad-fence-generation", "device_fence", {**fence, "recovery": recovery(2)}),
        ("bad-fence-next", "device_fence", {**fence, "recovery": {**recovery(), "next_client_sequence": 8}}),
        ("bad-fence-field", "device_fence", {**fence, "future_field": True}),
        ("bad-range-lineage", "import_range_close", {**seen, "import_lineage_id": A}),
        ("bad-range-revision", "import_range_close", {**seen, "resulting_import_revision": 4}),
        ("bad-range-reservation", "import_range_close", {**seen, "terminal_client_sequence": 2}),
        ("bad-range-highest", "import_range_close", {**seen, "recovery": recovery(0, 2)}),
        ("bad-range-manifest", "import_range_close", {**seen, "manifest": {**manifest, "source_epoch": 1}}),
        ("bad-range-publication-type", "import_range_close", {**seen, "lineage_ever_published": "false"}),
        ("bad-range-missing-publication", "import_range_close", {key: value for key, value in seen.items() if key != "lineage_ever_published"}),
        ("bad-never-advance", "import_range_close", {**never, "sequence_advanced": True}),
        ("bad-deleted-state", "account_deleted", {"account_id": A, "state": "active"}),
    ])
    out = [{"id": name, "purpose": purpose, "account_id": A, "data": data, "key_slot": slot} for name, purpose, data, slot in values]
    for name, patch in (("version", {"proof_version": 2}), ("algorithm", {"algorithm": "none"}),
                        ("extra", {"key_url": "https://invalid.example/never-fetched"}), ("boolean-version", {"proof_version": True})):
        out.append({**out[0], "id": "bad-capsule-" + name, "claims_override": patch})
    return out


def generate_seeds():
    scratch = Path(tempfile.mkdtemp(prefix="excellent-calendar-public-proof-golden-"))
    jdk = Path("A:/Android/AndroidStudio/jbr/bin")
    subprocess.run([str(jdk / "javac.exe"), "-encoding", "UTF-8", "-d", str(scratch),
                    str(HERE / "JcsProbe.java"), str(HERE / "ProofSignatureProbe.java"), str(HERE / "ProofCapsuleProbe.java")], check=True)
    items = templates()
    completed = subprocess.run([str(jdk / "java.exe"), "-cp", str(scratch), "ProofCapsuleProbe", "--generate-public-golden"],
        input="\n".join(canonical(value).decode() for value in items) + "\n", capture_output=True, encoding="utf-8", check=True)
    lines = [json.loads(line) for line in completed.stdout.splitlines()]
    if len(lines) != len(items) + 1 or [line["id"] for line in lines[1:]] != [item["id"] for item in items]:
        raise ValueError("signer coverage")
    value = {"fixture_version": 1, "private_key_persisted": False, "keys": lines[0]["keys"], "signed": lines[1:]}
    (FIXTURES / "proof_capsule_seeds.json").write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def trust(keys):
    value = {"schema_version": 1, "keys": sorted(copy.deepcopy(keys), key=lambda key: key["key_id"])}
    return {**value, "trust_store_id": digest(value)}


def derive():
    seeds = json.loads((FIXTURES / "proof_capsule_seeds.json").read_text(encoding="utf-8"))
    signed = {item["id"]: item for item in seeds["signed"]}
    cases = []
    def emit(name, value, valid=True, domain_valid=None):
        cases.append({"id": "FX-PROOF-" + name, "family": "FX-IMPORT-RANGE", "rule_anchor": "cloud-sync-02/6.1,7.6/IMP-07,IMP-09,IMP-12",
            "input": copy.deepcopy(value), "expected": {"authenticated": valid, "typed_domain_valid": valid if domain_valid is None else domain_valid}})
    for item in templates():
        value = {"trust_store": trust(seeds["keys"]), "locally_revoked_keys": [], "token": signed[item["id"]]["token"],
                 "expected_account_id": A, "expected_purpose": item["purpose"], "claim_data": item["data"], "claimed_hash": signed[item["id"]]["claimed_hash"]}
        emit(item["id"], value, not item["id"].startswith("bad-capsule"), not item["id"].startswith("bad-"))
    base = cases[0]["input"]
    published = next(case["input"] for case in cases if case["id"] == "FX-PROOF-range-published-lineage")
    emit("tampered-publication-history", {**published, "claim_data": {**published["claim_data"], "lineage_ever_published": False}}, False)
    for name, patch in (("wrong-account", {"expected_account_id": B}), ("wrong-purpose", {"expected_purpose": "account_deleted"}),
                        ("unknown-purpose", {"expected_purpose": "future"}), ("wrong-hash", {"claimed_hash": "0" * 64}),
                        ("padded-token", {"token": base["token"] + "="}), ("oversize-token", {"token": "A" * 2049}),
                        ("bad-account", {"expected_account_id": A.upper().replace("1111", "zzzz", 1)}),
                        ("tampered-generation", {"claim_data": {**base["claim_data"], "previous_sync_transport_generation": 1}}),
                        ("forged-key-url", {"key_url": "https://invalid.example/never-fetched"})):
        emit(name, {**base, **patch}, False)
    raw = base64.urlsafe_b64decode(base["token"] + "=" * (-len(base["token"]) % 4))
    capsule = json.loads(raw)
    emit("noncanonical-capsule", {**base, "token": b64(json.dumps(capsule, indent=1).encode())}, False)
    emit("duplicate-capsule-field", {**base, "token": b64(raw[:-1] + b',"signature":"' + capsule["signature"].encode() + b'"}')}, False)
    emit("bad-utf8", {**base, "token": b64(raw.replace(b"rsa_pss_sha256", b"rsa_pss_\xffha256"))}, False)
    emit("surrogate", {**base, "token": b64(raw.replace(b"rsa_pss_sha256", b"rsa_pss_\\ud800"))}, False)
    changed = copy.deepcopy(capsule); changed["signature"] = "A" * 342
    emit("bad-signature", {**base, "token": b64(canonical(changed))}, False)
    changed = copy.deepcopy(capsule); changed["signature"] += "="
    emit("padded-signature", {**base, "token": b64(canonical(changed))}, False)
    changed = copy.deepcopy(capsule)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    changed["signature"] = changed["signature"][:-1] + alphabet[alphabet.index(changed["signature"][-1]) + 1]
    emit("signature-unused-bits", {**base, "token": b64(canonical(changed))}, False)
    key_id = capsule["claims"]["key_id"]
    emit("persisted-revocation", {**base, "locally_revoked_keys": [key_id]}, False)
    emit("duplicate-persisted-revocation", {**base, "locally_revoked_keys": [key_id, key_id]}, False)
    only_other = [key for key in seeds["keys"] if key["key_id"] != key_id]
    emit("unknown-key", {**base, "trust_store": trust(only_other)}, False)
    emit("rotated-old-remains-valid", {**base, "trust_store": trust(seeds["keys"])})
    revoked = [{**key, "verification_status": "revoked"} if key["key_id"] == key_id else key for key in seeds["keys"]]
    emit("revoked-key", {**base, "trust_store": trust(revoked)}, False)
    malformed_keys = copy.deepcopy(seeds["keys"]); malformed_keys[0]["modulus_hex"] = "f" * 512
    emit("key-id-mismatch", {**base, "trust_store": trust(malformed_keys)}, False)
    emit("duplicate-trust-key", {**base, "trust_store": trust(seeds["keys"] + [seeds["keys"][0]])}, False)
    wrong_store = trust(seeds["keys"]); wrong_store["trust_store_id"] = "0" * 64
    emit("trust-content-address", {**base, "trust_store": wrong_store}, False)
    wrong_store = trust(seeds["keys"]); wrong_store["keys"].reverse()
    wrong_store["trust_store_id"] = digest({key: value for key, value in wrong_store.items() if key != "trust_store_id"})
    emit("trust-key-order", {**base, "trust_store": wrong_store}, False)
    return {"fixture_version": 1, "scope": "Actual signature authentication plus separately checked typed claims; no production data or keys", "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__); parser.add_argument("--generate-seeds", action="store_true"); parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.generate_seeds:
        if args.check: raise ValueError("cannot regenerate while checking")
        generate_seeds()
    value = derive(); path = FIXTURES / "proof_capsule_vectors.json"
    if args.check:
        if json.loads(path.read_text(encoding="utf-8")) != value: raise ValueError("capsule fixture drift")
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Public capsule cases:", len(value["cases"]))
