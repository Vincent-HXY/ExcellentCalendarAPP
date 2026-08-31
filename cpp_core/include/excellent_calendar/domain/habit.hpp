#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::domain {

inline constexpr std::int64_t kHabitMaxHundredths = 9007199254740991LL;
inline constexpr int kHabitMaxChallengeDays = 400;

inline constexpr std::string_view kHabitCheckInDone = "done";
inline constexpr std::string_view kHabitCheckInPartial = "partial";
inline constexpr std::string_view kHabitCheckInSkipped = "skipped";
inline constexpr std::string_view kHabitCheckInManual = "manual";
inline constexpr std::string_view kHabitCheckInNotificationAction =
    "notification_action";

struct HabitRecurrence {
  std::string id;
  std::string frequency = "daily";
  int interval = 1;
  std::string timezone_mode = "follow_device";
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

struct Habit {
  std::string id;
  std::string title;
  std::optional<std::string> description;
  std::optional<std::string> category_id;
  std::string recurrence_id;
  std::optional<std::int64_t> target_count_hundredths;
  std::optional<std::string> unit;
  LocalDate start_date;
  LocalDate end_date;
  std::optional<LocalDate> ended_date;
  bool is_active = true;
  std::optional<std::string> first_check_in_at;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

struct HabitCheckIn {
  std::string id;
  std::string habit_id;
  LocalDate check_date;
  std::string status;
  std::optional<std::int64_t> completed_count_hundredths;
  std::optional<std::int64_t> target_count_snapshot_hundredths;
  std::optional<std::string> unit_snapshot;
  std::optional<std::string> completed_at;
  std::optional<std::string> note;
  std::string source;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

struct HabitReminderTemplate {
  std::string template_key;
  std::string habit_id;
  std::string local_time;
  std::string timezone_mode = "follow_device";
  std::string method = "popup";
  bool is_enabled = true;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

enum class HabitLifecycle { upcoming, active, completed, ended_early, deleted };

std::string habit_lifecycle_to_string(HabitLifecycle value);
HabitLifecycle habit_lifecycle(const Habit& habit, const LocalDate& today);
LocalDate habit_effective_end_date(const Habit& habit);

common::Result<common::Unit> validate_habit_recurrence(
    const HabitRecurrence& recurrence);
common::Result<common::Unit> validate_habit(const Habit& habit);
common::Result<common::Unit> validate_habit_check_in(
    const HabitCheckIn& check_in);
common::Result<common::Unit> validate_habit_reminder_template(
    const HabitReminderTemplate& reminder_template);

}  // namespace excellent_calendar::domain
