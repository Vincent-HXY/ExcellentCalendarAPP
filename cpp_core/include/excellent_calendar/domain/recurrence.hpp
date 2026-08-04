#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/domain/event.hpp"

namespace excellent_calendar::domain {

inline constexpr std::string_view kRecurrenceDaily = "daily";
inline constexpr std::string_view kRecurrenceWeekly = "weekly";
inline constexpr std::string_view kRecurrenceMonthly = "monthly";
inline constexpr std::string_view kRecurrenceYearly = "yearly";
inline constexpr std::string_view kRecurrenceCustom = "custom";

struct EventRecurrenceRuleInput {
  std::string frequency;
  int interval = 1;
  std::optional<std::string> end_at;
  std::optional<int> count;
};

struct Recurrence {
  std::string id;
  int revision = 1;
  std::string frequency;
  int interval = 1;
  std::optional<std::string> start_at;
  std::optional<std::string> start_date;
  std::string timezone;
  std::optional<int> day_of_month;
  std::vector<int> days_of_week;
  std::optional<int> month_of_year;
  std::optional<std::string> end_at;
  std::optional<int> count;
  std::string created_at;
};

struct RecurringEventSchedule {
  std::string event_id;
  std::optional<std::string> start_at;
  std::optional<std::string> end_at;
  std::optional<std::string> start_date;
  std::optional<std::string> end_date;
  bool is_all_day = false;
  std::string timezone;
};

struct EventOccurrence {
  std::string event_id;
  int recurrence_revision = 1;
  std::string occurrence_key;
  std::optional<std::string> occurrence_start_at;
  std::optional<std::string> occurrence_end_at;
  std::optional<std::string> occurrence_start_date;
  std::optional<std::string> occurrence_end_date;
  std::string original_local_start;
  std::string timezone;
};

bool is_supported_recurrence_frequency(std::string_view value);
bool is_known_recurrence_frequency(std::string_view value);
RecurringEventSchedule recurring_schedule_from_event(const Event& event);

}  // namespace excellent_calendar::domain
