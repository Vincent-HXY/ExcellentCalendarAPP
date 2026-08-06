#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

std::string create_notification(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
