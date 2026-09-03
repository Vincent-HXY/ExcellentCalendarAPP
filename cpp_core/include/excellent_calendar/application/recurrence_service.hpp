#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/recurrence.hpp"

namespace excellent_calendar::application {

class RecurrenceService {
 public:
  explicit RecurrenceService(std::shared_ptr<domain::LocalTimeResolver> time_resolver);

  common::Result<common::Unit> validate_timezone(std::string_view timezone) const;

  common::Result<domain::Recurrence> derive_recurrence(
      const domain::RecurringEventSchedule& event,
      const domain::EventRecurrenceRuleInput& input,
      std::string recurrence_id,
      int revision,
      std::string created_at) const;

  common::Result<domain::EventOccurrence> occurrence_at(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      int index) const;

  common::Result<std::vector<domain::EventOccurrence>> list_timed_occurrences(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      std::string_view range_start_at,
      std::string_view range_end_at,
      int limit = 200) const;

  common::Result<std::vector<domain::EventOccurrence>> list_all_day_occurrences(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      std::string_view range_start_date,
      std::string_view range_end_date,
      int limit = 200) const;

  /**
   * Expands monotonically from an already bounded index until the first
   * occurrence whose start is at or after the exclusive range end. These
   * batch paths prepare the immutable source schedule once, preserving the
   * same DST and UUIDv5 rules as occurrence_at() without reparsing it for
   * every CalendarView occurrence.
   */
  common::Result<std::vector<domain::EventOccurrence>>
  list_timed_occurrences_from_index(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      int first_index,
      std::string_view exclusive_range_end_at) const;

  common::Result<std::vector<domain::EventOccurrence>>
  list_all_day_occurrences_from_index(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      int first_index,
      std::string_view exclusive_range_end_date) const;

  common::Result<domain::EventOccurrence> first_timed_occurrence_with_reminder_after(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      int advance_minutes,
      std::string_view after_at) const;

 private:
  std::shared_ptr<domain::LocalTimeResolver> time_resolver_;
};

}  // namespace excellent_calendar::application
