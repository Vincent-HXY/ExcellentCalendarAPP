"""Authenticated receipt capsule format, separate from JCS hashes and DB keys."""
import argparse
import json

from build_sync_domain_contracts import CONTRACTS, yaml
from build_sync_protocol_contracts import HASH, UUID4, SAFE, const, object_of, array, ref, document


def derive():
    out = {}
    def emit(name, body):
        value = document(name, body, "6.1,7.6,8.3", "sync/proof")
        value.update({"x-contract-domain": "sync_proof", "x-contract-version": 1,
            "x-exposure": "backend_and_kotlin_jni_cpp_only_never_flutter_event_or_diagnostics"})
        out[CONTRACTS / "sync/proof" / (name + ".schema.json")] = value
        return ref(name, "sync/proof")
    claims = emit("signed_proof_claims", object_of({"proof_version": const(1), "algorithm": const("rsa_pss_sha256"),
        "key_id": HASH, "account_id": UUID4, "purpose": {"enum": ["device_fence", "import_range_close", "account_deleted"]},
        "claims_sha256": HASH}))
    emit("signed_proof_capsule", object_of({"claims": claims,
        "signature": {"type": "string", "minLength": 342, "maxLength": 342, "pattern": "^[A-Za-z0-9_-]{341}[AQgw]$"}}))
    emit("account_deleted_claim_data", object_of({"account_id": UUID4, "state": const("deleted")}))
    emit("proof_trust_store", object_of({"schema_version": const(1), "trust_store_id": HASH,
        "keys": array(object_of({"key_id": HASH, "algorithm": const("rsa_pss_sha256"), "exponent": const(65537),
            "modulus_hex": {"type": "string", "pattern": "^[89a-f][0-9a-f]{511}$"},
            "verification_status": {"enum": ["trusted", "revoked"]}}), 32, 1)}))
    revocations = emit("proof_key_revocation_record", object_of({"schema_version": const(1),
        "installation_id": UUID4, "revoked_key_ids": {**array(HASH, 4096), "uniqueItems": True}}))
    out[CONTRACTS / "sync/proof/proof_key_revocation_record.schema.json"].update({"x-owner": "kotlin_installation_private_registry",
        "x-lifecycle": "monotone set union in the same installation; retained through account clear/logout; excluded from backup and D2D"})
    out[CONTRACTS / "sync/sync_proof_protocol.yaml"] = {
        "version": 1, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/6.1,7.6,8.3",
        "capsule_schema": "sync/proof/signed_proof_capsule.schema.json", "trust_store_schema": "sync/proof/proof_trust_store.schema.json",
        "algorithm": {"name": "rsa_pss_sha256", "rsa_modulus_bits": 2048, "public_exponent": 65537,
            "message_digest": "SHA-256", "mask": "MGF1", "mask_digest": "SHA-256", "salt_bytes": 32, "trailer_field": 1,
            "parameters": "fixed; reject provider defaults, SHA-1 MGF, alternative salt lengths, PKCS1v1.5 and algorithm negotiation"},
        "encoding": {"token": "canonical unpadded base64url of UTF-8 JCS(capsule); decoded bytes must exactly equal recanonicalized capsule",
            "max_token_ascii_bytes": 2048, "signature": "canonical unpadded base64url of exactly 256 raw RSA-PSS bytes",
            "signed_message": "UTF8('ExcellentCalendar.SyncProof.v1\\n') followed by JCS(capsule.claims)",
            "signed_message_prefix_utf8_hex": b"ExcellentCalendar.SyncProof.v1\n".hex(),
            "claims_hash": "lowercase SHA-256 of JCS(the exact typed claim data defined below)",
            "key_id": "lowercase SHA-256 of UTF8('ExcellentCalendar.RSAKey.v1\\n') followed by 01 00 01 then the exact 256 unsigned big-endian modulus bytes",
            "key_id_prefix_utf8_hex": b"ExcellentCalendar.RSAKey.v1\n".hex(),
            "json_guards": "strict UTF-8, duplicate-key rejection, exact keys/types, no non-finite numbers or unsupported versions before signature verification"},
        "purposes": {
            "device_fence": {"wire_schema": "sync/sync_device_fence_response.schema.json", "token_field": "fence_receipt", "hash_field": "result_hash",
                "claim_data": "exact complete typed fence response with only fence_receipt and result_hash removed",
                "additional_checks": "Principal-derived expected account; original operation/old generation; resulting generation is checked old+1; full recovery/absent-range proof identities; persist exact receipt before destructive lifecycle step"},
            "import_range_close": {"wire_schema": "sync/import_range_close_proof.schema.json", "token_field": "proof_token", "hash_field": "proof_hash",
                "claim_data": "exact complete typed range proof with only proof_token and proof_hash removed",
                "manifest_hash": "authenticated original declaration; never recompute from metadata alone because ordered item hashes are unavailable for absent/partial batches",
                "additional_checks": "expected account and recomputed lineage; manifest/source epoch/origin/range/reason/revision; current durable reservation or never-visible fenced branch; signature alone never advances an allocator"},
            "account_deleted": {"wire_schema": "workspace/import_finalize_source_lease_request.schema.json", "token_field": "proof.owner_bound_account_deleted_proof", "hash_field": "proof.deletion_receipt_hash",
                "claim_data": "sync/proof/account_deleted_claim_data.schema.json, reconstructed from the authenticated expected owner account and constant deleted state",
                "additional_checks": "Backend signs only after authoritative terminal account deletion; matching opaque guest lease owner required; ordinary auth failure/device revoke cannot manufacture this proof",
                "producer": "planned Backend account-deletion terminal evidence hook; unavailable without authenticated signed evidence"}},
        "ownership": {"signing": "Backend only; private key never enters HTTP, APK, fixture, logs or database-key seed",
            "cpp": "strict capsule and domain claims validation, pinned key selection, exact account/purpose/hash/range/CAS check and atomic receipt acceptance",
            "windows_primitive": "existing Windows CNG BCryptVerifySignature BCRYPT_PAD_PSS with explicit SHA256 and salt length 32",
            "android_primitive": "narrow synchronous JNI crypto port to existing java.security.Signature SHA256withRSA/PSS (API 23+), explicit PSSParameterSpec; no network, key discovery or domain decisions",
            "java_primitive": "existing JDK RSASSA-PSS with explicit SHA-256/MGF1-SHA256/salt32/trailer1",
            "unavailable_provider": "fail closed; never replace signature verification with a boolean from HTTP or a hash comparison"},
        "trust_and_rotation": {"origin": "read-only trust store shipped with the same verified APK; never accept keys or URLs supplied by a proof",
            "native_injection": "immutable trust asset plus installation-bound durable revocation set supplied by the private platform crypto port at runtime construction; no HTTP/MethodChannel method accepts a trust store",
            "revocation_record_schema": revocations["$ref"],
            "revocation_update": "verified installed APK contributes a sorted monotone union before enabling proof acceptance; duplicate/unknown shape/over-capacity fails closed without pruning; installation mismatch rejects restored state",
            "trust_store_id": "content address: lowercase SHA-256 of JCS({schema_version, keys}); keys sorted by key_id, no duplicates; not an allocated counter",
            "duplicate_key_id": "reject", "key_id_check": "recompute from exact exponent/modulus and reject mismatch", "unknown_or_revoked_key": "reject before any mutation or deletion",
            "rollout": "ship new verification key before Backend signs with it; preserve old trusted verification keys while durable pending proof dependencies exist and within N-1 support",
            "revocation": "a signed APK/trust-store revision can mark compromised keys revoked; old evidence then cannot authorize a new acceptance; obtain new Backend evidence or remain blocked",
            "receipts": "replay returns original capsule bytes from the idempotency receipt; signing randomized PSS again is not a new receipt",
            "clock": "proof authenticates a durable result, not current time; issuer timestamp never substitutes for generation/revision/operation identity",
            "rollback": "within a supported same-installation rollback, an older trust asset cannot erase the persisted union; the old release must understand this record or refuse proof-dependent lifecycle work; uninstall is a new installation, not a supported rollback",
            "accepted_receipt_read": "previously accepted receipts remain readable transaction evidence; a revoked key cannot authorize a new acceptance or a new destructive action"},
        "evidence": {"primitive_report": "spikes/sync_v1/proof_signature_spike_result.json",
            "capsule_and_domain_evidence": "spikes/sync_v1/proof_capsule_spike_result.json",
            "limitations": "isolated acceptance oracle only; full import saga, Android revocation persistence and authoritative account-deletion producer remain unverified", "production_activated": False},
        "primary_sources": ["https://www.rfc-editor.org/rfc/rfc8017.html", "https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptverifysignature",
            "https://developer.android.com/reference/java/security/Signature", "https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/spec/PSSParameterSpec.html"]}
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            assert actual == value, str(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(value, allow_unicode=True, sort_keys=False) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Proof v1 capsule/trust definitions generated; full acceptance evidence pending")
