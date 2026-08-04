#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"

namespace excellent_calendar::storage::json {

JsonReminderNotificationTransaction::JsonReminderNotificationTransaction(
    std::filesystem::path storage_directory,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : transaction_(
          std::move(storage_directory),
          "reminder_notification_transaction.json",
          {"reminders.json", "notifications.json"}),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonReminderNotificationTransaction::initialize() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(
        storage::runtime_storage_revoked_error(
            "reminder_notification_transaction.initialize"));
  }
  return transaction_.initialize();
}

common::Result<common::Unit> JsonReminderNotificationTransaction::execute(
    const Operation& operation) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(
        storage::runtime_storage_revoked_error("reminder_notification_transaction.execute"));
  }
  return transaction_.execute(operation);
}

}  // namespace excellent_calendar::storage::json
