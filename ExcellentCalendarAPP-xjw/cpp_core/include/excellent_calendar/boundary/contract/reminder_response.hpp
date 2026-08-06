#pragma once

#include <optional>
#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::contract {

struct ReminderResponse {
  std::string id;
  std::string target_type;
  std::string target_id;
  std::string remind_at;
  std::vector<std::string> methods;
  std::optional<int> advance_minutes;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string status;
  std::optional<std::string> scheduled_at;
  std::optional<std::string> last_triggered_at;
  std::optional<std::string> failure_reason;
  std::optional<std::string> cancellation_reason;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

ReminderResponse make_reminder_response(const domain::Reminder& reminder);

picojson::value reminder_response_to_json(const ReminderResponse& reminder);

picojson::value reminder_response_to_json(const domain::Reminder& reminder);

}  // namespace excellent_calendar::boundary::contract
