"""Complete ordinary Event audit records, independent of the retirement writer."""
import uuid

NOW = "2026-09-06T06:00:00Z"


def identifier(label):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "excellent-calendar/review/" + label))


def reminder(target, label, *, sent=False):
    return {"reminder_id": identifier(label), "target_type": "event", "target_id": target,
        "recurrence_revision": None, "occurrence_key": None, "occurrence_start_at": None,
        "template_key": None, "occurrence_date": None, "advance_days": None, "local_time": None,
        "timezone_mode": None, "fulfillment_delivery_id": None, "remind_at": NOW,
        "advance_minutes": 0, "methods": ["popup"], "message": "Retain the original audit message",
        "is_enabled": True, "status": "sent" if sent else "pending", "scheduled_at": None,
        "last_triggered_at": NOW if sent else None, "failure_reason": None,
        "last_cancellation_reason": None, "last_cancelled_at": None, "expiration_reason": None,
        "expired_at": None, "reactivated_at": None, "reactivation_count": 0,
        "created_at": NOW, "updated_at": NOW, "deleted_at": None,
        "source": "manual", "recovery_batch_id": None}


def notification(parent, label, *, sent=False):
    return {"notification_id": identifier(label), "delivery_id": identifier(label + "/delivery"),
        "delivery_attempt_id": identifier(label + "/attempt"), "kind": "reminder",
        "reminder_id": parent["reminder_id"], "recovery_batch_id": None, "resolved_by_recovery_batch_id": None,
        "target_type": "event", "target_id": parent["target_id"], "occurrence_key": None,
        "covered_reminder_ids": [], "method": "popup", "title": "Original title", "body": "Original body",
        "planned_at": NOW, "status": "sent" if sent else "prepared", "failure_class": None,
        "error_code": None, "abandon_reason": None, "prepared_at": NOW,
        "finalized_at": NOW if sent else None, "sent_at": NOW if sent else None,
        "created_at": NOW, "updated_at": NOW}
