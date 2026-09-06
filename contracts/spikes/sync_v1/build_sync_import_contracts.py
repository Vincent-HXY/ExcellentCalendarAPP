"""Generate exact import lifecycle shapes from IMP-01 through IMP-12.

Proof strings are opaque authenticated Backend evidence, never client assertions.
Shapes alone cannot authenticate proofs or establish a source-retirement decision.
"""
import argparse
import copy
import json

from build_sync_protocol_contracts import (CONTRACTS, SAFE, POSITIVE, UUID, UUID4, HASH, BOOL, NULL, OPAQUE,
    DATE_TIME, const, array, nullable, object_of, ref, document)


def derive():
    out = {}

    def emit(name, body, anchor="7.6", directory="sync"):
        out[CONTRACTS / directory / (name + ".schema.json")] = document(name, body, anchor, directory)
        return ref(name, directory)

    transport = {"protocol_version": const(1), "device_id": UUID4, "sync_transport_generation": SAFE}
    binding = {"import_lineage_id": UUID, "import_batch_id": UUID4, "source_workspace_id": UUID4,
        "source_epoch": SAFE, "origin_device_id": UUID4, "origin_sync_transport_generation": SAFE,
        "begin_client_sequence": POSITIVE, "terminal_client_sequence": POSITIVE, "manifest": ref("sync_import_manifest")}
    proof_identity = {**binding, "proof_id": UUID4, "previous_import_revision": SAFE, "resulting_import_revision": POSITIVE,
        "resulting_head_batch_id": UUID4, "issued_at": DATE_TIME, "proof_token": OPAQUE, "proof_hash": HASH,
        "recovery": ref("sync_sequence_recovery_bundle"), "lineage_ever_published": BOOL}
    proof = emit("import_range_close_proof", {"oneOf": [
        object_of({**proof_identity, "kind": const("seen_range_closed"), "sequence_advanced": BOOL,
            "reason": {"enum": ["abandoned", "superseded", "capacity_rejected", "ttl_payload_reclaimed"]},
            "fence_operation_id": NULL}),
        object_of({**proof_identity, "kind": const("never_visible_after_transport_fence"), "sequence_advanced": const(False),
            "reason": {"enum": ["abandoned", "superseded"]}, "fence_operation_id": UUID4,
            "resulting_sync_transport_generation": POSITIVE})]}, "7.6/IMP-07,IMP-08,IMP-12")
    publication = emit("import_publication_evidence", object_of({"import_publish_group_id": UUID4,
        "commit_server_sequence": POSITIVE, "publish_digest": HASH, "mapping_digest": HASH,
        "published_at": DATE_TIME}), "7.6/IMP-04")
    cleanup = emit("guest_import_cleanup_receipt", object_of({"source_workspace_id": UUID4, "source_epoch": SAFE,
        "import_lineage_id": UUID, "through_published_batch_id": UUID4, "through_import_revision": POSITIVE,
        "source_snapshot_hash": HASH, "mapping_digest": HASH, "cleaned_at": DATE_TIME, "receipt_hash": HASH}), "7.6/IMP-09")
    confirmation = emit("import_cleanup_confirm_response", object_of({
        "disposition": {"enum": ["cleanup_confirmed", "already_cleanup_confirmed"]}, "import_lineage_id": UUID,
        "source_workspace_id": UUID4, "source_epoch": SAFE, "resulting_import_revision": POSITIVE,
        "confirmed_through_published_batch_id": UUID4, "confirmed_through_import_revision": POSITIVE,
        "guest_cleanup_receipt_hash": HASH}), "7.6/IMP-09")
    head = object_of({"current_head_batch_id": UUID4, "current_import_revision": POSITIVE})
    stage_fields = {**binding, "predecessor_batch_id": nullable(UUID4), "import_revision": POSITIVE,
        "current_head": head, "expires_at": nullable(DATE_TIME), "server_staged_item_count": SAFE,
        "local_staged_item_count": SAFE, "publication": nullable(publication), "cleanup_receipt": nullable(cleanup),
        "range_close_proof": nullable(proof), "stage": {}, "abandon_status": {}, "reconciliation_status": {}, "resume_disposition": {}}
    stage_rows = {
        "local_staging": (["not_requested", "pending", "unconfirmed"], ["not_required"], ["resume_upload", "close_range_then_successor"]),
        "server_staging": (["not_requested", "pending", "unconfirmed"], ["not_required"], ["resume_upload", "close_range_then_successor"]),
        "repair_required": (["not_requested", "pending", "unconfirmed", "not_applicable"], ["full_successor_required"], ["close_range_then_successor", "create_successor"]),
        "server_confirmed": (["not_applicable"], ["not_required", "full_successor_required"], ["resume_publish"]),
        "publish_applied": (["not_applicable"], ["not_required", "cleanup_recovery_required", "full_successor_required"], ["resume_cleanup", "create_successor"]),
        "cleanup_pending": (["not_applicable"], ["cleanup_recovery_required"], ["resume_cleanup"]),
        "completed": (["not_applicable"], ["not_required"], ["terminal"]),
        "superseded": (["not_applicable"], ["not_required", "full_successor_required"], ["terminal", "create_successor"]),
        "abandoned": (["confirmed"], ["not_required"], ["terminal"]),
    }
    statuses = []
    for stage, (abandon, reconciliation, resume) in stage_rows.items():
        p = {**stage_fields, "disposition": const("found"), "stage": const(stage),
            "abandon_status": {"enum": abandon}, "reconciliation_status": {"enum": reconciliation},
            "resume_disposition": {"enum": resume}}
        if stage in {"local_staging", "server_staging"}:
            p.update(publication=NULL, cleanup_receipt=NULL)
        if stage == "local_staging":
            p["import_revision"] = SAFE
            p["current_head"] = object_of({"current_head_batch_id": UUID4, "current_import_revision": SAFE})
        if stage in {"server_confirmed", "publish_applied", "cleanup_pending", "completed"}:
            p["publication"] = publication
        if stage in {"cleanup_pending", "completed"}:
            p["cleanup_receipt"] = cleanup
        statuses.append(object_of(p))
    empty = object_of({"disposition": const("none"), "stage": NULL, "abandon_status": const("not_applicable"),
        "reconciliation_status": const("not_required"), "resume_disposition": const("none"),
        "import_lineage_id": NULL, "import_batch_id": NULL, "source_epoch": NULL, "current_head": NULL, "import_revision": NULL})
    # Server cannot know local-only counts, apply stages or the guest's cleaned_at.
    # Its terminal evidence is exactly what cleanup-confirm actually persisted.
    server_statuses = []
    for local_shape in statuses:
        if local_shape["properties"]["stage"]["const"] in {"local_staging", "publish_applied", "cleanup_pending"}:
            continue
        fields = copy.deepcopy(local_shape["properties"])
        del fields["local_staged_item_count"]
        del fields["cleanup_receipt"]
        fields["cleanup_confirmation"] = confirmation if fields["stage"]["const"] == "completed" else NULL
        server_statuses.append(object_of(fields))
    status = emit("import_status_response", {"oneOf": [empty, *server_statuses]}, "7.6/IMP-06")
    query = emit("import_status_request", {"oneOf": [
        object_of({**transport, "import_batch_id": UUID4}),
        object_of({**transport, "source_workspace_id": UUID4, "source_epoch": SAFE, "source_snapshot_hash": nullable(HASH)})]}, "7.6/IMP-06")

    takeover = emit("import_takeover_request", object_of({**transport, **binding, "expected_import_revision": POSITIVE,
        "takeover_reason": {"enum": ["local_evidence_lost", "origin_unavailable", "ttl_payload_reclaimed"]}}), "7.6/IMP-07")
    emit("import_takeover_response", {"oneOf": [
        object_of({"disposition": {"enum": ["range_closed", "already_range_closed"]}, "proof": proof, "current_head": head}),
        object_of({"disposition": const("already_confirmed"), "publication": publication, "current_head": head})]}, "7.6/IMP-07")
    emit("import_abandon_request", object_of({**transport, **binding, "predecessor_batch_id": nullable(UUID4),
        "expected_import_revision": SAFE, "reason": {"enum": ["user_cancelled", "privacy_destroy", "capacity_rejected"]}}), "7.6/IMP-08")
    abandon = emit("import_abandon_response", {"oneOf": [
        object_of({"disposition": {"enum": ["abandoned", "already_abandoned"]}, "proof": proof, "sequence_advanced": BOOL, "current_head": head}),
        object_of({"disposition": const("absent_fenced"), "proof": NULL, "sequence_advanced": const(False),
            "absent_batch_fence_id": UUID4, "current_head": nullable(head)}),
        object_of({"disposition": const("already_confirmed"), "publication": publication, "current_head": head})]}, "7.6/IMP-08")
    emit("import_cleanup_confirm_request", object_of({**transport, "import_lineage_id": UUID,
        "source_workspace_id": UUID4, "source_epoch": SAFE, "through_published_batch_id": UUID4,
        "through_import_revision": POSITIVE, "source_snapshot_hash": HASH, "mapping_digest": HASH,
        "guest_cleanup_receipt_hash": HASH, "expected_import_revision": POSITIVE}), "7.6/IMP-09")

    route = {"workspace_id": UUID4, "expected_active_route_revision": SAFE}
    runtime = {"workspace_id": UUID4, "runtime_instance_id": UUID4, "session_generation": SAFE}
    emit("import_accept_range_close_request", object_of({**runtime, "proof": proof}), "7.6/IMP-07", "workspace")
    preview_request = emit("import_preview_request", object_of({**route, "source_workspace_id": UUID4,
        "target_workspace_id": UUID4, "predecessor_lineage_id": nullable(UUID)}), "7.6/IMP-01", "workspace")
    emit("import_preview_response", {"oneOf": [
        object_of({"disposition": const("ready"), "source_workspace_id": UUID4, "target_workspace_id": UUID4,
            "source_epoch": SAFE, "preview_token": OPAQUE, "proposed_import_batch_id": UUID4, "import_lineage_id": UUID,
            "manifest": ref("sync_import_manifest"), "warnings": array({"enum": ["opaque_category_reference", "identity_remapped", "local_execution_history_retained"]}, 3)}),
        object_of({"disposition": const("previous_epoch_cleanup_pending"), "source_workspace_id": UUID4,
            "source_epoch": SAFE, "recovery_handle": OPAQUE})]}, "7.6/IMP-01", "workspace")
    commit_base = {**route, "preview_token": OPAQUE, "import_lineage_id": UUID, "import_batch_id": UUID4,
        "source_workspace_id": UUID4, "source_epoch": SAFE, "expected_import_revision": SAFE,
        "predecessor_batch_id": nullable(UUID4), "takeover_reason": NULL, "range_close_proof_id": NULL}
    emit("native_import_commit_request", {"oneOf": [
        object_of({**commit_base, "expected_import_revision": const(0), "predecessor_batch_id": NULL}),
        object_of({**commit_base, "expected_import_revision": POSITIVE, "predecessor_batch_id": UUID4}),
        object_of({**commit_base, "expected_import_revision": POSITIVE, "predecessor_batch_id": UUID4,
            "takeover_reason": {"enum": ["local_evidence_lost", "origin_unavailable", "ttl_payload_reclaimed"]}, "range_close_proof_id": UUID4})]}, "7.6/IMP-01,IMP-05,IMP-07", "workspace")
    emit("import_commit_request", object_of({**route, "preview_token": OPAQUE, "import_batch_id": UUID4,
        "target_workspace_id": UUID4, "expected_import_revision": SAFE}), "7.6/IMP-01,IMP-05", "workspace")
    emit("native_import_status_request", object_of({**runtime, "query": query, "server_snapshot": nullable(status)}), "7.6/IMP-06", "workspace")
    # A commit receipt authenticates publication identity but carries no server
    # timestamp. Native can therefore represent a not-yet-observed timestamp;
    # the HTTP publication evidence above always requires the server's value.
    native_publication = object_of({"import_publish_group_id": UUID4, "commit_server_sequence": POSITIVE,
        "publish_digest": HASH, "mapping_digest": HASH, "published_at": nullable(DATE_TIME)})
    for shape in statuses:
        stage = shape["properties"]["stage"]["const"]
        if stage in {"server_confirmed", "publish_applied", "cleanup_pending", "completed"}:
            shape["properties"]["publication"] = native_publication
        elif stage not in {"local_staging", "server_staging"}:
            shape["properties"]["publication"] = nullable(native_publication)
    emit("native_import_status_response", {"oneOf": [empty, *statuses]}, "7.6/IMP-06", "workspace")
    emit("import_status_request", object_of({**route, "import_batch_id": nullable(UUID4), "source_workspace_id": UUID4,
        "source_epoch": SAFE, "target_workspace_id": UUID4, "source_snapshot_hash": nullable(HASH)}), "7.6/IMP-06", "workspace")
    public_stages = []
    for private_stage in statuses:
        fields = {name: shape for name, shape in private_stage["properties"].items() if name in {
            "disposition", "stage", "abandon_status", "reconciliation_status", "resume_disposition",
            "import_lineage_id", "import_batch_id", "source_workspace_id", "source_epoch", "predecessor_batch_id",
            "import_revision", "current_head", "expires_at", "server_staged_item_count", "local_staged_item_count"}}
        fields["target_workspace_id"] = UUID4
        public_stages.append(object_of(fields))
    emit("import_status_response", {"oneOf": [empty, *public_stages]}, "7.6/IMP-06", "workspace")
    emit("native_import_abandon_request", object_of({**runtime, "import_lineage_id": UUID, "import_batch_id": UUID4,
        "expected_import_revision": POSITIVE, "server_result": nullable(abandon)}), "7.6/IMP-08", "workspace")
    emit("import_abandon_request", object_of({**route, "import_lineage_id": UUID, "import_batch_id": UUID4,
        "expected_import_revision": POSITIVE}), "7.6/IMP-08", "workspace")
    emit("import_cleanup_confirm_request", object_of({**runtime, "guest_receipt": cleanup, "server_result": confirmation}), "7.6/IMP-09", "workspace")
    release_identity = {"source_workspace_id": UUID4, "source_epoch": SAFE, "import_lineage_id": UUID,
        "protected_owner_binding_digest": HASH, "expected_source_lease_revision": SAFE}
    release_proofs = [
        object_of({"kind": const("prepublish_abandon_range_terminal"), "server_abandon": abandon,
            "terminal_local_range_receipt_hash": HASH}),
        object_of({"kind": const("prepublish_abandon_crypto_destroyed"), "server_abandon": abandon,
            "crypto_destroy_final_receipt_hash": HASH}),
        object_of({"kind": const("cleanup_completed"), "guest_receipt": cleanup,
            "native_completed_receipt_hash": HASH, "server_confirmation": confirmation}),
        object_of({"kind": const("account_deleted"), "owner_bound_account_deleted_proof": OPAQUE,
            "deletion_receipt_hash": HASH}),
    ]
    emit("import_finalize_source_lease_request", object_of({**release_identity, "proof": {"oneOf": release_proofs}}), "7.6/IMP-10", "workspace")
    lease_backup = object_of({"source_workspace_id": UUID4, "source_epoch": SAFE, "lineage_id": UUID,
        "protected_owner_binding_digest": HASH, "source_snapshot_hash": HASH, "reserved_operation_id": UUID4,
        "active_batch_id": UUID4, "active_manifest_hash": HASH, "begin_client_sequence": POSITIVE,
        "terminal_client_sequence": POSITIVE, "state": const("active"), "lease_revision": SAFE})
    lease_backup["x-semantic-rules"] = ["terminal_client_sequence > begin_client_sequence",
        "backup belongs to the same source, epoch, lineage and opaque owner as its reserved successor",
        "restore only after absence of successor account receipt; restore increments the current lease revision"]
    emit("guest_import_source_lease_backup", lease_backup, "7.6/IMP-01,IMP-05;10", "storage")
    out[CONTRACTS / "storage/guest_import_source_lease_backup.schema.json"].update({"x-contract-domain": "calendar_core_storage", "x-contract-version": 6})
    return out


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, value in derive().items():
        if args.check:
            if json.loads(path.read_text(encoding="utf-8")) != value:
                raise ValueError("Import schema drift: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"schemas": len(derive()), "status": "planned_not_frozen"}))


if __name__ == "__main__":
    main()
