#pragma once

#include <string>
#include <vector>

namespace excellent_calendar::boundary::contract {

struct ListSchedulableRemindersRequest {
  std::string from_at;
  std::string to_at;
  int limit = 500;
  bool include_failed = true;
  bool include_scheduled = false;
  std::vector<std::string> supported_methods;
};

}  // namespace excellent_calendar::boundary::contract
