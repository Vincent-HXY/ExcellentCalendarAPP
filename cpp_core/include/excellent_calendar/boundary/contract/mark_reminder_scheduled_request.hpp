#pragma once

#include <string>

namespace excellent_calendar::boundary::contract {

struct MarkReminderScheduledRequest {
  std::string id;
  std::string scheduled_at;
};

}  // namespace excellent_calendar::boundary::contract
