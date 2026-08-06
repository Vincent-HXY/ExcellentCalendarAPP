#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/repository/event_reminder_transaction.hpp"

namespace excellent_calendar::application {

struct ReminderDraftCommand {
  std::string target_type;
  std::optional<std::string> target_id;
  std::optional<std::string> remind_at;
  std::optional<int> advance_minutes;
  std::vector<std::string> methods;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string source;
};

struct CreateEventWorkflowCommand {
  CreateEventCommand event;
  std::vector<ReminderDraftCommand> reminders;
};

class CreateEventWorkflowService {
 public:
  CreateEventWorkflowService(
      std::shared_ptr<EventService> event_service,
      std::shared_ptr<ReminderService> reminder_service,
      std::shared_ptr<repository::EventReminderTransaction> transaction);

  common::Result<domain::Event> create_event(const CreateEventWorkflowCommand& command);

 private:
  std::shared_ptr<EventService> event_service_;
  std::shared_ptr<ReminderService> reminder_service_;
  std::shared_ptr<repository::EventReminderTransaction> transaction_;
};

}  // namespace excellent_calendar::application
