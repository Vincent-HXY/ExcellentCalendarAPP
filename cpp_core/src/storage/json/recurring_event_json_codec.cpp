#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

#include <algorithm>
#include <cmath>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {
namespace {

struct StoreDefinition {
  const char* file;
  const char* collection;
};

constexpr StoreDefinition kStores[] = {
    {"events.json", "events"},
    {"recurrence_versions.json", "recurrence_versions"},
    {"event_occurrence_states.json", "event_occurrence_states"},
    {"reminders.json", "reminders"},
    {"notifications.json", "notifications"},
    {"reminder_recovery_batches.json", "reminder_recovery_batches"},
};

class DecodeFailure final : public std::runtime_error {
 public:
  explicit DecodeFailure(std::string message) : std::runtime_error(std::move(message)) {}
};

const StoreDefinition& definition(std::string_view file_name) {
  for (const auto& item : kStores) {
    if (file_name == item.file) return item;
  }
  throw DecodeFailure("unknown recurring Event store");
}

const picojson::object& require_object(const picojson::value& value, std::string_view field) {
  if (!value.is<picojson::object>()) throw DecodeFailure(std::string(field) + " must be object");
  return value.get<picojson::object>();
}

void require_exact_keys(const picojson::object& object,
                        const std::set<std::string>& expected,
                        std::string_view field) {
  if (object.size() != expected.size()) {
    throw DecodeFailure(std::string(field) + " has missing or unknown fields");
  }
  for (const auto& key : expected) {
    if (object.find(key) == object.end()) {
      throw DecodeFailure(std::string(field) + " is missing " + key);
    }
  }
}

const picojson::value& member(const picojson::object& object,
                              const std::string& key,
                              std::string_view field) {
  const auto found = object.find(key);
  if (found == object.end()) throw DecodeFailure(std::string(field) + " is missing " + key);
  return found->second;
}

std::string string_value(const picojson::object& object,
                         const std::string& key,
                         std::string_view field) {
  const auto& value = member(object, key, field);
  if (!value.is<std::string>()) throw DecodeFailure(std::string(field) + "." + key + " must be string");
  return value.get<std::string>();
}

std::optional<std::string> nullable_string(const picojson::object& object,
                                           const std::string& key,
                                           std::string_view field) {
  const auto& value = member(object, key, field);
  if (value.is<picojson::null>()) return std::nullopt;
  if (!value.is<std::string>()) {
    throw DecodeFailure(std::string(field) + "." + key + " must be string or null");
  }
  return value.get<std::string>();
}

bool bool_value(const picojson::object& object,
                const std::string& key,
                std::string_view field) {
  const auto& value = member(object, key, field);
  if (!value.is<bool>()) throw DecodeFailure(std::string(field) + "." + key + " must be boolean");
  return value.get<bool>();
}

int integer_value(const picojson::object& object,
                  const std::string& key,
                  std::string_view field) {
  const auto& value = member(object, key, field);
  if (!value.is<double>() || !std::isfinite(value.get<double>()) ||
      std::floor(value.get<double>()) != value.get<double>()) {
    throw DecodeFailure(std::string(field) + "." + key + " must be integer");
  }
  return static_cast<int>(value.get<double>());
}

std::optional<int> nullable_integer(const picojson::object& object,
                                    const std::string& key,
                                    std::string_view field) {
  const auto& value = member(object, key, field);
  if (value.is<picojson::null>()) return std::nullopt;
  return integer_value(object, key, field);
}

std::vector<std::string> string_array(const picojson::object& object,
                                      const std::string& key,
                                      std::string_view field) {
  const auto& value = member(object, key, field);
  if (!value.is<picojson::array>()) throw DecodeFailure(std::string(field) + "." + key + " must be array");
  std::vector<std::string> result;
  for (const auto& item : value.get<picojson::array>()) {
    if (!item.is<std::string>()) throw DecodeFailure(std::string(field) + "." + key + " item must be string");
    result.push_back(item.get<std::string>());
  }
  return result;
}

std::vector<int> integer_array(const picojson::object& object,
                               const std::string& key,
                               std::string_view field) {
  const auto& value = member(object, key, field);
  if (!value.is<picojson::array>()) throw DecodeFailure(std::string(field) + "." + key + " must be array");
  std::vector<int> result;
  for (const auto& item : value.get<picojson::array>()) {
    if (!item.is<double>() || std::floor(item.get<double>()) != item.get<double>()) {
      throw DecodeFailure(std::string(field) + "." + key + " item must be integer");
    }
    result.push_back(static_cast<int>(item.get<double>()));
  }
  return result;
}

picojson::value optional_value(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value optional_value(const std::optional<int>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value)) : picojson::value();
}

