#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

struct PrepareDeliveryCommand {
  std::string kind;
  std::optional<std::string> reminder_id;
  std::optional<std::string> recovery_batch_id;
  std::string method;
  std::optional<std::string> expected_remind_at;
};

struct PrepareDeliveryResult {
  domain::Notification notification;
  bool idempotent_replay = false;
};

struct FinalizeDeliveryCommand {
  std::string delivery_attempt_id;
  std::string outcome;
  std::optional<std::string> failure_class;
  std::optional<std::string> error_code;
};

struct FinalizeDeliveryResult {
  domain::Notification notification;
  std::optional<domain::Reminder> reminder;
  std::optional<domain::Reminder> successor;
  std::optional<domain::ReminderRecoveryBatch> recovery_batch;
  bool idempotent_replay = false;
};

class RecurringReminderDeliveryWorkflowService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  RecurringReminderDeliveryWorkflowService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      std::shared_ptr<RollingReminderService> rolling_reminder_service,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<PrepareDeliveryResult> prepare_delivery(
      const PrepareDeliveryCommand& command);
  common::Result<FinalizeDeliveryResult> finalize_delivery(
      const FinalizeDeliveryCommand& command);

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  std::shared_ptr<RollingReminderService> rolling_reminder_service_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
