#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string search_query_v2(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
