#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"

namespace excellent_calendar::storage::json {

JsonReminderNotificationTransaction::JsonReminderNotificationTransaction(
    std::filesystem::path storage_directory)
    : transaction_(
          std::move(storage_directory),
          "reminder_notification_transaction.json",
          {"reminders.json", "notifications.json"}) {}

common::Result<common::Unit> JsonReminderNotificationTransaction::initialize() {
  return transaction_.initialize();
}

common::Result<common::Unit> JsonReminderNotificationTransaction::execute(
    const Operation& operation) {
  return transaction_.execute(operation);
}

}  // namespace excellent_calendar::storage::json
