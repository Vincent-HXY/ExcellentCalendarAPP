#include "excellent_calendar/application/reminder_snooze_workflow_service.hpp"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/notification.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kReminderNamespace = "57b84799-6049-567e-8f29-ae597c333140";
constexpr int kSnoozeMinutes = 10;

common::Error contract_invalid(std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", "source_delivery_id"}, {"reason", std::move(reason)}});
}

common::Error snooze_not_allowed(const std::string& delivery_id,
                                 std::string reason) {
  return common::make_error(
      "REMINDER_SNOOZE_NOT_ALLOWED",
      "The source ring delivery cannot create a snoozed Reminder",
      {{"source_delivery_id", delivery_id}, {"reason", std::move(reason)}});
}

common::Error idempotency_conflict(const std::string& reminder_id) {
  return common::make_error(
      "REMINDER_IDEMPOTENCY_CONFLICT", "Reminder idempotency conflict",
      {{"reminder_id", reminder_id}, {"reason", "snoozed Reminder identity is occupied"}});
}

common::Result<std::string> snoozed_reminder_id(
    const std::string& source_delivery_id) {
  return common::generate_uuid_v5(
      kReminderNamespace,
      "[\"" + source_delivery_id + "\",\"snooze\",10]");
}

const domain::Notification* find_sent_source(
    const repository::RecurringEventState& state,
    const std::string& source_delivery_id) {
  const auto found = std::find_if(
      state.notifications.begin(), state.notifications.end(), [&](const auto& notification) {
        return notification.delivery_id == source_delivery_id &&
               notification.status == domain::kNotificationStatusSent;
      });
  return found == state.notifications.end() ? nullptr : &*found;
}

const domain::Reminder* find_reminder(
    const repository::RecurringEventState& state,
    const std::string& reminder_id) {
  const auto found = std::find_if(
      state.reminders.begin(), state.reminders.end(),
      [&](const auto& reminder) { return reminder.id == reminder_id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

const domain::Event* find_event(
    const repository::RecurringEventState& state,
    const std::string& event_id) {
  const auto found = std::find_if(
      state.events.begin(), state.events.end(),
      [&](const auto& event) { return event.id == event_id; });
  return found == state.events.end() ? nullptr : &*found;
}

bool valid_source_reminder(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() &&
         reminder.target_type == domain::kReminderTargetEvent &&
         !reminder.recurrence_revision.has_value() &&
         !reminder.occurrence_key.has_value() &&
         !reminder.occurrence_start_at.has_value() &&
         reminder.methods == std::vector<std::string>{"ring"} &&
         reminder.status == domain::kReminderStatusSent;
}

bool valid_source_event(const domain::Event& event) {
  return !event.deleted_at.has_value() &&
         event.status == domain::kEventStatusActive &&
         !event.is_all_day && !event.has_recurrence &&
         !event.recurrence_id.has_value() &&
         !event.recurrence_revision.has_value();
}

bool matches_snoozed_identity(const domain::Reminder& reminder,
                              const domain::Reminder& source) {
  return reminder.target_type == domain::kReminderTargetEvent &&
         reminder.target_id == source.target_id &&
         !reminder.recurrence_revision.has_value() &&
         !reminder.occurrence_key.has_value() &&
         !reminder.occurrence_start_at.has_value() &&
         reminder.methods == std::vector<std::string>{"ring"} &&
         !reminder.advance_minutes.has_value() && !reminder.message.has_value();
}

}  // namespace

ReminderSnoozeWorkflowService::ReminderSnoozeWorkflowService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    ClockFn clock)
    : transaction_(std::move(transaction)),
      clock_(std::move(clock)) {}

common::Result<SnoozeReminderResult> ReminderSnoozeWorkflowService::snooze(
    const SnoozeReminderCommand& command) {
  if (!common::is_uuid(command.source_delivery_id)) {
    return common::Result<SnoozeReminderResult>::failure(
        contract_invalid("source_delivery_id must be a UUID"));
  }
  const auto generated_id = snoozed_reminder_id(command.source_delivery_id);
  if (!generated_id.ok()) {
    return common::Result<SnoozeReminderResult>::failure(generated_id.error());
  }
  const auto now = clock_();
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (!now_epoch.has_value()) {
    return common::Result<SnoozeReminderResult>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "snooze Clock returned invalid UTC time"}}));
  }

  std::optional<SnoozeReminderResult> output;
  auto committed = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state,
          std::vector<domain::Reminder>& reminders) {
        const auto* notification = find_sent_source(state, command.source_delivery_id);
        if (notification == nullptr || notification->kind != "reminder" ||
            notification->method != domain::kReminderMethodRing ||
            !notification->reminder_id.has_value() ||
            notification->occurrence_key.has_value()) {
          return common::Result<common::Unit>::failure(
              snooze_not_allowed(command.source_delivery_id,
                                 "source delivery is not a successful ordinary ring attempt"));
        }
        const auto* source = find_reminder(state, *notification->reminder_id);
        if (source == nullptr || !valid_source_reminder(*source)) {
          return common::Result<common::Unit>::failure(
              snooze_not_allowed(command.source_delivery_id,
                                 "source Reminder is missing or no longer valid"));
        }
        const auto* event = find_event(state, source->target_id);
        if (event == nullptr || !valid_source_event(*event)) {
          return common::Result<common::Unit>::failure(
              snooze_not_allowed(command.source_delivery_id,
                                 "source Event is missing or no longer eligible for ring"));
        }

        const auto existing = std::find_if(
            reminders.begin(), reminders.end(),
            [&](const auto& reminder) { return reminder.id == generated_id.value(); });
        if (existing != reminders.end()) {
          if (!matches_snoozed_identity(*existing, *source)) {
            return common::Result<common::Unit>::failure(
                idempotency_conflict(generated_id.value()));
          }
          output = SnoozeReminderResult{
              command.source_delivery_id, kSnoozeMinutes, *existing, true};
          return common::Result<common::Unit>::success(common::Unit{});
        }

        domain::Reminder reminder;
        reminder.id = generated_id.value();
        reminder.target_type = std::string(domain::kReminderTargetEvent);
        reminder.target_id = source->target_id;
        reminder.remind_at = common::format_epoch_seconds_utc_iso8601(
            *now_epoch + static_cast<std::int64_t>(kSnoozeMinutes) * 60);
        reminder.methods = {std::string(domain::kReminderMethodRing)};
        reminder.message = std::nullopt;
        reminder.is_enabled = true;
        reminder.status = std::string(domain::kReminderStatusPending);
        reminder.source = source->source;
        reminder.created_at = now;
        reminder.updated_at = now;
        reminders.push_back(reminder);
        output = SnoozeReminderResult{
            command.source_delivery_id, kSnoozeMinutes, reminder, false};
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) {
    return common::Result<SnoozeReminderResult>::failure(committed.error());
  }
  if (!output.has_value()) {
    return common::Result<SnoozeReminderResult>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "snooze transaction returned no result"}}));
  }
  return common::Result<SnoozeReminderResult>::success(std::move(*output));
}

}  // namespace excellent_calendar::application
