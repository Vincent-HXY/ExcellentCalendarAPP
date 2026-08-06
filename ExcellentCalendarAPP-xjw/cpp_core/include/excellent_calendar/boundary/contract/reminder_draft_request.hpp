#pragma once

#include <optional>
#include <string>
#include <vector>

namespace excellent_calendar::boundary::contract {

struct ReminderDraftRequest {
  std::string target_type;
  std::optional<std::string> target_id;
  std::optional<std::string> remind_at;
  std::optional<int> advance_minutes;
  std::vector<std::string> methods;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string source;
};

}  // namespace excellent_calendar::boundary::contract
