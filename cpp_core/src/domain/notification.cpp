#include "excellent_calendar/domain/notification.hpp"

namespace excellent_calendar::domain {

bool is_valid_notification_status(std::string_view value) {
  return value == kNotificationStatusPending ||
         value == kNotificationStatusPrepared ||
         value == kNotificationStatusSent ||
         value == kNotificationStatusFailed ||
         value == kNotificationStatusCancelled ||
         value == kNotificationStatusAbandoned;
}

bool is_valid_notification_target_type(std::string_view value) {
  return value == "event" || value == "habit" ||
         value == "anniversary" || value == "dated_message" ||
         value == "reminder_recovery_batch";
}

}  // namespace excellent_calendar::domain
