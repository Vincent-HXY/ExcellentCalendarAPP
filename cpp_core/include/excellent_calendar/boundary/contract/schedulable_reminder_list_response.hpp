#pragma once

#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/boundary/contract/reminder_response.hpp"

namespace excellent_calendar::boundary::contract {

struct SchedulableReminderListResponse {
  std::vector<ReminderResponse> items;
  int selected_count = 0;
  bool has_more = false;
  std::optional<std::string> next_cursor_remind_at;
  std::optional<std::string> next_cursor_id;
  std::vector<std::string> unsupported_reminder_ids;
};

SchedulableReminderListResponse make_schedulable_reminder_list_response(
    const application::SchedulableReminderListResult& result);

picojson::value schedulable_reminder_list_response_to_json(
    const SchedulableReminderListResponse& response);

}  // namespace excellent_calendar::boundary::contract
