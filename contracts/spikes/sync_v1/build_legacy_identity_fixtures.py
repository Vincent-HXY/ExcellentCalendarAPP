"""Literal legacy-v1 migration and lossless eligibility cases (no user data)."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "contracts/fixtures/sync/v1/legacy_identity_vectors.json"
TARGET = "77777777-7777-4777-8777-777777777777"


def derive():
    event = {"id": "old/event😀", "title": "旧日程", "content": None, "start_at": "2026-09-05T01:00:00Z",
        "end_at": "2026-09-05T02:00:00Z", "is_all_day": False, "has_recurrence": False,
        "status": "active", "completed_at": None, "recurrence_id": None, "category_id": "  e\u0301😀  ",
        "importance": None, "location": None, "timezone": "Asia/Shanghai", "source": "manual",
        "created_at": "2026-09-01T00:00:00Z", "updated_at": "2026-09-02T00:00:00Z", "deleted_at": None}
    reminder = {"id": "old/reminder", "target_type": "event", "target_id": event["id"],
        "remind_at": "2026-09-05T00:45:00Z", "advance_minutes": 15, "methods": ["ring", "popup"],
        "message": "旧提醒", "is_enabled": True, "status": "scheduled", "scheduled_at": "2026-09-04T00:00:00Z",
        "last_triggered_at": None, "failure_reason": None, "cancellation_reason": None, "source": "manual",
        "created_at": event["created_at"], "updated_at": event["updated_at"], "deleted_at": None}
    cases = []

    def add(name, events, reminders=None, *, error=None, event_count=1, intent_count=0, core_error=None):
        cases.append({"id": "LEGACY-" + name, "family": "FX-TARGET", "rule_anchor": "cloud-sync-02/4.2,7.6/IMP-01,IMP-09",
            "input": {"events": events, "reminders": reminders or [], "target_uuid": TARGET},
            "expected": {"core_error": core_error, "projection_error": error,
                "portable_events": 0 if error else event_count, "portable_intents": 0 if error else intent_count,
                "v1_to_v5_migration_ids": ["calendar_core_json_v1_compat_to_sqlite_v4", "calendar_core_sqlite_v4_to_v5_habit_v1"]}})
    add("opaque-id-and-weak-category", [event])
    add("two-methods-one-owned-intent", [event], [reminder], intent_count=1)
    disabled = copy.deepcopy(reminder); disabled["is_enabled"] = False
    add("disabled-configuration-preserved", [event], [disabled], intent_count=1)
    terminal = copy.deepcopy(reminder); terminal["status"] = "sent"; terminal["last_triggered_at"] = terminal["remind_at"]
    add("terminal-delivery-stays-guest", [event], [terminal])
    absolute = copy.deepcopy(reminder); absolute["advance_minutes"] = None
    add("absolute-reminder-time-preserved", [event], [absolute], intent_count=1)
    for name, changes, error in (
        ("uuid-lexeme-is-still-legacy", {"id": TARGET}, None),
        ("missing-timezone-no-device-default", {"timezone": None}, "IMPORT_REFERENCE_INVALID"),
        ("unknown-timezone", {"timezone": "Unknown/Zone"}, "SYNC_TIMEZONE_INVALID"),
        ("all-day-no-invented-civil-dates", {"is_all_day": True}, "IMPORT_REFERENCE_INVALID"),
        ("recurrence-without-rule-or-revision", {"has_recurrence": True, "recurrence_id": "legacy/rule"}, "IMPORT_REFERENCE_INVALID"),
        ("dangling-recurrence-link", {"recurrence_id": "legacy/rule"}, "IMPORT_REFERENCE_INVALID"),
        ("legacy-invalid-time-order", {"end_at": event["start_at"]}, "EVENT_TIME_INVALID"),
        ("source-identity-too-long-no-truncation", {"id": "中" * 100}, "IMPORT_REFERENCE_INVALID"),
    ):
        add(name, [{**event, **changes}], error=error)
    missing = {key: value for key, value in event.items() if key not in {"content", "location", "importance"}}
    add("missing-optional-preserved-as-null", [missing])
    add("deleted-event-stays-local-audit", [{**event, "deleted_at": "2026-09-04T00:00:00Z"}], event_count=0)
    add("legacy-unsupported-wechat-no-silent-drop", [event], [{**reminder, "methods": ["wechat"]}], error="REMINDER_METHOD_UNSUPPORTED")
    add("legacy-orphan-reminder", [event], [{**reminder, "target_id": "missing"}], error="IMPORT_REFERENCE_INVALID")
    add("advance-and-stored-time-disagree", [event], [{**reminder, "advance_minutes": 30}], error="IMPORT_REFERENCE_INVALID")
    add("corrupted-required-field-rejected-by-core", [{**event, "start_at": "invalid"}], error="STORAGE_DATA_CORRUPTED", core_error="STORAGE_DATA_CORRUPTED")
    return {"fixture_version": 1, "scope": "unchanged Core v1 migration plus explicit read-only conversion eligibility; no product converter",
            "cases": cases}


if __name__ == "__main__":
    value = derive(); FIXTURE.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(value["cases"])}))
