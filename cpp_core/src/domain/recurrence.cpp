#include "excellent_calendar/domain/recurrence.hpp"

namespace excellent_calendar::domain {

bool is_supported_recurrence_frequency(std::string_view value) {
  return value == kRecurrenceDaily || value == kRecurrenceWeekly ||
         value == kRecurrenceMonthly;
}

bool is_known_recurrence_frequency(std::string_view value) {
  return is_supported_recurrence_frequency(value) || value == kRecurrenceYearly ||
         value == kRecurrenceCustom;
}

RecurringEventSchedule recurring_schedule_from_event(const Event& event) {
  RecurringEventSchedule schedule;
  schedule.event_id = event.id;
  if (!event.start_at.empty()) schedule.start_at = event.start_at;
  if (!event.end_at.empty()) schedule.end_at = event.end_at;
  schedule.start_date = event.start_date;
  schedule.end_date = event.end_date;
  schedule.is_all_day = event.is_all_day;
  schedule.timezone = event.timezone.value_or("");
  return schedule;
}

}  // namespace excellent_calendar::domain
