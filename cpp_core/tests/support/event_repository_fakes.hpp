#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/repository/event_repository.hpp"

namespace excellent_calendar::test_support {

class InMemoryEventRepository final : public repository::EventRepository {
 public:
  common::Result<domain::Event> create(const domain::Event& event) override {
    events.push_back(event);
    return common::Result<domain::Event>::success(event);
  }

  common::Result<domain::Event> update(const domain::Event& event) override {
    for (auto& existing : events) {
      if (existing.id == event.id) {
        existing = event;
        return common::Result<domain::Event>::success(event);
      }
    }
    return common::Result<domain::Event>::failure(
        common::make_error("EVENT_NOT_FOUND", "Event not found", {{"id", event.id}}));
  }

  common::Result<std::optional<domain::Event>> find_by_id(std::string_view id) override {
    for (const auto& event : events) {
      if (event.id == id) {
        return common::Result<std::optional<domain::Event>>::success(event);
      }
    }
    return common::Result<std::optional<domain::Event>>::success(std::nullopt);
  }

  common::Result<std::vector<domain::Event>> find_all() override {
    return common::Result<std::vector<domain::Event>>::success(events);
  }

  std::vector<domain::Event> events;
};

class FailingEventRepository final : public repository::EventRepository {
 public:
  common::Result<domain::Event> create(const domain::Event& /*event*/) override {
    return common::Result<domain::Event>::failure(storage_error());
  }

  common::Result<domain::Event> update(const domain::Event& /*event*/) override {
    return common::Result<domain::Event>::failure(storage_error());
  }

  common::Result<std::optional<domain::Event>> find_by_id(std::string_view /*id*/) override {
    return common::Result<std::optional<domain::Event>>::failure(storage_error());
  }

  common::Result<std::vector<domain::Event>> find_all() override {
    return common::Result<std::vector<domain::Event>>::failure(storage_error());
  }

 private:
  static common::Error storage_error() {
    return common::make_error("STORAGE_IO_ERROR", "Storage input/output operation failed");
  }
};

}  // namespace excellent_calendar::test_support
