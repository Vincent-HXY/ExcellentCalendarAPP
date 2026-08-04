#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

struct PlanReminderRecoveryCommand {
  std::string recovery_request_id;
  std::string trigger_source;
};

struct PreparedAttemptRecoveryResolution {
  std::string delivery_attempt_id;
  std::string delivery_id;
  std::string reminder_id;
  std::string resolution;
  std::optional<std::string> replacement_delivery_id;
};

struct PlanReminderRecoveryResult {
  domain::ReminderRecoveryBatch batch;
  std::vector<domain::Reminder> detail_reminders;
  std::vector<PreparedAttemptRecoveryResolution> prepared_attempt_resolutions;
  bool idempotent_replay = false;
};

class ReminderRecoveryWorkflowService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  ReminderRecoveryWorkflowService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      std::shared_ptr<RecurrenceService> recurrence_service,
      std::shared_ptr<RollingReminderService> rolling_reminder_service,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<PlanReminderRecoveryResult> plan_recovery(
      const PlanReminderRecoveryCommand& command);

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  std::shared_ptr<RecurrenceService> recurrence_service_;
  std::shared_ptr<RollingReminderService> rolling_reminder_service_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
