#pragma once

#include <filesystem>

#include "excellent_calendar/repository/reminder_notification_transaction.hpp"
#include "excellent_calendar/storage/json/json_snapshot_transaction.hpp"

namespace excellent_calendar::storage::json {

class JsonReminderNotificationTransaction final
    : public repository::ReminderNotificationTransaction {
 public:
  explicit JsonReminderNotificationTransaction(std::filesystem::path storage_directory);

  common::Result<common::Unit> initialize();

  common::Result<common::Unit> execute(const Operation& operation) override;

 private:
  JsonSnapshotTransaction transaction_;
};

}  // namespace excellent_calendar::storage::json
