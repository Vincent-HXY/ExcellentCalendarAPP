#pragma once

#include <filesystem>
#include <memory>

#include "excellent_calendar/repository/reminder_notification_transaction.hpp"
#include "excellent_calendar/storage/json/json_snapshot_transaction.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage::json {

class JsonReminderNotificationTransaction final
    : public repository::ReminderNotificationTransaction {
 public:
  explicit JsonReminderNotificationTransaction(
      std::filesystem::path storage_directory,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();

  common::Result<common::Unit> execute(const Operation& operation) override;

 private:
  JsonSnapshotTransaction transaction_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

}  // namespace excellent_calendar::storage::json
