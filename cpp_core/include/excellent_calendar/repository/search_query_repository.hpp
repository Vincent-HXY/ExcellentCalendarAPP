#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/category.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/search.hpp"

namespace excellent_calendar::repository {

inline constexpr std::array<std::string_view, 8>
    kSearchQueryContributingStores{{
        "events", "recurrence_versions", "event_occurrence_states",
        "categories", "habits", "habit_recurrences", "anniversaries",
        "anniversary_recurrences",
    }};

struct SearchQuerySnapshot {
  std::size_t sql_statements_executed = 0;
  std::array<std::int64_t, kSearchQueryContributingStores.size()> generations{};
  std::vector<domain::Event> events;
  std::vector<domain::Recurrence> event_recurrences;
  std::vector<domain::EventOccurrenceState> event_occurrence_states;
  std::vector<domain::Category> categories;
  std::vector<domain::Habit> habits;
  std::vector<domain::HabitRecurrence> habit_recurrences;
  std::vector<domain::Anniversary> anniversaries;
  std::vector<domain::AnniversaryRecurrence> anniversary_recurrences;
};

class SearchQueryRepository {
 public:
  virtual ~SearchQueryRepository() = default;
  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<SearchQuerySnapshot> load_snapshot(
      const std::vector<domain::SearchTargetType>& requested_targets,
      const std::optional<std::array<
          std::int64_t, kSearchQueryContributingStores.size()>>&
          expected_generations = std::nullopt) = 0;
};

}  // namespace excellent_calendar::repository
