#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::domain {

/** importance 字符串白名单校验。 */
bool is_valid_importance(std::string_view value) {
  return value == "unimportant_noturgent" ||
         value == "important_noturgent" ||
         value == "unimportant_urgent" ||
         value == "important_urgent";
}

/** importance 排序权重。数值越大代表越靠后/越高优先级，具体方向由 sort_direction 控制。 */
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
