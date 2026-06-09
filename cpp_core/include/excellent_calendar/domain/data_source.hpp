#pragma once

#include <string_view>

namespace excellent_calendar::domain {

bool is_valid_create_event_source(std::string_view value);

}  // namespace excellent_calendar::domain