picojson::value strings_value(const std::vector<std::string>& values) {
  picojson::array result;
  for (const auto& value : values) result.emplace_back(value);
  return picojson::value(std::move(result));
}

picojson::value integers_value(const std::vector<int>& values) {
  picojson::array result;
  for (int value : values) result.emplace_back(static_cast<double>(value));
  return picojson::value(std::move(result));
}

picojson::value encode_event(const domain::Event& event) {
  picojson::object value;
  value["id"] = picojson::value(event.id);
  value["title"] = picojson::value(event.title);
  value["content"] = optional_value(event.content);
  value["start_at"] = event.start_at.empty() ? picojson::value() : picojson::value(event.start_at);
  value["end_at"] = event.end_at.empty() ? picojson::value() : picojson::value(event.end_at);
  value["start_date"] = optional_value(event.start_date);
  value["end_date"] = optional_value(event.end_date);
  value["is_all_day"] = picojson::value(event.is_all_day);
  value["status"] = picojson::value(event.status);
  value["completed_at"] = optional_value(event.completed_at);
  value["recurrence_id"] = optional_value(event.recurrence_id);
  value["recurrence_revision"] = optional_value(event.recurrence_revision);
  value["category_id"] = optional_value(event.category_id);
  value["importance"] = optional_value(event.importance);
  value["location"] = optional_value(event.location);
  value["timezone"] = picojson::value(event.timezone.value_or(""));
  value["source"] = picojson::value(event.source);
  value["created_at"] = picojson::value(event.created_at);
  value["updated_at"] = picojson::value(event.updated_at);
  value["deleted_at"] = optional_value(event.deleted_at);
  return picojson::value(std::move(value));
}

domain::Event decode_event(const picojson::value& source) {
  const auto& value = require_object(source, "Event");
  require_exact_keys(value,
                     {"id", "title", "content", "start_at", "end_at", "start_date", "end_date",
                      "is_all_day", "status", "completed_at", "recurrence_id", "recurrence_revision",
                      "category_id", "importance", "location", "timezone", "source", "created_at",
                      "updated_at", "deleted_at"},
                     "Event");
  domain::Event event;
  event.id = string_value(value, "id", "Event");
  event.title = string_value(value, "title", "Event");
  event.content = nullable_string(value, "content", "Event");
  event.start_at = nullable_string(value, "start_at", "Event").value_or("");
  event.end_at = nullable_string(value, "end_at", "Event").value_or("");
  event.start_date = nullable_string(value, "start_date", "Event");
  event.end_date = nullable_string(value, "end_date", "Event");
  event.is_all_day = bool_value(value, "is_all_day", "Event");
  event.status = string_value(value, "status", "Event");
  event.completed_at = nullable_string(value, "completed_at", "Event");
  event.recurrence_id = nullable_string(value, "recurrence_id", "Event");
  event.recurrence_revision = nullable_integer(value, "recurrence_revision", "Event");
  event.has_recurrence = event.recurrence_id.has_value();
  event.category_id = nullable_string(value, "category_id", "Event");
  event.importance = nullable_string(value, "importance", "Event");
  event.location = nullable_string(value, "location", "Event");
  event.timezone = string_value(value, "timezone", "Event");
  event.source = string_value(value, "source", "Event");
  event.created_at = string_value(value, "created_at", "Event");
  event.updated_at = string_value(value, "updated_at", "Event");
  event.deleted_at = nullable_string(value, "deleted_at", "Event");
  return event;
}

