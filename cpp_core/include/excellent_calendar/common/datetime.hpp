#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace excellent_calendar::common {

std::optional<std::int64_t> parse_iso8601_utc_epoch_seconds(std::string_view value);

bool is_iso8601_utc_datetime(std::string_view value);

}  // namespace excellent_calendar::common
