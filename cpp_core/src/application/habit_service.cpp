#include "excellent_calendar/application/habit_service.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <set>
#include <string>
#include <tuple>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/category.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::application {
namespace {

constexpr std::string_view kHabitOccurrenceNamespace =
    "395bbed4-6e85-5ac1-b192-5699a5c963e8";
constexpr std::string_view kHabitReminderNamespace =
    "e1f91a58-4138-5984-b14d-6cd94e527890";
constexpr std::string_view kHabitActionNamespace =
    "23e50bd1-fbd4-5338-b842-7547a97091cf";

bool less_equal(const domain::LocalDate& left, const domain::LocalDate& right) {
  return left < right || left == right;
}

common::Error not_found(std::string id) {
  return common::make_error("HABIT_NOT_FOUND", "Habit not found",
                            {{"id", std::move(id)}});
}

common::Error deleted() {
  return common::make_error("HABIT_TARGET_DELETED", "Habit target is deleted");
}

common::Error ended() {
  return common::make_error("HABIT_ALREADY_ENDED",
                            "Habit is ended and its history is read-only");
}

common::Result<common::Unit> request_text(
    std::string_view value, std::size_t maximum, std::string field,
    bool require_non_blank) {
  const auto count = domain::utf8_code_point_count(value);
  const auto trimmed = domain::trim_unicode_whitespace(value);
  if (!count.has_value() || !trimmed.has_value() || *count > maximum) {
    return common::Result<common::Unit>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", std::move(field)},
         {"reason", "text is invalid or exceeds the Unicode code-point limit"}}));
  }
  if (require_non_blank && trimmed->empty()) {
    return common::Result<common::Unit>::failure(common::make_error(
        "HABIT_TITLE_EMPTY", "Habit title cannot be empty"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_write_text(
    std::string_view title, const std::optional<std::string>& description,
    const std::optional<std::string>& unit) {
  auto title_valid = request_text(title, 80, "title", true);
  if (!title_valid.ok()) return title_valid;
  if (description.has_value()) {
    auto valid = request_text(*description, 2000, "description", false);
    if (!valid.ok()) return valid;
  }
  if (unit.has_value()) {
    auto valid = request_text(*unit, 32, "unit", true);
    if (!valid.ok()) return valid;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_reminder_plan(
    const HabitReminderPlan& plan) {
  bool local_time_valid = false;
  if (plan.local_time.has_value() && plan.local_time->size() == 5U &&
      (*plan.local_time)[2] == ':') {
    const auto& value = *plan.local_time;
    const bool digits = value[0] >= '0' && value[0] <= '9' &&
                        value[1] >= '0' && value[1] <= '9' &&
                        value[3] >= '0' && value[3] <= '9' &&
                        value[4] >= '0' && value[4] <= '9';
    if (digits) {
      const int hour = (value[0] - '0') * 10 + value[1] - '0';
      const int minute = (value[3] - '0') * 10 + value[4] - '0';
      local_time_valid = hour <= 23 && minute <= 59;
    }
  }
  if (plan.timezone_mode != "follow_device" || plan.method != "popup" ||
      (plan.is_enabled && !local_time_valid) ||
      (!plan.is_enabled && plan.local_time.has_value())) {
    return common::Result<common::Unit>::failure(common::make_error(
        "HABIT_REMINDER_CONFIG_INVALID",
        "Habit reminder configuration is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Error conflict() {
  return common::make_error("HABIT_UPDATE_CONFLICT",
                            "Habit changed after the caller loaded it");
}

common::Error internal(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
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

common::Result<std::string> habit_occurrence_id(std::string_view habit_id,
                                                std::string_view template_key,
                                                const domain::LocalDate& date) {
  const auto text = domain::format_local_date(date);
  return common::generate_uuid_v5(
      kHabitOccurrenceNamespace, json_name({habit_id, template_key, text}));
}

common::Result<std::string> habit_reminder_id(std::string_view habit_id,
                                              std::string_view template_key,
                                              const domain::LocalDate& date) {
  const auto text = domain::format_local_date(date);
  return common::generate_uuid_v5(
      kHabitReminderNamespace,
      json_name({"habit", habit_id, template_key, text}));
}

common::Result<std::string> habit_action_id(std::string_view habit_id,
                                            const domain::LocalDate& date,
                                            std::string_view occurrence_key) {
  const auto text = domain::format_local_date(date);
  return common::generate_uuid_v5(
      kHabitActionNamespace,
      json_name({"habit_complete", habit_id, text, occurrence_key}));
}

domain::Habit* find_habit(repository::HabitState& state, std::string_view id) {
  const auto found = std::find_if(state.habits.begin(), state.habits.end(),
                                  [&](const auto& item) { return item.id == id; });
  return found == state.habits.end() ? nullptr : &*found;
}

const domain::Habit* find_habit(const repository::HabitState& state,
                                std::string_view id) {
  const auto found = std::find_if(state.habits.begin(), state.habits.end(),
                                  [&](const auto& item) { return item.id == id; });
  return found == state.habits.end() ? nullptr : &*found;
}

domain::HabitCheckIn* find_check_in(repository::HabitState& state,
                                    std::string_view habit_id,
                                    const domain::LocalDate& date) {
  const auto found = std::find_if(
      state.check_ins.begin(), state.check_ins.end(), [&](const auto& item) {
        return item.habit_id == habit_id && item.check_date == date;
      });
  return found == state.check_ins.end() ? nullptr : &*found;
}

const domain::HabitCheckIn* find_active_check_in(
    const repository::HabitState& state, std::string_view habit_id,
    const domain::LocalDate& date) {
  const auto found = std::find_if(
      state.check_ins.begin(), state.check_ins.end(), [&](const auto& item) {
        return item.habit_id == habit_id && item.check_date == date &&
               !item.deleted_at.has_value();
      });
  return found == state.check_ins.end() ? nullptr : &*found;
}

domain::HabitReminderTemplate* active_template(repository::HabitState& state,
                                                std::string_view habit_id) {
  const auto found = std::find_if(
      state.reminder_templates.begin(), state.reminder_templates.end(),
      [&](const auto& item) {
        return item.habit_id == habit_id && !item.deleted_at.has_value();
      });
  return found == state.reminder_templates.end() ? nullptr : &*found;
}

const domain::HabitReminderTemplate* active_template(
    const repository::HabitState& state, std::string_view habit_id) {
  const auto found = std::find_if(
      state.reminder_templates.begin(), state.reminder_templates.end(),
      [&](const auto& item) {
        return item.habit_id == habit_id && !item.deleted_at.has_value();
      });
  return found == state.reminder_templates.end() ? nullptr : &*found;
}

bool is_open(const domain::Reminder& reminder) {
  return domain::is_open_reminder(reminder);
}

bool has_display_reservation(const repository::HabitState& state,
                             std::string_view habit_id,
                             const domain::LocalDate& date) {
  const auto date_text = domain::format_local_date(date);
  for (const auto& reminder : state.reminders) {
    if (reminder.target_type == domain::kReminderTargetHabit &&
        reminder.target_id == habit_id &&
        reminder.occurrence_date == date_text &&
        reminder.status == domain::kReminderStatusSent) {
      return true;
    }
    if (reminder.target_type != domain::kReminderTargetHabit ||
        reminder.target_id != habit_id || reminder.occurrence_date != date_text)
      continue;
    const auto prepared = std::find_if(
        state.notifications.begin(), state.notifications.end(),
        [&](const auto& notification) {
          return notification.reminder_id == reminder.id &&
                 notification.status == domain::kNotificationStatusPrepared;
        });
    if (prepared != state.notifications.end()) return true;
  }
  return false;
}

bool has_template_change_reservation(const repository::HabitState& state,
                                     std::string_view habit_id,
                                     const domain::LocalDate& date) {
  if (has_display_reservation(state, habit_id, date)) return true;
  const auto date_text = domain::format_local_date(date);
  for (const auto& reminder : state.reminders) {
    if (reminder.target_type != domain::kReminderTargetHabit ||
        reminder.target_id != habit_id || reminder.occurrence_date != date_text ||
        (reminder.cancellation_reason !=
             std::optional<std::string>(
                 domain::kReminderCancellationReasonHabitTemplateDisabled) &&
         reminder.cancellation_reason !=
             std::optional<std::string>(
                 domain::kReminderCancellationReasonHabitTemplateReplaced)))
      continue;
    if (std::any_of(state.notifications.begin(), state.notifications.end(),
                    [&](const auto& notification) {
                      return notification.reminder_id == reminder.id &&
                             notification.status ==
                                 domain::kNotificationStatusAbandoned &&
                             notification.abandon_reason ==
                                 std::optional<std::string>(
                                     "habit_reminder_cancelled");
                    }))
      return true;
  }
  return false;
}

std::string next_timestamp(std::string_view previous, std::string now) {
  const auto previous_epoch = common::parse_iso8601_utc_epoch_seconds(previous);
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (previous_epoch.has_value() && now_epoch.has_value() &&
      *now_epoch <= *previous_epoch) {
    return common::format_epoch_seconds_utc_iso8601(*previous_epoch + 1);
  }
  return now;
}

common::Result<common::Unit> cancel_open_reminders(
    repository::HabitState& state, std::string_view habit_id,
    std::optional<domain::LocalDate> date, std::string reason,
    const std::string& now) {
  for (auto& reminder : state.reminders) {
    if (reminder.target_type != domain::kReminderTargetHabit ||
        reminder.target_id != habit_id || !is_open(reminder) ||
        (date.has_value() &&
         reminder.occurrence_date != domain::format_local_date(*date))) {
      continue;
    }
    reminder.status = std::string(domain::kReminderStatusCancelled);
    reminder.is_enabled = false;
    reminder.scheduled_at = std::nullopt;
    reminder.cancellation_reason = reason;
    reminder.last_cancelled_at = now;
    reminder.updated_at = next_timestamp(reminder.updated_at, now);
  }
  for (auto& notification : state.notifications) {
    if (notification.target_type != domain::kReminderTargetHabit ||
        notification.target_id != habit_id ||
        notification.status != domain::kNotificationStatusPrepared)
      continue;
    if (date.has_value()) {
      const auto reminder = std::find_if(
          state.reminders.begin(), state.reminders.end(),
          [&](const auto& item) {
            return notification.reminder_id == item.id &&
                   item.occurrence_date == domain::format_local_date(*date);
          });
      if (reminder == state.reminders.end()) continue;
    }
    notification.status = std::string(domain::kNotificationStatusAbandoned);
    notification.abandon_reason = "habit_reminder_cancelled";
    notification.finalized_at = now;
    notification.sent_at = std::nullopt;
    notification.recovery_batch_id = std::nullopt;
    notification.resolved_by_recovery_batch_id = std::nullopt;
    notification.updated_at = next_timestamp(notification.updated_at, now);
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<bool> cancel_open_reminders_except(
    repository::HabitState& state, std::string_view habit_id,
    std::string_view template_key, const domain::LocalDate& occurrence_date,
    std::string reason, const std::string& now) {
  const auto occurrence_text = domain::format_local_date(occurrence_date);
  std::set<std::string> cancelled_ids;
  for (auto& reminder : state.reminders) {
    if (reminder.target_type != domain::kReminderTargetHabit ||
        reminder.target_id != habit_id || !is_open(reminder) ||
        (reminder.template_key == template_key &&
         reminder.occurrence_date == occurrence_text)) {
      continue;
    }
    cancelled_ids.insert(reminder.id);
    reminder.status = std::string(domain::kReminderStatusCancelled);
    reminder.is_enabled = false;
    reminder.scheduled_at = std::nullopt;
    reminder.cancellation_reason = reason;
    reminder.last_cancelled_at = now;
    reminder.updated_at = next_timestamp(reminder.updated_at, now);
  }
  for (auto& notification : state.notifications) {
    if (!notification.reminder_id.has_value() ||
        cancelled_ids.count(*notification.reminder_id) == 0U ||
        notification.status != domain::kNotificationStatusPrepared) {
      continue;
    }
    notification.status = std::string(domain::kNotificationStatusAbandoned);
    notification.abandon_reason = "habit_reminder_cancelled";
    notification.finalized_at = now;
    notification.sent_at = std::nullopt;
    notification.recovery_batch_id = std::nullopt;
    notification.resolved_by_recovery_batch_id = std::nullopt;
    notification.updated_at = next_timestamp(notification.updated_at, now);
  }
  return common::Result<bool>::success(!cancelled_ids.empty());
}

common::Result<domain::Reminder> make_reminder(
    const domain::Habit& habit,
    const domain::HabitReminderTemplate& reminder_template,
    const domain::LocalDate& date, std::string_view timezone,
    const std::string& now, const domain::LocalTimeResolver& resolver) {
  auto occurrence = habit_occurrence_id(habit.id, reminder_template.template_key, date);
  auto id = habit_reminder_id(habit.id, reminder_template.template_key, date);
  if (!occurrence.ok()) return common::Result<domain::Reminder>::failure(occurrence.error());
  if (!id.ok()) return common::Result<domain::Reminder>::failure(id.error());
  const int hour = (reminder_template.local_time[0] - '0') * 10 +
                   reminder_template.local_time[1] - '0';
  const int minute = (reminder_template.local_time[3] - '0') * 10 +
                     reminder_template.local_time[4] - '0';
  auto resolved = resolver.resolve_local_datetime(
      domain::LocalDateTime{date.year, date.month, date.day, hour, minute, 0},
      timezone);
  if (!resolved.ok()) return common::Result<domain::Reminder>::failure(resolved.error());
  auto remind_at = resolved.value().utc_instant;
  const auto remind_epoch = common::parse_iso8601_utc_epoch_seconds(remind_at);
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (remind_epoch.has_value() && now_epoch.has_value() &&
      *remind_epoch < *now_epoch) {
    remind_at = now;
  }
  domain::Reminder reminder;
  reminder.id = id.value();
  reminder.target_type = std::string(domain::kReminderTargetHabit);
  reminder.target_id = habit.id;
  reminder.occurrence_key = occurrence.value();
  reminder.remind_at = remind_at;
  reminder.methods = {std::string(domain::kReminderMethodPopup)};
  reminder.message = habit.target_count_hundredths.has_value()
                         ? std::optional<std::string>(habit.title + "：完成今日目标")
                         : std::optional<std::string>(habit.title + "：点击完成今天的挑战");
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.source = "auto";
  reminder.created_at = now;
  reminder.updated_at = now;
  reminder.template_key = reminder_template.template_key;
  reminder.occurrence_date = domain::format_local_date(date);
  reminder.local_time = reminder_template.local_time;
  reminder.timezone_mode = "follow_device";
  return common::Result<domain::Reminder>::success(std::move(reminder));
}

common::Result<bool> materialize_reminder(
    repository::HabitState& state, const domain::Habit& habit,
    const domain::HabitReminderTemplate& reminder_template,
    const domain::LocalDate& date, std::string_view timezone,
    const std::string& now, const domain::LocalTimeResolver& resolver) {
  const auto* check_in = find_active_check_in(state, habit.id, date);
  if (!reminder_template.is_enabled || date < habit.start_date ||
      habit.end_date < date ||
      (check_in != nullptr &&
       (check_in->status == domain::kHabitCheckInDone ||
        check_in->status == domain::kHabitCheckInSkipped)) ||
      has_display_reservation(state, habit.id, date)) {
    return common::Result<bool>::success(false);
  }
  auto built = make_reminder(habit, reminder_template, date, timezone, now, resolver);
  if (!built.ok()) return common::Result<bool>::failure(built.error());
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& item) {
                                    return item.id == built.value().id;
                                  });
  if (found == state.reminders.end()) {
    state.reminders.push_back(std::move(built.value()));
    return common::Result<bool>::success(true);
  }
  if (is_open(*found)) return common::Result<bool>::success(false);
  const bool clear_reactivatable =
      found->status == domain::kReminderStatusCancelled &&
      (found->cancellation_reason ==
           std::optional<std::string>(
               domain::kReminderCancellationReasonHabitCompleted) ||
       found->cancellation_reason ==
           std::optional<std::string>(
               domain::kReminderCancellationReasonHabitSkipped));
  if (!clear_reactivatable)
    return common::Result<bool>::success(false);
  found->is_enabled = true;
  found->status = std::string(domain::kReminderStatusPending);
  found->scheduled_at = std::nullopt;
  found->failure_reason = std::nullopt;
  found->cancellation_reason = std::nullopt;
  found->last_cancelled_at = std::nullopt;
  found->expiration_reason = std::nullopt;
  found->expired_at = std::nullopt;
  found->remind_at = built.value().remind_at;
  found->message = built.value().message;
  found->reactivated_at = now;
  ++found->reactivation_count;
  found->updated_at = next_timestamp(found->updated_at, now);
  return common::Result<bool>::success(true);
}

HabitDailyStatus project_day(const repository::HabitState& state,
                             const domain::Habit& habit,
                             const domain::LocalDate& date,
                             const domain::LocalDate& today) {
  HabitDailyStatus result;
  result.date = date;
  if (today < date) {
    result.status = "upcoming";
    return result;
  }
  const auto* check_in = find_active_check_in(state, habit.id, date);
  if (check_in == nullptr) {
    result.status = date < today ? "missed" : "absent";
    result.is_final = date < today;
    return result;
  }
  result.status = check_in->status;
  result.check_in = *check_in;
  if (check_in->status == domain::kHabitCheckInSkipped) {
    result.is_final = true;
  } else if (check_in->status == domain::kHabitCheckInDone) {
    result.is_final = true;
    result.completion_ratio = 1.0;
  } else {
    result.is_final = date < today;
    result.completion_ratio =
        static_cast<double>(*check_in->completed_count_hundredths) /
        static_cast<double>(*check_in->target_count_snapshot_hundredths);
  }
  return result;
}

common::Result<HabitStatistics> statistics(
    const repository::HabitState& state, const domain::Habit& habit,
    const domain::LocalDate& today) {
  HabitStatistics result;
  result.as_of_date = today;
  const auto effective_end = domain::habit_effective_end_date(habit);
  if (today < habit.start_date) {
    if (habit.target_count_hundredths.has_value()) {
      result.quantity_progress_rate_7_days = 0.0;
      result.quantity_progress_rate_30_days = 0.0;
      result.quantity_progress_rate_all = 0.0;
      result.total_completed_count_hundredths = 0;
      result.average_completed_count_per_eligible_day_hundredths = 0;
    }
    return common::Result<HabitStatistics>::success(result);
  }
  auto settled_end = std::min(effective_end, domain::add_local_days(today, -1));
  if (less_equal(habit.start_date, today) && less_equal(today, effective_end)) {
    const auto* check = find_active_check_in(state, habit.id, today);
    if (check != nullptr && (check->status == domain::kHabitCheckInDone ||
                             check->status == domain::kHabitCheckInSkipped)) {
      settled_end = today;
    }
  } else if (effective_end < today) {
    settled_end = effective_end;
  }
  std::vector<HabitDailyStatus> days;
  if (less_equal(habit.start_date, settled_end)) {
    for (auto date = habit.start_date; less_equal(date, settled_end);
         date = domain::add_local_days(date, 1)) {
      days.push_back(project_day(state, habit, date, today));
    }
  }
  result.elapsed_eligible_days = static_cast<int>(days.size());
  std::int64_t total = 0;
  int current_run = 0;
  for (const auto& day : days) {
    if (day.status == "done") {
      ++result.done_days;
      ++current_run;
      result.longest_streak = std::max(result.longest_streak, current_run);
    } else if (day.status == "skipped") {
      ++result.skipped_days;
    } else {
      if (day.status == "partial") ++result.partial_days;
      if (day.status == "missed") ++result.missed_days;
      current_run = 0;
    }
    if (day.check_in.has_value() &&
        day.check_in->completed_count_hundredths.has_value()) {
      const auto amount = *day.check_in->completed_count_hundredths;
      if (total > domain::kHabitMaxHundredths - amount) {
        return common::Result<HabitStatistics>::failure(common::make_error(
            "HABIT_STATISTICS_OVERFLOW",
            "Habit quantity statistics exceed the exact cross-language fixed-point range"));
      }
      total += amount;
    }
  }
  current_run = 0;
  for (auto iterator = days.rbegin(); iterator != days.rend(); ++iterator) {
    if (iterator->status == "skipped") continue;
    if (iterator->status == "done") {
      ++current_run;
      continue;
    }
    break;
  }
  result.current_streak = current_run;

  const auto rates = [&](int window) {
    int denominator = 0;
    int done_count = 0;
    double quantity_sum = 0.0;
    const auto window_start = domain::add_local_days(today, -(window - 1));
    for (const auto& day : days) {
      if (day.date < window_start || day.status == "skipped") continue;
      ++denominator;
      if (day.status == "done") ++done_count;
      if (habit.target_count_hundredths.has_value() &&
          day.completion_ratio.has_value()) {
        quantity_sum += std::min(1.0, *day.completion_ratio);
      }
    }
    return std::tuple<double, double>{
        denominator == 0 ? 0.0
                         : static_cast<double>(done_count) / denominator,
        denominator == 0 ? 0.0 : quantity_sum / denominator};
  };
  const auto rate7 = rates(7);
  const auto rate30 = rates(30);
  int all_denominator = result.elapsed_eligible_days - result.skipped_days;
  result.completion_rate_7_days = std::get<0>(rate7);
  result.completion_rate_30_days = std::get<0>(rate30);
  result.completion_rate_all = all_denominator == 0
                                   ? 0.0
                                   : static_cast<double>(result.done_days) /
                                         all_denominator;
  if (habit.target_count_hundredths.has_value()) {
    double all_quantity = 0.0;
    for (const auto& day : days) {
      if (day.status != "skipped" && day.completion_ratio.has_value())
        all_quantity += std::min(1.0, *day.completion_ratio);
    }
    result.quantity_progress_rate_7_days = std::get<1>(rate7);
    result.quantity_progress_rate_30_days = std::get<1>(rate30);
    result.quantity_progress_rate_all =
        all_denominator == 0 ? 0.0 : all_quantity / all_denominator;
    result.total_completed_count_hundredths = total;
    if (all_denominator == 0) {
      result.average_completed_count_per_eligible_day_hundredths = 0;
    } else {
      auto average = total / all_denominator;
      const auto remainder = total % all_denominator;
      if (remainder * 2 >= all_denominator) ++average;
      result.average_completed_count_per_eligible_day_hundredths = average;
    }
  }
  return common::Result<HabitStatistics>::success(result);
}

HabitReminderSettings reminder_settings(const repository::HabitState& state,
                                         std::string_view habit_id) {
  HabitReminderSettings result;
  const auto* reminder_template = active_template(state, habit_id);
  if (reminder_template == nullptr) return result;
  result.is_enabled = reminder_template->is_enabled;
  result.reminder_template = *reminder_template;
  result.active_reminder_count = static_cast<int>(std::count_if(
      state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
        return reminder.target_type == domain::kReminderTargetHabit &&
               reminder.target_id == habit_id && is_open(reminder);
      }));
  result.schedule_reconciliation_required = result.active_reminder_count > 0;
  return result;
}

double time_progress(const domain::Habit& habit,
                     const domain::LocalDate& today) {
  const int total = domain::local_days_between(habit.start_date, habit.end_date) + 1;
  if (today < habit.start_date) return 0.0;
  const auto boundary = habit.ended_date.has_value()
                            ? *habit.ended_date
                            : habit.end_date < today ? habit.end_date : today;
  const int elapsed = domain::local_days_between(habit.start_date, boundary) + 1;
  return std::clamp(static_cast<double>(elapsed) / total, 0.0, 1.0);
}

int remaining_days(const domain::Habit& habit,
                   const domain::LocalDate& today) {
  const auto lifecycle = domain::habit_lifecycle(habit, today);
  if (lifecycle == domain::HabitLifecycle::completed ||
      lifecycle == domain::HabitLifecycle::ended_early)
    return 0;
  if (lifecycle == domain::HabitLifecycle::upcoming)
    return domain::local_days_between(habit.start_date, habit.end_date) + 1;
  return domain::local_days_between(today, habit.end_date) + 1;
}

common::Result<common::Unit> validate_operation_target(
    const domain::Habit& habit, const domain::LocalDate& today) {
  const auto lifecycle = domain::habit_lifecycle(habit, today);
  if (lifecycle == domain::HabitLifecycle::deleted)
    return common::Result<common::Unit>::failure(deleted());
  if (lifecycle == domain::HabitLifecycle::completed ||
      lifecycle == domain::HabitLifecycle::ended_early)
    return common::Result<common::Unit>::failure(ended());
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

HabitService::HabitService(
    std::shared_ptr<repository::HabitTransaction> transaction,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
    ClockFn clock, IdGeneratorFn id_generator)
    : transaction_(std::move(transaction)),
      local_time_resolver_(std::move(local_time_resolver)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::LocalDate> HabitService::today(
    std::string_view timezone, std::string_view now) const {
  auto valid = local_time_resolver_->validate_timezone(timezone);
  if (!valid.ok()) return common::Result<domain::LocalDate>::failure(valid.error());
  auto local = local_time_resolver_->to_local(now, timezone);
  if (!local.ok()) return common::Result<domain::LocalDate>::failure(local.error());
  return common::Result<domain::LocalDate>::success(
      domain::LocalDate{local.value().year, local.value().month,
                        local.value().day});
}

common::Result<HabitDetail> HabitService::project_detail(
    const repository::HabitState& state, const domain::Habit& habit,
    const domain::LocalDate& today_value, int history_page_size) const {
  const auto recurrence = std::find_if(
      state.recurrences.begin(), state.recurrences.end(),
      [&](const auto& item) { return item.id == habit.recurrence_id; });
  if (recurrence == state.recurrences.end())
    return common::Result<HabitDetail>::failure(internal("Habit recurrence is missing"));
  auto computed_statistics = statistics(state, habit, today_value);
  if (!computed_statistics.ok())
    return common::Result<HabitDetail>::failure(computed_statistics.error());
  HabitDetail result;
  result.habit = habit;
  result.recurrence = *recurrence;
  result.lifecycle_status =
      domain::habit_lifecycle_to_string(domain::habit_lifecycle(habit, today_value));
  result.statistics = computed_statistics.value();
  result.reminder_settings = reminder_settings(state, habit.id);
  if (less_equal(habit.start_date, today_value) &&
      less_equal(today_value, domain::habit_effective_end_date(habit))) {
    result.today = project_day(state, habit, today_value, today_value);
  }
  std::vector<HabitDailyStatus> history;
  auto history_end = std::min(domain::habit_effective_end_date(habit), today_value);
  if (less_equal(habit.start_date, history_end)) {
    for (auto date = history_end; less_equal(habit.start_date, date);
         date = domain::add_local_days(date, -1)) {
      history.push_back(project_day(state, habit, date, today_value));
      if (static_cast<int>(history.size()) >= history_page_size ||
          date == habit.start_date)
        break;
    }
  }
  result.history = std::move(history);
  if (!result.history.empty()) {
    result.history_start_date = result.history.back().date;
    result.history_end_date = result.history.front().date;
    result.has_earlier_history = habit.start_date < *result.history_start_date;
  }
  for (const auto& check_in : state.check_ins) {
    if (check_in.habit_id != habit.id) continue;
    result.has_ever_checked_in = true;
    if (!result.latest_check_in_date.has_value() ||
        *result.latest_check_in_date < check_in.check_date)
      result.latest_check_in_date = check_in.check_date;
  }
  result.challenge_time_progress = time_progress(habit, today_value);
  result.remaining_days = remaining_days(habit, today_value);
  return common::Result<HabitDetail>::success(std::move(result));
}

common::Result<HabitMutationCommit> HabitService::create(
    const CreateHabitCommand& command) {
  auto text_valid = validate_write_text(command.title, command.description,
                                        command.unit);
  if (!text_valid.ok())
    return common::Result<HabitMutationCommit>::failure(text_valid.error());
  auto reminder_valid = validate_reminder_plan(command.reminder);
  if (!reminder_valid.ok())
    return common::Result<HabitMutationCommit>::failure(reminder_valid.error());
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok())
    return common::Result<HabitMutationCommit>::failure(today_value.error());
  if (command.recurrence_frequency != "daily" ||
      command.recurrence_interval != 1 ||
      command.recurrence_timezone_mode != "follow_device") {
    return common::Result<HabitMutationCommit>::failure(
        common::make_error("CONTRACT_VALIDATION_FAILED",
                           "Request does not match contract schema",
                           {{"field", "CreateHabitRequest.recurrence"}}));
  }
  HabitMutationCommit output;
  auto committed = transaction_->execute("habit.create", [&](auto& state) {
    domain::HabitRecurrence recurrence;
    recurrence.id = id_generator_();
    recurrence.created_at = now;
    recurrence.updated_at = now;
    domain::Habit habit;
    habit.id = id_generator_();
    habit.title = domain::trim_unicode_whitespace(command.title)
                      .value_or(command.title);
    habit.description = command.description;
    habit.category_id = command.category_id;
    habit.recurrence_id = recurrence.id;
    habit.target_count_hundredths = command.target_count_hundredths;
    habit.unit = command.unit;
    habit.start_date = command.start_date;
    habit.end_date = command.end_date;
    habit.created_at = now;
    habit.updated_at = now;
    auto recurrence_valid = domain::validate_habit_recurrence(recurrence);
    if (!recurrence_valid.ok()) return recurrence_valid;
    auto habit_valid = domain::validate_habit(habit);
    if (!habit_valid.ok()) return habit_valid;
    state.recurrences.push_back(recurrence);
    state.habits.push_back(habit);
    if (command.reminder.is_enabled) {
      if (!command.reminder.local_time.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_REMINDER_CONFIG_INVALID",
            "Habit reminder configuration is invalid"));
      domain::HabitReminderTemplate reminder_template;
      reminder_template.template_key = id_generator_();
      reminder_template.habit_id = habit.id;
      reminder_template.local_time = *command.reminder.local_time;
      reminder_template.created_at = now;
      reminder_template.updated_at = now;
      auto template_valid =
          domain::validate_habit_reminder_template(reminder_template);
      if (!template_valid.ok()) return template_valid;
      state.reminder_templates.push_back(reminder_template);
      auto first_date = std::max(habit.start_date, today_value.value());
      auto materialized = materialize_reminder(
          state, state.habits.back(), state.reminder_templates.back(), first_date,
          command.timezone, now, *local_time_resolver_);
      if (!materialized.ok())
        return common::Result<common::Unit>::failure(materialized.error());
      output.schedule_reconciliation_required = materialized.value();
    }
    auto detail_result = project_detail(state, state.habits.back(),
                                        today_value.value(), 30);
    if (!detail_result.ok())
      return common::Result<common::Unit>::failure(detail_result.error());
    output.detail = std::move(detail_result.value());
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok()
             ? common::Result<HabitMutationCommit>::success(std::move(output))
             : common::Result<HabitMutationCommit>::failure(committed.error());
}

common::Result<HabitMutationCommit> HabitService::update(
    const UpdateHabitCommand& command) {
  auto text_valid = validate_write_text(command.title, command.description,
                                        command.unit);
  if (!text_valid.ok())
    return common::Result<HabitMutationCommit>::failure(text_valid.error());
  if (command.reminder.has_value()) {
    auto reminder_valid = validate_reminder_plan(*command.reminder);
    if (!reminder_valid.ok())
      return common::Result<HabitMutationCommit>::failure(
          reminder_valid.error());
  }
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok())
    return common::Result<HabitMutationCommit>::failure(today_value.error());
  HabitMutationCommit output;
  auto committed = transaction_->execute("habit.update", [&](auto& state) {
    auto* habit = find_habit(state, command.id);
    if (habit == nullptr)
      return common::Result<common::Unit>::failure(not_found(command.id));
    auto target_valid = validate_operation_target(*habit, today_value.value());
    if (!target_valid.ok()) return target_valid;
    if (habit->updated_at != command.expected_updated_at)
      return common::Result<common::Unit>::failure(conflict());
    if (habit->first_check_in_at.has_value()) {
      if (habit->target_count_hundredths != command.target_count_hundredths ||
          habit->unit != command.unit)
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_TARGET_LOCKED",
            "Habit target and unit are locked after the first check-in"));
      if (!(habit->start_date == command.start_date))
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_START_DATE_LOCKED",
            "Habit start date is locked after the first check-in"));
    }
    std::optional<domain::LocalDate> latest;
    for (const auto& check : state.check_ins) {
      if (check.habit_id == habit->id &&
          (!latest.has_value() || *latest < check.check_date))
        latest = check.check_date;
    }
    if (command.end_date < today_value.value() ||
        (latest.has_value() && command.end_date < *latest))
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_DATE_RANGE_INVALID",
          "Habit challenge dates or requested end date are invalid"));
    const bool date_range_changed =
        !(habit->start_date == command.start_date) ||
        !(habit->end_date == command.end_date);
    habit->title = domain::trim_unicode_whitespace(command.title)
                       .value_or(command.title);
    habit->description = command.description;
    habit->category_id = command.category_id;
    habit->target_count_hundredths = command.target_count_hundredths;
    habit->unit = command.unit;
    habit->start_date = command.start_date;
    habit->end_date = command.end_date;
    habit->updated_at = next_timestamp(habit->updated_at, now);
    auto valid = domain::validate_habit(*habit);
    if (!valid.ok()) return valid;
    std::optional<domain::LocalDate> projected_reminder_date;
    if (command.reminder.has_value()) {
      SetHabitReminderCommand nested{habit->id, habit->updated_at,
                                     *command.reminder, command.timezone};
      auto* current = active_template(state, habit->id);
      const bool reserved_before_template_change = has_template_change_reservation(
          state, habit->id, today_value.value());
      if (current != nullptr &&
          (!nested.reminder.is_enabled ||
           !current->is_enabled ||
           current->local_time != nested.reminder.local_time.value_or(""))) {
        auto cancelled = cancel_open_reminders(
            state, habit->id, std::nullopt,
            nested.reminder.is_enabled
                ? std::string(domain::kReminderCancellationReasonHabitTemplateReplaced)
                : std::string(domain::kReminderCancellationReasonHabitTemplateDisabled),
            now);
        if (!cancelled.ok()) return cancelled;
        if (nested.reminder.is_enabled) current->deleted_at = now;
        else {
          current->is_enabled = false;
          current->updated_at = next_timestamp(current->updated_at, now);
        }
      }
      if (nested.reminder.is_enabled &&
          (current == nullptr || current->deleted_at.has_value())) {
        if (!nested.reminder.local_time.has_value())
          return common::Result<common::Unit>::failure(common::make_error(
              "HABIT_REMINDER_CONFIG_INVALID",
              "Habit reminder configuration is invalid"));
        domain::HabitReminderTemplate created;
        created.template_key = id_generator_();
        created.habit_id = habit->id;
        created.local_time = *nested.reminder.local_time;
        created.created_at = now;
        created.updated_at = now;
        state.reminder_templates.push_back(created);
        current = &state.reminder_templates.back();
      }
      if (current != nullptr && current->is_enabled &&
          !current->deleted_at.has_value()) {
        auto start_date = std::max(habit->start_date, today_value.value());
        if (reserved_before_template_change ||
            has_display_reservation(state, habit->id, start_date))
          start_date = domain::add_local_days(start_date, 1);
        projected_reminder_date = start_date;
        auto materialized = materialize_reminder(
            state, *habit, *current, start_date, command.timezone, now,
            *local_time_resolver_);
        if (!materialized.ok())
          return common::Result<common::Unit>::failure(materialized.error());
        output.schedule_reconciliation_required = materialized.value();
      }
    }
    if (date_range_changed) {
      auto* current = active_template(state, habit->id);
      if (current != nullptr && current->is_enabled &&
          !current->deleted_at.has_value()) {
        const auto first_legal_date = projected_reminder_date.value_or(
            std::max(habit->start_date, today_value.value()));
        if (habit->end_date < first_legal_date) {
          auto cancelled = cancel_open_reminders(
              state, habit->id, std::nullopt,
              std::string(domain::kReminderCancellationReasonHabitCompleted),
              now);
          if (!cancelled.ok()) return cancelled;
          output.schedule_reconciliation_required = true;
        } else {
          auto cancelled = cancel_open_reminders_except(
              state, habit->id, current->template_key, first_legal_date,
              std::string(
                  domain::kReminderCancellationReasonHabitTemplateReplaced),
              now);
          if (!cancelled.ok())
            return common::Result<common::Unit>::failure(cancelled.error());
          auto materialized = materialize_reminder(
              state, *habit, *current, first_legal_date, command.timezone, now,
              *local_time_resolver_);
          if (!materialized.ok())
            return common::Result<common::Unit>::failure(materialized.error());
          output.schedule_reconciliation_required =
              output.schedule_reconciliation_required || cancelled.value() ||
              materialized.value();
        }
      }
    }
    auto detail_result = project_detail(state, *habit, today_value.value(), 30);
    if (!detail_result.ok())
      return common::Result<common::Unit>::failure(detail_result.error());
    output.detail = std::move(detail_result.value());
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok()
             ? common::Result<HabitMutationCommit>::success(std::move(output))
             : common::Result<HabitMutationCommit>::failure(committed.error());
}

common::Result<HabitDetail> HabitService::detail(std::string id,
                                                 std::string timezone,
                                                 int history_page_size) {
  const auto now = clock_();
  auto today_value = today(timezone, now);
  if (!today_value.ok()) return common::Result<HabitDetail>::failure(today_value.error());
  auto state = transaction_->load();
  if (!state.ok()) return common::Result<HabitDetail>::failure(state.error());
  const auto* habit = find_habit(state.value(), id);
  if (habit == nullptr)
    return common::Result<HabitDetail>::failure(not_found(std::move(id)));
  if (habit->deleted_at.has_value())
    return common::Result<HabitDetail>::failure(deleted());
  return project_detail(state.value(), *habit, today_value.value(), history_page_size);
}

common::Result<HabitListPage> HabitService::list(const ListHabitsQuery& query) {
  if (query.page < 1 || query.page > domain::kHabitMaxHundredths ||
      query.page_size < 1 || query.page_size > 100) {
    return common::Result<HabitListPage>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "ListHabitsRequest.pagination"}}));
  }
  const auto now = clock_();
  auto today_value = today(query.timezone, now);
  if (!today_value.ok()) return common::Result<HabitListPage>::failure(today_value.error());
  auto state = transaction_->load();
  if (!state.ok()) return common::Result<HabitListPage>::failure(state.error());
  HabitListPage result;
  result.page = query.page;
  result.page_size = query.page_size;
  result.today_progress.as_of_date = today_value.value();
  std::vector<HabitSummary> filtered;
  for (const auto& habit : state.value().habits) {
    if (habit.deleted_at.has_value()) continue;
    const auto lifecycle = domain::habit_lifecycle(habit, today_value.value());
    const auto lifecycle_text = domain::habit_lifecycle_to_string(lifecycle);
    if (lifecycle == domain::HabitLifecycle::active) {
      ++result.today_progress.active_count;
      const auto day = project_day(state.value(), habit, today_value.value(),
                                   today_value.value());
      if (day.status == "done") {
        ++result.today_progress.done_count;
        ++result.today_progress.eligible_count;
      } else if (day.status == "skipped") {
        ++result.today_progress.skipped_count;
      } else {
        ++result.today_progress.eligible_count;
        if (day.status == "partial") ++result.today_progress.partial_count;
        else ++result.today_progress.absent_count;
      }
    }
    if (!query.lifecycle_statuses.empty() &&
        std::find(query.lifecycle_statuses.begin(), query.lifecycle_statuses.end(),
                  lifecycle_text) == query.lifecycle_statuses.end())
      continue;
    if (!query.category_ids.empty() &&
        (!habit.category_id.has_value() ||
         std::find(query.category_ids.begin(), query.category_ids.end(),
                   *habit.category_id) == query.category_ids.end()))
      continue;
    auto detail_result = project_detail(state.value(), habit, today_value.value(), 1);
    if (!detail_result.ok())
      return common::Result<HabitListPage>::failure(detail_result.error());
    HabitSummary summary;
    summary.habit = detail_result.value().habit;
    summary.lifecycle_status = detail_result.value().lifecycle_status;
    summary.today = detail_result.value().today;
    summary.statistics = detail_result.value().statistics;
    summary.reminder_settings = detail_result.value().reminder_settings;
    summary.challenge_time_progress = detail_result.value().challenge_time_progress;
    summary.remaining_days = detail_result.value().remaining_days;
    filtered.push_back(std::move(summary));
  }
  const auto lifecycle_rank = [](std::string_view value) {
    if (value == "active") return 0;
    if (value == "upcoming") return 1;
    if (value == "completed") return 2;
    return 3;
  };
  const auto today_rank = [](const std::optional<HabitDailyStatus>& value) {
    if (!value.has_value() || value->status == "absent" || value->status == "partial") return 0;
    if (value->status == "skipped") return 1;
    return 2;
  };
  std::sort(filtered.begin(), filtered.end(), [&](const auto& left, const auto& right) {
    const auto left_time = left.reminder_settings.reminder_template.has_value()
                               ? left.reminder_settings.reminder_template->local_time
                               : "~";
    const auto right_time = right.reminder_settings.reminder_template.has_value()
                                ? right.reminder_settings.reminder_template->local_time
                                : "~";
    return std::tuple{lifecycle_rank(left.lifecycle_status), today_rank(left.today),
                      left_time, left.habit.created_at, left.habit.id} <
           std::tuple{lifecycle_rank(right.lifecycle_status), today_rank(right.today),
                      right_time, right.habit.created_at, right.habit.id};
  });
  result.total = static_cast<std::int64_t>(filtered.size());
  std::size_t offset = static_cast<std::size_t>(query.page - 1) *
                       static_cast<std::size_t>(query.page_size);
  if (query.cursor.has_value()) {
    const std::string prefix = "habit-list-r1:";
    if (query.cursor->rfind(prefix, 0) != 0)
      return common::Result<HabitListPage>::failure(common::make_error(
          "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
          {{"field", "ListHabitsRequest.pagination.cursor"}}));
    const auto last = query.cursor->substr(prefix.size());
    const auto found = std::find_if(filtered.begin(), filtered.end(),
                                    [&](const auto& item) { return item.habit.id == last; });
    if (found == filtered.end())
      return common::Result<HabitListPage>::failure(common::make_error(
          "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
          {{"field", "ListHabitsRequest.pagination.cursor"}}));
    offset = static_cast<std::size_t>(std::distance(filtered.begin(), found)) + 1U;
  }
  const auto end = std::min(filtered.size(), offset + static_cast<std::size_t>(query.page_size));
  if (offset < filtered.size())
    result.items.assign(filtered.begin() + static_cast<std::ptrdiff_t>(offset),
                        filtered.begin() + static_cast<std::ptrdiff_t>(end));
  result.has_more = end < filtered.size();
  if (result.has_more && !result.items.empty())
    result.next_cursor = "habit-list-r1:" + result.items.back().habit.id;
  return common::Result<HabitListPage>::success(std::move(result));
}

common::Result<HabitMutationCommit> HabitService::end(
    const HabitIdentityCommand& command) {
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok()) return common::Result<HabitMutationCommit>::failure(today_value.error());
  HabitMutationCommit output;
  auto committed = transaction_->execute("habit.end", [&](auto& state) {
    auto* habit = find_habit(state, command.id);
    if (habit == nullptr) return common::Result<common::Unit>::failure(not_found(command.id));
    if (habit->deleted_at.has_value()) return common::Result<common::Unit>::failure(deleted());
    const auto lifecycle = domain::habit_lifecycle(*habit, today_value.value());
    if (lifecycle == domain::HabitLifecycle::upcoming)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_NOT_STARTED", "Habit cannot be ended before its first challenge date"));
    if (lifecycle != domain::HabitLifecycle::active)
      return common::Result<common::Unit>::failure(ended());
    if (today_value.value() == habit->end_date)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_END_NOT_EARLY",
          "Habit cannot be ended early on its natural final challenge date"));
    if (habit->updated_at != command.expected_updated_at)
      return common::Result<common::Unit>::failure(conflict());
    habit->is_active = false;
    habit->ended_date = today_value.value();
    habit->updated_at = next_timestamp(habit->updated_at, now);
    auto cancelled = cancel_open_reminders(
        state, habit->id, std::nullopt,
        std::string(domain::kReminderCancellationReasonHabitEnded), now);
    if (!cancelled.ok()) return cancelled;
    auto detail_result = project_detail(state, *habit, today_value.value(), 30);
    if (!detail_result.ok()) return common::Result<common::Unit>::failure(detail_result.error());
    output.detail = std::move(detail_result.value());
    output.schedule_reconciliation_required = true;
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok() ? common::Result<HabitMutationCommit>::success(std::move(output))
                        : common::Result<HabitMutationCommit>::failure(committed.error());
}

