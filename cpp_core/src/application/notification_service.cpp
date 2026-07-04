#include "excellent_calendar/application/notification_service.hpp"

#include <algorithm>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/failure_reason.hpp"
#include "excellent_calendar/common/string_utils.hpp"

namespace excellent_calendar::application {
namespace {

common::Error contract_error(std::string field, std::string message) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", std::move(message), {{"field", std::move(field)}});
}

common::Error reminder_not_found(std::string id) {
  return common::make_error(
      "REMINDER_NOT_FOUND", "Reminder not found", {{"id", std::move(id)}});
}

common::Error reminder_not_deliverable(const domain::Reminder& reminder) {
  return common::make_error(
      "REMINDER_NOT_DELIVERABLE",
      "Reminder is not deliverable",
      {{"id", reminder.id}, {"status", reminder.status}});
}

common::Error reminder_already_consumed(std::string id) {
  return common::make_error(
      "REMINDER_ALREADY_CONSUMED",
      "Reminder has already been consumed",
      {{"id", std::move(id)}});
}

common::Error reminder_not_due(const domain::Reminder& reminder,
                               const std::string& planned_at) {
  return common::make_error(
      "REMINDER_NOT_DUE",
      "Reminder is not due yet",
      {{"id", reminder.id},
       {"expected_remind_at", reminder.remind_at},
       {"planned_at", planned_at}},
      true);
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

bool has_method(const domain::Reminder& reminder, const std::string& method) {
  return std::find(reminder.methods.begin(), reminder.methods.end(), method) != reminder.methods.end();
}

common::Result<common::Unit> validate_common_notification_fields(
    const std::string& reminder_id,
    const std::string& method,
    const std::string& title,
    const std::string& planned_at) {
  if (common::trim_ascii(reminder_id).empty()) {
    return common::Result<common::Unit>::failure(
        contract_error("reminder_id", "reminder_id must be non-empty."));
  }
  if (method != std::string(domain::kReminderMethodPopup)) {
    return common::Result<common::Unit>::failure(
        contract_error("method", "Version 1 only supports popup delivery."));
  }
  if (common::trim_ascii(title).empty()) {
    return common::Result<common::Unit>::failure(
        contract_error("title", "title must be non-empty."));
  }
  if (!common::is_iso8601_utc_datetime(planned_at)) {
    return common::Result<common::Unit>::failure(
        contract_error("planned_at", "planned_at must be ISO 8601 UTC date-time."));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

domain::Notification build_notification(
    const domain::Reminder& reminder,
    const std::string& id,
    const std::string& method,
    const std::string& title,
    const std::optional<std::string>& body,
    const std::string& planned_at,
    const std::optional<std::string>& sent_at,
    const std::string& status,
    const std::optional<std::string>& failure_reason,
    const std::string& now) {
  domain::Notification notification;
  notification.id = id;
  notification.reminder_id = reminder.id;
  notification.target_type = reminder.target_type;
  notification.target_id = reminder.target_id;
  notification.method = method;
  notification.title = common::trim_ascii(title);
  notification.body = body;
  notification.planned_at = planned_at;
  notification.sent_at = sent_at;
  notification.status = status;
  notification.failure_reason = failure_reason;
  notification.created_at = now;
  notification.updated_at = now;
  return notification;
}

}  // namespace

NotificationService::NotificationService(
    std::shared_ptr<repository::ReminderRepository> reminder_repository,
    std::shared_ptr<repository::NotificationRepository> notification_repository,
    std::shared_ptr<repository::ReminderNotificationTransaction> transaction,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : reminder_repository_(std::move(reminder_repository)),
      notification_repository_(std::move(notification_repository)),
      transaction_(std::move(transaction)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Notification> NotificationService::create_notification(
    const CreateNotificationCommand& command) {
  auto valid = validate_common_notification_fields(
      command.reminder_id, command.method, command.title, command.planned_at);
  if (!valid.ok()) return common::Result<domain::Notification>::failure(valid.error());
  if (common::trim_ascii(command.target_id).empty() ||
      !domain::is_valid_notification_target_type(command.target_type)) {
    return common::Result<domain::Notification>::failure(
        contract_error("target_type", "Notification target is invalid."));
  }
  if (command.status != std::string(domain::kNotificationStatusSent) &&
      command.status != std::string(domain::kNotificationStatusFailed)) {
    return common::Result<domain::Notification>::failure(
        contract_error("status", "Notification status must be sent or failed."));
  }
  if (command.status == std::string(domain::kNotificationStatusSent)) {
    if (!command.sent_at.has_value() || !common::is_iso8601_utc_datetime(*command.sent_at) ||
        command.failure_reason.has_value()) {
      return common::Result<domain::Notification>::failure(
          contract_error("sent_at", "Sent notifications require sent_at and no failure_reason."));
    }
  } else if (!command.failure_reason.has_value() ||
             common::trim_ascii(*command.failure_reason).empty()) {
    return common::Result<domain::Notification>::failure(
        contract_error("failure_reason", "Failed notifications require failure_reason."));
  }
  if (command.sent_at.has_value() && !common::is_iso8601_utc_datetime(*command.sent_at)) {
    return common::Result<domain::Notification>::failure(
        contract_error("sent_at", "sent_at must be ISO 8601 UTC date-time or null."));
  }

  auto found = reminder_repository_->find_by_id(command.reminder_id);
  if (!found.ok()) return common::Result<domain::Notification>::failure(found.error());
  if (!found.value().has_value()) {
    return common::Result<domain::Notification>::failure(reminder_not_found(command.reminder_id));
  }
  const auto& reminder = *found.value();
  if (reminder.target_type != command.target_type || reminder.target_id != command.target_id ||
      !has_method(reminder, command.method)) {
    return common::Result<domain::Notification>::failure(
        contract_error("target_id", "Notification target or method does not match its Reminder."));
  }
  const auto now = clock_();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<domain::Notification>::failure(internal_error("clock returned invalid UTC time"));
  }
  std::optional<std::string> failure_reason;
  if (command.failure_reason.has_value()) {
    failure_reason = common::sanitize_failure_reason(
        *command.failure_reason, "Notification delivery failed");
  }
  auto notification = build_notification(
      reminder,
      id_generator_(),
      command.method,
      command.title,
      command.body,
      command.planned_at,
      command.sent_at,
      command.status,
      failure_reason,
      now);
  return notification_repository_->create(notification);
}

common::Result<ConsumeReminderAfterDeliveryResult> NotificationService::consume_after_delivery(
    const ConsumeReminderAfterDeliveryCommand& command) {
  auto valid = validate_common_notification_fields(
      command.reminder_id, command.method, command.title, command.planned_at);
  if (!valid.ok()) {
    return common::Result<ConsumeReminderAfterDeliveryResult>::failure(valid.error());
  }
  if (!common::is_iso8601_utc_datetime(command.sent_at)) {
    return common::Result<ConsumeReminderAfterDeliveryResult>::failure(
        contract_error("sent_at", "sent_at must be ISO 8601 UTC date-time."));
  }
  if (!command.delete_after_sent) {
    return common::Result<ConsumeReminderAfterDeliveryResult>::failure(
        contract_error("delete_after_sent", "Version 1 requires delete_after_sent=true."));
  }

  std::optional<ConsumeReminderAfterDeliveryResult> consumed;
  auto transaction_result = transaction_->execute([&]() -> common::Result<common::Unit> {
    auto found = reminder_repository_->find_by_id(command.reminder_id);
    if (!found.ok()) return common::Result<common::Unit>::failure(found.error());
    if (!found.value().has_value()) {
      return common::Result<common::Unit>::failure(reminder_not_found(command.reminder_id));
    }
    auto reminder = *found.value();
    if (reminder.status == std::string(domain::kReminderStatusSent)) {
      auto notification = notification_repository_->find_sent_by_reminder_id(reminder.id);
      if (!notification.ok()) return common::Result<common::Unit>::failure(notification.error());
      if (!notification.value().has_value()) {
        return common::Result<common::Unit>::failure(reminder_already_consumed(reminder.id));
      }
      consumed = ConsumeReminderAfterDeliveryResult{reminder, *notification.value()};
      return common::Result<common::Unit>::success(common::Unit{});
    }
    if (!reminder.is_enabled || reminder.deleted_at.has_value() ||
        reminder.status == std::string(domain::kReminderStatusCancelled)) {
      return common::Result<common::Unit>::failure(reminder_not_deliverable(reminder));
    }
    if (reminder.status != std::string(domain::kReminderStatusPending) &&
        reminder.status != std::string(domain::kReminderStatusScheduled) &&
        reminder.status != std::string(domain::kReminderStatusFailed)) {
      return common::Result<common::Unit>::failure(reminder_not_deliverable(reminder));
    }
    if (!has_method(reminder, command.method)) {
      return common::Result<common::Unit>::failure(
          common::make_error(
              "UNSUPPORTED_REMINDER_METHOD",
              "Reminder method is not supported in current version",
              {{"method", command.method}}));
    }
    if (reminder.remind_at != command.planned_at) {
      return common::Result<common::Unit>::failure(reminder_not_due(reminder, command.planned_at));
    }

    const auto now = clock_();
    if (!common::is_iso8601_utc_datetime(now)) {
      return common::Result<common::Unit>::failure(internal_error("clock returned invalid UTC time"));
    }
    auto existing_notification = notification_repository_->find_sent_by_reminder_id(reminder.id);
    if (!existing_notification.ok()) {
      return common::Result<common::Unit>::failure(existing_notification.error());
    }
    domain::Notification notification;
    if (existing_notification.value().has_value()) {
      notification = *existing_notification.value();
      if (notification.target_type != reminder.target_type ||
          notification.target_id != reminder.target_id ||
          notification.method != command.method ||
          notification.planned_at != command.planned_at) {
        return common::Result<common::Unit>::failure(
            contract_error("reminder_id", "Existing notification does not match this delivery."));
      }
    } else {
      notification = build_notification(
          reminder,
          id_generator_(),
          command.method,
          command.title,
          command.body,
          command.planned_at,
          command.sent_at,
          std::string(domain::kNotificationStatusSent),
          std::nullopt,
          now);
      auto created = notification_repository_->create(notification);
      if (!created.ok()) return common::Result<common::Unit>::failure(created.error());
      notification = created.value();
    }

    reminder.status = std::string(domain::kReminderStatusSent);
    reminder.last_triggered_at = command.sent_at;
    reminder.failure_reason = std::nullopt;
    reminder.updated_at = now;
    auto updated = reminder_repository_->update(reminder);
    if (!updated.ok()) return common::Result<common::Unit>::failure(updated.error());
    consumed = ConsumeReminderAfterDeliveryResult{updated.value(), notification};
    return common::Result<common::Unit>::success(common::Unit{});
  });
  if (!transaction_result.ok()) {
    return common::Result<ConsumeReminderAfterDeliveryResult>::failure(transaction_result.error());
  }
  if (!consumed.has_value()) {
    return common::Result<ConsumeReminderAfterDeliveryResult>::failure(
        internal_error("consume transaction returned no result"));
  }
  return common::Result<ConsumeReminderAfterDeliveryResult>::success(std::move(*consumed));
}

}  // namespace excellent_calendar::application
