#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::domain {

inline constexpr std::string_view kAnniversaryCalendarSolar = "solar";
inline constexpr std::string_view kAnniversaryCalendarLunar = "lunar";
inline constexpr std::string_view kAnniversaryRecurrenceYearly = "yearly";
inline constexpr std::string_view kAnniversaryCountdownRemaining = "remaining";
inline constexpr std::string_view kAnniversaryCountdownElapsed = "elapsed";
inline constexpr std::string_view kAnniversaryCountdownToday = "today";

struct Anniversary {
  std::string id;
  std::string title;
  LocalDate date;
  std::string calendar_type;
  std::optional<std::string> category_id;
  std::optional<std::string> recurrence_id;
  std::optional<std::string> note;
  std::optional<std::string> importance;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

struct AnniversaryRecurrence {
  std::string id;
  std::string frequency;
  int interval = 1;
  std::string created_at;
  std::optional<std::string> deleted_at;
};

struct AnniversaryCountdown {
  std::string relation;
  int days = 0;
  LocalDate target_occurrence_date;
  int iso_weekday = 1;
  std::string timezone;
  std::string calculated_at;
};

common::Result<common::Unit> validate_anniversary_input(
    std::string_view title,
    const LocalDate& date,
    std::string_view calendar_type,
    const std::optional<std::string>& category_id,
    const std::optional<std::string>& importance);

common::Result<common::Unit> validate_anniversary(const Anniversary& anniversary);

common::Result<common::Unit> validate_anniversary_recurrence(
    const AnniversaryRecurrence& recurrence);

common::Result<AnniversaryCountdown> calculate_anniversary_countdown(
    const LocalDate& anniversary_date,
    bool repeats_yearly,
    const LocalDate& today,
    std::string timezone,
    std::string calculated_at);

}  // namespace excellent_calendar::domain
