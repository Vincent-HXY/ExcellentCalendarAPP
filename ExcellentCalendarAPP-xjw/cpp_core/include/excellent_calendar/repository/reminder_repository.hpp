#pragma once

#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::repository {

class ReminderRepository {
 public:
  virtual ~ReminderRepository() = default;

  virtual common::Result<domain::Reminder> create(const domain::Reminder& reminder) = 0;

  virtual common::Result<std::optional<domain::Reminder>> find_by_id(std::string_view id) = 0;

  virtual common::Result<domain::Reminder> update(const domain::Reminder& reminder) = 0;

  virtual common::Result<std::vector<domain::Reminder>> find_all() = 0;
};

}  // namespace excellent_calendar::repository
