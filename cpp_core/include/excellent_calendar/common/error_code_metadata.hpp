#pragma once

#include <optional>
#include <string_view>

namespace excellent_calendar::common {

// Returns the retryable metadata frozen in contracts/error_codes.yaml.
// Unknown codes return nullopt so unversioned error strings cannot cross the
// delivery boundary silently.
std::optional<bool> contract_error_retryable(std::string_view error_code);

}  // namespace excellent_calendar::common
