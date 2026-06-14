#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::domain {

bool is_valid_reminder_target_type(std::string_view value) {
  return value == kReminderTargetEvent ||
         value == kReminderTargetHabit ||
         value == kReminderTargetAnniversary;
}

bool is_supported_reminder_target_type(std::string_view value) {
  return value == kReminderTargetEvent;
}

bool is_valid_reminder_method(std::string_view value) {
  return value == kReminderMethodRing ||
         value == kReminderMethodPopup ||
         value == kReminderMethodWechat;
}

bool is_valid_reminder_status(std::string_view value) {
  return value == kReminderStatusPending ||
         value == kReminderStatusScheduled ||
         value == kReminderStatusSent ||
         value == kReminderStatusFailed ||
         value == kReminderStatusCancelled;
}

bool is_valid_reminder_source(std::string_view value) {
  return value == "manual" ||
         value == "auto" ||
         value == "ai_extraction" ||
         value == "sync" ||
         value == "import" ||
         value == "wechat";
}

}  // namespace excellent_calendar::domain
