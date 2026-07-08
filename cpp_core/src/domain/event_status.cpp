#include "excellent_calendar/domain/event_status.hpp"

namespace excellent_calendar::domain {

/** 事件状态白名单校验。 */
bool is_valid_event_status(std::string_view value) {
  return value == kEventStatusActive ||
         value == kEventStatusCompleted ||
         value == kEventStatusCancelled ||
         value == kEventStatusArchived;
}

}  // namespace excellent_calendar::domain
