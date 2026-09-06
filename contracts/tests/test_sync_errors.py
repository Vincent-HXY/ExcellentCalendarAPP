"""Stable error context/owner boundaries for the planned compatibility revision."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
import yaml
from build_sync_error_contracts import derive
from domain_reference import validate_schema


class ErrorTests(unittest.TestCase):
    def test_generated_contexts_and_registry_are_exact(self):
        for path, expected in derive().items():
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(actual, expected, path.name)

    def test_all_counter_owners_have_exact_error_context_and_cross_owner_counter_is_rejected(self):
        registry = yaml.safe_load((ROOT / "contracts/sync/sync_counter_registry.yaml").read_text(encoding="utf-8"))
        for kind, row in registry["counter_kinds"].items():
            value = {"code": row["error"], "message": "计数已达到上限", "retryable": False, "context": {"counter_kind": kind}}
            validate_schema("native_v3/common/native_error.schema.json", value)
            for bad_context in (None, {}, {"counter_kind": "pending_upload_count"}, {"counter_kind": kind, "owner_override": "caller"}):
                with self.assertRaises(ValueError):
                    validate_schema("native_v3/common/native_error.schema.json", {**value, "context": bad_context})
            wrong = next(other for other, definition in registry["counter_kinds"].items() if definition["error"] != row["error"])
            with self.assertRaises(ValueError):
                validate_schema("native_v3/common/native_error.schema.json", {**value, "context": {"counter_kind": wrong}})

    def test_error_enum_never_accepts_unknown_code_or_free_context(self):
        value = {"code": "SYNC_PAYLOAD_INVALID", "message": "输入格式无效", "retryable": False, "context": None}
        validate_schema("native_v3/common/native_error.schema.json", value)
        for key, replacement in (("code", "SYNC_UNREVIEWED_NEW_ERROR"), ("context", {"raw_payload": "private"}),
                                 ("retryable", True), ("message", "")):
            with self.assertRaises(ValueError):
                validate_schema("native_v3/common/native_error.schema.json", {**value, key: replacement})

    def test_retry_hint_range_and_non_retryable_hint_are_closed(self):
        value = {"code": "API_RATE_LIMITED", "message": "请稍后重试", "retryable": True, "context": None,
                 "field_errors": [], "retry_after_seconds": 60}
        validate_schema("backend_sync_v1/common/api_error.schema.json", value)
        for hint in (0, -1, 86401, "60", True):
            with self.assertRaises(ValueError):
                validate_schema("backend_sync_v1/common/api_error.schema.json", {**value, "retry_after_seconds": hint})
        with self.assertRaises(ValueError):
            validate_schema("backend_sync_v1/common/api_error.schema.json", {**value, "code": "SYNC_PAYLOAD_INVALID", "retryable": False})

    def test_native_and_http_envelopes_keep_separate_versions_and_failure_null_data(self):
        error = {"code": "SYNC_PAYLOAD_INVALID", "message": "输入格式无效", "retryable": False, "context": None}
        native = {"ok": False, "data": None, "error": error, "contract_version": 3, "request_id": "synthetic"}
        api = {"ok": False, "data": None, "error": {**error, "field_errors": [], "retry_after_seconds": None},
               "contract_version": 1, "request_id": "synthetic"}
        validate_schema("native_v3/common/native_result.schema.json", native)
        validate_schema("backend_sync_v1/common/api_result.schema.json", api)
        for path, good, wrong_version in (("native_v3/common/native_result.schema.json", native, 1),
                                           ("backend_sync_v1/common/api_result.schema.json", api, 3)):
            for key, value in (("contract_version", wrong_version), ("data", {"leak": True}), ("error", None)):
                with self.assertRaises(ValueError):
                    validate_schema(path, {**good, key: value})

    def test_local_platform_auth_and_import_failures_never_become_saved_user_intent(self):
        registry = derive()[ROOT / "contracts/sync/sync_error_registry.yaml"]["errors"]
        for code in ("ALARM_SCHEDULE_FAILED", "AUTH_SESSION_EXPIRED", "API_RATE_LIMITED", "AI_EXTRACTION_FAILED",
                     "STORAGE_IO_ERROR", "SYNC_PAYLOAD_INVALID", "SYNC_COUNTER_EXHAUSTED", "IMPORT_BATCH_ABANDONED"):
            self.assertFalse(registry[code]["allows_local_saved_intent"], code)
            with self.assertRaises(ValueError):
                validate_schema("sync/sync_saved_intent_failure.schema.json", {"code": code, "context": None})
        for code in ("ALARM_SCHEDULE_FAILED", "RING_OUTPUT_UNAVAILABLE", "WORKSPACE_KEY_UNAVAILABLE", "SYNC_APPLY_FAILED"):
            value = {"code": code, "message": "本地失败", "retryable": registry[code]["retryable"], "context": None,
                     "field_errors": [], "retry_after_seconds": None}
            with self.assertRaises(ValueError):
                validate_schema("backend_sync_v1/common/api_error.schema.json", value)

    def test_backend_counter_context_cannot_claim_a_platform_owner(self):
        value = {"code": "SYNC_COUNTER_EXHAUSTED", "message": "计数达到上限", "retryable": False,
                 "context": {"counter_kind": "entity_version"}, "field_errors": [], "retry_after_seconds": None}
        validate_schema("backend_sync_v1/common/api_error.schema.json", value)
        with self.assertRaises(ValueError):
            validate_schema("backend_sync_v1/common/api_error.schema.json", {**value, "context": {"counter_kind": "session_generation"}})

    def test_terminal_business_rejection_keeps_exact_safe_context(self):
        a = "11111111-1111-4111-8111-111111111111"
        value = {"status": "rejected", "receipt": {"receipt_id": a, "device_id": a, "client_sequence": 1,
                 "mutation_id": a, "payload_hash": "0" * 64}, "effect": None, "per_key_results": [], "conflict_ids": [],
                 "failure_code": "SYNC_CONFLICT_VERSION_MISMATCH", "failure_context": {"conflict_id": a, "current_conflict_version": 2},
                 "import_batch_id": None, "import_stage": None}
        validate_schema("sync/sync_terminal_upload_result.schema.json", value)
        for patch in ({"failure_context": None}, {"failure_context": {"conflict_id": a, "current_conflict_version": 2, "raw_payload": {}}},
                      {"failure_code": "API_UNAUTHENTICATED", "failure_context": None},
                      {"failure_code": "SYNC_COUNTER_EXHAUSTED", "failure_context": {"counter_kind": "entity_version"}},
                      {"status": "accepted", "failure_code": None}):
            with self.assertRaises(ValueError):
                validate_schema("sync/sync_terminal_upload_result.schema.json", {**value, **patch})


if __name__ == "__main__":
    unittest.main()
