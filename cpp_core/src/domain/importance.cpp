#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::domain {

bool is_valid_importance(std::string_view value) {
  return value == "unimportant_noturgent" ||
         value == "important_noturgent" ||
         value == "unimportant_urgent" ||
         value == "important_urgent";
}

int importance_rank(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return 0;
  }
  if (*value == "unimportant_noturgent") {
    return 1;
  }
  if (*value == "important_noturgent") {
    return 2;
  }
  if (*value == "unimportant_urgent") {
    return 3;
  }
  if (*value == "important_urgent") {
    return 4;
  }
  return 0;
}

}  // namespace excellent_calendar::domain
