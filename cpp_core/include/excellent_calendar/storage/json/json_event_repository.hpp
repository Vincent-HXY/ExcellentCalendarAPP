#pragma once

#include <filesystem>
#include <mutex>
#include <vector>

#include "excellent_calendar/repository/event_repository.hpp"

namespace excellent_calendar::storage::json {

class JsonEventRepository final : public repository::EventRepository {
 public:
  explicit JsonEventRepository(std::filesystem::path storage_directory);

  common::Result<common::Unit> initialize();

  common::Result<domain::Event> create(const domain::Event& event) override;

  common::Result<std::vector<domain::Event>> find_all() override;

  const std::filesystem::path& storage_directory() const { return storage_directory_; }

 private:
  common::Result<std::vector<domain::Event>> load_events_locked();

  common::Result<common::Unit> save_events_locked(const std::vector<domain::Event>& events);

  std::filesystem::path events_file() const;

  std::filesystem::path storage_directory_;
  mutable std::mutex mutex_;
};

}  // namespace excellent_calendar::storage::json
