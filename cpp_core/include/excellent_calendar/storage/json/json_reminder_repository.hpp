#pragma once

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/repository/reminder_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage::json {

class JsonReminderRepository final : public repository::ReminderRepository {
 public:
  explicit JsonReminderRepository(
      std::filesystem::path storage_directory,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize();

  common::Result<domain::Reminder> create(const domain::Reminder& reminder) override;

  common::Result<std::optional<domain::Reminder>> find_by_id(std::string_view id) override;

  common::Result<domain::Reminder> update(const domain::Reminder& reminder) override;

  common::Result<std::vector<domain::Reminder>> find_all() override;

  const std::filesystem::path& storage_directory() const { return store_.storage_directory(); }

 private:
  common::Result<std::vector<domain::Reminder>> load_reminders_locked();

  common::Result<common::Unit> save_reminders_locked(const std::vector<domain::Reminder>& reminders);

  AtomicJsonFileStore store_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
  mutable std::mutex mutex_;
};

}  // namespace excellent_calendar::storage::json