picojson::value encode_recurrence(const domain::Recurrence& recurrence) {
  picojson::object value;
  value["recurrence_id"] = picojson::value(recurrence.id);
  value["revision"] = picojson::value(static_cast<double>(recurrence.revision));
  value["frequency"] = picojson::value(recurrence.frequency);
  value["interval"] = picojson::value(static_cast<double>(recurrence.interval));
  value["start_at"] = optional_value(recurrence.start_at);
  value["start_date"] = optional_value(recurrence.start_date);
  value["timezone"] = picojson::value(recurrence.timezone);
  value["day_of_month"] = optional_value(recurrence.day_of_month);
  value["days_of_week"] = integers_value(recurrence.days_of_week);
  value["month_of_year"] = optional_value(recurrence.month_of_year);
  value["end_at"] = optional_value(recurrence.end_at);
  value["count"] = optional_value(recurrence.count);
  value["created_at"] = picojson::value(recurrence.created_at);
  return picojson::value(std::move(value));
}

domain::Recurrence decode_recurrence(const picojson::value& source) {
  const auto& value = require_object(source, "Recurrence");
  require_exact_keys(value,
                     {"recurrence_id", "revision", "frequency", "interval", "start_at", "start_date",
                      "timezone", "day_of_month", "days_of_week", "month_of_year", "end_at", "count",
                      "created_at"},
                     "Recurrence");
  domain::Recurrence recurrence;
  recurrence.id = string_value(value, "recurrence_id", "Recurrence");
  recurrence.revision = integer_value(value, "revision", "Recurrence");
  recurrence.frequency = string_value(value, "frequency", "Recurrence");
  recurrence.interval = integer_value(value, "interval", "Recurrence");
  recurrence.start_at = nullable_string(value, "start_at", "Recurrence");
  recurrence.start_date = nullable_string(value, "start_date", "Recurrence");
  recurrence.timezone = string_value(value, "timezone", "Recurrence");
  recurrence.day_of_month = nullable_integer(value, "day_of_month", "Recurrence");
  recurrence.days_of_week = integer_array(value, "days_of_week", "Recurrence");
  recurrence.month_of_year = nullable_integer(value, "month_of_year", "Recurrence");
  recurrence.end_at = nullable_string(value, "end_at", "Recurrence");
  recurrence.count = nullable_integer(value, "count", "Recurrence");
  recurrence.created_at = string_value(value, "created_at", "Recurrence");
  return recurrence;
}

picojson::value encode_occurrence_state(const domain::EventOccurrenceState& state) {
  picojson::object value;
  value["event_id"] = picojson::value(state.event_id);
  value["recurrence_revision"] = picojson::value(static_cast<double>(state.recurrence_revision));
  value["occurrence_key"] = picojson::value(state.occurrence_key);
  value["occurrence_start_at"] = optional_value(state.occurrence_start_at);
  value["occurrence_start_date"] = optional_value(state.occurrence_start_date);
  value["status"] = picojson::value(state.status);
  value["state_changed_at"] = picojson::value(state.state_changed_at);
  value["reopened_at"] = optional_value(state.reopened_at);
  value["created_at"] = picojson::value(state.created_at);
  value["updated_at"] = picojson::value(state.updated_at);
  return picojson::value(std::move(value));
}

