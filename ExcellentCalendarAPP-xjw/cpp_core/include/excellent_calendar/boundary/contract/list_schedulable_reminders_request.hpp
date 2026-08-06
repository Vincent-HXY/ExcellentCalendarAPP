#pragma once

#include <optional>
#include <string>
#include <vector>

namespace excellent_calendar::boundary::contract {

struct SchedulableReminderCursor {
  std::string remind_at;
  std::string id;
};

struct ListSchedulableRemindersRequest {
  std::optional<std::string> from_at;
  std::optional<std::string> to_at;
  std::optional<SchedulableReminderCursor> cursor;
  int limit = 500;
  bool include_failed = true;
  bool include_scheduled = false;
  std::vector<std::string> supported_methods;
};

}  // namespace excellent_calendar::boundary::contract