common::Result<HabitDeleteCommit> HabitService::remove(
    const HabitIdentityCommand& command) {
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok()) return common::Result<HabitDeleteCommit>::failure(today_value.error());
  HabitDeleteCommit output;
  auto committed = transaction_->execute("habit.delete", [&](auto& state) {
    auto* habit = find_habit(state, command.id);
    if (habit == nullptr) return common::Result<common::Unit>::failure(not_found(command.id));
    if (habit->deleted_at.has_value()) return common::Result<common::Unit>::failure(deleted());
    if (habit->updated_at != command.expected_updated_at)
      return common::Result<common::Unit>::failure(conflict());
    habit->deleted_at = now;
    habit->updated_at = next_timestamp(habit->updated_at, now);
    for (auto& recurrence : state.recurrences)
      if (recurrence.id == habit->recurrence_id) recurrence.deleted_at = now;
    if (auto* reminder_template = active_template(state, habit->id);
        reminder_template != nullptr) {
      reminder_template->is_enabled = false;
      reminder_template->deleted_at = now;
      reminder_template->updated_at = next_timestamp(reminder_template->updated_at, now);
    }
    auto cancelled = cancel_open_reminders(
        state, habit->id, std::nullopt,
        std::string(domain::kReminderCancellationReasonHabitDeleted), now);
    if (!cancelled.ok()) return cancelled;
    output = HabitDeleteCommit{habit->id, now, true};
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok() ? common::Result<HabitDeleteCommit>::success(std::move(output))
                        : common::Result<HabitDeleteCommit>::failure(committed.error());
}

common::Result<HabitCheckInCommit> HabitService::check_in(
    const HabitCheckInCommand& command) {
  if (command.note.has_value()) {
    auto note_valid = request_text(*command.note, 500, "note", false);
    if (!note_valid.ok())
      return common::Result<HabitCheckInCommit>::failure(note_valid.error());
  }
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok()) return common::Result<HabitCheckInCommit>::failure(today_value.error());
  HabitCheckInCommit output;
  auto committed = transaction_->execute("habit.check_in", [&](auto& state) {
    auto* habit = find_habit(state, command.habit_id);
    if (habit == nullptr) return common::Result<common::Unit>::failure(not_found(command.habit_id));
    auto target_valid = validate_operation_target(*habit, today_value.value());
    if (!target_valid.ok()) return target_valid;
    if (today_value.value() < command.check_date)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_CHECK_IN_FUTURE_DATE",
          "Habit check-in date is in the future for the current device timezone"));
    if (command.check_date < habit->start_date ||
        domain::habit_effective_end_date(*habit) < command.check_date)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_CHECK_IN_DATE_OUT_OF_RANGE",
          "Habit check-in date is outside the effective challenge interval"));
    if (command.source == domain::kHabitCheckInNotificationAction) {
      if (!(command.check_date == today_value.value()))
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_NOTIFICATION_ACTION_EXPIRED",
            "Habit notification action is outside its local occurrence date"));
      if (!command.occurrence_key.has_value() || !command.action_id.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH",
            "Habit notification action identity does not match the active occurrence"));
      const auto reminder = std::find_if(
          state.reminders.begin(), state.reminders.end(), [&](const auto& item) {
            return item.target_type == domain::kReminderTargetHabit &&
                   item.target_id == habit->id &&
                   item.occurrence_date == domain::format_local_date(command.check_date) &&
                   item.occurrence_key == command.occurrence_key;
          });
      auto expected = habit_action_id(habit->id, command.check_date,
                                      *command.occurrence_key);
      const auto existing_action_check = find_active_check_in(
          state, habit->id, command.check_date);
      const bool action_already_applied =
          existing_action_check != nullptr &&
          existing_action_check->source ==
              domain::kHabitCheckInNotificationAction &&
          existing_action_check->status == domain::kHabitCheckInDone;
      const bool live_attempt = reminder != state.reminders.end() &&
          std::any_of(state.notifications.begin(), state.notifications.end(),
                      [&](const auto& notification) {
                        return notification.reminder_id == reminder->id &&
                               notification.target_type ==
                                   domain::kReminderTargetHabit &&
                               notification.target_id == habit->id &&
                               notification.occurrence_key ==
                                   command.occurrence_key &&
                               (notification.status ==
                                    domain::kNotificationStatusPrepared ||
                                notification.status ==
                                    domain::kNotificationStatusSent);
                      });
      if (reminder == state.reminders.end() || !expected.ok() ||
          expected.value() != *command.action_id ||
          (!live_attempt && !action_already_applied))
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_NOTIFICATION_ACTION_IDENTITY_MISMATCH",
            "Habit notification action identity does not match the active occurrence"));
    }
    if (command.source != domain::kHabitCheckInManual &&
        command.source != domain::kHabitCheckInNotificationAction)
      return common::Result<common::Unit>::failure(common::make_error(
          "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
          {{"field", "HabitCheckInCommandRequest.source"}}));
    auto* check = find_check_in(state, habit->id, command.check_date);
    std::string status = command.status;
    auto amount = command.completed_count_hundredths;
    if (command.source == domain::kHabitCheckInNotificationAction) {
      status = "done";
      amount = habit->target_count_hundredths;
    }
    if (status == domain::kHabitCheckInSkipped) {
      if (amount.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_TARGET_INVALID", "Habit target count and unit are invalid"));
    } else if (!habit->target_count_hundredths.has_value()) {
      if (status != domain::kHabitCheckInDone || amount.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_TARGET_INVALID", "Habit target count and unit are invalid"));
    } else {
      if (!amount.has_value() || *amount < 1 || *amount > domain::kHabitMaxHundredths)
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_TARGET_INVALID", "Habit target count and unit are invalid"));
      status = *amount >= *habit->target_count_hundredths ? "done" : "partial";
    }
    const bool same = check != nullptr && !check->deleted_at.has_value() &&
                      check->status == status &&
                      check->completed_count_hundredths == amount &&
                      check->note == command.note && check->source == command.source;
    if (same) {
      output.idempotent_replay = true;
    } else if (check == nullptr) {
      domain::HabitCheckIn created;
      created.id = id_generator_();
      created.habit_id = habit->id;
      created.check_date = command.check_date;
      created.status = status;
      created.completed_count_hundredths =
          status == domain::kHabitCheckInSkipped ? std::nullopt : amount;
      created.target_count_snapshot_hundredths =
          status == domain::kHabitCheckInSkipped ? std::nullopt
                                                 : habit->target_count_hundredths;
      created.unit_snapshot = status == domain::kHabitCheckInSkipped
                                  ? std::nullopt
                                  : habit->unit;
      created.completed_at = status == domain::kHabitCheckInSkipped
                                 ? std::nullopt
                                 : std::optional<std::string>(now);
      created.note = command.note;
      created.source = command.source;
      created.created_at = now;
      created.updated_at = now;
      state.check_ins.push_back(created);
      check = &state.check_ins.back();
    } else {
      check->status = status;
      check->completed_count_hundredths =
          status == domain::kHabitCheckInSkipped ? std::nullopt : amount;
      check->target_count_snapshot_hundredths =
          status == domain::kHabitCheckInSkipped ? std::nullopt
                                                 : habit->target_count_hundredths;
      check->unit_snapshot = status == domain::kHabitCheckInSkipped
                                 ? std::nullopt
                                 : habit->unit;
      check->completed_at = status == domain::kHabitCheckInSkipped
                                ? std::nullopt
                                : std::optional<std::string>(now);
      check->note = command.note;
      check->source = command.source;
      check->updated_at = next_timestamp(check->updated_at, now);
      check->deleted_at = std::nullopt;
    }
    if (!habit->first_check_in_at.has_value()) habit->first_check_in_at = now;
    if (status == domain::kHabitCheckInDone ||
        status == domain::kHabitCheckInSkipped) {
      auto cancelled = cancel_open_reminders(
          state, habit->id, command.check_date,
          status == domain::kHabitCheckInDone
              ? std::string(domain::kReminderCancellationReasonHabitCompleted)
              : std::string(domain::kReminderCancellationReasonHabitSkipped),
          now);
      if (!cancelled.ok()) return cancelled;
      output.schedule_reconciliation_required = true;
    } else {
      for (auto& reminder : state.reminders) {
        if (reminder.target_type == domain::kReminderTargetHabit &&
            reminder.target_id == habit->id &&
            reminder.occurrence_date == domain::format_local_date(command.check_date) &&
            is_open(reminder)) {
          const auto remaining = *habit->target_count_hundredths - *amount;
          reminder.message = habit->title + "：还差 " +
                             common::format_hundredths(remaining) + " " +
                             habit->unit.value_or("");
          reminder.updated_at = next_timestamp(reminder.updated_at, now);
        }
      }
    }
    output.check_in = *check;
    output.daily_status = project_day(state, *habit, command.check_date,
                                      today_value.value());
    auto computed = statistics(state, *habit, today_value.value());
    if (!computed.ok()) return common::Result<common::Unit>::failure(computed.error());
    output.statistics = computed.value();
    output.reminder_settings = reminder_settings(state, habit->id);
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok() ? common::Result<HabitCheckInCommit>::success(std::move(output))
                        : common::Result<HabitCheckInCommit>::failure(committed.error());
}

common::Result<HabitCheckInCommit> HabitService::clear_check_in(
    const ClearHabitCheckInCommand& command) {
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok()) return common::Result<HabitCheckInCommit>::failure(today_value.error());
  HabitCheckInCommit output;
  auto committed = transaction_->execute("habit.clear_check_in", [&](auto& state) {
    auto* habit = find_habit(state, command.habit_id);
    if (habit == nullptr) return common::Result<common::Unit>::failure(not_found(command.habit_id));
    auto target_valid = validate_operation_target(*habit, today_value.value());
    if (!target_valid.ok()) return target_valid;
    if (today_value.value() < command.check_date)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_CHECK_IN_FUTURE_DATE",
          "Habit check-in date is in the future for the current device timezone"));
    if (command.check_date < habit->start_date || habit->end_date < command.check_date)
      return common::Result<common::Unit>::failure(common::make_error(
          "HABIT_CHECK_IN_DATE_OUT_OF_RANGE",
          "Habit check-in date is outside the effective challenge interval"));
    auto* check = find_check_in(state, habit->id, command.check_date);
    if (check == nullptr || check->deleted_at.has_value()) {
      output.idempotent_replay = true;
    } else {
      check->deleted_at = now;
      check->updated_at = next_timestamp(check->updated_at, now);
    }
    const auto* reminder_template = active_template(state, habit->id);
    if (command.check_date == today_value.value() &&
        reminder_template != nullptr && reminder_template->is_enabled &&
        !has_display_reservation(state, habit->id, command.check_date)) {
      auto restored = materialize_reminder(
          state, *habit, *reminder_template, command.check_date,
          command.timezone, now, *local_time_resolver_);
      if (!restored.ok()) return common::Result<common::Unit>::failure(restored.error());
      output.schedule_reconciliation_required = restored.value();
    }
    output.check_in = std::nullopt;
    output.daily_status = project_day(state, *habit, command.check_date,
                                      today_value.value());
    auto computed = statistics(state, *habit, today_value.value());
    if (!computed.ok()) return common::Result<common::Unit>::failure(computed.error());
    output.statistics = computed.value();
    output.reminder_settings = reminder_settings(state, habit->id);
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok() ? common::Result<HabitCheckInCommit>::success(std::move(output))
                        : common::Result<HabitCheckInCommit>::failure(committed.error());
}

