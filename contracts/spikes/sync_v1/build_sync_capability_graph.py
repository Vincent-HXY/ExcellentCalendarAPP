"""Map every planned public capability to explicit local/JNI/HTTP owners.

Legacy definitions stay in their original registries. This graph describes the
same-APK v3 transition and is never used as evidence of a production handler.
"""
import argparse
import copy
import json
from urllib.parse import urljoin

from build_sync_domain_contracts import CONTRACTS, BASE, yaml
from build_sync_protocol_contracts import SAFE, UUID, UUID4, BOOL, NULL, const, object_of, document, ref

INTERNAL = "native_v3/internal/"
METHODS = {
    "auth.session.adopt": ("auth/session_adopt_request", "auth/session_status_response", "SessionCredentialBroker", ["runtime.open_workspace"], ["user.get_current", "device.register"]),
    "auth.session.get_access_token": ("auth/session_get_access_token_request", "auth/session_access_token_response", "SessionCredentialBroker", [], ["auth.token.refresh"]),
    "auth.session.get_status": ("common/native_empty_request", "auth/session_status_response", "SessionCredentialBroker", [], []),
    "auth.session.logout": ("auth/session_logout_request", "auth/session_logout_response", "SessionCredentialBroker", ["sync.prepare_upload_batch", "sync.acknowledge_upload", "sync.apply_download_batch", "runtime.close_workspace"], ["sync.exchange", "auth.logout"]),
    "auth.session.clear_local": ("auth/session_clear_local_request", "auth/session_cache_result", "SessionCredentialBroker", ["runtime.close_workspace"], []),
    "auth.session.reauthenticate": ("auth/session_reauthenticate_request", "auth/session_reauthenticate_response", "SessionCredentialBroker", [], ["auth.reauthenticate"]),
    "workspace.get_state": ("workspace/get_workspace_state_request", "workspace/workspace_state_response", "WorkspaceCoordinator", ["workspace.get_state"], []),
    "workspace.list": ("common/native_empty_request", "workspace/workspace_list_response", "WorkspaceRegistry", [], []),
    "workspace.activate": ("workspace/activate_workspace_request", "workspace/workspace_state_response", "WorkspaceCoordinator", ["runtime.close_workspace", "runtime.open_workspace"], []),
    "workspace.import_preview": ("workspace/import_preview_request", "workspace/import_preview_response", "WorkspaceImportCoordinator", ["workspace.import_preview"], []),
    "workspace.import_commit": ("workspace/import_commit_request", "workspace/import_status_response", "WorkspaceImportCoordinator", ["workspace.import_accept_range_close", "workspace.import_commit"], ["sync.import.takeover"]),
    "workspace.import_status": ("workspace/import_status_request", "workspace/import_status_response", "WorkspaceImportCoordinator", ["workspace.import_status"], ["sync.import.status"]),
    "workspace.import_abandon": ("workspace/import_abandon_request", "workspace/import_status_response", "WorkspaceImportCoordinator", ["workspace.import_abandon", "workspace.import_accept_range_close"], ["sync.import.abandon"]),
    "workspace.clear_account_cache": ("workspace/clear_account_cache_request", "workspace/workspace_state_response", "WorkspaceCoordinator", ["sync.accept_transport_fence", "runtime.close_workspace", "runtime.open_workspace", "sync.begin_bootstrap", "sync.apply_bootstrap_page", "sync.finalize_bootstrap"], ["sync.import.status", "sync.import.takeover", "sync.import.abandon", "sync.device_fence", "sync.bootstrap", "sync.import.cleanup_confirm"]),
    "sync.get_status": ("sync/get_sync_status_request", "sync/sync_status_response", "SyncStatusAggregator", ["sync.get_status"], []),
    "sync.claim_conflict_notice": ("sync/claim_conflict_notice_request", "sync/claim_conflict_notice_response", "SyncCoordinator", ["sync.claim_conflict_notice"], []),
    "sync.export_diagnostics": ("sync/export_diagnostics_request", "sync/export_diagnostics_response", "SyncDiagnosticExporter", ["sync.build_diagnostic_snapshot"], []),
    "sync.set_enabled": ("sync/set_sync_enabled_request", "sync/sync_status_response", "SyncCoordinator", ["sync.set_enabled"], []),
    "sync.run_now": ("sync/run_sync_now_request", "sync/run_sync_now_response", "SyncCoordinator", ["sync.prepare_upload_batch", "sync.acknowledge_upload", "sync.apply_download_batch"], ["sync.exchange", "sync.conflict.resolve"]),
    "sync.conflict.list": ("sync/list_sync_conflicts_request", "sync/sync_conflict_list_response", "SyncConflictCoordinator", ["sync.conflict.list"], []),
    "sync.conflict.detail": ("sync/get_sync_conflict_request", "sync/native_sync_conflict_detail_response", "SyncConflictCoordinator", ["sync.conflict.detail"], []),
    "sync.conflict.resolve": ("sync/resolve_sync_conflict_request", "sync/sync_conflict_resolution_response", "SyncConflictCoordinator", ["sync.conflict.resolve"], []),
    "sync.failed_change.list": ("sync/list_sync_failed_local_changes_request", "sync/sync_failed_local_change_list_response", "SyncConflictCoordinator", ["sync.failed_change.list"], []),
    "sync.failed_change.detail": ("sync/get_sync_failed_local_change_request", "sync/sync_failed_local_change_detail", "SyncConflictCoordinator", ["sync.failed_change.detail"], []),
    "sync.failed_change.discard": ("sync/discard_sync_failed_local_change_request", "sync/discard_sync_failed_local_change_response", "SyncConflictCoordinator", ["sync.failed_change.discard"], []),
    "device.list": ("device/method_device_list_request", "device/method_device_list_response", "DeviceCoordinator", [], ["device.list"]),
    "device.rename": ("device/method_rename_device_request", "device/method_rename_device_response", "DeviceCoordinator", [], ["device.rename"]),
    "device.update_settings": ("device/method_update_device_settings_request", "device/method_update_device_settings_response", "DeviceSettingsCoordinator", ["sync.set_enabled"], ["device.update_settings"]),
    "device.revoke": ("device/method_revoke_device_request", "device/method_revoke_device_response", "DeviceCoordinator", ["runtime.open_workspace"], ["device.revoke", "device.register"]),
    "preferences.get": ("preferences/get_preferences_request", "preferences/preferences_response", "PreferencesCoordinator", ["preferences.get"], []),
    "preferences.update": ("preferences/update_preferences_request", "preferences/preferences_response", "PreferencesCoordinator", ["preferences.update"], []),
    "search.get_workspace_history": ("native_v3/search/get_workspace_history_request", "native_v3/search/workspace_history_response", "WorkspaceSearchHistoryStore", [], []),
    "search.replace_workspace_history": ("native_v3/search/replace_workspace_history_request", "native_v3/search/workspace_history_response", "WorkspaceSearchHistoryStore", [], []),
    "profile.get_cached": ("user/get_cached_profile_request", "user/cached_profile_response", "ProfileCoordinator", ["profile.get_cached"], []),
    "profile.accept_server_snapshot": ("user/accept_server_profile_snapshot_request", "user/cached_profile_response", "ProfileCoordinator", ["profile.accept_server_snapshot"], []),
}
CALLS = {
    "runtime.open_workspace": (INTERNAL + "open_workspace_request", INTERNAL + "open_workspace_response"),
    "runtime.close_workspace": (INTERNAL + "close_workspace_request", INTERNAL + "close_workspace_response"),
    "workspace.get_state": (INTERNAL + "get_workspace_state_request", INTERNAL + "get_workspace_state_response"),
    "workspace.import_preview": ("workspace/import_preview_request", "workspace/import_preview_response"),
    "workspace.import_accept_range_close": ("workspace/import_accept_range_close_request", INTERNAL + "native_apply_result"),
    "workspace.import_commit": ("workspace/native_import_commit_request", "workspace/native_import_status_response"),
    "workspace.import_status": ("workspace/native_import_status_request", "workspace/native_import_status_response"),
    "workspace.import_abandon": ("workspace/native_import_abandon_request", "workspace/native_import_status_response"),
    "workspace.import_cleanup_confirm": ("workspace/import_cleanup_confirm_request", "workspace/native_import_status_response"),
    "workspace.import_finalize_source_lease": ("workspace/import_finalize_source_lease_request", INTERNAL + "native_operation_response"),
    "sync.accept_transport_fence": (INTERNAL + "accept_transport_fence_request", INTERNAL + "accept_transport_fence_response"),
    "sync.prepare_upload_batch": (INTERNAL + "prepare_upload_batch_request", "sync/native_prepared_exchange_request"),
    "sync.acknowledge_upload": ("sync/native_acknowledge_upload_request", INTERNAL + "native_apply_result"),
    "sync.apply_download_batch": ("sync/native_apply_exchange_response", INTERNAL + "native_apply_result"),
    "sync.record_transport_terminal": ("sync/record_transport_terminal_request", INTERNAL + "native_operation_response"),
    "sync.begin_bootstrap": (INTERNAL + "begin_bootstrap_request", INTERNAL + "bootstrap_staging_response"),
    "sync.apply_bootstrap_page": (INTERNAL + "apply_bootstrap_page_request", INTERNAL + "bootstrap_staging_response"),
    "sync.finalize_bootstrap": (INTERNAL + "finalize_bootstrap_request", INTERNAL + "native_apply_result"),
    "sync.get_status": (INTERNAL + "bound_empty_request", "sync/native_sync_status_snapshot"),
    "sync.set_enabled": ("sync/native_set_sync_enabled_request", "sync/native_sync_status_snapshot"),
    "sync.claim_conflict_notice": (INTERNAL + "claim_conflict_notice_request", INTERNAL + "claim_conflict_notice_response"),
    "sync.build_diagnostic_snapshot": (INTERNAL + "build_diagnostic_snapshot_request", INTERNAL + "diagnostic_snapshot_response"),
    "sync.run_local_maintenance": (INTERNAL + "run_local_maintenance_request", INTERNAL + "run_local_maintenance_response"),
}
BLOCKED = {"sync.apply", "ai.extract", "notification.list", "search.get_local_history", "search.replace_local_history",
    "auth.refresh_token.store", "auth.refresh_token.read", "auth.refresh_token.delete", "auth.refresh_token.exists"}