domain::EventOccurrenceState decode_occurrence_state(const picojson::value& source) {
  const auto& value = require_object(source, "EventOccurrenceState");
  require_exact_keys(value,
                     {"event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
                      "occurrence_start_date", "status", "state_changed_at", "reopened_at", "created_at",
                      "updated_at"},
                     "EventOccurrenceState");
  domain::EventOccurrenceState state;
  state.event_id = string_value(value, "event_id", "EventOccurrenceState");
  state.recurrence_revision = integer_value(value, "recurrence_revision", "EventOccurrenceState");
  state.occurrence_key = string_value(value, "occurrence_key", "EventOccurrenceState");
  state.occurrence_start_at = nullable_string(value, "occurrence_start_at", "EventOccurrenceState");
  state.occurrence_start_date = nullable_string(value, "occurrence_start_date", "EventOccurrenceState");
  state.status = string_value(value, "status", "EventOccurrenceState");
  state.state_changed_at = string_value(value, "state_changed_at", "EventOccurrenceState");
  state.reopened_at = nullable_string(value, "reopened_at", "EventOccurrenceState");
  state.created_at = string_value(value, "created_at", "EventOccurrenceState");
  state.updated_at = string_value(value, "updated_at", "EventOccurrenceState");
  return state;
}

picojson::value encode_reminder(const domain::Reminder& reminder) {
  picojson::object value;
  value["reminder_id"] = picojson::value(reminder.id);
  value["target_type"] = picojson::value(reminder.target_type);
  value["target_id"] = picojson::value(reminder.target_id);
  value["recurrence_revision"] = optional_value(reminder.recurrence_revision);
  value["occurrence_key"] = optional_value(reminder.occurrence_key);
  value["occurrence_start_at"] = optional_value(reminder.occurrence_start_at);
  value["remind_at"] = picojson::value(reminder.remind_at);
  value["advance_minutes"] = optional_value(reminder.advance_minutes);
  value["methods"] = strings_value(reminder.methods);
  value["message"] = optional_value(reminder.message);
  value["is_enabled"] = picojson::value(reminder.is_enabled);
  value["status"] = picojson::value(reminder.status);
  value["scheduled_at"] = optional_value(reminder.scheduled_at);
  value["last_triggered_at"] = optional_value(reminder.last_triggered_at);
  value["failure_reason"] = optional_value(reminder.failure_reason);
  value["last_cancellation_reason"] = optional_value(reminder.cancellation_reason);
  value["last_cancelled_at"] = optional_value(reminder.last_cancelled_at);
  value["expiration_reason"] = optional_value(reminder.expiration_reason);
  value["expired_at"] = optional_value(reminder.expired_at);
  value["reactivated_at"] = optional_value(reminder.reactivated_at);
  value["reactivation_count"] = picojson::value(static_cast<double>(reminder.reactivation_count));
  value["recovery_batch_id"] = optional_value(reminder.recovery_batch_id);
  value["source"] = picojson::value(reminder.source);
  value["created_at"] = picojson::value(reminder.created_at);
  value["updated_at"] = picojson::value(reminder.updated_at);
  value["deleted_at"] = optional_value(reminder.deleted_at);
  return picojson::value(std::move(value));
}

