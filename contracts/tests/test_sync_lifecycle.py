"""Decision tables and real durable notice transactions, without claiming Android behavior."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_sync_lifecycle_contracts import derive, SESSIONS
from domain_reference import validate_schema
from lifecycle_reference import (NoticeStore, backend_capability, begin_retention, device_name, observe_boot,
                                  retention_due, retry_delay, sync_phase)
from counter_reference import MAXIMUM
from sqlite_reference import connect

A = "11111111-1111-4111-8111-111111111111"
B = "22222222-2222-4222-8222-222222222222"


class LifecycleTests(unittest.TestCase):
    def test_exact_generated_lifecycle_definitions(self):
        for path, expected in derive().items():
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), expected, path.name)

    def test_three_route_states_are_exclusive_and_empty_locked_never_reuse_runtime(self):
        for state in ("empty", "ready", "locked"):
            value = {"route_state": state, "active_workspace_id": None if state == "empty" else A,
                "workspace_kind": None if state == "empty" else "account", "runtime_instance_id": B if state == "ready" else None,
                "lock_reason": "WORKSPACE_KEY_UNAVAILABLE" if state == "locked" else None, "active_route_revision": 0}
            validate_schema("workspace/workspace_route_state.schema.json", value)
            for field in value:
                with self.assertRaises(ValueError):
                    validate_schema("workspace/workspace_route_state.schema.json", {k: v for k, v in value.items() if k != field})
            if state != "ready":
                with self.assertRaises(ValueError):
                    validate_schema("workspace/workspace_route_state.schema.json", {**value, "runtime_instance_id": B})
            for hidden in ("directory", "key_alias", "token", "cursor", "counts"):
                with self.assertRaises(ValueError):
                    validate_schema("workspace/workspace_route_state.schema.json", {**value, hidden: "hidden"})

    def test_session_seven_states_have_no_token_or_device_and_pending_capability_is_closed(self):
        for state in SESSIONS:
            value = {"state": state, "session_generation": None if state == "empty" else 0,
                "capabilities": {"can_request_access_token": state in {"active", "refreshing"},
                                 "can_manage_devices": state in {"active", "registration_pending"},
                                 "can_open_account_workspace": state == "active"}}
            validate_schema("auth/session_status_response.schema.json", value)
            for forbidden in ("device_id", "refresh_token", "access_token", "boot_id", "account_directory"):
                with self.assertRaises(ValueError):
                    validate_schema("auth/session_status_response.schema.json", {**value, forbidden: A})
        for operation in ("device.list", "auth.reauthenticate", "device.revoke"):
            self.assertFalse(backend_capability("unregistered", operation))
            self.assertTrue(backend_capability("pending_registration", operation))
        for state in ("unregistered", "pending_registration"):
            for operation in ("sync.exchange", "preferences.update", "user.update_current", "future.unknown"):
                self.assertFalse(backend_capability(state, operation))
        self.assertFalse(backend_capability("pending_registration", "device.register", same_installation=False))
        self.assertFalse(backend_capability("registered", "system.time"))

    def test_unicode_device_name_normalization_preserves_code_points(self):
        self.assertEqual(device_name(" Google\t", "Google  Pixel\n 9"), "Google Pixel 9")
        self.assertEqual(device_name(" SAMSUNG ", "samsung SM-A"), "samsung SM-A")
        self.assertEqual(device_name("", "\t \u3000"), "Android 设备")
        self.assertEqual(device_name("牌", "😀" * 100), "牌 " + "😀" * 62)
        self.assertEqual(len(device_name("牌", "😀" * 100)), 64)
        with self.assertRaises(UnicodeError):
            device_name("x", "\ud800")

    def test_sync_phase_priority_does_not_let_workmanager_constraints_fake_queued(self):
        cases = [
            ({"workspace_kind": "local", "globally_blocked": True}, "local_only"),
            ({"workspace_kind": "account", "identity_valid": False, "globally_blocked": True}, "auth_required"),
            ({"workspace_kind": "account", "globally_blocked": True, "rebuilding": True}, "blocked"),
            ({"workspace_kind": "account", "rebuilding": True, "running": True}, "rebuilding"),
            ({"workspace_kind": "account", "running": True, "enabled": False}, "syncing"),
            ({"workspace_kind": "account", "logout_authorized_queued": True, "enabled": False}, "queued"),
            ({"workspace_kind": "account", "enabled": False, "pending": 2, "online": False}, "paused"),
            ({"workspace_kind": "account", "pending": 2, "online": False, "ordinary_queued": True}, "offline_pending"),
            ({"workspace_kind": "account", "ordinary_queued": True, "recoverable_failure": True}, "queued"),
            ({"workspace_kind": "account", "recoverable_failure": True}, "failed"),
            ({"workspace_kind": "account"}, "idle"),
        ]
        for request, expected in cases:
            self.assertEqual(sync_phase(**request), expected)

    def test_retry_budget_jitter_hint_and_header_mismatch(self):
        self.assertEqual(retry_delay(0, 1), 5)
        self.assertEqual(retry_delay(7, 1), 640)
        self.assertEqual(retry_delay(1, 0.5), 5)
        self.assertEqual(retry_delay(0, 0, retry_after=86400, retry_after_header=86400), 86400)
        for args in ((0, 1, {"retry_after": 0}), (0, 1, {"retry_after": 86401}),
                     (0, 1, {"retry_after": 60, "retry_after_header": 30}), (0, 1, {"retry_after_header": 60})):
            with self.assertRaises(ValueError):
                retry_delay(args[0], args[1], **args[2])
        with self.assertRaisesRegex(ValueError, "RETRY_BUDGET_EXHAUSTED"):
            retry_delay(8, 0)

    def test_boot_count_same_process_restart_reboot_and_tampering_fail_closed(self):
        first, reused = observe_boot(None, boot_count=8, elapsed_ms=1000, aad_verified=True, uuid_factory=lambda: uuid.UUID(A))
        self.assertFalse(reused)
        second, reused = observe_boot(first, boot_count=8, elapsed_ms=1500, aad_verified=True)
        self.assertTrue(reused)
        self.assertEqual(second["boot_id"], A)
        rebooted, reused = observe_boot(second, boot_count=9, elapsed_ms=10, aad_verified=True, uuid_factory=lambda: uuid.UUID(B))
        self.assertFalse(reused)
        self.assertEqual(rebooted["boot_id"], B)
        for kwargs in ({"boot_count": 7, "elapsed_ms": 2000, "aad_verified": True},
                       {"boot_count": 8, "elapsed_ms": 999, "aad_verified": True},
                       {"boot_count": 8, "elapsed_ms": 2000, "aad_verified": False},
                       {"boot_count": 9, "elapsed_ms": 20, "aad_verified": True, "uuid_factory": lambda: uuid.UUID(A)}):
            with self.assertRaisesRegex(ValueError, "BOOT_IDENTITY_UNTRUSTED"):
                observe_boot(first, **kwargs)

    def test_api23_process_only_identity_is_not_trusted_after_process_restart(self):
        record, _ = observe_boot(None, boot_count=None, elapsed_ms=1000, aad_verified=True, uuid_factory=lambda: uuid.UUID(A))
        self.assertNotIn("observed_boot_count", record)
        current, reused = observe_boot(record, boot_count=None, elapsed_ms=1500, aad_verified=True, process_continues=True)
        self.assertTrue(reused)
        new, reused = observe_boot(current, boot_count=None, elapsed_ms=2000, aad_verified=True, uuid_factory=lambda: uuid.UUID(B))
        self.assertFalse(reused)
        self.assertEqual(new["boot_id"], B)

    def test_retained_deadline_never_depends_on_wall_clock_and_cannot_be_extended(self):
        record = begin_retention(policy="retain_30d", lifecycle_revision=1, server_time="2026-08-06T00:00:00Z", boot_id=A, elapsed_ms=1000)
        self.assertEqual(record["retained_until"], "2026-09-05T00:00:00Z")
        before = copy.deepcopy(record)
        self.assertFalse(retention_due(record, current_boot_id=B, elapsed_ms=MAXIMUM))
        self.assertFalse(retention_due(record, https_time_lower_bound="2026-09-04T23:59:59Z"))
        self.assertTrue(retention_due(record, https_time_lower_bound="2026-09-05T00:00:00Z"))
        self.assertTrue(retention_due(record, current_boot_id=A, elapsed_ms=2592001000))
        self.assertEqual(record, before)
        with self.assertRaisesRegex(ValueError, "RETENTION_TRUSTED_TIME_REQUIRED"):
            begin_retention(policy="retain_30d", lifecycle_revision=1, boot_id=A, elapsed_ms=1000)
        destroyed = begin_retention(policy="destroy_now", lifecycle_revision=1)
        self.assertIsNone(destroyed["retained_until"])
        with self.assertRaises(ValueError):
            retention_due({**record, "retained_until": "2026-09-06T00:00:00Z"})
        with self.assertRaises(ValueError):
            validate_schema("auth/session_cache_result.schema.json", {"cache_action": "retained", "retained_until": None,
                "retention_clock_state": "untrusted", "lifecycle_revision": 1})

    def test_device_method_settings_one_owner_and_remote_summary_cannot_leak_sequence(self):
        request = {"workspace_id": A, "expected_active_route_revision": 2, "device_id": B,
            "expected_local_settings_revision": 3, "expected_sync_policy_revision": None, "patch": {"receive_reminders": False}}
        validate_schema("device/method_update_device_settings_request.schema.json", request)
        with self.assertRaises(ValueError):
            validate_schema("device/method_update_device_settings_request.schema.json", {**request, "patch": {"receive_reminders": False, "sync_enabled": False}})
        http = {"expected_device_version": 3, "patch": {"receive_reminders": False, "sync_enabled": False}}
        validate_schema("device/update_device_settings_request.schema.json", http)
        summary = {"device_id": B, "display_name": "手机", "platform": "android", "app_version": "1.0.0", "protocol_version": 1,
            "receive_reminders": True, "sync_enabled": False, "device_version": 4, "status": "active", "registered_at": "2026-09-05T00:00:00Z",
            "last_seen_at": None, "last_sync_at": None, "revoked_at": None}
        validate_schema("device/method_device_summary.schema.json", summary)
        with self.assertRaises(ValueError):
            validate_schema("device/method_device_summary.schema.json", {**summary, "sequence_recovery": {}})

    def test_pending_logout_rejects_active_route_review_fields_and_security_reason(self):
        request = {"expected_session_generation": 1, "session_state": "registration_pending", "mode": "server_then_local",
            "final_sync_policy": None, "cache_policy": "destroy_now", "observed_active_workspace_id": None,
            "expected_active_route_revision": None, "logout_operation_id": None, "expected_logout_risk_revision": None, "confirmation_id": None}
        validate_schema("auth/session_logout_request.schema.json", request)
        for key, value in (("observed_active_workspace_id", A), ("expected_active_route_revision", 0),
                           ("logout_operation_id", A), ("final_sync_policy", "attempt_once")):
            with self.assertRaises(ValueError):
                validate_schema("auth/session_logout_request.schema.json", {**request, key: value})
        with self.assertRaises(ValueError):
            validate_schema("auth/session_clear_local_request.schema.json", {"reason": "device_revoked", "confirmation_id": A, "expected_session_generation": 1})

    def test_notice_net_new_rollback_exact_head_and_at_most_once_survive_reopen(self):
        with tempfile.TemporaryDirectory(prefix="sync-notice-") as folder:
            path = Path(folder) / "notice.db"
            store = NoticeStore(path)
            store.begin("w1", 5)
            store.delta("w1", "old-resolved-in-window", 1)
            store.delta("w1", "old-resolved-in-window", 2, resolved=True)
            store.delta("w1", "a", 1)
            with self.assertRaises(RuntimeError):
                store.terminal("w1", rollback=True)
            self.assertFalse(store.snapshot()["notices"])
            first = store.terminal("w1")
            store.begin("w2", 8)
            store.delta("w2", "b", 1)
            second = store.terminal("w2")
            self.assertEqual(len(store.snapshot()["notices"]), 2)
            self.assertFalse(store.snapshot()["windows"])
            self.assertFalse(store.snapshot()["discovered"])
            with self.assertRaisesRegex(ValueError, "SYNC_NOTICE_HEAD_MISMATCH"):
                store.claim(*second)
            self.assertEqual(store.claim(*first), {"disposition": "claimed", "count": 1})
            reopened = NoticeStore(path)
            self.assertEqual(reopened.claim(*first), {"disposition": "no_longer_actionable", "count": 0})
            self.assertEqual(reopened.snapshot()["notices"], [second])
            reopened.begin("w3", 9)
            reopened.delta("w3", "b", 2, resolved=True)
            self.assertIsNone(reopened.terminal("w3"))
            self.assertEqual(reopened.claim(*second), {"disposition": "no_longer_actionable", "count": 0})
            self.assertFalse(reopened.snapshot()["notice_members"])

    def test_last_notice_does_not_stop_conflict_discovery_or_repeat_toast_after_max(self):
        with tempfile.TemporaryDirectory(prefix="sync-notice-") as folder:
            store = NoticeStore(Path(folder) / "notice.db")
            with connect(store.path) as db:
                db.execute("UPDATE state SET next_sequence=?", (MAXIMUM,))
            store.begin("w1", 1)
            store.delta("w1", "a", 1)
            last = store.terminal("w1")
            self.assertEqual(last[0], MAXIMUM)
            store.begin("w2", 2)
            store.delta("w2", "b", 1)
            self.assertIsNone(store.terminal("w2"))
            self.assertEqual(len(store.snapshot()["conflicts"]), 2)
            self.assertFalse(store.snapshot()["discovered"])
            self.assertEqual(store.claim(*last)["count"], 1)


if __name__ == "__main__":
    unittest.main()
