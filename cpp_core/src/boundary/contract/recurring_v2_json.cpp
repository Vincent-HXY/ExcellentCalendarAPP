#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"

#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value optional_string(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value optional_int(const std::optional<int>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value)) : picojson::value();
}

picojson::value strings(const std::vector<std::string>& values) {
  picojson::array result;
  result.reserve(values.size());
  for (const auto& value : values) result.emplace_back(value);
  return picojson::value(std::move(result));
}

picojson::value ints(const std::vector<int>& values) {
  picojson::array result;
  result.reserve(values.size());
  for (const auto value : values) result.emplace_back(static_cast<double>(value));
  return picojson::value(std::move(result));
}

picojson::value error_details(const std::map<std::string, std::string>& details) {
  picojson::object result;
  for (const auto& [key, value] : details) result[key] = picojson::value(value);
  return picojson::value(std::move(result));
}

std::string native_result(picojson::object object) {
  object["contract_version"] = picojson::value(2.0);
  return picojson::value(std::move(object)).serialize();
}

picojson::value prepared_tap_payload(const domain::Notification& notification) {
  picojson::object object;
  object["notification_id"] = picojson::value(notification.id);
  object["delivery_id"] = optional_string(notification.delivery_id);
  object["delivery_attempt_id"] = optional_string(notification.delivery_attempt_id);
  object["kind"] = picojson::value(notification.kind);
  object["reminder_id"] = optional_string(notification.reminder_id);
  object["recovery_batch_id"] = optional_string(notification.recovery_batch_id);
  object["target_type"] = picojson::value(notification.target_type);
  object["target_id"] = picojson::value(notification.target_id);
  object["occurrence_key"] = optional_string(notification.occurrence_key);
  object["route"] = notification.target_type == "anniversary"
                        ? picojson::value("anniversary.detail")
                        : notification.target_type == "habit"
                              ? picojson::value("habit.detail")
                              : picojson::value();
  return picojson::value(std::move(object));
}

}  // namespace

std::string native_success_json_v2(
    const picojson::value& data,
    const std::string& request_id) {
  picojson::object object;
  object["ok"] = picojson::value(true);
  object["data"] = data;
  object["error"] = picojson::value();
  object["request_id"] = picojson::value(request_id);
  return native_result(std::move(object));
}

std::string native_failure_json_v2(
    const common::Error& error,
    const std::string& request_id) {
  picojson::object error_object;
  error_object["code"] = picojson::value(error.code);
  error_object["message"] = picojson::value(error.message);
  error_object["details"] = error_details(error.details);
  error_object["retryable"] = picojson::value(error.retryable);
  picojson::object object;
  object["ok"] = picojson::value(false);
  object["data"] = picojson::value();
  object["error"] = picojson::value(std::move(error_object));
  object["request_id"] = picojson::value(request_id);
  return native_result(std::move(object));
}

picojson::value event_response_v2_to_json(const domain::Event& event) {
  picojson::object object;
  object["id"] = picojson::value(event.id);
  object["title"] = picojson::value(event.title);
  object["content"] = optional_string(event.content);
  object["start_at"] = event.is_all_day ? picojson::value() : picojson::value(event.start_at);
  object["end_at"] = event.is_all_day ? picojson::value() : picojson::value(event.end_at);
  object["start_date"] = optional_string(event.start_date);
  object["end_date"] = optional_string(event.end_date);
  object["is_all_day"] = picojson::value(event.is_all_day);
  object["has_recurrence"] = picojson::value(event.has_recurrence);
  object["status"] = picojson::value(event.status);
  object["completed_at"] = optional_string(event.completed_at);
  object["recurrence_id"] = optional_string(event.recurrence_id);
  object["recurrence_revision"] = optional_int(event.recurrence_revision);
  object["category_id"] = optional_string(event.category_id);
  object["importance"] = optional_string(event.importance);
  object["location"] = optional_string(event.location);
  object["timezone"] = optional_string(event.timezone);
  object["source"] = picojson::value(event.source);
  object["created_at"] = picojson::value(event.created_at);
  object["updated_at"] = picojson::value(event.updated_at);
  object["deleted_at"] = optional_string(event.deleted_at);
  return picojson::value(std::move(object));
}

picojson::value recurrence_response_v2_to_json(const domain::Recurrence& recurrence) {
  picojson::object object;
  object["recurrence_id"] = picojson::value(recurrence.id);
  object["revision"] = picojson::value(static_cast<double>(recurrence.revision));
  object["frequency"] = picojson::value(recurrence.frequency);
  object["interval"] = picojson::value(static_cast<double>(recurrence.interval));
  object["start_at"] = optional_string(recurrence.start_at);
  object["start_date"] = optional_string(recurrence.start_date);
  object["timezone"] = picojson::value(recurrence.timezone);
  object["day_of_month"] = optional_int(recurrence.day_of_month);
  object["days_of_week"] = ints(recurrence.days_of_week);
  object["month_of_year"] = optional_int(recurrence.month_of_year);
  object["end_at"] = optional_string(recurrence.end_at);
  object["count"] = optional_int(recurrence.count);
  object["created_at"] = picojson::value(recurrence.created_at);
  return picojson::value(std::move(object));
}