domain::Reminder decode_reminder(const picojson::value& source) {
  const auto& value = require_object(source, "Reminder");
  require_exact_keys(value,
                     {"reminder_id", "target_type", "target_id", "recurrence_revision", "occurrence_key",
                      "occurrence_start_at", "remind_at", "advance_minutes", "methods", "message",
                      "is_enabled", "status", "scheduled_at", "last_triggered_at", "failure_reason",
                      "last_cancellation_reason", "last_cancelled_at", "expiration_reason", "expired_at",
                      "reactivated_at", "reactivation_count",
                      "recovery_batch_id", "source", "created_at", "updated_at", "deleted_at"},
                     "Reminder");
  domain::Reminder reminder;
  reminder.id = string_value(value, "reminder_id", "Reminder");
  reminder.target_type = string_value(value, "target_type", "Reminder");
  reminder.target_id = string_value(value, "target_id", "Reminder");
  reminder.recurrence_revision = nullable_integer(value, "recurrence_revision", "Reminder");
  reminder.occurrence_key = nullable_string(value, "occurrence_key", "Reminder");
  reminder.occurrence_start_at = nullable_string(value, "occurrence_start_at", "Reminder");
  reminder.remind_at = string_value(value, "remind_at", "Reminder");
  reminder.advance_minutes = nullable_integer(value, "advance_minutes", "Reminder");
  reminder.methods = string_array(value, "methods", "Reminder");
  reminder.message = nullable_string(value, "message", "Reminder");
  reminder.is_enabled = bool_value(value, "is_enabled", "Reminder");
  reminder.status = string_value(value, "status", "Reminder");
  reminder.scheduled_at = nullable_string(value, "scheduled_at", "Reminder");
  reminder.last_triggered_at = nullable_string(value, "last_triggered_at", "Reminder");
  reminder.failure_reason = nullable_string(value, "failure_reason", "Reminder");
  reminder.cancellation_reason = nullable_string(value, "last_cancellation_reason", "Reminder");
  reminder.last_cancelled_at = nullable_string(value, "last_cancelled_at", "Reminder");
  reminder.expiration_reason = nullable_string(value, "expiration_reason", "Reminder");
  reminder.expired_at = nullable_string(value, "expired_at", "Reminder");
  reminder.reactivated_at = nullable_string(value, "reactivated_at", "Reminder");
  reminder.reactivation_count = integer_value(value, "reactivation_count", "Reminder");
  reminder.recovery_batch_id = nullable_string(value, "recovery_batch_id", "Reminder");
  reminder.source = string_value(value, "source", "Reminder");
  reminder.created_at = string_value(value, "created_at", "Reminder");
  reminder.updated_at = string_value(value, "updated_at", "Reminder");
  reminder.deleted_at = nullable_string(value, "deleted_at", "Reminder");
  return reminder;
}

picojson::value encode_notification(const domain::Notification& notification) {
  picojson::object value;
  value["notification_id"] = picojson::value(notification.id);
  value["delivery_id"] = optional_value(notification.delivery_id);
  value["delivery_attempt_id"] = optional_value(notification.delivery_attempt_id);
  value["kind"] = picojson::value(notification.kind);
  value["reminder_id"] = optional_value(notification.reminder_id);
  value["recovery_batch_id"] = optional_value(notification.recovery_batch_id);
  value["resolved_by_recovery_batch_id"] =
      optional_value(notification.resolved_by_recovery_batch_id);
  value["target_type"] = picojson::value(notification.target_type);
  value["target_id"] = picojson::value(notification.target_id);
  value["occurrence_key"] = optional_value(notification.occurrence_key);
  value["method"] = picojson::value(notification.method);
  value["title"] = picojson::value(notification.title);
  value["body"] = optional_value(notification.body);
  value["planned_at"] = picojson::value(notification.planned_at);
  value["prepared_at"] = optional_value(notification.prepared_at);
  value["finalized_at"] = optional_value(notification.finalized_at);
  value["sent_at"] = optional_value(notification.sent_at);
  value["status"] = picojson::value(notification.status);
  value["failure_class"] = optional_value(notification.failure_class);
  value["error_code"] = optional_value(notification.error_code);
  value["abandon_reason"] = optional_value(notification.abandon_reason);
  value["created_at"] = picojson::value(notification.created_at);
  value["updated_at"] = picojson::value(notification.updated_at);
  return picojson::value(std::move(value));
}

