"""Reviewable test inputs; expected outcomes are explicit and do not come from validators."""
import copy
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[3]
T = "2026-09-05T01:00:00Z"
IDS = {name: f"{index:08d}-1111-4111-8111-111111111111" for index, name in enumerate(
    ("account", "category", "event", "event_rule", "anniversary", "anniversary_rule", "habit", "habit_rule"), 1)}


def derived(kind, values):
    namespace = uuid.uuid5(uuid.NAMESPACE_DNS, "excellent-calendar.local/sync-protocol-v1/" + kind)
    return str(uuid.uuid5(namespace, json.dumps(values, ensure_ascii=False, separators=(",", ":"))))


def build():
    facts = {
        "category": {"id": IDS["category"], "name": "工作", "description": None, "color": "#39AFBD", "icon": None,
                     "sort_order": 1, "created_at": T, "updated_at": T, "deleted_at": None, "reorder_revision": 0},
        "event": {"id": IDS["event"], "title": "会面", "content": None, "start_at": T, "end_at": "2026-09-05T02:00:00Z",
                  "start_date": None, "end_date": None, "is_all_day": False, "has_recurrence": False,
                  "status": "active", "completed_at": None, "recurrence_id": None, "recurrence_revision": None,
                  "category_id": "legacy-category😀", "importance": None, "location": None, "timezone": "Asia/Shanghai",
                  "source": "manual", "created_at": T, "updated_at": T, "deleted_at": None},
        "event_recurrence": {"recurrence_id": IDS["event_rule"], "revision": 1, "frequency": "daily", "interval": 1,
                             "start_at": T, "start_date": None, "timezone": "Asia/Shanghai", "day_of_month": None,
                             "days_of_week": [], "month_of_year": None, "end_at": None, "count": None, "created_at": T},
        "anniversary": {"id": IDS["anniversary"], "title": "纪念日", "date": "2024-02-29", "calendar_type": "solar",
                        "category_id": "legacy-category😀", "recurrence_id": IDS["anniversary_rule"], "note": None,
                        "importance": None, "created_at": T, "updated_at": T, "deleted_at": None},
        "anniversary_recurrence": {"recurrence_id": IDS["anniversary_rule"], "frequency": "yearly", "interval": 1,
                                   "created_at": T, "deleted_at": None},
        "habit": {"id": IDS["habit"], "title": "阅读", "description": None, "category_id": "legacy-category😀",
                  "recurrence_id": IDS["habit_rule"], "target_count_hundredths": 500, "unit": "页",
                  "start_date": "2026-09-01", "end_date": "2026-09-30", "ended_date": None, "is_active": True,
                  "first_check_in_at": T, "created_at": T, "updated_at": T, "deleted_at": None},
        "habit_recurrence": {"id": IDS["habit_rule"], "frequency": "daily", "interval": 1, "timezone_mode": "follow_device",
                             "created_at": T, "updated_at": T, "deleted_at": None},
        "habit_check_in": {"habit_id": IDS["habit"], "check_date": "2026-09-05", "status": "done",
                           "completed_count_hundredths": 500, "target_count_snapshot_hundredths": 500, "unit_snapshot": "页",
                           "completed_at": T, "note": None, "source": "manual", "created_at": T, "updated_at": T, "deleted_at": None},
        "user_preferences": {"timezone": "Asia/Shanghai", "habit_progress_color": "teal",
                             "default_reminder_methods": ["ring", "popup"], "auto_enable_reminders_on_other_devices": False},
        "account_profile": {"email": "synthetic@example.com", "username": "calendar_user", "display_name": "测试用户", "avatar": None},
        "reminder_intent_event": {"owner_type": "event", "owner_id": IDS["event"], "is_enabled": True,
                                  "templates": [{"remind_at": None, "advance_minutes": 15, "method": "popup", "message": None,
                                                 "is_enabled": True, "source": "manual"}]},
        "reminder_intent_anniversary": {"owner_type": "anniversary", "owner_id": IDS["anniversary"], "is_enabled": True,
                                        "templates": [{"advance_days": 7, "local_time": "09:00", "timezone_mode": "follow_device",
                                                       "method": "popup", "is_enabled": True}]},
        "reminder_intent_habit": {"owner_type": "habit", "owner_id": IDS["habit"], "is_enabled": True,
                                  "template": {"local_time": "09:00", "timezone_mode": "follow_device", "method": "popup"}},
    }
    original_local = "2026-09-05T09:00:00"
    key = str(uuid.uuid5(uuid.UUID("2fa8ebd0-958e-5eae-83d1-1aa5da893415"),
                         json.dumps([IDS["event"], 1, original_local], separators=(",", ":"))))
    facts["event_occurrence_state"] = {"event_id": IDS["event"], "recurrence_revision": 1, "occurrence_key": key,
        "occurrence_start_at": T, "occurrence_start_date": None, "original_local_start": original_local, "status": "completed",
        "state_changed_at": T, "reopened_at": None, "created_at": T, "updated_at": T}
    samples = {}
    for name, fact in facts.items():
        target = "reminder_intent" if name.startswith("reminder_intent_") else name
        if target == "reminder_intent":
            identifier = derived("reminder-intent", [fact["owner_type"], fact["owner_id"]])
        elif target == "habit_check_in":
            identifier = derived("habit-check-in", [fact["habit_id"], fact["check_date"]])
        elif target == "event_recurrence":
            identifier = fact["recurrence_id"] + "#1"
        elif target == "anniversary_recurrence":
            identifier = fact["recurrence_id"]
        elif target == "event_occurrence_state":
            identifier = key
        else:
            identifier = fact.get("id", IDS["account"])
        samples[name] = {"target_type": target, "target_id": identifier, "fact": fact}
    cases = [{"id": "TARGET-" + name + "-valid", "rule_anchor": "cloud-sync-02/7.7", "input": record, "expected_error": None}
             for name, record in samples.items()]
    changes = [
        ("event", "end_at", T, "EVENT_TIME_INVALID"),
        ("event", "start_date", "2026-09-05", "SYNC_PAYLOAD_INVALID"),
        ("event", "timezone", "+08:00", "SYNC_TIMEZONE_INVALID"),
        ("event", "start_at", "2026-09-05T09:00:00+08:00", "SYNC_PAYLOAD_INVALID"),
        ("event", "recurrence_revision", 1, "SYNC_PAYLOAD_INVALID"),
        ("event", "category_id", 7, "SYNC_PAYLOAD_INVALID"),
        ("event", "category_id", "", None),
        ("event", "source", "sync", None),
        ("category", "name", " ", "SYNC_PAYLOAD_INVALID"),
        ("category", "description", "", "SYNC_PAYLOAD_INVALID"),
        ("category", "sort_order", 9007199254740991, None),
        ("category", "sort_order", 9007199254740992, "SYNC_PAYLOAD_INVALID"),
        ("category", "sort_order", 1.5, "SYNC_PAYLOAD_INVALID"),
        ("category", "sort_order", 1.0, None),
        ("category", "sort_order", None, None),
        ("category", "sort_order", True, "SYNC_PAYLOAD_INVALID"),
        ("anniversary", "date", "2026-02-30", "SYNC_PAYLOAD_INVALID"),
        ("anniversary", "calendar_type", "lunar", "SYNC_PAYLOAD_INVALID"),
        ("anniversary", "category_id", "e\u0301😀", None),
        ("anniversary", "timezone", "Asia/Shanghai", "SYNC_PAYLOAD_INVALID"),
        ("habit", "end_date", "2027-12-31", "HABIT_DATE_RANGE_INVALID"),
        ("habit", "target_count_hundredths", 0, "SYNC_PAYLOAD_INVALID"),
        ("habit", "unit", None, "SYNC_PAYLOAD_INVALID"),
        ("habit_check_in", "status", "missed", "SYNC_PAYLOAD_INVALID"),
        ("habit_check_in", "completed_count_hundredths", 100, "HABIT_CHECK_IN_STATE_INVALID"),
        ("habit_check_in", "id", IDS["category"], "SYNC_PAYLOAD_INVALID"),
        ("habit_check_in", "source", "sync", "SYNC_PAYLOAD_INVALID"),
        ("habit_check_in", "source", "notification_action", None),
        ("habit_check_in", "deleted_at", T, None),
        ("habit_recurrence", "timezone_mode", "fixed", "SYNC_PAYLOAD_INVALID"),
        ("habit_recurrence", "frequency", "yearly", "SYNC_PAYLOAD_INVALID"),
        ("anniversary_recurrence", "interval", 2, "SYNC_PAYLOAD_INVALID"),
        ("event_recurrence", "revision", 9007199254740992, "SYNC_PAYLOAD_INVALID"),
        ("event_recurrence", "count", 10, "SYNC_PAYLOAD_INVALID"),
        ("event_recurrence", "frequency", "yearly", "SYNC_PAYLOAD_INVALID"),
        ("event_occurrence_state", "original_local_start", "2026-09-05T10:00:00", "SYNC_IDENTITY_MISMATCH"),
        ("event_occurrence_state", "status", "pending", "SYNC_PAYLOAD_INVALID"),
        ("user_preferences", "locale", "zh-CN", "SYNC_PAYLOAD_INVALID"),
        ("user_preferences", "habit_progress_color", "#39AFBD", "SYNC_PAYLOAD_INVALID"),
        ("user_preferences", "default_reminder_methods", ["wechat"], "SYNC_PAYLOAD_INVALID"),
        ("user_preferences", "default_reminder_methods", ["popup", "popup"], "SYNC_PAYLOAD_INVALID"),
        ("user_preferences", "default_reminder_methods", [], None),
        ("user_preferences", "default_reminder_methods", ["popup", "ring"], None),
        ("account_profile", "access_token", "synthetic-secret-never-a-profile-field", "SYNC_PAYLOAD_INVALID"),
        ("account_profile", "timezone", "Asia/Shanghai", "SYNC_PAYLOAD_INVALID"),
        ("reminder_intent_habit", "template", None, "HABIT_REMINDER_CONFIG_INVALID"),
        ("reminder_intent_event", "notification_status", "delivered", "SYNC_PAYLOAD_INVALID"),
    ]
    for ordinal, (name, field, value, error) in enumerate(changes, 1):
        record = copy.deepcopy(samples[name])
        record["fact"][field] = value
        cases.append({"id": f"TARGET-boundary-{ordinal:03d}-{name}-{field}", "rule_anchor": "cloud-sync-02/7.7",
                      "input": record, "expected_error": error})
    return {"fixture_version": 1, "family": "FX-TARGET", "scope": "typed_fact_and_reference_oracle_not_complete_mutation_protocol",
            "samples": samples, "cases": cases}


if __name__ == "__main__":
    path = ROOT / "contracts/fixtures/sync/v1/target_vectors.json"
    value = build()
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(value["cases"])}))
