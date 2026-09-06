"""Read-only eligibility/projection oracle for frozen JSON v1 compatibility rows.

The actual Core reader/migration is exercised separately. This module never opens a
guest database, allocates identities or erases history. Call it before lease/mapping
allocation, then project once more with the durable mapping inside the writer txn.
"""
import base64
import copy
from datetime import datetime, timedelta

from domain_reference import check, validate_fact, validate_graph
from identity_reference import canonical_uuid, reminder_intent_id

PREFIX = "legacy-v1/event/"
EVENT_FIELDS = set("id title content start_at end_at is_all_day has_recurrence status completed_at recurrence_id category_id importance location timezone source created_at updated_at deleted_at".split())
REMINDER_FIELDS = set("id target_type target_id remind_at methods advance_minutes message is_enabled status scheduled_at last_triggered_at failure_reason cancellation_reason source created_at updated_at deleted_at".split())
OPTIONAL = set("content completed_at recurrence_id category_id importance location timezone deleted_at".split())


def legacy_source_id(value: str) -> str:
    check(isinstance(value, str) and bool(value), "IMPORT_REFERENCE_INVALID")
    try:
        raw = value.encode("utf-8", errors="strict")
    except UnicodeError:
        raise ValueError("IMPORT_REFERENCE_INVALID") from None
    result = PREFIX + base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    check(len(result) <= 256, "IMPORT_REFERENCE_INVALID")
    return result


def decode_legacy_source_id(value: str) -> str:
    check(isinstance(value, str) and value.startswith(PREFIX), "IMPORT_REFERENCE_INVALID")
    encoded = value[len(PREFIX):]
    try:
        raw = base64.b64decode(encoded + "=" * (-len(encoded) % 4), altchars=b"-_", validate=True).decode("utf-8", errors="strict")
    except (ValueError, UnicodeError):
        raise ValueError("IMPORT_REFERENCE_INVALID") from None
    check(legacy_source_id(raw) == value, "IMPORT_REFERENCE_INVALID")
    return raw


def project_legacy_graph(events: list[dict], reminders: list[dict], mapping: dict[str, str]) -> list[dict]:
    """No guesses for missing timezone, civil dates, recurrence rules or references.

    mapping keys are explicit encoded source IDs. Deleted domain rows and terminal
    execution history stay in the guest partition, as required by IMP-09.
    """
    all_ids = [row.get("id") for row in events]
    check(all(isinstance(value, str) for value in all_ids) and len(set(all_ids)) == len(all_ids), "IMPORT_DUPLICATE_IDENTITY")
    reminder_ids = [row.get("id") for row in reminders]
    check(all(isinstance(value, str) for value in reminder_ids) and len(set(reminder_ids)) == len(reminder_ids), "IMPORT_DUPLICATE_IDENTITY")
    records, live, owned = [], {}, {}
    for source in events:
        check(set(source) <= EVENT_FIELDS and EVENT_FIELDS - OPTIONAL <= set(source), "IMPORT_REFERENCE_INVALID")
        row = {**{name: None for name in OPTIONAL}, **copy.deepcopy(source)}
        if row["deleted_at"] is not None:
            continue
        source_id = legacy_source_id(row["id"])
        check(source_id in mapping, "IMPORT_REFERENCE_INVALID")
        identifier = canonical_uuid(mapping[source_id], 4)
        # V1 has no persisted recurrence revision/rule table or date-only range.
        check(row["is_all_day"] is False and row["has_recurrence"] is False and row["recurrence_id"] is None,
              "IMPORT_REFERENCE_INVALID")
        check(isinstance(row["timezone"], str) and bool(row["timezone"]), "IMPORT_REFERENCE_INVALID")
        row.update(id=identifier, start_date=None, end_date=None, recurrence_revision=None)
        record = {"target_type": "event", "target_id": identifier, "fact": row}
        validate_fact(record)
        records.append(record)
        live[source["id"]] = row
    check(len({row["target_id"] for row in records}) == len(records), "IMPORT_DUPLICATE_IDENTITY")
    for reminder in reminders:
        check(set(reminder) <= REMINDER_FIELDS, "IMPORT_REFERENCE_INVALID")
        if reminder.get("deleted_at") is not None or reminder.get("status") not in {"pending", "scheduled"}:
            continue
        check(reminder.get("target_type") == "event" and reminder.get("target_id") in live, "IMPORT_REFERENCE_INVALID")
        owner = live[reminder["target_id"]]
        # A completed owner cannot acquire a newly active portable reminder.
        check(owner["status"] == "active", "IMPORT_REFERENCE_INVALID")
        identifier = reminder_intent_id("event", owner["id"])
        fact = owned.setdefault(identifier, {"owner_type": "event", "owner_id": owner["id"], "is_enabled": False, "templates": []})
        methods = reminder.get("methods")
        check(isinstance(methods, list) and bool(methods) and len(methods) == len(set(methods))
              and all(method in {"ring", "popup"} for method in methods), "REMINDER_METHOD_UNSUPPORTED")
        advance = reminder.get("advance_minutes")
        if advance is not None:
            check(type(advance) is int and 0 <= advance <= 2147483647, "IMPORT_REFERENCE_INVALID")
            expected = datetime.fromisoformat(owner["start_at"].replace("Z", "+00:00")) - timedelta(minutes=advance)
            check(expected.isoformat(timespec="seconds").replace("+00:00", "Z") == reminder.get("remind_at"), "IMPORT_REFERENCE_INVALID")
        for method in methods:
            fact["templates"].append({"remind_at": reminder.get("remind_at") if advance is None else None,
                "advance_minutes": advance, "method": method, "message": reminder.get("message"),
                "is_enabled": reminder.get("is_enabled"), "source": reminder.get("source")})
        fact["is_enabled"] = fact["is_enabled"] or reminder.get("is_enabled") is True
    for identifier, fact in sorted(owned.items()):
        records.append({"target_type": "reminder_intent", "target_id": identifier, "fact": fact})
    validate_graph(records)
    return records