domain::Notification decode_notification(const picojson::value& source) {
  const auto& value = require_object(source, "Notification");
  require_exact_keys(value,
                     {"notification_id", "delivery_id", "delivery_attempt_id", "kind", "reminder_id",
                      "recovery_batch_id", "resolved_by_recovery_batch_id", "target_type", "target_id",
                      "occurrence_key", "method", "title",
                      "body", "planned_at", "prepared_at", "finalized_at", "sent_at", "status",
                      "failure_class", "error_code", "abandon_reason", "created_at", "updated_at"},
                     "Notification");
  domain::Notification notification;
  notification.id = string_value(value, "notification_id", "Notification");
  notification.delivery_id = nullable_string(value, "delivery_id", "Notification");
  notification.delivery_attempt_id = nullable_string(value, "delivery_attempt_id", "Notification");
  notification.kind = string_value(value, "kind", "Notification");
  notification.reminder_id = nullable_string(value, "reminder_id", "Notification");
  notification.recovery_batch_id = nullable_string(value, "recovery_batch_id", "Notification");
  notification.resolved_by_recovery_batch_id =
      nullable_string(value, "resolved_by_recovery_batch_id", "Notification");
  notification.target_type = string_value(value, "target_type", "Notification");
  notification.target_id = string_value(value, "target_id", "Notification");
  notification.occurrence_key = nullable_string(value, "occurrence_key", "Notification");
  notification.method = string_value(value, "method", "Notification");
  notification.title = string_value(value, "title", "Notification");
  notification.body = nullable_string(value, "body", "Notification");
  notification.planned_at = string_value(value, "planned_at", "Notification");
  notification.prepared_at = nullable_string(value, "prepared_at", "Notification");
  notification.finalized_at = nullable_string(value, "finalized_at", "Notification");
  notification.sent_at = nullable_string(value, "sent_at", "Notification");
  notification.status = string_value(value, "status", "Notification");
  notification.failure_class = nullable_string(value, "failure_class", "Notification");
  notification.error_code = nullable_string(value, "error_code", "Notification");
  notification.abandon_reason = nullable_string(value, "abandon_reason", "Notification");
  notification.created_at = string_value(value, "created_at", "Notification");
  notification.updated_at = string_value(value, "updated_at", "Notification");
  return notification;
}

picojson::value encode_recovery_batch(const domain::ReminderRecoveryBatch& batch) {
  picojson::object value;
  value["recovery_batch_id"] = picojson::value(batch.id);
  value["recovery_request_id"] = picojson::value(batch.recovery_request_id);
  value["trigger_source"] = picojson::value(batch.trigger_source);
  value["started_at"] = picojson::value(batch.started_at);
  value["window_start_at"] = picojson::value(batch.window_start_at);
  value["detail_reminder_ids"] = strings_value(batch.detail_reminder_ids);
  value["summary_reminder_ids"] = strings_value(batch.summary_reminder_ids);
  value["older_skipped_occurrence_count"] =
      picojson::value(static_cast<double>(batch.older_skipped_occurrence_count));
  value["older_skipped_reminder_count"] =
      picojson::value(static_cast<double>(batch.older_skipped_reminder_count));
  value["window_overflow_count"] = picojson::value(static_cast<double>(batch.window_overflow_count));
  value["summary_delivery_id"] = optional_value(batch.summary_delivery_id);
  value["status"] = picojson::value(batch.status);
  value["completed_at"] = optional_value(batch.completed_at);
  return picojson::value(std::move(value));
}

domain::ReminderRecoveryBatch decode_recovery_batch(const picojson::value& source) {
  const auto& value = require_object(source, "ReminderRecoveryBatch");
  require_exact_keys(value,
                     {"recovery_batch_id", "recovery_request_id", "trigger_source", "started_at",
                      "window_start_at", "detail_reminder_ids", "summary_reminder_ids",
                      "older_skipped_occurrence_count", "older_skipped_reminder_count",
                      "window_overflow_count", "summary_delivery_id", "status", "completed_at"},
                     "ReminderRecoveryBatch");
  domain::ReminderRecoveryBatch batch;
  batch.id = string_value(value, "recovery_batch_id", "ReminderRecoveryBatch");
  batch.recovery_request_id = string_value(value, "recovery_request_id", "ReminderRecoveryBatch");
  batch.trigger_source = string_value(value, "trigger_source", "ReminderRecoveryBatch");
  batch.started_at = string_value(value, "started_at", "ReminderRecoveryBatch");
  batch.window_start_at = string_value(value, "window_start_at", "ReminderRecoveryBatch");
  batch.detail_reminder_ids = string_array(value, "detail_reminder_ids", "ReminderRecoveryBatch");
  batch.summary_reminder_ids = string_array(value, "summary_reminder_ids", "ReminderRecoveryBatch");
  batch.older_skipped_occurrence_count =
      integer_value(value, "older_skipped_occurrence_count", "ReminderRecoveryBatch");
  batch.older_skipped_reminder_count =
      integer_value(value, "older_skipped_reminder_count", "ReminderRecoveryBatch");
  batch.window_overflow_count =
      integer_value(value, "window_overflow_count", "ReminderRecoveryBatch");
  batch.summary_delivery_id = nullable_string(value, "summary_delivery_id", "ReminderRecoveryBatch");
  batch.status = string_value(value, "status", "ReminderRecoveryBatch");
  batch.completed_at = nullable_string(value, "completed_at", "ReminderRecoveryBatch");
  return batch;
}

