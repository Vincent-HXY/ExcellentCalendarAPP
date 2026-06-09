#pragma once

#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"

namespace excellent_calendar::repository {

class EventRepository {
 public:
  virtual ~EventRepository() = default;

  virtual common::Result<domain::Event> create(const domain::Event& event) = 0;

  virtual common::Result<std::vector<domain::Event>> find_all() = 0;
};

}  // namespace excellent_calendar::repository
