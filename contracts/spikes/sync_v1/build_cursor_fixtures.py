"""Byte-layout goldens derived independently of either cursor consumer."""
import base64
import copy
import hashlib
import hmac
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/cursor_vectors.json"
KEY_ID = "11111111-1111-4111-8111-111111111111"
A = "22222222-2222-4222-8222-222222222222"
D = "33333333-3333-4333-8333-333333333333"
BOOT = "44444444-4444-4444-8444-444444444444"
KEY = bytes(range(32))  # Public synthetic vector key; never production key material.


def signed_layout(claims, *, magic=b"ECSCUR01", mac_domain=b"ExcellentCalendar.SyncCursor.v1\n"):
    # Independent explicit offset construction; intentionally permits forged
    # but correctly authenticated malformed claims for negative tests.
    raw = bytearray(magic)
    raw.append(0 if claims["kind"] == "sync" else 1)
    for name in ("key_id", "account_id", "device_id"): raw.extend(uuid.UUID(claims[name]).bytes)
    raw.extend(claims["protocol_version"].to_bytes(4, "big"))
    for name in ("account_generation", "snapshot_upper_bound", "position"): raw.extend(claims[name].to_bytes(8, "big"))
    raw.extend(bytes(16) if claims["bootstrap_id"] is None else uuid.UUID(claims["bootstrap_id"]).bytes)
    for name in ("sync_transport_generation", "expires_at_epoch_seconds", "retention_floor_server_sequence", "resolved_cleanup_before_epoch_seconds"):
        raw.extend(claims[name].to_bytes(8, "big"))
    assert len(raw) == 133
    return base64.urlsafe_b64encode(raw + hmac.new(KEY, mac_domain + raw, hashlib.sha256).digest()).decode()


def derive():
    normal = {"kind": "sync", "key_id": KEY_ID, "account_id": A, "device_id": D, "protocol_version": 1,
        "account_generation": 3, "snapshot_upper_bound": 10, "position": 6, "bootstrap_id": None,
        "sync_transport_generation": 0, "expires_at_epoch_seconds": 0, "retention_floor_server_sequence": 2,
        "resolved_cleanup_before_epoch_seconds": 1700000000}
    bootstrap = {**normal, "kind": "bootstrap", "bootstrap_id": BOOT, "position": 1,
                 "sync_transport_generation": 7, "expires_at_epoch_seconds": 1800000000}
    context = {"account_id": A, "device_id": D, "account_generation": 3, "retention_floor_server_sequence": 4,
               "sync_transport_generation": 7, "now_epoch_seconds": 1799999999}
    keys = {KEY_ID: KEY.hex()}
    cases = []

    def add(name, request, expected):
        cases.append({"id": "CURSOR-" + name, "family": "FX-CURSOR", "rule_anchor": "cloud-sync-02/6.3,12",
            "input": {"keys": keys, **request}, "expected": {"output": expected}})
    for name, claims in (("sync", normal), ("bootstrap", bootstrap), ("terminal", {**normal, "position": 10}),
                         ("safe-maximum", {**normal, "snapshot_upper_bound": 9007199254740991, "position": 9007199254740991})):
        token = signed_layout(claims)
        add(name + "-issue", {"action": "issue", "claims": claims}, "SIGNED\t" + token)
        add(name + "-validate", {"action": "validate", "token": token, "context": context}, "VALID")
    normal_token, bootstrap_token = signed_layout(normal), signed_layout(bootstrap)
    for name, patch, code in (("account", {"account_id": BOOT}, "SYNC_CURSOR_ACCOUNT_MISMATCH"),
        ("device", {"device_id": BOOT}, "SYNC_CURSOR_DEVICE_MISMATCH"),
        ("generation", {"account_generation": 4}, "SYNC_CURSOR_GENERATION_MISMATCH"),
        ("retention-expired", {"retention_floor_server_sequence": 7}, "SYNC_CURSOR_EXPIRED")):
        add(name, {"action": "validate", "token": normal_token, "context": {**context, **patch}}, code)
    for name, patch, code in (("bootstrap-generation", {"account_generation": 4}, "SYNC_BOOTSTRAP_GENERATION_CHANGED"),
        ("bootstrap-transport", {"sync_transport_generation": 8}, "SYNC_TRANSPORT_GENERATION_MISMATCH"),
        ("bootstrap-expiry-boundary", {"now_epoch_seconds": 1800000000}, "SYNC_BOOTSTRAP_EXPIRED")):
        add(name, {"action": "validate", "token": bootstrap_token, "context": {**context, **patch}}, code)
    raw = bytearray(base64.urlsafe_b64decode(normal_token)); raw[84] ^= 1
    for name, token in (("tamper", base64.urlsafe_b64encode(raw).decode()), ("padding", normal_token + "="),
        ("truncated", normal_token[:-1]), ("long", normal_token + "AAAA"), ("wrong-domain", signed_layout(normal, mac_domain=b"Different.Protocol\n")),
        ("wrong-magic-valid-mac", signed_layout(normal, magic=b"ECSCUR02")),
        ("unknown-key", signed_layout({**normal, "key_id": BOOT})),
        ("future-position-valid-mac", signed_layout({**normal, "position": 11})),
        ("unsafe-counter-valid-mac", signed_layout({**normal, "snapshot_upper_bound": 9007199254740992})),
        ("protocol-version-valid-mac", signed_layout({**normal, "protocol_version": 2})),
        ("normal-with-bootstrap-identity", signed_layout({**normal, "bootstrap_id": BOOT})),
        ("normal-with-expiry", signed_layout({**normal, "expires_at_epoch_seconds": 1800000000})),
        ("floor-beyond-upper", signed_layout({**normal, "retention_floor_server_sequence": 11}))):
        add(name, {"action": "validate", "token": token, "context": context}, "SYNC_CURSOR_INVALID")
    for name, patch in (("null-account", {"account_id": None}), ("fractional-counter", {"position": 1.5}),
                         ("boolean-counter", {"position": True}), ("unsafe-counter", {"position": 9007199254740992}),
                         ("uppercase-uuid", {"device_id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"})):
        add("issue-" + name, {"action": "issue", "claims": {**normal, **patch}}, "SYNC_CURSOR_INVALID")
    return {"fixture_version": 1, "scope": "Backend opaque binary HMAC cursor; clients treat the token as an uninterpreted string",
            "public_synthetic_key_only": True, "claims": {"normal": normal, "bootstrap": bootstrap}, "cases": cases}


if __name__ == "__main__":
    value = derive(); FIXTURE.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(value["cases"])}))