common::Result<HabitDailyStatusList> HabitService::list_daily_statuses(
    std::string habit_id, domain::LocalDate start_date,
    domain::LocalDate end_date, std::string timezone) {
  const auto now = clock_();
  auto today_value = today(timezone, now);
  if (!today_value.ok()) return common::Result<HabitDailyStatusList>::failure(today_value.error());
  auto state = transaction_->load();
  if (!state.ok()) return common::Result<HabitDailyStatusList>::failure(state.error());
  const auto* habit = find_habit(state.value(), habit_id);
  if (habit == nullptr || habit->deleted_at.has_value())
    return common::Result<HabitDailyStatusList>::failure(not_found(habit_id));
  const int days = domain::local_days_between(start_date, end_date) + 1;
  if (days <= 0 || start_date < habit->start_date || habit->end_date < end_date)
    return common::Result<HabitDailyStatusList>::failure(common::make_error(
        "HABIT_DAILY_STATUS_RANGE_INVALID",
        "Habit daily-status range is empty, reversed, or outside the challenge"));
  if (days > domain::kHabitMaxChallengeDays)
    return common::Result<HabitDailyStatusList>::failure(common::make_error(
        "HABIT_DAILY_STATUS_RANGE_TOO_LARGE",
        "Habit daily-status range exceeds 400 natural days"));
  HabitDailyStatusList result{habit_id, start_date, end_date, {}};
  for (auto date = start_date; less_equal(date, end_date);
       date = domain::add_local_days(date, 1))
    result.items.push_back(project_day(state.value(), *habit, date,
                                       today_value.value()));
  return common::Result<HabitDailyStatusList>::success(std::move(result));
}

