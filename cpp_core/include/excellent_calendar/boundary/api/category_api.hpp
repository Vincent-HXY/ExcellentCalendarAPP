#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string list_categories_v2(std::string_view request_json);

std::string create_category_v2(std::string_view request_json);

} // namespace excellent_calendar::boundary::api
