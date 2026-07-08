#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/notification_repository.hpp"
#include "excellent_calendar/repository/reminder_notification_transaction.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"

namespace excellent_calendar::application {

struct CreateNotificationCommand {
  std::string reminder_id;
  std::string target_type;
  std::string target_id;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::optional<std::string> sent_at;
  std::string status;
  std::optional<std::string> failure_reason;
};

struct ConsumeReminderAfterDeliveryCommand {
  std::string reminder_id;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::string sent_at;
  bool delete_after_sent = true;
};

struct ConsumeReminderAfterDeliveryResult {
  domain::Reminder reminder;
  domain::Notification notification;
};

class NotificationService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  NotificationService(
      std::shared_ptr<repository::ReminderRepository> reminder_repository,
      std::shared_ptr<repository::NotificationRepository> notification_repository,
      std::shared_ptr<repository::ReminderNotificationTransaction> transaction,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<domain::Notification> create_notification(
      const CreateNotificationCommand& command);

  common::Result<ConsumeReminderAfterDeliveryResult> consume_after_delivery(
      const ConsumeReminderAfterDeliveryCommand& command);

 private:
  std::shared_ptr<repository::ReminderRepository> reminder_repository_;
  std::shared_ptr<repository::NotificationRepository> notification_repository_;
  std::shared_ptr<repository::ReminderNotificationTransaction> transaction_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
