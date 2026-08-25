#include "excellent_calendar/application/anniversary_reminder_projection.hpp"

#include <algorithm>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/anniversary.hpp"

namespace excellent_calendar::application {
namespace {

common::Error corrupted(std::string reason) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
      {{"reason", std::move(reason)}});
}

const domain::Anniversary* find_anniversary(
    const repository::RecurringEventState& state,
    const std::string& id) {
  const auto found = std::find_if(
      state.anniversaries.begin(), state.anniversaries.end(),
      [&](const auto& value) { return value.id == id; });
  return found == state.anniversaries.end() ? nullptr : &*found;
}

const domain::AnniversaryRecurrence* find_recurrence(
    const repository::RecurringEventState& state,
    const std::string& id) {
  const auto found = std::find_if(
      state.anniversary_recurrences.begin(), state.anniversary_recurrences.end(),
      [&](const auto& value) { return value.id == id; });
  return found == state.anniversary_recurrences.end() ? nullptr : &*found;
}

const domain::AnniversaryReminderTemplate* find_template(
    const repository::RecurringEventState& state,
    const std::string& key) {
  const auto found = std::find_if(
      state.anniversary_reminder_templates.begin(),
      state.anniversary_reminder_templates.end(),
      [&](const auto& value) { return value.template_key == key; });
  return found == state.anniversary_reminder_templates.end() ? nullptr : &*found;
}

common::Result<domain::LocalDateTime> reminder_local_datetime(
    const domain::LocalDate& occurrence,
    int advance_days,
    const std::string& local_time) {
  if (local_time.size() != 5U || local_time[2] != ':') {
    return common::Result<domain::LocalDateTime>::failure(
        corrupted("Anniversary Reminder local_time is invalid"));
  }
  const int hour = (local_time[0] - '0') * 10 + local_time[1] - '0';
  const int minute = (local_time[3] - '0') * 10 + local_time[4] - '0';
  const auto date = domain::add_local_days(occurrence, -advance_days);
  domain::LocalDateTime result{date.year, date.month, date.day, hour, minute, 0};
  if (!domain::is_valid_local_date_time(result)) {
    return common::Result<domain::LocalDateTime>::failure(
        corrupted("Anniversary Reminder local projection is invalid"));
  }
  return common::Result<domain::LocalDateTime>::success(result);
}

bool open(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
}

}  // namespace

common::Result<std::string> anniversary_occurrence_cutoff_utc(
    const domain::Reminder& reminder,
    const std::string& timezone,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  if (!resolver || reminder.target_type != domain::kReminderTargetAnniversary ||
      !reminder.occurrence_date.has_value()) {
    return common::Result<std::string>::failure(
        corrupted("Anniversary Reminder cutoff identity is missing"));
  }
  auto occurrence = domain::parse_local_date(*reminder.occurrence_date);
  if (!occurrence.ok()) return common::Result<std::string>::failure(occurrence.error());
  const auto next_day = domain::add_local_days(occurrence.value(), 1);
  auto resolved = resolver->resolve_local_datetime(
      {next_day.year, next_day.month, next_day.day, 0, 0, 0}, timezone);
  return resolved.ok()
             ? common::Result<std::string>::success(resolved.value().utc_instant)
             : common::Result<std::string>::failure(resolved.error());
}

common::Result<std::size_t> reproject_open_anniversary_reminders(
    repository::RecurringEventState& state,
    const std::string& timezone,
    const std::string& now,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  if (!resolver) {
    return common::Result<std::size_t>::failure(
        corrupted("Anniversary timezone resolver is unavailable"));
  }
  auto timezone_valid = resolver->validate_timezone(timezone);
  if (!timezone_valid.ok()) {
    return common::Result<std::size_t>::failure(timezone_valid.error());
  }

  std::size_t changed = 0;
  for (auto& reminder : state.reminders) {
    if (reminder.target_type != domain::kReminderTargetAnniversary ||
        !open(reminder)) {
      continue;
    }
    if (!reminder.occurrence_date.has_value() ||
        !reminder.advance_days.has_value() ||
        !reminder.local_time.has_value() ||
        reminder.timezone_mode !=
            std::optional<std::string>(
                domain::kAnniversaryReminderTimezoneFollowDevice)) {
      return common::Result<std::size_t>::failure(
          corrupted("Anniversary Reminder timezone projection identity is missing"));
    }
    auto occurrence = domain::parse_local_date(*reminder.occurrence_date);
    if (!occurrence.ok()) {
      return common::Result<std::size_t>::failure(occurrence.error());
    }
    auto local = reminder_local_datetime(
        occurrence.value(), *reminder.advance_days, *reminder.local_time);
    if (!local.ok()) {
      return common::Result<std::size_t>::failure(local.error());
    }
    auto resolved = resolver->resolve_local_datetime(local.value(), timezone);
    if (!resolved.ok()) {
      return common::Result<std::size_t>::failure(resolved.error());
    }
    if (reminder.remind_at == resolved.value().utc_instant) {
      continue;
    }

    reminder.remind_at = resolved.value().utc_instant;
    reminder.status = std::string(domain::kReminderStatusPending);
    reminder.scheduled_at = std::nullopt;
    reminder.updated_at = now;
    ++changed;
  }
  return common::Result<std::size_t>::success(changed);
}

