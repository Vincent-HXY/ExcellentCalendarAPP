#pragma once

#include <filesystem>
#include <mutex>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/repository/notification_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {

class JsonNotificationRepository final : public repository::NotificationRepository {
 public:
  explicit JsonNotificationRepository(std::filesystem::path storage_directory);

  common::Result<common::Unit> initialize();

  common::Result<domain::Notification> create(const domain::Notification& notification) override;

  common::Result<std::optional<domain::Notification>> find_sent_by_reminder_id(
      std::string_view reminder_id) override;

  common::Result<std::vector<domain::Notification>> find_all() override;

 private:
  common::Result<std::vector<domain::Notification>> load_notifications_locked();

  common::Result<common::Unit> save_notifications_locked(
      const std::vector<domain::Notification>& notifications);

  AtomicJsonFileStore store_;
  mutable std::mutex mutex_;
};

}  // namespace excellent_calendar::storage::json
