#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string create_reminder(std::string_view request_json);

std::string cancel_reminder(std::string_view request_json);

std::string list_reminders(std::string_view request_json);

std::string mark_reminder_scheduled(std::string_view reminder_id);

std::string mark_reminder_failed(std::string_view reminder_id, std::string_view failure_reason);

}  // namespace excellent_calendar::boundary::api