std::optional<domain::Reminder> find_persisted_anniversary_successor(
    const repository::RecurringEventState& state,
    const domain::Reminder& source) {
  if (source.target_type != domain::kReminderTargetAnniversary ||
      !source.template_key.has_value() || !source.occurrence_date.has_value()) {
    return std::nullopt;
  }
  const domain::Reminder* result = nullptr;
  for (const auto& candidate : state.reminders) {
    if (candidate.id == source.id || candidate.target_id != source.target_id ||
        candidate.template_key != source.template_key ||
        !candidate.occurrence_date.has_value() ||
        *candidate.occurrence_date <= *source.occurrence_date || !open(candidate)) {
      continue;
    }
    if (result == nullptr || *candidate.occurrence_date < *result->occurrence_date ||
        (*candidate.occurrence_date == *result->occurrence_date && candidate.id < result->id)) {
      result = &candidate;
    }
  }
  return result == nullptr ? std::nullopt : std::optional<domain::Reminder>(*result);
}

common::Result<std::optional<domain::Reminder>> ensure_anniversary_successor(
    repository::RecurringEventState& state,
    const domain::Reminder& source,
    const std::string& timezone,
    const std::string& now,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  if (source.target_type != domain::kReminderTargetAnniversary ||
      !source.template_key.has_value() || !source.occurrence_date.has_value() ||
      !source.advance_days.has_value() || !source.local_time.has_value()) {
    return common::Result<std::optional<domain::Reminder>>::failure(
        corrupted("Anniversary Reminder successor identity is missing"));
  }
  const auto* anniversary = find_anniversary(state, source.target_id);
  if (anniversary == nullptr || anniversary->deleted_at.has_value() ||
      !anniversary->reminders_enabled || !anniversary->recurrence_id.has_value()) {
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  }
  const auto* recurrence = find_recurrence(state, *anniversary->recurrence_id);
  if (recurrence == nullptr || recurrence->deleted_at.has_value() ||
      recurrence->frequency != domain::kAnniversaryRecurrenceYearly ||
      recurrence->interval != 1) {
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  }
  const auto* reminder_template = find_template(state, *source.template_key);
  if (reminder_template == nullptr || reminder_template->deleted_at.has_value() ||
      !reminder_template->is_enabled ||
      reminder_template->anniversary_id != anniversary->id ||
      reminder_template->advance_days != *source.advance_days ||
      reminder_template->local_time != *source.local_time ||
      reminder_template->timezone_mode != source.timezone_mode ||
      reminder_template->method != domain::kAnniversaryReminderMethodPopup) {
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  }
  auto current_occurrence = domain::parse_local_date(*source.occurrence_date);
  if (!current_occurrence.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(
        current_occurrence.error());
  }
  const auto next_occurrence = domain::anniversary_occurrence_in_year(
      anniversary->date, current_occurrence.value().year + 1);
  auto occurrence_key = domain::anniversary_occurrence_key(
      anniversary->id, next_occurrence);
  if (!occurrence_key.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(occurrence_key.error());
  }
  auto reminder_id = domain::anniversary_reminder_id(
      anniversary->id, occurrence_key.value(), reminder_template->template_key);
  if (!reminder_id.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(reminder_id.error());
  }
  const auto existing = std::find_if(
      state.reminders.begin(), state.reminders.end(),
      [&](const auto& value) { return value.id == reminder_id.value(); });
  if (existing != state.reminders.end()) {
    return common::Result<std::optional<domain::Reminder>>::success(*existing);
  }
  auto local = reminder_local_datetime(
      next_occurrence, reminder_template->advance_days, reminder_template->local_time);
  if (!local.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(local.error());
  }
  auto resolved = resolver->resolve_local_datetime(local.value(), timezone);
  if (!resolved.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(resolved.error());
  }
  domain::Reminder successor;
  successor.id = reminder_id.value();
  successor.target_type = std::string(domain::kReminderTargetAnniversary);
  successor.target_id = anniversary->id;
  successor.occurrence_key = occurrence_key.value();
  successor.remind_at = resolved.value().utc_instant;
  successor.methods = {std::string(domain::kReminderMethodPopup)};
  successor.message = source.message;
  successor.is_enabled = true;
  successor.status = std::string(domain::kReminderStatusPending);
  successor.source = source.source;
  successor.created_at = now;
  successor.updated_at = now;
  successor.template_key = reminder_template->template_key;
  successor.occurrence_date = domain::format_local_date(next_occurrence);
  successor.advance_days = reminder_template->advance_days;
  successor.local_time = reminder_template->local_time;
  successor.timezone_mode = reminder_template->timezone_mode;
  state.reminders.push_back(successor);
  return common::Result<std::optional<domain::Reminder>>::success(successor);
}

}  // namespace excellent_calendar::application
