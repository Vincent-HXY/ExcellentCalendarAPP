#pragma once

#include <functional>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::repository {

class ReminderNotificationTransaction {
 public:
  using Operation = std::function<common::Result<common::Unit>()>;

  virtual ~ReminderNotificationTransaction() = default;

  virtual common::Result<common::Unit> execute(const Operation& operation) = 0;
};

}  // namespace excellent_calendar::repository
