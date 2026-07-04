#pragma once

#include <string>

namespace excellent_calendar::boundary::contract {

struct GetReminderRequest {
  std::string id;
};

}  // namespace excellent_calendar::boundary::contract
