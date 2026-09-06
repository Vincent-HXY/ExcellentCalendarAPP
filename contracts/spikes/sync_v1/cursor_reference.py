"""Backend-only opaque cursor Contract candidate; clients never decode this format."""
import base64
import hashlib
import hmac
import re
import struct
import uuid

from counter_reference import integer
from domain_reference import check
from identity_reference import canonical_uuid

MAGIC = b"ECSCUR01"
DOMAIN = b"ExcellentCalendar.SyncCursor.v1\n"
STRUCT = struct.Struct(">8sB16s16s16sIQQQ16sQQQQ")
FIELDS = ("kind", "key_id", "account_id", "device_id", "protocol_version", "account_generation", "snapshot_upper_bound",
          "position", "bootstrap_id", "sync_transport_generation", "expires_at_epoch_seconds", "retention_floor_server_sequence",
          "resolved_cleanup_before_epoch_seconds")


def _check_claims(claims):
    check(set(claims) == set(FIELDS), "SYNC_CURSOR_INVALID")
    check(claims["kind"] in {"sync", "bootstrap"} and integer(claims["protocol_version"]) == 1,
          "SYNC_CURSOR_INVALID")
    for name in ("key_id", "account_id", "device_id"):
        canonical_uuid(claims[name], 4 if name != "account_id" else None)
    for name in FIELDS[5:8] + FIELDS[9:]: integer(claims[name])
    check(claims["retention_floor_server_sequence"] <= claims["snapshot_upper_bound"], "SYNC_CURSOR_INVALID")
    if claims["kind"] == "sync":
        check(claims["bootstrap_id"] is None and claims["sync_transport_generation"] == 0 and
              claims["expires_at_epoch_seconds"] == 0 and claims["position"] <= claims["snapshot_upper_bound"], "SYNC_CURSOR_INVALID")
    else:
        canonical_uuid(claims["bootstrap_id"], 4)
        check(claims["expires_at_epoch_seconds"] > 0, "SYNC_CURSOR_INVALID")


def check_claims(claims):
    try:
        _check_claims(claims)
    except (ValueError, TypeError, KeyError):
        raise ValueError("SYNC_CURSOR_INVALID") from None


def encode_claims(claims):
    check_claims(claims)
    return STRUCT.pack(MAGIC, int(claims["kind"] == "bootstrap"),
        *[uuid.UUID(claims[name]).bytes for name in FIELDS[1:4]], claims["protocol_version"],
        *[integer(claims[name]) for name in FIELDS[5:8]],
        bytes(16) if claims["bootstrap_id"] is None else uuid.UUID(claims["bootstrap_id"]).bytes,
        *[integer(claims[name]) for name in FIELDS[9:]])


class CursorCodec:
    def __init__(self, keys):
        self.keys = dict(keys)
        for identifier, value in self.keys.items():
            canonical_uuid(identifier, 4)
            check(type(value) is bytes and len(value) == 32, "SYNC_CURSOR_INVALID")

    def issue(self, claims):
        raw = encode_claims(claims)
        check(claims["key_id"] in self.keys, "SYNC_CURSOR_INVALID")
        mac = hmac.new(self.keys[claims["key_id"]], DOMAIN + raw, hashlib.sha256).digest()
        return base64.urlsafe_b64encode(raw + mac).decode("ascii").rstrip("=")

    def authenticate(self, token):
        try:
            check(isinstance(token, str) and re.fullmatch(r"[A-Za-z0-9_-]{220}", token) is not None, "SYNC_CURSOR_INVALID")
            data = base64.b64decode(token, altchars=b"-_", validate=True)
            check(len(data) == STRUCT.size + 32 and base64.urlsafe_b64encode(data).decode("ascii") == token, "SYNC_CURSOR_INVALID")
            values = STRUCT.unpack(data[:-32])
            identifier = str(uuid.UUID(bytes=values[2]))
            check(identifier in self.keys and hmac.compare_digest(data[-32:],
                hmac.new(self.keys[identifier], DOMAIN + data[:-32], hashlib.sha256).digest()), "SYNC_CURSOR_INVALID")
            check(values[0] == MAGIC and values[1] in {0, 1}, "SYNC_CURSOR_INVALID")
            claims = dict(zip(FIELDS, ["bootstrap" if values[1] else "sync",
                *[str(uuid.UUID(bytes=value)) for value in values[2:5]], *values[5:9],
                None if values[9] == bytes(16) else str(uuid.UUID(bytes=values[9])), *values[10:]]))
            check_claims(claims)
            return claims
        except (ValueError, TypeError, KeyError, struct.error):
            raise ValueError("SYNC_CURSOR_INVALID") from None

    def validate(self, token, *, account_id, device_id, account_generation, retention_floor_server_sequence,
                 sync_transport_generation, now_epoch_seconds):
        claims = self.authenticate(token)
        check(claims["account_id"] == account_id, "SYNC_CURSOR_ACCOUNT_MISMATCH")
        check(claims["device_id"] == device_id, "SYNC_CURSOR_DEVICE_MISMATCH")
        bootstrap = claims["kind"] == "bootstrap"
        check(claims["account_generation"] == integer(account_generation),
              "SYNC_BOOTSTRAP_GENERATION_CHANGED" if bootstrap else "SYNC_CURSOR_GENERATION_MISMATCH")
        if bootstrap:
            check(claims["sync_transport_generation"] == integer(sync_transport_generation), "SYNC_TRANSPORT_GENERATION_MISMATCH")
            check(integer(now_epoch_seconds) < claims["expires_at_epoch_seconds"], "SYNC_BOOTSTRAP_EXPIRED")
        else:
            check(claims["position"] >= integer(retention_floor_server_sequence), "SYNC_CURSOR_EXPIRED")
        return claims


class KeyRetirementLedger:
    """Pure eligibility model; production key usage must be durably stored by Backend."""
    def __init__(self): self.issued = []

    def record(self, claims):
        check_claims(claims); self.issued.append(dict(claims))

    def can_retire(self, key_id, watermarks, now_epoch_seconds):
        integer(now_epoch_seconds)
        for claims in self.issued:
            if claims["key_id"] != key_id: continue
            current = watermarks.get(claims["account_id"])
            if current is None: return False
            generation, floor = map(integer, current)
            covered = generation > claims["account_generation"] or generation == claims["account_generation"] and floor > claims["snapshot_upper_bound"]
            if not covered or claims["kind"] == "bootstrap" and now_epoch_seconds < claims["expires_at_epoch_seconds"]: return False
        return True
