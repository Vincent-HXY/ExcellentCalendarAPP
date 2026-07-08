#pragma once

#include <functional>
#include <memory>
#include <string>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/repository/event_reminder_transaction.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"

namespace excellent_calendar::application {

class EventLifecycleWorkflowService {
 public:
  using ClockFn = std::function<std::string()>;

  EventLifecycleWorkflowService(
      std::shared_ptr<EventService> event_service,
      std::shared_ptr<repository::ReminderRepository> reminder_repository,
      std::shared_ptr<repository::EventReminderTransaction> transaction,
      ClockFn clock);

  common::Result<domain::Event> complete_event(const CompleteEventCommand& command);

  common::Result<domain::Event> reopen_event(const ReopenEventCommand& command);

 private:
  common::Result<common::Unit> cancel_open_event_reminders(const std::string& event_id);

  common::Result<common::Unit> restore_future_event_completed_reminders(
      const std::string& event_id,
      const std::string& reopened_at);

  std::shared_ptr<EventService> event_service_;
  std::shared_ptr<repository::ReminderRepository> reminder_repository_;
  std::shared_ptr<repository::EventReminderTransaction> transaction_;
  ClockFn clock_;
};

}  // namespace excellent_calendar::application
