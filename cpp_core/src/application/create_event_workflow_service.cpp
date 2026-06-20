#include "excellent_calendar/application/create_event_workflow_service.hpp"

#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::application {
namespace {

common::Error invalid_embedded_target(std::size_t index) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED",
      "An Event reminder draft must target the Event being created",
      {{"field", "CreateEventRequest.reminders[" + std::to_string(index) + "].target_type"}});
}

}  // namespace

CreateEventWorkflowService::CreateEventWorkflowService(
    std::shared_ptr<EventService> event_service,
    std::shared_ptr<ReminderService> reminder_service,
    std::shared_ptr<repository::EventReminderTransaction> transaction)
    : event_service_(std::move(event_service)),
      reminder_service_(std::move(reminder_service)),
      transaction_(std::move(transaction)) {}

common::Result<domain::Event> CreateEventWorkflowService::create_event(
    const CreateEventWorkflowCommand& command) {
  for (std::size_t index = 0; index < command.reminders.size(); ++index) {
    if (command.reminders[index].target_type != domain::kReminderTargetEvent) {
      return common::Result<domain::Event>::failure(invalid_embedded_target(index));
    }
  }

  std::optional<domain::Event> created_event;
  auto committed = transaction_->execute([&]() -> common::Result<common::Unit> {
    auto event = event_service_->create_event(command.event);
    if (!event.ok()) {
      return common::Result<common::Unit>::failure(event.error());
    }
    created_event = event.value();

    for (const auto& draft : command.reminders) {
      CreateReminderCommand reminder;
      reminder.target_type = std::string(domain::kReminderTargetEvent);
      reminder.target_id = created_event->id;
      reminder.remind_at = draft.remind_at;
      reminder.advance_minutes = draft.advance_minutes;
      reminder.methods = draft.methods;
      reminder.message = draft.message;
      reminder.is_enabled = draft.is_enabled;
      reminder.source = draft.source;

      auto created_reminder = reminder_service_->create_reminder(reminder);
      if (!created_reminder.ok()) {
        return common::Result<common::Unit>::failure(created_reminder.error());
      }
    }

    return common::Result<common::Unit>::success(common::Unit{});
  });

  if (!committed.ok()) {
    return common::Result<domain::Event>::failure(committed.error());
  }
  if (!created_event.has_value()) {
    return common::Result<domain::Event>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR",
        "Native internal error",
        {{"reason", "event transaction completed without a result"}}));
  }
  return common::Result<domain::Event>::success(*created_event);
}

}  // namespace excellent_calendar::application
