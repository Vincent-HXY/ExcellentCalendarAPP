#pragma once

#include <string>

namespace excellent_calendar::boundary::contract {

struct MarkReminderFailedRequest {
  std::string id;
  std::string failure_reason;
};

}  // namespace excellent_calendar::boundary::contract