common::Result<HabitMutationCommit> HabitService::set_reminder(
    const SetHabitReminderCommand& command) {
  auto reminder_valid = validate_reminder_plan(command.reminder);
  if (!reminder_valid.ok())
    return common::Result<HabitMutationCommit>::failure(reminder_valid.error());
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok()) return common::Result<HabitMutationCommit>::failure(today_value.error());
  HabitMutationCommit output;
  auto committed = transaction_->execute("habit.set_reminder", [&](auto& state) {
    auto* habit = find_habit(state, command.habit_id);
    if (habit == nullptr) return common::Result<common::Unit>::failure(not_found(command.habit_id));
    auto target_valid = validate_operation_target(*habit, today_value.value());
    if (!target_valid.ok()) return target_valid;
    if (habit->updated_at != command.expected_updated_at)
      return common::Result<common::Unit>::failure(conflict());
    auto* current = active_template(state, habit->id);
    const bool reserved_before_template_change = has_template_change_reservation(
        state, habit->id, today_value.value());
    if (!command.reminder.is_enabled) {
      if (command.reminder.local_time.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_REMINDER_CONFIG_INVALID", "Habit reminder configuration is invalid"));
      if (current != nullptr) {
        current->is_enabled = false;
        current->updated_at = next_timestamp(current->updated_at, now);
      }
      auto cancelled = cancel_open_reminders(
          state, habit->id, std::nullopt,
          std::string(domain::kReminderCancellationReasonHabitTemplateDisabled), now);
      if (!cancelled.ok()) return cancelled;
      output.schedule_reconciliation_required = true;
    } else {
      if (!command.reminder.local_time.has_value())
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_REMINDER_CONFIG_INVALID", "Habit reminder configuration is invalid"));
      const bool replace = current == nullptr || !current->is_enabled ||
                           current->local_time != *command.reminder.local_time;
      if (replace && current != nullptr) {
        auto cancelled = cancel_open_reminders(
            state, habit->id, std::nullopt,
            std::string(domain::kReminderCancellationReasonHabitTemplateReplaced), now);
        if (!cancelled.ok()) return cancelled;
        current->deleted_at = now;
        current->is_enabled = false;
        current->updated_at = next_timestamp(current->updated_at, now);
      }
      if (replace) {
        domain::HabitReminderTemplate created;
        created.template_key = id_generator_();
        created.habit_id = habit->id;
        created.local_time = *command.reminder.local_time;
        created.created_at = now;
        created.updated_at = now;
        auto valid = domain::validate_habit_reminder_template(created);
        if (!valid.ok()) return valid;
        state.reminder_templates.push_back(created);
        current = &state.reminder_templates.back();
      }
      auto first_date = std::max(habit->start_date, today_value.value());
      if (reserved_before_template_change ||
          has_display_reservation(state, habit->id, first_date))
        first_date = domain::add_local_days(first_date, 1);
      auto materialized = materialize_reminder(
          state, *habit, *current, first_date, command.timezone, now,
          *local_time_resolver_);
      if (!materialized.ok()) return common::Result<common::Unit>::failure(materialized.error());
      output.schedule_reconciliation_required = materialized.value();
    }
    habit->updated_at = next_timestamp(habit->updated_at, now);
    auto detail_result = project_detail(state, *habit, today_value.value(), 30);
    if (!detail_result.ok()) return common::Result<common::Unit>::failure(detail_result.error());
    output.detail = std::move(detail_result.value());
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok() ? common::Result<HabitMutationCommit>::success(std::move(output))
                        : common::Result<HabitMutationCommit>::failure(committed.error());
}

common::Result<ReconcileHabitRemindersResult>
HabitService::reconcile_reminders(
    const ReconcileHabitRemindersCommand& command) {
  const auto now = clock_();
  auto today_value = today(command.timezone, now);
  if (!today_value.ok())
    return common::Result<ReconcileHabitRemindersResult>::failure(today_value.error());
  if (command.limit < 1 || command.limit > 100)
    return common::Result<ReconcileHabitRemindersResult>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
        {{"field", "ReconcileHabitRemindersRequest.limit"}}));
  const std::set<std::string> trigger_sources{
      "app_start", "device_boot", "app_update", "date_changed",
      "time_changed", "timezone_changed", "permission_restored",
      "manual_retry"};
  if (trigger_sources.count(command.trigger_source) == 0U)
    return common::Result<ReconcileHabitRemindersResult>::failure(
        common::make_error(
            "CONTRACT_VALIDATION_FAILED",
            "Request does not match contract schema",
            {{"field", "ReconcileHabitRemindersRequest.trigger_source"}}));
  ReconcileHabitRemindersResult output;
  output.request_limit = command.limit;
  auto committed = transaction_->execute("habit.reconcile_reminders", [&](auto& state) {
    std::vector<std::string> ids;
    for (const auto& habit : state.habits)
      if (active_template(state, habit.id) != nullptr) ids.push_back(habit.id);
    std::sort(ids.begin(), ids.end());
    std::size_t offset = 0;
    if (command.cursor.has_value()) {
      const std::string prefix = "habit-r1:";
      if (command.cursor->rfind(prefix, 0) != 0)
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_RECONCILIATION_CURSOR_INVALID",
            "Habit reminder reconciliation cursor is invalid or stale"));
      const auto id = command.cursor->substr(prefix.size());
      if (!common::is_uuid(id))
        return common::Result<common::Unit>::failure(common::make_error(
            "HABIT_RECONCILIATION_CURSOR_INVALID",
            "Habit reminder reconciliation cursor is invalid or stale"));
      const auto found = std::upper_bound(ids.begin(), ids.end(), id);
      offset = static_cast<std::size_t>(std::distance(ids.begin(), found));
    }
    const auto end = std::min(ids.size(), offset + static_cast<std::size_t>(command.limit));
    for (std::size_t index = offset; index < end; ++index) {
      auto* habit = find_habit(state, ids[index]);
      auto* reminder_template = active_template(state, ids[index]);
      if (habit == nullptr || reminder_template == nullptr) continue;
      bool expired_outcome = false;
      bool cancelled_outcome = false;
      bool materialized_outcome = false;
      for (auto& reminder : state.reminders) {
        if (reminder.target_type != domain::kReminderTargetHabit ||
            reminder.target_id != habit->id || !is_open(reminder) ||
            !reminder.occurrence_date.has_value())
          continue;
        auto date = domain::parse_local_date(*reminder.occurrence_date);
        if (!date.ok())
          return common::Result<common::Unit>::failure(date.error());
        if (date.value() < today_value.value()) {
          reminder.status = std::string(domain::kReminderStatusExpired);
          reminder.is_enabled = false;
          reminder.scheduled_at = std::nullopt;
          reminder.expiration_reason =
              std::string(domain::kReminderExpirationReasonHabitOccurrenceElapsed);
          reminder.expired_at = now;
          reminder.updated_at = next_timestamp(reminder.updated_at, now);
          for (auto& notification : state.notifications) {
            if (notification.reminder_id != reminder.id ||
                notification.status != domain::kNotificationStatusPrepared)
              continue;
            notification.status =
                std::string(domain::kNotificationStatusAbandoned);
            notification.abandon_reason = "habit_occurrence_elapsed";
            notification.finalized_at = now;
            notification.sent_at = std::nullopt;
            notification.recovery_batch_id = std::nullopt;
            notification.resolved_by_recovery_batch_id = std::nullopt;
            notification.updated_at =
                next_timestamp(notification.updated_at, now);
          }
          expired_outcome = true;
        }
      }
      const auto lifecycle = domain::habit_lifecycle(*habit, today_value.value());
      const bool occurrence_is_current =
          lifecycle == domain::HabitLifecycle::active;
      const auto reconciliation_date =
          lifecycle == domain::HabitLifecycle::upcoming
              ? habit->start_date
              : today_value.value();
      const auto* check = occurrence_is_current
                              ? find_active_check_in(
                                    state, habit->id, reconciliation_date)
                              : nullptr;
      if ((lifecycle != domain::HabitLifecycle::active &&
           lifecycle != domain::HabitLifecycle::upcoming) ||
          !reminder_template->is_enabled ||
          (check != nullptr && (check->status == domain::kHabitCheckInDone ||
                                check->status == domain::kHabitCheckInSkipped))) {
        bool has_open = false;
        for (const auto& reminder : state.reminders)
          if (reminder.target_type == domain::kReminderTargetHabit &&
              reminder.target_id == habit->id && is_open(reminder))
            has_open = true;
        std::string reason =
            std::string(domain::kReminderCancellationReasonHabitCompleted);
        if (!reminder_template->is_enabled)
          reason = std::string(
              domain::kReminderCancellationReasonHabitTemplateDisabled);
        else if (check != nullptr &&
                 check->status == domain::kHabitCheckInSkipped)
          reason = std::string(
              domain::kReminderCancellationReasonHabitSkipped);
        else if (lifecycle == domain::HabitLifecycle::ended_early)
          reason = std::string(
              domain::kReminderCancellationReasonHabitEnded);
        auto cancelled = cancel_open_reminders(
            state, habit->id, std::nullopt, reason, now);
        if (!cancelled.ok()) return cancelled;
        cancelled_outcome = has_open;
      } else {
        auto existing = std::find_if(
            state.reminders.begin(), state.reminders.end(),
            [&](const auto& reminder) {
              return reminder.target_type == domain::kReminderTargetHabit &&
                     reminder.target_id == habit->id && is_open(reminder) &&
                     reminder.template_key == reminder_template->template_key &&
                     reminder.occurrence_date ==
                         domain::format_local_date(reconciliation_date);
            });
        if (existing != state.reminders.end()) {
          const bool prepared = std::any_of(
              state.notifications.begin(), state.notifications.end(),
              [&](const auto& notification) {
                return notification.reminder_id == existing->id &&
                       notification.status ==
                           domain::kNotificationStatusPrepared;
              });
          if (!prepared) {
            const bool reproject_time =
                command.trigger_source == "time_changed" ||
                command.trigger_source == "timezone_changed";
            std::optional<domain::Reminder> expected;
            if (reproject_time) {
              auto built = make_reminder(
                  *habit, *reminder_template, reconciliation_date,
                  command.timezone, now, *local_time_resolver_);
              if (!built.ok())
                return common::Result<common::Unit>::failure(built.error());
              expected = std::move(built.value());
            }
            const auto desired_message =
                check != nullptr &&
                        check->status == domain::kHabitCheckInPartial
                    ? existing->message
                    : expected.has_value() ? expected->message
                                           : existing->message;
            if ((expected.has_value() &&
                 existing->remind_at != expected->remind_at) ||
                existing->message != desired_message ||
                existing->status == domain::kReminderStatusScheduled) {
              if (expected.has_value())
                existing->remind_at = expected->remind_at;
              existing->message = desired_message;
              existing->status =
                  std::string(domain::kReminderStatusPending);
              existing->scheduled_at = std::nullopt;
              existing->failure_reason = std::nullopt;
              existing->updated_at = next_timestamp(existing->updated_at, now);
              materialized_outcome = true;
            }
          }
        }
        auto materialized = materialize_reminder(
            state, *habit, *reminder_template, reconciliation_date,
            command.timezone, now, *local_time_resolver_);
        if (!materialized.ok()) return common::Result<common::Unit>::failure(materialized.error());
        if (materialized.value()) {
          materialized_outcome = true;
        }
      }
      ++output.processed_count;
      // One scanned Habit contributes exactly one externally visible outcome,
      // even if the same atomic reconciliation both expires stale work and
      // materializes the current occurrence.
      if (materialized_outcome)
        ++output.materialized_count;
      else if (cancelled_outcome)
        ++output.cancelled_count;
      else if (expired_outcome)
        ++output.expired_count;
      else
        ++output.unchanged_count;
    }
    output.has_more = end < ids.size();
    if (output.has_more && end > offset) output.next_cursor = "habit-r1:" + ids[end - 1U];
    output.schedule_reconciliation_required =
        output.materialized_count > 0 || output.expired_count > 0 ||
        output.cancelled_count > 0 ||
        std::any_of(state.reminders.begin(), state.reminders.end(),
                    [](const auto& reminder) {
                      return reminder.target_type ==
                                 domain::kReminderTargetHabit &&
                             is_open(reminder);
                    });
    return common::Result<common::Unit>::success(common::Unit{});
  });
  return committed.ok()
             ? common::Result<ReconcileHabitRemindersResult>::success(std::move(output))
             : common::Result<ReconcileHabitRemindersResult>::failure(committed.error());
}

}  // namespace excellent_calendar::application
