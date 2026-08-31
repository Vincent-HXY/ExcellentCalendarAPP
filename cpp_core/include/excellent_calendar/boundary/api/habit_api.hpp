#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string create_habit_v2(std::string_view request_json);
std::string update_habit_v2(std::string_view request_json);
std::string list_habits_v2(std::string_view request_json);
std::string get_habit_detail_v2(std::string_view request_json);
std::string end_habit_v2(std::string_view request_json);
std::string delete_habit_v2(std::string_view request_json);
std::string check_in_habit_v2(std::string_view request_json);
std::string clear_habit_check_in_v2(std::string_view request_json);
std::string list_habit_daily_statuses_v2(std::string_view request_json);
std::string set_habit_reminder_v2(std::string_view request_json);
std::string reconcile_habit_reminders_v2(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
