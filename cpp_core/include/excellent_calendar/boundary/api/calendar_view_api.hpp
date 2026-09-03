#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string calendar_range_summary_v2(std::string_view request_json);
std::string calendar_list_day_items_v2(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
