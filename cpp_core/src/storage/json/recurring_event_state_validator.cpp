#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

#include <algorithm>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {
namespace {

class DecodeFailure final : public std::runtime_error {
 public:
  explicit DecodeFailure(std::string message)
      : std::runtime_error(std::move(message)) {}
};

common::Result<common::Unit> corrupted(const std::exception& error) {
  return common::Result<common::Unit>::failure(
      storage_data_corrupted(error.what()));
}

template <typename T>
bool insert_unique(std::set<T>& values, T value) {
  return values.insert(std::move(value)).second;
}

bool valid_optional_instant(const std::optional<std::string>& value) {
  return !value.has_value() || common::is_iso8601_utc_datetime(*value);
}

std::set<std::string> validate_events(
    const repository::RecurringEventState& state) {
  std::set<std::string> ids;
  std::set<std::string> event_ids;
  for (const auto& event : state.events) {
    if (!common::is_uuid(event.id) || event.title.empty() || !event.timezone.has_value() ||
        event.timezone->empty() || !domain::is_valid_event_status(event.status) ||
        !domain::is_valid_create_event_source(event.source) ||
        (event.importance.has_value() && !domain::is_valid_importance(*event.importance)) ||
        !common::is_iso8601_utc_datetime(event.created_at) ||
        !common::is_iso8601_utc_datetime(event.updated_at) ||
        !valid_optional_instant(event.completed_at) || !valid_optional_instant(event.deleted_at) ||
        event.recurrence_id.has_value() != event.recurrence_revision.has_value() ||
        event.has_recurrence != event.recurrence_id.has_value() ||
        (event.status == domain::kEventStatusCompleted) != event.completed_at.has_value()) {
      throw DecodeFailure("Event invariant is invalid");
    }
    if (event.is_all_day) {
      if (!event.start_at.empty() || !event.end_at.empty() || !event.start_date.has_value() ||
          !event.end_date.has_value() || !domain::parse_local_date(*event.start_date).ok() ||
          !domain::parse_local_date(*event.end_date).ok() ||
          *event.start_date >= *event.end_date) {
        throw DecodeFailure("Event all-day shape is invalid");
      }
    } else if (event.start_at.empty() || event.end_at.empty() || event.start_date.has_value() ||
                event.end_date.has_value() ||
                !common::is_iso8601_utc_datetime(event.start_at) ||
                !common::is_iso8601_utc_datetime(event.end_at) ||
                event.start_at >= event.end_at) {
      throw DecodeFailure("Event timed shape is invalid");
    }
    if (!insert_unique(ids, event.id)) throw DecodeFailure("Event ID is duplicated");
    event_ids.insert(event.id);
  }
  return event_ids;
}

std::set<std::string> validate_recurrences(
    const repository::RecurringEventState& state,
    const std::set<std::string>& event_ids) {
  std::set<std::string> ids;
  std::set<std::string> recurrence_keys;
  for (const auto& recurrence : state.recurrences) {
    const bool timed_start = recurrence.start_at.has_value() &&
                             common::is_iso8601_utc_datetime(*recurrence.start_at) &&
                             !recurrence.start_date.has_value();
    const bool all_day_start = !recurrence.start_at.has_value() &&
                               recurrence.start_date.has_value() &&
                               domain::parse_local_date(*recurrence.start_date).ok();
    const bool daily_shape = recurrence.frequency == domain::kRecurrenceDaily &&
                             recurrence.days_of_week.empty() &&
                             !recurrence.day_of_month.has_value();
    const bool weekly_shape = recurrence.frequency == domain::kRecurrenceWeekly &&
                              recurrence.days_of_week.size() == 1U &&
                              recurrence.days_of_week.front() >= 1 &&
                              recurrence.days_of_week.front() <= 7 &&
                              !recurrence.day_of_month.has_value();
    const bool monthly_shape = recurrence.frequency == domain::kRecurrenceMonthly &&
                               recurrence.days_of_week.empty() &&
                               recurrence.day_of_month.has_value() &&
                               *recurrence.day_of_month >= 1 &&
                               *recurrence.day_of_month <= 31;
    if (!common::is_uuid(recurrence.id) || recurrence.revision < 1 || recurrence.interval != 1 ||
        !domain::is_supported_recurrence_frequency(recurrence.frequency) ||
        recurrence.timezone.empty() || !common::is_iso8601_utc_datetime(recurrence.created_at) ||
        (!timed_start && !all_day_start) || (!daily_shape && !weekly_shape && !monthly_shape) ||
        recurrence.end_at.has_value() || recurrence.count.has_value() ||
        recurrence.month_of_year.has_value()) {
      throw DecodeFailure("Recurrence invariant is invalid");
    }
    if (!insert_unique(ids, recurrence.id + ":" + std::to_string(recurrence.revision))) {
      throw DecodeFailure("Recurrence revision is duplicated");
    }
    recurrence_keys.insert(recurrence.id + ":" + std::to_string(recurrence.revision));
  }
  for (const auto& event : state.events) {
    if (event.recurrence_id.has_value() &&
        recurrence_keys.find(*event.recurrence_id + ":" +
                             std::to_string(*event.recurrence_revision)) == recurrence_keys.end()) {
      throw DecodeFailure("Event current recurrence revision is missing");
    }
  }
  return recurrence_keys;
}

void validate_occurrence_states(
    const repository::RecurringEventState& state,
    const std::set<std::string>& event_ids) {
  std::set<std::string> ids;
  for (const auto& item : state.occurrence_states) {
    const bool timed_start = item.occurrence_start_at.has_value() &&
                             common::is_iso8601_utc_datetime(*item.occurrence_start_at) &&
                             !item.occurrence_start_date.has_value();
    const bool all_day_start = !item.occurrence_start_at.has_value() &&
                               item.occurrence_start_date.has_value() &&
                               domain::parse_local_date(*item.occurrence_start_date).ok();
    if (!common::is_uuid(item.event_id) || !common::is_uuid(item.occurrence_key) ||
        item.recurrence_revision < 1 || !domain::is_valid_occurrence_status(item.status) ||
        (!timed_start && !all_day_start) || event_ids.find(item.event_id) == event_ids.end() ||
        !common::is_iso8601_utc_datetime(item.state_changed_at) ||
        !common::is_iso8601_utc_datetime(item.created_at) ||
        !common::is_iso8601_utc_datetime(item.updated_at) ||
        !valid_optional_instant(item.reopened_at)) {
      throw DecodeFailure("EventOccurrenceState invariant is invalid");
    }
    if (!insert_unique(ids, item.event_id + ":" + std::to_string(item.recurrence_revision) + ":" +
                               item.occurrence_key)) {
      throw DecodeFailure("EventOccurrenceState identity is duplicated");
    }
  }
}

void validate_reminders(
    const repository::RecurringEventState& state,
    const std::set<std::string>& event_ids,
    const std::set<std::string>& recurrence_keys) {
  std::set<std::string> ids;
  std::set<std::string> reminder_business_keys;
  for (const auto& reminder : state.reminders) {
    const bool recurring = reminder.recurrence_revision.has_value();
    if (!common::is_uuid(reminder.id) || !domain::is_valid_reminder_target_type(reminder.target_type) ||
        !domain::is_valid_reminder_status(reminder.status) || reminder.methods.empty() ||
        !common::is_uuid(reminder.target_id) ||
        !common::is_iso8601_utc_datetime(reminder.remind_at) ||
        !domain::is_valid_reminder_source(reminder.source) ||
        !common::is_iso8601_utc_datetime(reminder.created_at) ||
        !common::is_iso8601_utc_datetime(reminder.updated_at) ||
        !valid_optional_instant(reminder.scheduled_at) ||
         !valid_optional_instant(reminder.last_triggered_at) ||
         !valid_optional_instant(reminder.last_cancelled_at) ||
         !valid_optional_instant(reminder.expired_at) ||
         !valid_optional_instant(reminder.reactivated_at) ||
        !valid_optional_instant(reminder.deleted_at) ||
        reminder.reactivation_count < 0 ||
        recurring != reminder.occurrence_key.has_value() || recurring != reminder.occurrence_start_at.has_value()) {
      throw DecodeFailure("Reminder invariant is invalid");
    }
    if ((reminder.status == domain::kReminderStatusScheduled &&
         !reminder.scheduled_at.has_value()) ||
        (reminder.status == domain::kReminderStatusSent &&
         !reminder.last_triggered_at.has_value()) ||
        (reminder.status == domain::kReminderStatusFailed &&
         !reminder.failure_reason.has_value()) ||
         (reminder.status == domain::kReminderStatusCancelled &&
          (!reminder.cancellation_reason.has_value() ||
           !reminder.last_cancelled_at.has_value())) ||
         (reminder.status == domain::kReminderStatusExpired &&
          (reminder.is_enabled || reminder.scheduled_at.has_value() ||
           reminder.expiration_reason != std::optional<std::string>(
               domain::kReminderExpirationReasonRecoveryWindowElapsed) ||
           !reminder.expired_at.has_value())) ||
         (reminder.status != domain::kReminderStatusExpired &&
          (reminder.expiration_reason.has_value() || reminder.expired_at.has_value()))) {
      throw DecodeFailure("Reminder status audit invariant is invalid");
    }
    std::set<std::string> methods;
    for (const auto& method : reminder.methods) {
      if (!domain::is_valid_reminder_method(method) || !methods.insert(method).second) {
        throw DecodeFailure("Reminder methods are invalid");
      }
    }
    if ((reminder.cancellation_reason.has_value() &&
         !domain::is_valid_reminder_cancellation_reason(*reminder.cancellation_reason)) ||
         (reminder.recovery_batch_id.has_value() &&
          !common::is_uuid(*reminder.recovery_batch_id))) {
      throw DecodeFailure("Reminder audit identity is invalid");
    }
    if (reminder.target_type == domain::kReminderTargetEvent &&
        event_ids.find(reminder.target_id) == event_ids.end()) {
      throw DecodeFailure("Reminder Event target is missing");
    }
    if (recurring) {
      const auto event = std::find_if(
          state.events.begin(), state.events.end(), [&](const auto& value) {
            return value.id == reminder.target_id;
          });
      if (reminder.target_type != domain::kReminderTargetEvent ||
          !common::is_uuid(*reminder.occurrence_key) ||
          !common::is_iso8601_utc_datetime(*reminder.occurrence_start_at) ||
          !reminder.advance_minutes.has_value() || *reminder.advance_minutes < 0 ||
          reminder.methods != std::vector<std::string>{"popup"} ||
          event == state.events.end() ||
          !event->recurrence_id.has_value() ||
          recurrence_keys.find(*event->recurrence_id + ":" +
                               std::to_string(*reminder.recurrence_revision)) ==
              recurrence_keys.end()) {
        throw DecodeFailure("Recurring Reminder invariant is invalid");
      }
      const auto business_key = reminder.target_id + ":" +
                                std::to_string(*reminder.recurrence_revision) + ":" +
                                *reminder.occurrence_key + ":" +
                                std::to_string(*reminder.advance_minutes) + ":[popup]";
      if (!insert_unique(reminder_business_keys, business_key)) {
        throw DecodeFailure("Recurring Reminder business identity is duplicated");
      }
    }
    if (!insert_unique(ids, reminder.id)) throw DecodeFailure("Reminder ID is duplicated");
  }
}

void validate_notifications(
    const repository::RecurringEventState& state) {
  std::set<std::string> ids;
  std::set<std::string> attempts;
  std::set<std::string> prepared_deliveries;
  std::set<std::string> sent_deliveries;
  for (const auto& notification : state.notifications) {
    if (!common::is_uuid(notification.id) || !notification.delivery_id.has_value() ||
        !notification.delivery_attempt_id.has_value() ||
        !common::is_uuid(*notification.delivery_id) ||
        !common::is_uuid(*notification.delivery_attempt_id) ||
         (notification.status != domain::kNotificationStatusPrepared &&
          notification.status != domain::kNotificationStatusSent &&
          notification.status != domain::kNotificationStatusFailed &&
          notification.status != domain::kNotificationStatusAbandoned) ||
        !domain::is_valid_notification_target_type(notification.target_type) ||
        !common::is_uuid(notification.target_id) ||
        notification.method != domain::kReminderMethodPopup ||
        common::trim_ascii(notification.title).empty() ||
        !common::is_iso8601_utc_datetime(notification.planned_at) ||
         !notification.prepared_at.has_value() ||
         !common::is_iso8601_utc_datetime(*notification.prepared_at) ||
         (notification.resolved_by_recovery_batch_id.has_value() &&
          !common::is_uuid(*notification.resolved_by_recovery_batch_id)) ||
        !common::is_iso8601_utc_datetime(notification.created_at) ||
        !common::is_iso8601_utc_datetime(notification.updated_at)) {
      throw DecodeFailure("Notification invariant is invalid");
    }
    if (notification.kind == "reminder") {
      if (!notification.reminder_id.has_value() ||
          !common::is_uuid(*notification.reminder_id) ||
          std::find_if(state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
            return reminder.id == *notification.reminder_id;
          }) == state.reminders.end() ||
          notification.target_type == "reminder_recovery_batch") {
        throw DecodeFailure("Reminder Notification identity is invalid");
      }
    } else if (notification.kind == "recovery_summary") {
      if (notification.reminder_id.has_value() || !notification.recovery_batch_id.has_value() ||
          !common::is_uuid(*notification.recovery_batch_id) ||
          notification.target_type != "reminder_recovery_batch" ||
          notification.target_id != *notification.recovery_batch_id ||
          notification.occurrence_key.has_value()) {
        throw DecodeFailure("Recovery summary Notification identity is invalid");
      }
    } else {
      throw DecodeFailure("Notification kind is invalid");
    }
    if (notification.status == domain::kNotificationStatusPrepared) {
      if (notification.failure_class.has_value() || notification.error_code.has_value() ||
          notification.abandon_reason.has_value() || notification.finalized_at.has_value() ||
          notification.sent_at.has_value()) {
        throw DecodeFailure("Prepared Notification finalization fields are invalid");
      }
    } else if (notification.status == domain::kNotificationStatusSent) {
      if (notification.failure_class.has_value() || notification.error_code.has_value() ||
          notification.abandon_reason.has_value() ||
          !notification.finalized_at.has_value() || !notification.sent_at.has_value() ||
          !common::is_iso8601_utc_datetime(*notification.finalized_at) ||
          !common::is_iso8601_utc_datetime(*notification.sent_at)) {
        throw DecodeFailure("Sent Notification finalization fields are invalid");
      }
    } else if (notification.status == domain::kNotificationStatusFailed) {
      if (!notification.failure_class.has_value() ||
          (*notification.failure_class != "retryable" &&
           *notification.failure_class != "permanent") ||
          !notification.error_code.has_value() ||
          common::trim_ascii(*notification.error_code).empty() ||
          notification.abandon_reason.has_value() ||
          !notification.finalized_at.has_value() ||
          !common::is_iso8601_utc_datetime(*notification.finalized_at) ||
          notification.sent_at.has_value()) {
        throw DecodeFailure("Failed Notification finalization fields are invalid");
      }
    } else if (!notification.resolved_by_recovery_batch_id.has_value() ||
               notification.failure_class.has_value() ||
               notification.error_code.has_value() ||
               (notification.abandon_reason != "recovery_window_elapsed" &&
                notification.abandon_reason != "recovery_summary_superseded") ||
               !notification.finalized_at.has_value() ||
               !common::is_iso8601_utc_datetime(*notification.finalized_at) ||
               notification.sent_at.has_value()) {
      throw DecodeFailure("Abandoned Notification finalization fields are invalid");
    }
    if (!insert_unique(ids, notification.id) ||
        !insert_unique(attempts, *notification.delivery_attempt_id)) {
      throw DecodeFailure("Notification identity is duplicated");
    }
    if (notification.status == domain::kNotificationStatusPrepared &&
        !insert_unique(prepared_deliveries, *notification.delivery_id)) {
      throw DecodeFailure("Prepared delivery is duplicated");
    }
    if (notification.status == domain::kNotificationStatusSent &&
        !insert_unique(sent_deliveries, *notification.delivery_id)) {
      throw DecodeFailure("Sent delivery is duplicated");
    }
  }
}

