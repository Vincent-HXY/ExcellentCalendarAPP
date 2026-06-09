#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace excellent_calendar::domain {

bool is_valid_importance(std::string_view value);

int importance_rank(const std::optional<std::string>& value);

}  // namespace excellent_calendar::domain
