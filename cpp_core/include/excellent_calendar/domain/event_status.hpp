#pragma once

#include <string_view>

namespace excellent_calendar::domain {

inline constexpr std::string_view kEventStatusActive = "active";
inline constexpr std::string_view kEventStatusCompleted = "completed";
inline constexpr std::string_view kEventStatusCancelled = "cancelled";
inline constexpr std::string_view kEventStatusArchived = "archived";

bool is_valid_event_status(std::string_view value);

}  // namespace excellent_calendar::domain
