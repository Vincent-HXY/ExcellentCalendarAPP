#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::boundary::contract {

struct CreateNotificationRequest {
  std::string reminder_id;
  std::string target_type;
  std::string target_id;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::optional<std::string> sent_at;
  std::string status;
  std::optional<std::string> failure_reason;
};

}  // namespace excellent_calendar::boundary::contract
