#pragma once

#include <string>
#include <string_view>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::common {

bool is_uuid(std::string_view value);

/** Generate RFC 4122 UUIDv5 from a textual namespace UUID and UTF-8 name. */
Result<std::string> generate_uuid_v5(std::string_view namespace_uuid,
                                    std::string_view name);

}  // namespace excellent_calendar::common
