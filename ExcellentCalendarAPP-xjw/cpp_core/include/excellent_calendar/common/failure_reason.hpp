#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::common {

std::string sanitize_failure_reason(std::string_view reason,
                                    std::string_view fallback);

}  // namespace excellent_calendar::common
