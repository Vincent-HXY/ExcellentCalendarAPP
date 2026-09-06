"""Target HTTP constraints are separate from the observed old implementation."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "contracts/spikes/sync_v1"), str(ROOT / "contracts"),
                str(Path(tempfile.gettempdir()) / "excellent-calendar-contract-validation-py310")]
from build_backend_sync_revision import derive, yaml, NEW_ENDPOINTS, UNREGISTERED, PENDING
from domain_reference import validate_schema


class BackendRevisionTests(unittest.TestCase):
    def valid(self, path, data):
        validate_schema("backend_sync_v1/" + path + ".schema.json", data)

    def invalid(self, path, data):
        with self.assertRaisesRegex(ValueError, "SYNC_PAYLOAD_INVALID"):
            self.valid(path, data)

    def test_exact_generated_revision_and_old_endpoints_remain_present(self):
        for path, expected in derive().items():
            actual = yaml.safe_load(path.read_text(encoding="utf-8")) if path.suffix == ".yaml" else json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(actual, expected)
        old = yaml.safe_load((ROOT / "contracts/backend_api.yaml").read_text(encoding="utf-8"))
        revision = yaml.safe_load((ROOT / "contracts/backend_sync_v1/backend_api.yaml").read_text(encoding="utf-8"))
        self.assertEqual(set(old["endpoints"]) | set(NEW_ENDPOINTS), set(revision["endpoints"]))
        self.assertFalse(revision["endpoints"]["auth.registration.email.update"]["existing_controller"])
        self.assertEqual(revision["http_conventions"]["idempotency_payload_mismatch"], {"http_status": 409, "code": "API_IDEMPOTENCY_KEY_REUSED"})

    def test_registration_locale_and_no_scalar_coercion(self):
        body = {"email": "contract@example.test", "username": "contract_test", "display_name": "固定测试", "password": "test-only-example",
            "locale": "zh-CN", "timezone": "Asia/Shanghai", "agreement_version": "v1", "agreement_accepted": True}
        self.valid("auth/registration_request", body)
        for name, value in (("locale", "en-US"), ("password", 123456789), ("agreement_accepted", "true"), ("unknown", True)):
            self.invalid("auth/registration_request", {**body, name: value})

    def test_profile_writer_cannot_update_preferences_or_arbitrary_settings(self):
        self.valid("user/update_current_user_request", {"display_name": "资料名称"})
        self.valid("user/update_current_user_request", {"username": "profile_owner"})
        self.invalid("user/update_current_user_request", {})
        for name, value in (("timezone", "UTC"), ("locale", "zh-CN"), ("settings", {}), ("default_reminder_methods", ["popup"]), ("avatar_asset_id", "11111111-1111-4111-8111-111111111111")):
            self.invalid("user/update_current_user_request", {"display_name": "资料名称", name: value})

    def test_profile_and_preference_revisions_are_distinct_required_fields(self):
        schema = json.loads((ROOT / "contracts/backend_sync_v1/user/current_user_response.schema.json").read_text(encoding="utf-8"))
        self.assertEqual(set(schema["required"]), {"account", "profile", "preferences", "account_profile_revision", "preferences_revision", "legacy_locale"})
        self.assertEqual(schema["properties"]["preferences"]["$ref"], "https://excellent-calendar.local/contracts/sync/v1/user_preferences_fact.schema.json")
        self.assertNotIn("settings", schema["properties"])

    def test_every_planned_http_route_has_strict_schema_and_explicit_location(self):
        revision = derive()[ROOT / "contracts/backend_sync_v1/backend_api.yaml"]
        self.assertEqual(len(NEW_ENDPOINTS), 18)
        for operation in NEW_ENDPOINTS:
            endpoint = revision["endpoints"][operation]
            self.assertFalse(endpoint["existing_controller"])
            self.assertEqual(endpoint["implementation_status"], "planned")
            self.assertTrue((ROOT / "contracts" / endpoint["request"]).is_file(), operation)
            self.assertTrue((ROOT / "contracts" / endpoint["result"]["data"]).is_file(), operation)
            if endpoint["method"] == "GET":
                self.assertEqual(endpoint["get_body"], "forbidden")
                self.assertEqual(endpoint["request_location"], "query")
        self.assertEqual(revision["endpoints"]["system.time"]["account_session_device_database_access"], "forbidden")
        self.assertTrue(revision["endpoints"]["device.revoke"]["reauth_header"]["single_use"])

    def test_registration_gate_is_a_closed_allowlist_in_all_three_states(self):
        from lifecycle_reference import backend_capability
        revision = derive()[ROOT / "contracts/backend_sync_v1/backend_api.yaml"]
        for state, expected in (("unregistered", UNREGISTERED), ("pending_registration", PENDING)):
            self.assertEqual({name for name in revision["endpoints"] if backend_capability(state, name)}, expected)
        for state in ("unregistered", "pending_registration", "registered"):
            self.assertFalse(backend_capability(state, "future.unknown"))
            self.assertFalse(backend_capability(state, "system.time"))
        self.assertFalse(backend_capability("pending_registration", "device.register", same_installation=False))


if __name__ == "__main__":
    unittest.main()
