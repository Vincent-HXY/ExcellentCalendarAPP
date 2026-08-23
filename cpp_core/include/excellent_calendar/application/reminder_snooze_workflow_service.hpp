#pragma once

#include <functional>
#include <memory>
#include <string>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

struct SnoozeReminderCommand {
  std::string source_delivery_id;
};

struct SnoozeReminderResult {
  std::string source_delivery_id;
  int snooze_minutes = 10;
  domain::Reminder snoozed_reminder;
  bool idempotent_replay = false;
};

class ReminderSnoozeWorkflowService {
 public:
  using ClockFn = std::function<std::string()>;

  ReminderSnoozeWorkflowService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      ClockFn clock);

  common::Result<SnoozeReminderResult> snooze(
      const SnoozeReminderCommand& command);

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  ClockFn clock_;
};

}  // namespace excellent_calendar::application
