#include "excellent_calendar/domain/reminder_recovery_batch.hpp"

namespace excellent_calendar::domain {

bool is_valid_recovery_trigger_source(std::string_view value) {
  return value == "app_start" || value == "device_boot" || value == "alarm_reconcile";
}

}  // namespace excellent_calendar::domain
