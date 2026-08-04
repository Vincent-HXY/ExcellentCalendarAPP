#pragma once

#include <filesystem>
#include <memory>

#include "excellent_calendar/repository/event_reminder_transaction.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage::json {

class JsonEventReminderTransaction final : public repository::EventReminderTransaction {
 public:
  explicit JsonEventReminderTransaction(
      std::filesystem::path storage_directory,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();

  common::Result<common::Unit> execute(const Operation& operation) override;

 private:
  common::Result<common::Unit> recover_locked();

  AtomicJsonFileStore store_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

}  // namespace excellent_calendar::storage::json
