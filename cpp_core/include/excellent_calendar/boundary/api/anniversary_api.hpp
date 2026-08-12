#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string create_anniversary_v2(std::string_view request_json);
std::string update_anniversary_v2(std::string_view request_json);
std::string delete_anniversary_v2(std::string_view request_json);
std::string get_anniversary_detail_v2(std::string_view request_json);
std::string list_anniversaries_v2(std::string_view request_json);
std::string preview_anniversary_countdown_v2(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