picojson::value occurrence_state_response_v2_to_json(
    const domain::EventOccurrenceState& state) {
  picojson::object object;
  object["event_id"] = picojson::value(state.event_id);
  object["recurrence_revision"] = picojson::value(static_cast<double>(state.recurrence_revision));
  object["occurrence_key"] = picojson::value(state.occurrence_key);
  object["occurrence_start_at"] = optional_string(state.occurrence_start_at);
  object["occurrence_start_date"] = optional_string(state.occurrence_start_date);
  object["status"] = picojson::value(state.status);
  object["state_changed_at"] = picojson::value(state.state_changed_at);
  object["reopened_at"] = optional_string(state.reopened_at);
  object["created_at"] = picojson::value(state.created_at);
  object["updated_at"] = picojson::value(state.updated_at);
  return picojson::value(std::move(object));
}

picojson::value occurrence_projection_v2_to_json(
    const application::EventOccurrenceProjection& projection) {
  const auto& occurrence = projection.occurrence;
  picojson::object object;
  object["event_id"] = picojson::value(occurrence.event_id);
  object["recurrence_revision"] = picojson::value(
      static_cast<double>(occurrence.recurrence_revision));
  object["occurrence_key"] = picojson::value(occurrence.occurrence_key);
  object["occurrence_start_at"] = optional_string(occurrence.occurrence_start_at);
  object["occurrence_end_at"] = optional_string(occurrence.occurrence_end_at);
  object["occurrence_start_date"] = optional_string(occurrence.occurrence_start_date);
  object["occurrence_end_date"] = optional_string(occurrence.occurrence_end_date);
  object["timezone"] = picojson::value(occurrence.timezone);
  object["state"] = projection.state.has_value()
                          ? occurrence_state_response_v2_to_json(*projection.state)
                          : picojson::value();
  return picojson::value(std::move(object));
}

picojson::value occurrence_page_v2_to_json(
    const application::EventOccurrencePage& page) {
  picojson::array items;
  items.reserve(page.items.size());
  for (const auto& item : page.items) items.push_back(occurrence_projection_v2_to_json(item));
  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  object["has_more"] = picojson::value(page.has_more);
  object["next_cursor"] = optional_string(page.next_cursor);
  return picojson::value(std::move(object));
}

picojson::value reminder_response_v2_to_json(const domain::Reminder& reminder) {
  picojson::object object;
  object["reminder_id"] = picojson::value(reminder.id);
  object["target_type"] = picojson::value(reminder.target_type);
  object["target_id"] = picojson::value(reminder.target_id);
  object["recurrence_revision"] = optional_int(reminder.recurrence_revision);
  object["occurrence_key"] = optional_string(reminder.occurrence_key);
  object["occurrence_start_at"] = optional_string(reminder.occurrence_start_at);
  object["template_key"] = optional_string(reminder.template_key);
  object["occurrence_date"] = optional_string(reminder.occurrence_date);
  object["advance_days"] = optional_int(reminder.advance_days);
  object["local_time"] = optional_string(reminder.local_time);
  object["timezone_mode"] = optional_string(reminder.timezone_mode);
  object["fulfillment_delivery_id"] = optional_string(reminder.fulfillment_delivery_id);
  object["remind_at"] = picojson::value(reminder.remind_at);
  object["advance_minutes"] = optional_int(reminder.advance_minutes);
  object["methods"] = strings(reminder.methods);
  object["message"] = optional_string(reminder.message);
  object["is_enabled"] = picojson::value(reminder.is_enabled);
  object["status"] = picojson::value(reminder.status);
  object["scheduled_at"] = optional_string(reminder.scheduled_at);
  object["last_triggered_at"] = optional_string(reminder.last_triggered_at);
  object["failure_reason"] = optional_string(reminder.failure_reason);
  object["last_cancellation_reason"] = optional_string(reminder.cancellation_reason);
  object["last_cancelled_at"] = optional_string(reminder.last_cancelled_at);
  object["expiration_reason"] = optional_string(reminder.expiration_reason);
  object["expired_at"] = optional_string(reminder.expired_at);
  object["reactivated_at"] = optional_string(reminder.reactivated_at);
  object["reactivation_count"] = picojson::value(
      static_cast<double>(reminder.reactivation_count));
  object["created_at"] = picojson::value(reminder.created_at);
  object["updated_at"] = picojson::value(reminder.updated_at);
  object["deleted_at"] = optional_string(reminder.deleted_at);
  return picojson::value(std::move(object));
}