void validate_recovery_integrity(
    const repository::RecurringEventState& state) {
  std::set<std::string> ids;
  std::set<std::string> requests;
  bool has_in_progress = false;
  for (const auto& batch : state.recovery_batches) {
    if (!common::is_uuid(batch.id) || !common::is_uuid(batch.recovery_request_id) ||
        !domain::is_valid_recovery_trigger_source(batch.trigger_source) ||
        !common::is_iso8601_utc_datetime(batch.started_at) ||
        !common::is_iso8601_utc_datetime(batch.window_start_at) ||
        batch.window_overflow_count != static_cast<int>(batch.summary_reminder_ids.size()) ||
        batch.older_skipped_occurrence_count < 0 || batch.older_skipped_reminder_count < 0) {
      throw DecodeFailure("ReminderRecoveryBatch invariant is invalid");
    }
    if (!insert_unique(ids, batch.id) || !insert_unique(requests, batch.recovery_request_id)) {
      throw DecodeFailure("ReminderRecoveryBatch identity is duplicated");
    }
    if (batch.status == domain::kRecoveryInProgress) {
      if (has_in_progress) throw DecodeFailure("Multiple recovery batches are in progress");
      has_in_progress = true;
    } else if (batch.status != domain::kRecoveryCompleted) {
      throw DecodeFailure("Recovery batch status is invalid");
    }
    std::set<std::string> detail;
    for (const auto& id : batch.detail_reminder_ids) {
      const auto reminder = std::find_if(
          state.reminders.begin(), state.reminders.end(),
          [&](const auto& value) { return value.id == id; });
      if (!common::is_uuid(id) || !detail.insert(id).second || reminder == state.reminders.end() ||
          reminder->recovery_batch_id != batch.id) {
        throw DecodeFailure("Recovery batch detail identity is invalid");
      }
    }
    std::set<std::string> summary;
    for (const auto& id : batch.summary_reminder_ids) {
      const auto reminder = std::find_if(
          state.reminders.begin(), state.reminders.end(),
          [&](const auto& value) { return value.id == id; });
      if (!common::is_uuid(id) || !summary.insert(id).second ||
          detail.find(id) != detail.end() || reminder == state.reminders.end() ||
          reminder->recovery_batch_id != batch.id) {
        throw DecodeFailure("Recovery batch summary identity is invalid");
      }
    }
    const bool needs_summary = !batch.summary_reminder_ids.empty() ||
                               batch.older_skipped_occurrence_count > 0 ||
                               batch.older_skipped_reminder_count > 0;
    if (needs_summary != batch.summary_delivery_id.has_value()) {
      throw DecodeFailure("Recovery summary identity is invalid");
    }
    if ((batch.summary_delivery_id.has_value() &&
         !common::is_uuid(*batch.summary_delivery_id)) ||
        (batch.status == domain::kRecoveryCompleted) != batch.completed_at.has_value() ||
        (batch.completed_at.has_value() &&
         !common::is_iso8601_utc_datetime(*batch.completed_at))) {
      throw DecodeFailure("Recovery batch completion invariant is invalid");
    }
  }
  for (const auto& reminder : state.reminders) {
    if (reminder.recovery_batch_id.has_value() &&
        ids.find(*reminder.recovery_batch_id) == ids.end()) {
      throw DecodeFailure("Reminder recovery batch is missing");
    }
  }
  for (const auto& notification : state.notifications) {
    if (notification.recovery_batch_id.has_value() &&
        ids.find(*notification.recovery_batch_id) == ids.end()) {
      throw DecodeFailure("Notification recovery batch is missing");
    }
    if (notification.resolved_by_recovery_batch_id.has_value() &&
        (ids.find(*notification.resolved_by_recovery_batch_id) == ids.end() ||
         notification.recovery_batch_id.has_value())) {
      throw DecodeFailure("Notification recovery resolution is invalid");
    }
  }
}

}  // namespace

common::Result<common::Unit> validate_recurring_event_state(
    const repository::RecurringEventState& state) {
  try {
    const auto event_ids = validate_events(state);
    const auto recurrence_keys = validate_recurrences(state, event_ids);
    validate_occurrence_states(state, event_ids);
    validate_reminders(state, event_ids, recurrence_keys);
    validate_notifications(state);
    validate_recovery_integrity(state);
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (const std::exception& error) {
    return corrupted(error);
  }
}

}  // namespace excellent_calendar::storage::json
