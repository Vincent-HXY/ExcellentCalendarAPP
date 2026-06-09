#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::common {

std::string trim_ascii(std::string_view value);

std::string lowercase_ascii(std::string_view value);

bool contains_case_insensitive_ascii(std::string_view text, std::string_view keyword);

}  // namespace excellent_calendar::common