template <typename T, typename Encoder>
picojson::value encode_collection(const std::vector<T>& values,
                                  const char* collection,
                                  Encoder encoder) {
  picojson::array items;
  for (const auto& value : values) items.push_back(encoder(value));
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root[collection] = picojson::value(std::move(items));
  return picojson::value(std::move(root));
}

const picojson::array& collection(const picojson::value& root,
                                  const StoreDefinition& store) {
  const auto& object = require_object(root, store.file);
  require_exact_keys(object, {"storage_version", store.collection}, store.file);
  const auto& version = object.find("storage_version")->second;
  if (!version.is<double>() || version.get<double>() != 2.0) {
    throw DecodeFailure(std::string(store.file) + " storage_version must equal 2");
  }
  const auto& values = object.find(store.collection)->second;
  if (!values.is<picojson::array>()) {
    throw DecodeFailure(std::string(store.file) + " collection must be array");
  }
  return values.get<picojson::array>();
}

common::Result<common::Unit> corrupted(const std::exception& error) {
  return common::Result<common::Unit>::failure(storage_data_corrupted(error.what()));
}

}  // namespace

common::Result<picojson::value> encode_recurring_event_store(
    std::string_view file_name,
    const repository::RecurringEventState& state) {
  try {
    const auto& store = definition(file_name);
    if (file_name == "events.json") {
      return common::Result<picojson::value>::success(
          encode_collection(state.events, store.collection, encode_event));
    }
    if (file_name == "recurrence_versions.json") {
      return common::Result<picojson::value>::success(
          encode_collection(state.recurrences, store.collection, encode_recurrence));
    }
    if (file_name == "event_occurrence_states.json") {
      return common::Result<picojson::value>::success(
          encode_collection(state.occurrence_states, store.collection, encode_occurrence_state));
    }
    if (file_name == "reminders.json") {
      return common::Result<picojson::value>::success(
          encode_collection(state.reminders, store.collection, encode_reminder));
    }
    if (file_name == "notifications.json") {
      return common::Result<picojson::value>::success(
          encode_collection(state.notifications, store.collection, encode_notification));
    }
    return common::Result<picojson::value>::success(
        encode_collection(state.recovery_batches, store.collection, encode_recovery_batch));
  } catch (const std::exception& error) {
    return common::Result<picojson::value>::failure(storage_data_corrupted(error.what()));
  }
}

common::Result<common::Unit> decode_recurring_event_store(
    std::string_view file_name,
    const picojson::value& root,
    repository::RecurringEventState& state) {
  try {
    const auto& store = definition(file_name);
    const auto& values = collection(root, store);
    if (file_name == "events.json") {
      for (const auto& value : values) state.events.push_back(decode_event(value));
    } else if (file_name == "recurrence_versions.json") {
      for (const auto& value : values) state.recurrences.push_back(decode_recurrence(value));
    } else if (file_name == "event_occurrence_states.json") {
      for (const auto& value : values) state.occurrence_states.push_back(decode_occurrence_state(value));
    } else if (file_name == "reminders.json") {
      for (const auto& value : values) state.reminders.push_back(decode_reminder(value));
    } else if (file_name == "notifications.json") {
      for (const auto& value : values) state.notifications.push_back(decode_notification(value));
    } else {
      for (const auto& value : values) state.recovery_batches.push_back(decode_recovery_batch(value));
    }
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (const std::exception& error) {
    return corrupted(error);
  }
}
}  // namespace excellent_calendar::storage::json
