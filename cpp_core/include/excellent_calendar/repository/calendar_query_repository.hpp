#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::repository {

inline constexpr std::array<std::string_view, 9>
    kCalendarQueryContributingStores{{
        "events",
        "recurrence_versions",
        "event_occurrence_states",
        "habits",
        "habit_recurrences",
        "habit_check_ins",
        "anniversaries",
        "anniversary_recurrences",
        "reminders",
    }};

struct CalendarQuerySnapshot {
  std::array<std::int64_t, kCalendarQueryContributingStores.size()>
      generations{};
  std::vector<domain::Event> events;
  std::vector<domain::Recurrence> event_recurrences;
  std::vector<domain::EventOccurrenceState> event_occurrence_states;
  std::vector<domain::Habit> habits;
  std::vector<domain::HabitRecurrence> habit_recurrences;
  std::vector<domain::HabitCheckIn> habit_check_ins;
  std::vector<domain::Anniversary> anniversaries;
  std::vector<domain::AnniversaryRecurrence> anniversary_recurrences;
  std::vector<domain::Reminder> reminders;
};

/**
 * Narrow, read-only port used by CalendarView. Implementations must load the
 * generations and every contributing fact in one authoritative read
 * transaction.
 */
class CalendarQueryRepository {
 public:
  virtual ~CalendarQueryRepository() = default;

  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<CalendarQuerySnapshot> load_snapshot(
      const std::optional<std::array<
          std::int64_t, kCalendarQueryContributingStores.size()>>&
          expected_generations = std::nullopt) = 0;
};

}  // namespace excellent_calendar::repository