picojson::value schedulable_reminder_page_v2_to_json(
    const application::RecurringSchedulableReminderPage& page) {
  picojson::array items;
  items.reserve(page.items.size());
  for (const auto& reminder : page.items) items.push_back(reminder_response_v2_to_json(reminder));
  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  object["selected_count"] = picojson::value(static_cast<double>(page.items.size()));
  object["has_more"] = picojson::value(page.has_more);
  if (page.next_cursor_remind_at.has_value()) {
    picojson::object cursor;
    cursor["remind_at"] = picojson::value(*page.next_cursor_remind_at);
    cursor["reminder_id"] = picojson::value(*page.next_cursor_reminder_id);
    object["next_cursor"] = picojson::value(std::move(cursor));
  } else {
    object["next_cursor"] = picojson::value();
  }
  object["unsupported_reminder_ids"] = strings(page.unsupported_reminder_ids);
  return picojson::value(std::move(object));
}

picojson::value notification_response_v2_to_json(
    const domain::Notification& notification) {
  picojson::object object;
  object["notification_id"] = picojson::value(notification.id);
  object["delivery_id"] = optional_string(notification.delivery_id);
  object["delivery_attempt_id"] = optional_string(notification.delivery_attempt_id);
  object["kind"] = picojson::value(notification.kind);
  object["reminder_id"] = optional_string(notification.reminder_id);
  object["recovery_batch_id"] = optional_string(notification.recovery_batch_id);
  object["resolved_by_recovery_batch_id"] =
      optional_string(notification.resolved_by_recovery_batch_id);
  object["target_type"] = picojson::value(notification.target_type);
  object["target_id"] = picojson::value(notification.target_id);
  object["occurrence_key"] = optional_string(notification.occurrence_key);
  object["covered_reminder_ids"] = strings(notification.covered_reminder_ids);
  object["method"] = picojson::value(notification.method);
  object["title"] = picojson::value(notification.title);
  object["body"] = optional_string(notification.body);
  object["planned_at"] = picojson::value(notification.planned_at);
  object["status"] = picojson::value(notification.status);
  object["failure_class"] = optional_string(notification.failure_class);
  object["error_code"] = optional_string(notification.error_code);
  object["abandon_reason"] = optional_string(notification.abandon_reason);
  object["prepared_at"] = optional_string(notification.prepared_at);
  object["finalized_at"] = optional_string(notification.finalized_at);
  object["sent_at"] = optional_string(notification.sent_at);
  object["created_at"] = picojson::value(notification.created_at);
  object["updated_at"] = picojson::value(notification.updated_at);
  return picojson::value(std::move(object));
}

picojson::value recovery_batch_response_v2_to_json(
    const domain::ReminderRecoveryBatch& batch) {
  picojson::object object;
  object["recovery_batch_id"] = picojson::value(batch.id);
  object["recovery_request_id"] = picojson::value(batch.recovery_request_id);
  object["trigger_source"] = picojson::value(batch.trigger_source);
  object["started_at"] = picojson::value(batch.started_at);
  object["window_start_at"] = picojson::value(batch.window_start_at);
  object["detail_reminder_ids"] = strings(batch.detail_reminder_ids);
  object["summary_reminder_ids"] = strings(batch.summary_reminder_ids);
  object["older_skipped_occurrence_count"] = picojson::value(
      static_cast<double>(batch.older_skipped_occurrence_count));
  object["older_skipped_reminder_count"] = picojson::value(
      static_cast<double>(batch.older_skipped_reminder_count));
  object["window_overflow_count"] = picojson::value(
      static_cast<double>(batch.window_overflow_count));
  object["summary_delivery_id"] = optional_string(batch.summary_delivery_id);
  picojson::array anniversary_groups;
  for (const auto& group : batch.anniversary_catch_up_groups) {
    picojson::object value;
    value["anniversary_id"] = picojson::value(group.anniversary_id);
    value["occurrence_key"] = picojson::value(group.occurrence_key);
    value["occurrence_date"] = picojson::value(group.occurrence_date);
    value["covered_reminder_ids"] = strings(group.covered_reminder_ids);
    value["delivery_id"] = picojson::value(group.delivery_id);
    value["status"] = picojson::value(group.status);
    value["completed_at"] = optional_string(group.completed_at);
    anniversary_groups.emplace_back(std::move(value));
  }
  object["anniversary_catch_up_groups"] = picojson::value(std::move(anniversary_groups));
  object["status"] = picojson::value(batch.status);
  object["completed_at"] = optional_string(batch.completed_at);
  return picojson::value(std::move(object));
}

