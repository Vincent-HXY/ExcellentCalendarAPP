#include "excellent_calendar/domain/habit.hpp"

#include <algorithm>
#include <cstdint>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/category.hpp"

namespace excellent_calendar::domain {
namespace {

common::Error corrupted(std::string field, std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored Habit data is invalid",
                            {{"field", std::move(field)},
                             {"reason", std::move(reason)}});
}

bool valid_optional_timestamp(const std::optional<std::string>& value) {
  return !value.has_value() || common::is_iso8601_utc_datetime(*value);
}

common::Result<common::Unit> text_limit(std::string_view value,
                                        std::size_t maximum,
                                        std::string field) {
  auto count = utf8_code_point_count(value);
  if (!count.has_value()) {
    return common::Result<common::Unit>::failure(
        corrupted(std::move(field), "UTF-8 is invalid"));
  }
  if (*count > maximum) {
    return common::Result<common::Unit>::failure(
        corrupted(std::move(field), "Unicode code-point limit exceeded"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

std::string habit_lifecycle_to_string(HabitLifecycle value) {
  switch (value) {
    case HabitLifecycle::upcoming:
      return "upcoming";
    case HabitLifecycle::active:
      return "active";
    case HabitLifecycle::completed:
      return "completed";
    case HabitLifecycle::ended_early:
      return "ended_early";
    case HabitLifecycle::deleted:
      return "deleted";
  }
  return "deleted";
}

HabitLifecycle habit_lifecycle(const Habit& habit, const LocalDate& today) {
  if (habit.deleted_at.has_value()) return HabitLifecycle::deleted;
  if (!habit.is_active) return HabitLifecycle::ended_early;
  if (today < habit.start_date) return HabitLifecycle::upcoming;
  if (habit.end_date < today) return HabitLifecycle::completed;
  return HabitLifecycle::active;
}

LocalDate habit_effective_end_date(const Habit& habit) {
  return habit.ended_date.value_or(habit.end_date);
}

common::Result<common::Unit> validate_habit_recurrence(
    const HabitRecurrence& recurrence) {
  if (!common::is_canonical_uuid_v4(recurrence.id) ||
      recurrence.frequency != "daily" ||
      recurrence.interval != 1 || recurrence.timezone_mode != "follow_device" ||
      !common::is_iso8601_utc_datetime(recurrence.created_at) ||
      !common::is_iso8601_utc_datetime(recurrence.updated_at) ||
      !valid_optional_timestamp(recurrence.deleted_at)) {
    return common::Result<common::Unit>::failure(
        corrupted("habit_recurrence", "record does not satisfy V1 invariants"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_habit(const Habit& habit) {
  if (!common::is_canonical_uuid_v4(habit.id) ||
      !common::is_canonical_uuid_v4(habit.recurrence_id)) {
    return common::Result<common::Unit>::failure(
        corrupted("habit.id", "identity must be UUID"));
  }
  const auto trimmed = trim_unicode_whitespace(habit.title);
  if (!trimmed.has_value() || trimmed->empty()) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_TITLE_EMPTY", "Habit title cannot be empty"));
  }
  auto title = text_limit(habit.title, 80, "habit.title");
  if (!title.ok()) return title;
  if (habit.description.has_value()) {
    auto description = text_limit(*habit.description, 2000, "habit.description");
    if (!description.ok()) return description;
  }
  if (habit.unit.has_value()) {
    auto unit = text_limit(*habit.unit, 32, "habit.unit");
    if (!unit.ok()) return unit;
  }
  const bool has_target = habit.target_count_hundredths.has_value();
  if (has_target != habit.unit.has_value() ||
      (has_target && (*habit.target_count_hundredths < 1 ||
                      *habit.target_count_hundredths > kHabitMaxHundredths))) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_TARGET_INVALID",
                           "Habit target count and unit are invalid"));
  }
  const int days = local_days_between(habit.start_date, habit.end_date) + 1;
  if (!is_valid_local_date(habit.start_date) ||
      !is_valid_local_date(habit.end_date) || days <= 0) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_DATE_RANGE_INVALID",
                           "Habit challenge dates or requested end date are invalid"));
  }
  if (days > kHabitMaxChallengeDays) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_CHALLENGE_TOO_LONG",
                           "Habit challenge exceeds 400 inclusive natural days"));
  }
  if ((!habit.is_active && !habit.deleted_at.has_value() &&
       !habit.ended_date.has_value()) ||
      (habit.ended_date.has_value() &&
       (*habit.ended_date < habit.start_date || habit.end_date < *habit.ended_date)) ||
      !common::is_iso8601_utc_datetime(habit.created_at) ||
      !common::is_iso8601_utc_datetime(habit.updated_at) ||
      !valid_optional_timestamp(habit.first_check_in_at) ||
      !valid_optional_timestamp(habit.deleted_at)) {
    return common::Result<common::Unit>::failure(
        corrupted("habit", "record does not satisfy lifecycle or audit invariants"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_habit_check_in(
    const HabitCheckIn& check_in) {
  if (!common::is_canonical_uuid_v4(check_in.id) ||
      !common::is_canonical_uuid_v4(check_in.habit_id) ||
      !is_valid_local_date(check_in.check_date) ||
      (check_in.status != kHabitCheckInDone &&
       check_in.status != kHabitCheckInPartial &&
       check_in.status != kHabitCheckInSkipped) ||
      (check_in.source != kHabitCheckInManual &&
       check_in.source != kHabitCheckInNotificationAction) ||
      !common::is_iso8601_utc_datetime(check_in.created_at) ||
      !common::is_iso8601_utc_datetime(check_in.updated_at) ||
      !valid_optional_timestamp(check_in.completed_at) ||
      !valid_optional_timestamp(check_in.deleted_at)) {
    return common::Result<common::Unit>::failure(
        corrupted("habit_check_in", "record shape is invalid"));
  }
  if (check_in.note.has_value()) {
    auto note = text_limit(*check_in.note, 500, "habit_check_in.note");
    if (!note.ok()) return note;
  }
  if (check_in.unit_snapshot.has_value()) {
    auto unit = text_limit(*check_in.unit_snapshot, 32,
                           "habit_check_in.unit_snapshot");
    if (!unit.ok()) return unit;
  }
  const auto in_range = [](const std::optional<std::int64_t>& value) {
    return !value.has_value() || (*value >= 1 && *value <= kHabitMaxHundredths);
  };
  if (!in_range(check_in.completed_count_hundredths) ||
      !in_range(check_in.target_count_snapshot_hundredths)) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_TARGET_INVALID",
                           "Habit target count and unit are invalid"));
  }
  if (check_in.status == kHabitCheckInSkipped) {
    if (check_in.completed_count_hundredths.has_value() ||
        check_in.target_count_snapshot_hundredths.has_value() ||
        check_in.unit_snapshot.has_value() || check_in.completed_at.has_value()) {
      return common::Result<common::Unit>::failure(
          corrupted("habit_check_in", "skipped CheckIn contains completion data"));
    }
  } else if (check_in.completed_count_hundredths.has_value() !=
                 check_in.target_count_snapshot_hundredths.has_value() ||
             check_in.target_count_snapshot_hundredths.has_value() !=
                 check_in.unit_snapshot.has_value() ||
             !check_in.completed_at.has_value()) {
    return common::Result<common::Unit>::failure(
        corrupted("habit_check_in", "completion snapshots are inconsistent"));
  }
  if (check_in.status == kHabitCheckInPartial &&
      (!check_in.completed_count_hundredths.has_value() ||
       *check_in.completed_count_hundredths >=
           *check_in.target_count_snapshot_hundredths)) {
    return common::Result<common::Unit>::failure(
        corrupted("habit_check_in.status", "partial amount is not below target"));
  }
  if (check_in.status == kHabitCheckInDone &&
      check_in.completed_count_hundredths.has_value() &&
      *check_in.completed_count_hundredths <
          *check_in.target_count_snapshot_hundredths) {
    return common::Result<common::Unit>::failure(
        corrupted("habit_check_in.status", "done amount is below target"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_habit_reminder_template(
    const HabitReminderTemplate& reminder_template) {
  const auto& time = reminder_template.local_time;
  const bool valid_time = time.size() == 5U && time[2] == ':' &&
                          time[0] >= '0' && time[0] <= '2' &&
                          time[1] >= '0' && time[1] <= '9' &&
                          time[3] >= '0' && time[3] <= '5' &&
                          time[4] >= '0' && time[4] <= '9' &&
                          ((time[0] - '0') * 10 + (time[1] - '0')) <= 23;
  if (!common::is_canonical_uuid_v4(reminder_template.template_key) ||
      !common::is_canonical_uuid_v4(reminder_template.habit_id) ||
      !valid_time ||
      reminder_template.timezone_mode != "follow_device" ||
      reminder_template.method != "popup" ||
      !common::is_iso8601_utc_datetime(reminder_template.created_at) ||
      !common::is_iso8601_utc_datetime(reminder_template.updated_at) ||
      !valid_optional_timestamp(reminder_template.deleted_at)) {
    return common::Result<common::Unit>::failure(
        common::make_error("HABIT_REMINDER_CONFIG_INVALID",
                           "Habit reminder configuration is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::domain
