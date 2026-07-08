#include "excellent_calendar/application/event_lifecycle_workflow_service.hpp"

#include <optional>
#include <string>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::application {
namespace {

bool is_open_reminder_status(const std::string& status) {
  return status == std::string(domain::kReminderStatusPending) ||
         status == std::string(domain::kReminderStatusScheduled) ||
         status == std::string(domain::kReminderStatusFailed);
}

bool is_event_reminder(const domain::Reminder& reminder, const std::string& event_id) {
  return reminder.target_type == std::string(domain::kReminderTargetEvent) &&
         reminder.target_id == event_id;
}

common::Error storage_corrupted(std::string field, std::string reason) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED",
      "Storage data is corrupted",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

}  // namespace

EventLifecycleWorkflowService::EventLifecycleWorkflowService(
    std::shared_ptr<EventService> event_service,
    std::shared_ptr<repository::ReminderRepository> reminder_repository,
    std::shared_ptr<repository::EventReminderTransaction> transaction,
    ClockFn clock)
    : event_service_(std::move(event_service)),
      reminder_repository_(std::move(reminder_repository)),
      transaction_(std::move(transaction)),
      clock_(std::move(clock)) {}

common::Result<domain::Event> EventLifecycleWorkflowService::complete_event(
    const CompleteEventCommand& command) {
  std::optional<domain::Event> completed_event;
  auto committed = transaction_->execute([&]() -> common::Result<common::Unit> {
    auto completed = event_service_->complete_event(command);
    if (!completed.ok()) {
      return common::Result<common::Unit>::failure(completed.error());
    }
    completed_event = completed.value();

    auto cancelled = cancel_open_event_reminders(command.event_id);
    if (!cancelled.ok()) {
      return cancelled;
    }
    return common::Result<common::Unit>::success(common::Unit{});
  });

  if (!committed.ok()) {
    return common::Result<domain::Event>::failure(committed.error());
  }
  if (!completed_event.has_value()) {
    return common::Result<domain::Event>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR",
        "Native internal error",
        {{"reason", "event complete transaction completed without a result"}}));
  }
  return common::Result<domain::Event>::success(*completed_event);
}

common::Result<domain::Event> EventLifecycleWorkflowService::reopen_event(
    const ReopenEventCommand& command) {
  std::optional<domain::Event> reopened_event;
  auto committed = transaction_->execute([&]() -> common::Result<common::Unit> {
    auto reopened = event_service_->reopen_event(command);
    if (!reopened.ok()) {
      return common::Result<common::Unit>::failure(reopened.error());
    }
    reopened_event = reopened.value();

    auto restored = restore_future_event_completed_reminders(
        command.event_id,
        reopened.value().updated_at);
    if (!restored.ok()) {
      return restored;
    }
    return common::Result<common::Unit>::success(common::Unit{});
  });

  if (!committed.ok()) {
    return common::Result<domain::Event>::failure(committed.error());
  }
  if (!reopened_event.has_value()) {
    return common::Result<domain::Event>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR",
        "Native internal error",
        {{"reason", "event reopen transaction completed without a result"}}));
  }
  return common::Result<domain::Event>::success(*reopened_event);
}

common::Result<common::Unit> EventLifecycleWorkflowService::cancel_open_event_reminders(
    const std::string& event_id) {
  auto loaded = reminder_repository_->find_all();
  if (!loaded.ok()) {
    return common::Result<common::Unit>::failure(loaded.error());
  }

  const auto now = clock_();
  for (auto reminder : loaded.value()) {
    if (!is_event_reminder(reminder, event_id) ||
        reminder.deleted_at.has_value() ||
        !is_open_reminder_status(reminder.status)) {
      continue;
    }

    reminder.status = std::string(domain::kReminderStatusCancelled);
    reminder.is_enabled = false;
    reminder.scheduled_at = std::nullopt;
    reminder.cancellation_reason = std::string(domain::kReminderCancellationReasonEventCompleted);
    reminder.deleted_at = now;
    reminder.updated_at = now;
    auto updated = reminder_repository_->update(reminder);
    if (!updated.ok()) {
      return common::Result<common::Unit>::failure(updated.error());
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> EventLifecycleWorkflowService::restore_future_event_completed_reminders(
    const std::string& event_id,
    const std::string& reopened_at) {
  const auto reopened_time = common::parse_iso8601_utc_epoch_seconds(reopened_at);
  if (!reopened_time.has_value()) {
    return common::Result<common::Unit>::failure(
        storage_corrupted("Event.updated_at", "reopened event updated_at is invalid"));
  }

  auto loaded = reminder_repository_->find_all();
  if (!loaded.ok()) {
    return common::Result<common::Unit>::failure(loaded.error());
  }

  for (auto reminder : loaded.value()) {
    if (!is_event_reminder(reminder, event_id) ||
        reminder.status != std::string(domain::kReminderStatusCancelled) ||
        reminder.cancellation_reason !=
            std::optional<std::string>(std::string(domain::kReminderCancellationReasonEventCompleted))) {
      continue;
    }

    const auto remind_time = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
    if (!remind_time.has_value()) {
      return common::Result<common::Unit>::failure(
          storage_corrupted("Reminder.remind_at", "stored reminder remind_at is invalid"));
    }
    if (*remind_time <= *reopened_time) {
      continue;
    }

    reminder.status = std::string(domain::kReminderStatusPending);
    reminder.is_enabled = true;
    reminder.scheduled_at = std::nullopt;
    reminder.failure_reason = std::nullopt;
    reminder.cancellation_reason = std::nullopt;
    reminder.deleted_at = std::nullopt;
    reminder.updated_at = reopened_at;
    auto updated = reminder_repository_->update(reminder);
    if (!updated.ok()) {
      return common::Result<common::Unit>::failure(updated.error());
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::application
