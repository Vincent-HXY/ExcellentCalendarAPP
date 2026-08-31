#include "excellent_calendar/storage/json/habit_state_validator.hpp"

#include <algorithm>
#include <set>
#include <string>

#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr std::string_view kHabitOccurrenceNamespace =
    "395bbed4-6e85-5ac1-b192-5699a5c963e8";
constexpr std::string_view kHabitReminderNamespace =
    "e1f91a58-4138-5984-b14d-6cd94e527890";

common::Error corrupted(std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored Habit data is invalid",
                            {{"reason", std::move(reason)}});
}

std::string json_name(std::initializer_list<std::string_view> values) {
  std::string result = "[";
  bool first = true;
  for (const auto value : values) {
    if (!first) result += ',';
    first = false;
    result += '"';
    result += value;
    result += '"';
  }
  result += ']';
  return result;
}

}  // namespace

common::Result<common::Unit> validate_habit_state(
    const repository::HabitState& state) {
  std::set<std::string> recurrence_ids;
  for (const auto& item : state.recurrences) {
    auto valid = domain::validate_habit_recurrence(item);
    if (!valid.ok()) return valid;
    if (!recurrence_ids.insert(item.id).second)
      return common::Result<common::Unit>::failure(corrupted("duplicate recurrence id"));
  }
  std::set<std::string> habit_ids;
  std::set<std::string> recurrence_owners;
  for (const auto& item : state.habits) {
    auto valid = domain::validate_habit(item);
    if (!valid.ok()) return valid;
    if (!habit_ids.insert(item.id).second ||
        !recurrence_owners.insert(item.recurrence_id).second)
      return common::Result<common::Unit>::failure(corrupted("duplicate Habit identity or recurrence owner"));
    const auto recurrence = std::find_if(
        state.recurrences.begin(), state.recurrences.end(),
        [&](const auto& current) { return current.id == item.recurrence_id; });
    if (recurrence == state.recurrences.end() ||
        (!item.deleted_at.has_value() && recurrence->deleted_at.has_value()))
      return common::Result<common::Unit>::failure(corrupted("Habit recurrence relationship is invalid"));
  }
  for (const auto& recurrence : state.recurrences) {
    if (recurrence.deleted_at.has_value()) continue;
    const auto owner_count = std::count_if(
        state.habits.begin(), state.habits.end(), [&](const auto& habit) {
          return !habit.deleted_at.has_value() &&
                 habit.recurrence_id == recurrence.id;
        });
    if (owner_count != 1) {
      return common::Result<common::Unit>::failure(
          corrupted("active Habit recurrence must have exactly one active owner"));
    }
  }
  std::set<std::string> check_in_ids;
  std::set<std::string> check_in_keys;
  for (const auto& item : state.check_ins) {
    auto valid = domain::validate_habit_check_in(item);
    if (!valid.ok()) return valid;
    const auto key = item.habit_id + "\n" + domain::format_local_date(item.check_date);
    if (!check_in_ids.insert(item.id).second || !check_in_keys.insert(key).second)
      return common::Result<common::Unit>::failure(corrupted("duplicate CheckIn identity"));
    const auto habit = std::find_if(state.habits.begin(), state.habits.end(),
                                    [&](const auto& current) { return current.id == item.habit_id; });
    if (habit == state.habits.end() || item.check_date < habit->start_date ||
        domain::habit_effective_end_date(*habit) < item.check_date)
      return common::Result<common::Unit>::failure(corrupted("CheckIn relationship is invalid"));
    const bool skipped = item.status == domain::kHabitCheckInSkipped;
    if (!habit->first_check_in_at.has_value() ||
        (skipped && (item.completed_count_hundredths.has_value() ||
                     item.target_count_snapshot_hundredths.has_value() ||
                     item.unit_snapshot.has_value())) ||
        (!skipped &&
         (item.target_count_snapshot_hundredths !=
              habit->target_count_hundredths ||
          item.unit_snapshot != habit->unit)))
      return common::Result<common::Unit>::failure(
          corrupted("CheckIn snapshot or has-ever relationship is invalid"));
  }
  std::set<std::string> template_ids;
  std::set<std::string> active_template_owners;
  for (const auto& item : state.reminder_templates) {
    auto valid = domain::validate_habit_reminder_template(item);
    if (!valid.ok()) return valid;
    if (!template_ids.insert(item.template_key).second ||
        (!item.deleted_at.has_value() && !active_template_owners.insert(item.habit_id).second))
      return common::Result<common::Unit>::failure(corrupted("duplicate Habit template identity"));
    const auto habit = std::find_if(state.habits.begin(), state.habits.end(),
                                    [&](const auto& current) { return current.id == item.habit_id; });
    if (habit == state.habits.end() ||
        (!item.deleted_at.has_value() && habit->deleted_at.has_value()))
      return common::Result<common::Unit>::failure(corrupted("Habit template relationship is invalid"));
  }
  std::set<std::string> reminder_keys;
  std::set<std::string> sent_days;
  for (const auto& item : state.reminders) {
    if (item.target_type != domain::kReminderTargetHabit) continue;
    if (!item.template_key.has_value() || !item.occurrence_key.has_value() ||
        !item.occurrence_date.has_value() || !item.local_time.has_value() ||
        item.timezone_mode != std::optional<std::string>("follow_device") ||
        item.methods != std::vector<std::string>{"popup"} ||
        item.recurrence_revision.has_value() || item.occurrence_start_at.has_value() ||
        item.advance_days.has_value() || item.advance_minutes.has_value() ||
        item.fulfillment_delivery_id.has_value())
      return common::Result<common::Unit>::failure(corrupted("Habit Reminder branch is invalid"));
    const auto habit = std::find_if(
        state.habits.begin(), state.habits.end(),
        [&](const auto& current) { return current.id == item.target_id; });
    const auto reminder_template = std::find_if(
        state.reminder_templates.begin(), state.reminder_templates.end(),
        [&](const auto& current) {
          return current.template_key == *item.template_key &&
                 current.habit_id == item.target_id;
        });
    auto occurrence_date = domain::parse_local_date(*item.occurrence_date);
    const bool open = domain::is_open_reminder(item);
    if (habit == state.habits.end() ||
        reminder_template == state.reminder_templates.end() ||
        !occurrence_date.ok() || occurrence_date.value() < habit->start_date ||
        habit->end_date < occurrence_date.value() ||
        item.local_time !=
            std::optional<std::string>(reminder_template->local_time) ||
        (open && (habit->deleted_at.has_value() || !habit->is_active ||
                  domain::habit_effective_end_date(*habit) <
                      occurrence_date.value() ||
                  reminder_template->deleted_at.has_value() ||
                  !reminder_template->is_enabled)))
      return common::Result<common::Unit>::failure(
          corrupted("Habit Reminder relationship is invalid"));
    const auto key = item.target_id + "\n" + *item.template_key + "\n" + *item.occurrence_date;
    if (!reminder_keys.insert(key).second)
      return common::Result<common::Unit>::failure(corrupted("duplicate Habit Reminder tuple"));
    auto occurrence = common::generate_uuid_v5(
        kHabitOccurrenceNamespace,
        json_name({item.target_id, *item.template_key, *item.occurrence_date}));
    auto reminder = common::generate_uuid_v5(
        kHabitReminderNamespace,
        json_name({"habit", item.target_id, *item.template_key, *item.occurrence_date}));
    if (!occurrence.ok() || !reminder.ok() || *item.occurrence_key != occurrence.value() ||
        item.id != reminder.value())
      return common::Result<common::Unit>::failure(corrupted("Habit Reminder UUIDv5 identity mismatch"));
    if (item.status == domain::kReminderStatusSent &&
        !sent_days.insert(item.target_id + "\n" + *item.occurrence_date).second)
      return common::Result<common::Unit>::failure(corrupted("duplicate Habit display day"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::storage::json
