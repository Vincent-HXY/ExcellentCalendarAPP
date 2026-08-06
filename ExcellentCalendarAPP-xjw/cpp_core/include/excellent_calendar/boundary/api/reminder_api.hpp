#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string create_reminder(std::string_view request_json);

std::string update_reminder(std::string_view request_json);

std::string cancel_reminder(std::string_view request_json);

std::string list_reminders(std::string_view request_json);

std::string get_reminder(std::string_view request_json);

std::string list_schedulable_reminders(std::string_view request_json);

std::string mark_reminder_scheduled(std::string_view request_json);

std::string mark_reminder_sent(std::string_view request_json);

std::string mark_reminder_failed(std::string_view request_json);

std::string enable_reminder(std::string_view request_json);

std::string disable_reminder(std::string_view request_json);

std::string consume_reminder_after_delivery(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