picojson::value prepare_delivery_response_v2_to_json(
    const application::PrepareDeliveryResult& result) {
  picojson::object object;
  object["notification"] = notification_response_v2_to_json(result.notification);
  object["tap_payload"] = prepared_tap_payload(result.notification);
  object["idempotent_replay"] = picojson::value(result.idempotent_replay);
  if (result.habit_action_payload.has_value()) {
    const auto& value = *result.habit_action_payload;
    picojson::object action;
    action["action_id"] = picojson::value(value.action_id);
    action["action_type"] = picojson::value(value.action_type);
    action["habit_id"] = picojson::value(value.habit_id);
    action["check_date"] = picojson::value(value.check_date);
    action["occurrence_key"] = picojson::value(value.occurrence_key);
    action["reminder_id"] = picojson::value(value.reminder_id);
    action["delivery_id"] = picojson::value(value.delivery_id);
    object["habit_action_payload"] = picojson::value(std::move(action));
  } else {
    object["habit_action_payload"] = picojson::value();
  }
  return picojson::value(std::move(object));
}

picojson::value finalize_delivery_response_v2_to_json(
    const application::FinalizeDeliveryResult& result) {
  picojson::object object;
  object["notification"] = notification_response_v2_to_json(result.notification);
  object["reminder"] = result.reminder.has_value()
                             ? reminder_response_v2_to_json(*result.reminder)
                             : picojson::value();
  object["successor"] = result.successor.has_value()
                              ? reminder_response_v2_to_json(*result.successor)
                              : picojson::value();
  picojson::array covered;
  covered.reserve(result.covered_reminders.size());
  for (const auto& reminder : result.covered_reminders) {
    covered.push_back(reminder_response_v2_to_json(reminder));
  }
  object["covered_reminders"] = picojson::value(std::move(covered));
  picojson::array successors;
  successors.reserve(result.successors.size());
  for (const auto& reminder : result.successors) {
    successors.push_back(reminder_response_v2_to_json(reminder));
  }
  object["successors"] = picojson::value(std::move(successors));
  object["recovery_batch"] = result.recovery_batch.has_value()
                                   ? recovery_batch_response_v2_to_json(*result.recovery_batch)
                                   : picojson::value();
  object["idempotent_replay"] = picojson::value(result.idempotent_replay);
  return picojson::value(std::move(object));
}

picojson::value plan_recovery_response_v2_to_json(
    const application::PlanReminderRecoveryResult& result) {
  picojson::array reminders;
  reminders.reserve(result.detail_reminders.size());
  for (const auto& reminder : result.detail_reminders) {
    reminders.push_back(reminder_response_v2_to_json(reminder));
  }
  picojson::array resolutions;
  resolutions.reserve(result.prepared_attempt_resolutions.size());
  for (const auto& resolution : result.prepared_attempt_resolutions) {
    picojson::object item;
    item["delivery_attempt_id"] = picojson::value(resolution.delivery_attempt_id);
    item["delivery_id"] = picojson::value(resolution.delivery_id);
    item["reminder_id"] = picojson::value(resolution.reminder_id);
    item["resolution"] = picojson::value(resolution.resolution);
    item["replacement_delivery_id"] =
        optional_string(resolution.replacement_delivery_id);
    resolutions.emplace_back(std::move(item));
  }
  picojson::object object;
  object["batch"] = recovery_batch_response_v2_to_json(result.batch);
  object["detail_reminders"] = picojson::value(std::move(reminders));
  picojson::array anniversary_groups;
  anniversary_groups.reserve(result.anniversary_catch_up_groups.size());
  for (const auto& group : result.anniversary_catch_up_groups) {
    picojson::object item;
    item["anniversary_id"] = picojson::value(group.anniversary_id);
    item["occurrence_key"] = picojson::value(group.occurrence_key);
    item["occurrence_date"] = picojson::value(group.occurrence_date);
    item["covered_reminder_ids"] = strings(group.covered_reminder_ids);
    item["delivery_id"] = picojson::value(group.delivery_id);
    item["status"] = picojson::value(group.status);
    item["completed_at"] = optional_string(group.completed_at);
    anniversary_groups.emplace_back(std::move(item));
  }
  object["anniversary_catch_up_groups"] =
      picojson::value(std::move(anniversary_groups));
  object["prepared_attempt_resolutions"] = picojson::value(std::move(resolutions));
  object["idempotent_replay"] = picojson::value(result.idempotent_replay);
  return picojson::value(std::move(object));
}

picojson::value snooze_reminder_response_v2_to_json(
    const application::SnoozeReminderResult& result) {
  picojson::object object;
  object["source_delivery_id"] = picojson::value(result.source_delivery_id);
  object["snooze_minutes"] = picojson::value(static_cast<double>(result.snooze_minutes));
  object["snoozed_reminder"] = reminder_response_v2_to_json(result.snoozed_reminder);
  object["idempotent_replay"] = picojson::value(result.idempotent_replay);
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