GLOBAL_LEGACY = {"runtime.device_timezone", "runtime.resolve_local_datetime", "runtime.localize_instants",
    "notification.initialize", "notification.permission_status", "notification.request_permission", "notification.open_settings", "notification.get_initial_tap_payload",
    "ring.get_state", "ring.pick_ringtone", "ring.update_settings", "ring.test", "appearance.get_local", "appearance.update_local"}


def derive():
    out = {}
    old_methods = yaml.safe_load((CONTRACTS / "method_channels.yaml").read_text(encoding="utf-8"))["methods"]
    old_calls = yaml.safe_load((CONTRACTS / "native_calls.yaml").read_text(encoding="utf-8"))["calls"]
    business = yaml.safe_load((CONTRACTS / "native_v3/business_compatibility.yaml").read_text(encoding="utf-8"))
    compatibility = business["schema_mapping"]
    writer_refs = {BASE + compatibility[source]: BASE + target for source, target in business["writer_schema_mapping"].items()}

    def emit(name, value, lane):
        directory = "native_v3/" + lane
        schema = document(name, value, "8", directory)
        schema.update({"x-contract-domain": "native", "x-contract-version": 3})
        out[CONTRACTS / directory / (name + ".schema.json")] = schema
        return directory + "/" + name + ".schema.json"

    def mapped(path):
        return compatibility.get(path, path)

    def schema_ref(path):
        return {"$ref": BASE + path}

    def plain_body(path, native=False, writer=False):
        path = mapped(path)
        value = copy.deepcopy(out.get(CONTRACTS / path) or json.loads((CONTRACTS / path).read_text(encoding="utf-8")))
        uri = value.get("$id", BASE + path)
        def visit(node, at_root=False):
            if isinstance(node, dict):
                if "$ref" in node:
                    absolute = urljoin(uri, node["$ref"])
                    node["$ref"] = absolute.replace(BASE + "sync/sync_status_response.schema.json", BASE + "sync/native_sync_status_snapshot.schema.json") if native else absolute
                    if writer:
                        node["$ref"] = writer_refs.get(node["$ref"], node["$ref"])
                if native and "properties" in node:
                    for name in ("expected_active_route_revision", "active_route_revision"):
                        node["properties"].pop(name, None)
                        if name in node.get("required", []):
                            node["required"].remove(name)
                for key, child in list(node.items()):
                    if not at_root or not key.startswith("$"):
                        visit(child)
            elif isinstance(node, list):
                for child in node:
                    visit(child)
        visit(value, True)
        return {k: v for k, v in value.items() if k not in {"$id", "$schema", "title"}}

    def public_legacy(operation, source, response=False):
        if operation in GLOBAL_LEGACY:
            return mapped(source)
        properties = {"workspace_id": UUID4, "active_route_revision" if response else "expected_active_route_revision": SAFE,
            "payload": schema_ref(mapped(source))}
        if response:
            properties["runtime_instance_id"] = UUID4
            if operation.startswith("category."):
                properties["native_state_revision"] = SAFE
        return emit(operation.replace(".", "_") + ("_response" if response else "_request"), object_of(properties), "method")

    def native_payload(operation, source, response=False):
        if operation in {"runtime.resolve_local_datetime", "runtime.localize_instants"}:
            return mapped(source)
        # Native infrastructure already owns an exact runtime binding shape.
        if source.startswith(INTERNAL):
            return source
        payload_path = emit(operation.replace(".", "_") + ("_response_payload" if response else "_request_payload"),
            plain_body(source, native=True, writer=response and operation == "reminder.prepare_delivery"), "internal_payloads")
        return emit(operation.replace(".", "_") + ("_response" if response else "_request"), object_of({
            "binding": ref("runtime_binding", "native_v3/internal"), "payload": schema_ref(payload_path)
        }), "native")

    methods, calls = {}, {}
    category = json.loads((CONTRACTS / "category/category_response.schema.json").read_text(encoding="utf-8"))["properties"]
    editable_category = {name: category[name] for name in ("name", "description", "color", "icon", "sort_order")}
    editable_category["color"] = {**editable_category["color"], "pattern": "^#[0-9A-Fa-f]{6}$"}
    category_patch = {"type": "object", "properties": editable_category, "additionalProperties": False, "minProperties": 1}
    category_response = emit("category_lifecycle_response", object_of({"workspace_id": UUID4, "runtime_instance_id": UUID4,
        "active_route_revision": SAFE, "native_state_revision": SAFE, "category": ref("category_fact", "sync/v1")}), "category")
    category_requests = {}
    for action in ("update", "delete", "restore"):
        props = {"workspace_id": UUID4, "expected_active_route_revision": SAFE, "id": UUID4, "expected_native_state_revision": SAFE}
        if action == "update":
            props["patch"] = category_patch
        if action == "restore":
            props["candidate"] = object_of(editable_category)
        category_requests["category." + action] = emit(action + "_category_request", object_of(props), "category")
    for operation, row in old_methods.items():
        blocked = operation in BLOCKED
        native_edges = [operation] if operation in old_calls else []
        if operation == "reminder.reconcile_schedule":
            native_edges = ["reminder.list_schedulable", "reminder.mark_scheduled"]
        if operation == "ring.snooze_active":
            native_edges = ["reminder.snooze"]
        if operation == "ring.complete_item":
            native_edges = ["event.complete"]
        methods[operation] = {"module": row["module"], "request": public_legacy(operation, row["request"]),
            "result": {"envelope": "native_v3/common/native_result.schema.json", "data": public_legacy(operation, row["result"]["data"], True)},
            "implementation_status": "not_implemented" if blocked else "planned", "release_status": "blocked" if blocked else "planned",
            "implementation_path": "reserved_not_implemented" if blocked else "kotlin_jni_workflow" if native_edges else "kotlin_local",
            "kotlin_owner": row["module"].title().replace("_", "") + "MethodHandlerV3",
            "native_calls": [] if blocked else native_edges, "http_operations": [],
            "on_unsupported": "notImplemented_no_success_adapter", "preserved_v2_operation": operation,
            "route_policy": "global_local_capability" if operation in GLOBAL_LEGACY else "explicit_workspace_and_route_cas"}
    for operation, (request, response, owner, native_edges, http_edges) in METHODS.items():
        methods[operation] = {"module": operation.split(".")[0], "request": request + ".schema.json",
            "result": {"envelope": "native_v3/common/native_result.schema.json", "data": response + ".schema.json"},
            "implementation_status": "planned", "release_status": "planned", "kotlin_owner": owner,
            "implementation_path": "kotlin_workflow" if native_edges or http_edges else "kotlin_local",
            "native_calls": native_edges, "http_operations": http_edges,
            "route_policy": "schema_declared_recovery_or_session_cas" if operation.startswith("auth.") or operation in {"workspace.get_state", "workspace.list", "device.list", "device.revoke"} else "explicit_workspace_and_route_cas"}
    for operation, request in category_requests.items():
        methods[operation] = {"module": "category", "request": request,
            "result": {"envelope": "native_v3/common/native_result.schema.json", "data": category_response},
            "implementation_status": "planned", "release_status": "planned", "kotlin_owner": "CategoryMethodHandlerV3",
            "implementation_path": "kotlin_jni_workflow", "native_calls": [operation], "http_operations": [],
            "route_policy": "explicit_workspace_and_route_cas", "business_cas": "expected_native_state_revision",
            "atomicity": "workspace fact and account Outbox in one C++ transaction; guest has zero Outbox; deletion never rewrites weak references"}
    all_calls = {operation: (row["request"], row["result"]["data"]) for operation, row in old_calls.items() if operation != "runtime.initialize"}
    all_calls.update({name: (request + ".schema.json", response + ".schema.json") for name, (request, response) in CALLS.items()})
    all_calls.update({name: (request, category_response) for name, request in category_requests.items()})
    for operation in ("sync.conflict.list", "sync.conflict.detail", "sync.conflict.resolve", "sync.failed_change.list", "sync.failed_change.detail", "sync.failed_change.discard", "preferences.get", "preferences.update", "profile.get_cached", "profile.accept_server_snapshot"):
        request, response = METHODS[operation][:2]
        if operation == "sync.failed_change.discard":
            response = "sync/native_sync_status_snapshot"
        all_calls[operation] = (request + ".schema.json", response + ".schema.json")
    for operation, (request, response) in all_calls.items():
        module = operation.split(".")[0]
        if module == "event_occurrence":
            module = "event"
        owner = "Native" + module.title() + "BridgeV3"
        method = "native" + "".join(part.title() for part in operation.replace(".", "_").split("_")) + "V3"
        calls[operation] = {"module": module, "visibility": "internal", "caller": "kotlin", "implementation_status": "planned", "release_status": "planned",
            "request": native_payload(operation, request), "result": {"envelope": "native_v3/common/native_result.schema.json", "data": native_payload(operation, response, True)},
            "binding_equality": "every repeated workspace/runtime/device/session/transport identity must equal the pinned runtime; mismatch zero writes",
            "planned_symbols": {"kotlin_bridge": owner, "method": method,
                "jvm_class": "com.excellentcalendar.excellent_calendar.bridge.native." + owner,
                "jni_symbol": "Java_com_excellentcalendar_excellent_1calendar_bridge_native_" + owner + "_" + method,
                "cpp_boundary": "excellent_calendar::boundary::v3::" + operation.replace(".", "_"),
                "jni_translation_unit": "flutter_client/android/app/src/main/cpp/boundary/adapter/jni/" + ("calendar_view" if module == "calendar" else "workspace" if operation.startswith("runtime.") and operation.endswith("workspace") else module) + "_jni.cpp"},
            "public_method_required": False}
        if operation == "runtime.open_workspace":
            calls[operation]["binary_parameters"] = [{"name": "database_key", "kotlin": "ByteArray", "jni": "jbyteArray", "cpp": "const uint8_t* and size_t", "account_bytes": 32, "guest_bytes": 0, "json": "forbidden"}]
    def dto(path):
        # Kotlin consumes both public and JNI DTOs. Include the schema lane and
        # domain, so equally named leaves with different wire shapes cannot
        # accidentally share one generated class.
        qualified = path.removeprefix("native_v3/").removesuffix(".schema.json").replace("/", "_")
        return "".join(part.title() for part in qualified.split("_")) + "V3"
    for operation, row in methods.items():
        row["planned_dtos"] = {"dart_request": dto(row["request"]), "dart_response": dto(row["result"]["data"]),
            "kotlin_request": dto(row["request"]), "kotlin_response": dto(row["result"]["data"])}
        row["planned_gateway"] = "".join(part.title() for part in operation.split(".")[:1]) + "GatewayV3"
    for operation, row in calls.items():
        row["planned_dtos"] = {"kotlin_request": dto(row["request"]), "kotlin_response": dto(row["result"]["data"]),
            "cpp_request": dto(row["request"]), "cpp_response": dto(row["result"]["data"])}
    events = {
        "sync.status_changed": {"schema": "sync/sync_status_response.schema.json", "identity": ["workspace_id", "runtime_instance_id", "active_route_revision", "status_revision"], "recovery_method": "sync.get_status", "delivery": "may_repeat_or_drop_subscribe_then_query"},
        "workspace.state_changed": {"schema": "workspace/workspace_route_state.schema.json", "identity": ["route_state", "active_route_revision"], "recovery_method": "workspace.get_state", "delivery": "may_repeat_or_drop_subscribe_then_query"},
    }
    old_events = yaml.safe_load((CONTRACTS / "method_channels.yaml").read_text(encoding="utf-8"))["event_channels"]
    for name, row in old_events.items():
        path = mapped(row["data"])
        if name == "notification.opened":
            path = business["writer_schema_mapping"][row["data"]]
        elif name in {"reminder.status_changed", "notification.delivered"}:
            path = emit(name.replace(".", "_"), object_of({"workspace_id": UUID4, "runtime_instance_id": UUID4,
                "active_route_revision": SAFE, "payload": schema_ref(path)}), "events")
        events[name] = {"schema": path, "preserved_v2_event": name,
            "identity": row.get("identity", ["workspace_id"] if name == "notification.opened" else ["workspace_id", "runtime_instance_id", "active_route_revision"]),
            "recovery_method": "ring.get_state" if name == "ring.state_changed" else "notification.get_initial_tap_payload" if name == "notification.opened" else "reminder.list" if name == "reminder.status_changed" else None,
            "delivery": "advisory_delivery_event_may_drop_no_fake_notification_list" if name == "notification.delivered" else "preserve_v2_delivery_and_recovery",
            "implementation_status": "planned", "release_status": "planned"}
    event_envelope = emit("native_event", {"oneOf": [object_of({"contract_version": const(3), "event_name": const(name),
        "data": schema_ref(row["schema"])}) for name, row in events.items()]}, "common")
    common = {"version": 3, "implementation_status": "planned", "release_status": "planned", "rule_anchor": "cloud-sync-02/8", "activation": "same_apk_only_after_frozen_revision_and_all_consumer_gates"}
    out[CONTRACTS / "native_v3/method_channels.yaml"] = {**common, "channel": "excellent_calendar/native_v3", "preserved_v2": "method_channels.yaml", "methods": methods,
        "event_channels": {"channel": "excellent_calendar/events_v3", "envelope": event_envelope, "events": events}}
    out[CONTRACTS / "native_v3/native_calls.yaml"] = {**common, "bridge": "kotlin_jni", "preserved_v2": "native_calls.yaml", "calls": calls}
    out[CONTRACTS / "sync/capability_graph.yaml"] = {**common, "method_registry": "native_v3/method_channels.yaml", "native_registry": "native_v3/native_calls.yaml",
        "backend_registry": "backend_sync_v1/backend_api.yaml", "default_unknown_capability": "deny_notImplemented",
        "visibility": {"flutter_forbidden": ["raw_cursor", "client_sequence", "refresh_token", "outbox", "raw_change", "database_key"],
            "kotlin_forbidden": ["reconstruct_mutation", "merge_domain_fields", "persist_or_advance_sync_cursor"], "cpp_forbidden": ["http", "select_active_route"]},
        "schema_wire_shape": {"legacy_public": "route identity plus typed payload; v2 payload semantics unchanged except declared v3 revisions",
            "legacy_native": "pinned runtime binding plus typed payload; v2 global initialize cannot route a v6 workspace",
            "new": "strict schemas named per capability; nested repeated identity must equal binding, never caller-controlled account identity"},
        "internal_workflows": {
            "bootstrap": {"http": ["sync.bootstrap"], "native": ["sync.begin_bootstrap", "sync.apply_bootstrap_page", "sync.finalize_bootstrap"], "owner": "SyncCoordinator"},
            "receipt_ack_flush": {"http": ["sync.exchange"], "native": ["sync.prepare_upload_batch", "sync.acknowledge_upload"], "owner": "SyncCoordinator", "apply_download": False},
            "guest_source_cleanup": {"http": ["sync.import.cleanup_confirm"], "native": ["workspace.import_cleanup_confirm", "workspace.import_finalize_source_lease"], "owner": "WorkspaceImportCoordinator"},
            "maintenance": {"http": [], "native": ["sync.run_local_maintenance"], "owner": "WorkspaceMaintenanceWorker"}},
        "old_reserved_routes": {"sync.apply": "always notImplemented; no Native implementation", "notification.list": "absent from current NotificationMethodHandler; no fake path added by this revision", "ai.extract": "reserved; no new implementation in cloud sync 02"},
        "evidence_status": "schema_and_graph_only_runtime_owner_implementation_belongs_to_03_04_05_06"}
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = derive()
    for path, value in result.items():
        if args.check:
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            assert actual == value, str(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(yaml.safe_dump(value, sort_keys=False, allow_unicode=True) if path.suffix == ".yaml" else json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"public_methods": len(result[CONTRACTS / 'native_v3/method_channels.yaml']["methods"]), "native_calls": len(result[CONTRACTS / 'native_v3/native_calls.yaml']["calls"]), "generated_schemas": sum(p.suffix == '.json' for p in result), "status": "planned"}))
