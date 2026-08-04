#include "excellent_calendar/application/recurrence_service.hpp"

#include <algorithm>
#include <cstdint>
#include <sstream>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kOccurrenceNamespace = "2fa8ebd0-958e-5eae-83d1-1aa5da893415";
constexpr int kMaximumExpansionCount = 1000000;

common::Error recurrence_invalid(std::string reason, std::string field = "recurrence") {
  return common::make_error(
      "RECURRENCE_RULE_INVALID",
      "Recurrence rule is invalid",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error feature_not_implemented(std::string frequency) {
  return common::make_error(
      "FEATURE_NOT_IMPLEMENTED",
      "Requested feature is not implemented in this phase",
      {{"feature", "recurrence." + std::move(frequency)}});
}

domain::LocalDate date_part(const domain::LocalDateTime& value) {
  return domain::LocalDate{value.year, value.month, value.day};
}

domain::LocalDateTime combine(const domain::LocalDate& date,
                              const domain::LocalDateTime& time) {
  return domain::LocalDateTime{
      date.year, date.month, date.day, time.hour, time.minute, time.second};
}

domain::LocalDate occurrence_date(const domain::LocalDate& original,
                                  const domain::Recurrence& recurrence,
                                  int index) {
  if (recurrence.frequency == domain::kRecurrenceDaily) {
    return domain::add_local_days(original, index);
  }
  if (recurrence.frequency == domain::kRecurrenceWeekly) {
    return domain::add_local_days(original, index * 7);
  }
  return domain::add_local_months_with_anchor(original, index, *recurrence.day_of_month);
}

std::string canonical_occurrence_name(const std::string& event_id,
                                      int revision,
                                      const std::string& local_start) {
  return "[\"" + event_id + "\"," + std::to_string(revision) + ",\"" + local_start + "\"]";
}

common::Result<std::string> occurrence_key(const std::string& event_id,
                                           int revision,
                                           const std::string& local_start) {
  return common::generate_uuid_v5(
      kOccurrenceNamespace, canonical_occurrence_name(event_id, revision, local_start));
}

}  // namespace

RecurrenceService::RecurrenceService(std::shared_ptr<domain::LocalTimeResolver> time_resolver)
    : time_resolver_(std::move(time_resolver)) {}

common::Result<common::Unit> RecurrenceService::validate_timezone(
    std::string_view timezone) const {
  return time_resolver_->validate_timezone(timezone);
}

common::Result<domain::Recurrence> RecurrenceService::derive_recurrence(
    const domain::RecurringEventSchedule& event,
    const domain::EventRecurrenceRuleInput& input,
    std::string recurrence_id,
    int revision,
    std::string created_at) const {
  if (!domain::is_known_recurrence_frequency(input.frequency)) {
    return common::Result<domain::Recurrence>::failure(
        recurrence_invalid("unknown frequency", "recurrence.frequency"));
  }
  if (!domain::is_supported_recurrence_frequency(input.frequency)) {
    return common::Result<domain::Recurrence>::failure(feature_not_implemented(input.frequency));
  }
  if (input.interval != 1) {
    return common::Result<domain::Recurrence>::failure(
        recurrence_invalid("interval must equal 1", "recurrence.interval"));
  }
  if (input.end_at.has_value()) {
    return common::Result<domain::Recurrence>::failure(
        recurrence_invalid("end_at must be null", "recurrence.end_at"));
  }
  if (input.count.has_value()) {
    return common::Result<domain::Recurrence>::failure(
        recurrence_invalid("count must be null", "recurrence.count"));
  }
  if (revision < 1 || recurrence_id.empty()) {
    return common::Result<domain::Recurrence>::failure(
        recurrence_invalid("identity is invalid", "recurrence"));
  }
  auto timezone = time_resolver_->validate_timezone(event.timezone);
  if (!timezone.ok()) return common::Result<domain::Recurrence>::failure(timezone.error());

  domain::Recurrence recurrence;
  recurrence.id = std::move(recurrence_id);
  recurrence.revision = revision;
  recurrence.frequency = input.frequency;
  recurrence.interval = 1;
  recurrence.timezone = event.timezone;
  recurrence.created_at = std::move(created_at);

  if (event.is_all_day) {
    if (!event.start_date.has_value() || !event.end_date.has_value() || event.start_at.has_value() ||
        event.end_at.has_value()) {
      return common::Result<domain::Recurrence>::failure(
          recurrence_invalid("all-day time shape is invalid", "event"));
    }
    auto start = domain::parse_local_date(*event.start_date);
    auto end = domain::parse_local_date(*event.end_date);
    if (!start.ok()) return common::Result<domain::Recurrence>::failure(start.error());
    if (!end.ok()) return common::Result<domain::Recurrence>::failure(end.error());
    if (!(start.value() < end.value())) {
      return common::Result<domain::Recurrence>::failure(
          recurrence_invalid("all-day interval must be positive", "event.end_date"));
    }
    recurrence.start_date = *event.start_date;
    if (input.frequency == domain::kRecurrenceWeekly) {
      recurrence.days_of_week = {domain::iso_weekday(start.value())};
    } else if (input.frequency == domain::kRecurrenceMonthly) {
      recurrence.day_of_month = start.value().day;
    }
  } else {
    if (!event.start_at.has_value() || !event.end_at.has_value() || event.start_date.has_value() ||
        event.end_date.has_value()) {
      return common::Result<domain::Recurrence>::failure(
          recurrence_invalid("timed time shape is invalid", "event"));
    }
    auto start = time_resolver_->to_local(*event.start_at, event.timezone);
    auto end = time_resolver_->to_local(*event.end_at, event.timezone);
    if (!start.ok()) return common::Result<domain::Recurrence>::failure(start.error());
    if (!end.ok()) return common::Result<domain::Recurrence>::failure(end.error());
    const auto start_epoch = common::parse_iso8601_utc_epoch_seconds(*event.start_at);
    const auto end_epoch = common::parse_iso8601_utc_epoch_seconds(*event.end_at);
    if (!start_epoch.has_value() || !end_epoch.has_value() || *start_epoch >= *end_epoch ||
        !(start.value() < end.value())) {
      return common::Result<domain::Recurrence>::failure(
          recurrence_invalid("original timed interval must be positive", "event.end_at"));
    }
    recurrence.start_at = *event.start_at;
    if (input.frequency == domain::kRecurrenceWeekly) {
      recurrence.days_of_week = {domain::iso_weekday(date_part(start.value()))};
    } else if (input.frequency == domain::kRecurrenceMonthly) {
      recurrence.day_of_month = start.value().day;
    }
  }
  return common::Result<domain::Recurrence>::success(std::move(recurrence));
}

common::Result<domain::EventOccurrence> RecurrenceService::occurrence_at(
    const domain::RecurringEventSchedule& event,
    const domain::Recurrence& recurrence,
    int index) const {
  const bool daily_shape = recurrence.frequency == domain::kRecurrenceDaily &&
                           recurrence.days_of_week.empty() &&
                           !recurrence.day_of_month.has_value();
  const bool weekly_shape = recurrence.frequency == domain::kRecurrenceWeekly &&
                            recurrence.days_of_week.size() == 1U &&
                            !recurrence.day_of_month.has_value();
  const bool monthly_shape = recurrence.frequency == domain::kRecurrenceMonthly &&
                             recurrence.days_of_week.empty() &&
                             recurrence.day_of_month.has_value() &&
                             *recurrence.day_of_month >= 1 &&
                             *recurrence.day_of_month <= 31;
  if (index < 0 || index >= kMaximumExpansionCount || recurrence.interval != 1 ||
      !domain::is_supported_recurrence_frequency(recurrence.frequency) ||
      (!daily_shape && !weekly_shape && !monthly_shape) || recurrence.end_at.has_value() ||
      recurrence.count.has_value() || recurrence.month_of_year.has_value() ||
      recurrence.id.empty() || recurrence.revision < 1 || recurrence.timezone != event.timezone) {
    return common::Result<domain::EventOccurrence>::failure(
        recurrence_invalid("stored recurrence is invalid"));
  }

  domain::EventOccurrence occurrence;
  occurrence.event_id = event.event_id;
  occurrence.recurrence_revision = recurrence.revision;
  occurrence.timezone = recurrence.timezone;

  if (event.is_all_day) {
    if (!event.start_date.has_value() || !event.end_date.has_value() ||
        !recurrence.start_date.has_value() || recurrence.start_at.has_value() ||
        recurrence.start_date != event.start_date) {
      return common::Result<domain::EventOccurrence>::failure(
          recurrence_invalid("all-day recurrence shape is invalid"));
    }
    auto original_start = domain::parse_local_date(*event.start_date);
    auto original_end = domain::parse_local_date(*event.end_date);
    if (!original_start.ok()) return common::Result<domain::EventOccurrence>::failure(original_start.error());
    if (!original_end.ok()) return common::Result<domain::EventOccurrence>::failure(original_end.error());
    if ((weekly_shape && recurrence.days_of_week.front() !=
                             domain::iso_weekday(original_start.value())) ||
        (monthly_shape && *recurrence.day_of_month != original_start.value().day)) {
      return common::Result<domain::EventOccurrence>::failure(
          recurrence_invalid("stored recurrence derived fields conflict with Event start"));
    }
    const auto start = occurrence_date(original_start.value(), recurrence, index);
    const auto end = domain::add_local_days(
        start, domain::local_days_between(original_start.value(), original_end.value()));
    occurrence.original_local_start = domain::format_local_date(start);
    occurrence.occurrence_start_date = occurrence.original_local_start;
    occurrence.occurrence_end_date = domain::format_local_date(end);
  } else {
    if (!event.start_at.has_value() || !event.end_at.has_value() ||
        !recurrence.start_at.has_value() || recurrence.start_date.has_value() ||
        recurrence.start_at != event.start_at) {
      return common::Result<domain::EventOccurrence>::failure(
          recurrence_invalid("timed recurrence shape is invalid"));
    }
    auto original_start = time_resolver_->to_local(*event.start_at, event.timezone);
    auto original_end = time_resolver_->to_local(*event.end_at, event.timezone);
    if (!original_start.ok()) return common::Result<domain::EventOccurrence>::failure(original_start.error());
    if (!original_end.ok()) return common::Result<domain::EventOccurrence>::failure(original_end.error());
    if ((weekly_shape && recurrence.days_of_week.front() !=
                             domain::iso_weekday(date_part(original_start.value()))) ||
        (monthly_shape && *recurrence.day_of_month != original_start.value().day)) {
      return common::Result<domain::EventOccurrence>::failure(
          recurrence_invalid("stored recurrence derived fields conflict with Event start"));
    }
    const auto start_date = occurrence_date(date_part(original_start.value()), recurrence, index);
    const auto end_date = domain::add_local_days(
        start_date,
        domain::local_days_between(date_part(original_start.value()), date_part(original_end.value())));
    const auto local_start = combine(start_date, original_start.value());
    const auto local_end = combine(end_date, original_end.value());
    occurrence.original_local_start = domain::format_local_date_time(local_start);
    auto start_at = time_resolver_->to_utc(local_start, event.timezone);
    auto end_at = time_resolver_->to_utc(local_end, event.timezone);
    if (!start_at.ok()) return common::Result<domain::EventOccurrence>::failure(start_at.error());
    if (!end_at.ok()) return common::Result<domain::EventOccurrence>::failure(end_at.error());
    occurrence.occurrence_start_at = start_at.value();
    occurrence.occurrence_end_at = end_at.value();
  }

  auto key = occurrence_key(event.event_id, recurrence.revision, occurrence.original_local_start);
  if (!key.ok()) return common::Result<domain::EventOccurrence>::failure(key.error());
  occurrence.occurrence_key = key.value();
  return common::Result<domain::EventOccurrence>::success(std::move(occurrence));
}

common::Result<std::vector<domain::EventOccurrence>> RecurrenceService::list_timed_occurrences(
    const domain::RecurringEventSchedule& event,
    const domain::Recurrence& recurrence,
    std::string_view range_start_at,
    std::string_view range_end_at,
    int limit) const {
  const auto range_start = common::parse_iso8601_utc_epoch_seconds(range_start_at);
  const auto range_end = common::parse_iso8601_utc_epoch_seconds(range_end_at);
  if (event.is_all_day || !range_start.has_value() || !range_end.has_value() ||
      *range_start >= *range_end || limit < 1 || limit > 200) {
    return common::Result<std::vector<domain::EventOccurrence>>::failure(
        recurrence_invalid("timed occurrence range is invalid", "range"));
  }
  std::vector<domain::EventOccurrence> result;
  for (int index = 0; index < kMaximumExpansionCount && static_cast<int>(result.size()) < limit; ++index) {
    auto occurrence = occurrence_at(event, recurrence, index);
    if (!occurrence.ok()) return common::Result<std::vector<domain::EventOccurrence>>::failure(occurrence.error());
    const auto start = common::parse_iso8601_utc_epoch_seconds(*occurrence.value().occurrence_start_at);
    if (!start.has_value()) {
      return common::Result<std::vector<domain::EventOccurrence>>::failure(
          recurrence_invalid("expanded occurrence instant is invalid"));
    }
    if (*start >= *range_end) break;
    if (*start >= *range_start) result.push_back(occurrence.value());
  }
  return common::Result<std::vector<domain::EventOccurrence>>::success(std::move(result));
}

common::Result<std::vector<domain::EventOccurrence>> RecurrenceService::list_all_day_occurrences(
    const domain::RecurringEventSchedule& event,
    const domain::Recurrence& recurrence,
    std::string_view range_start_date,
    std::string_view range_end_date,
    int limit) const {
  auto range_start = domain::parse_local_date(range_start_date);
  auto range_end = domain::parse_local_date(range_end_date);
  if (!event.is_all_day || !range_start.ok() || !range_end.ok() ||
      !(range_start.value() < range_end.value()) || limit < 1 || limit > 200) {
    return common::Result<std::vector<domain::EventOccurrence>>::failure(
        recurrence_invalid("all-day occurrence range is invalid", "range"));
  }
  std::vector<domain::EventOccurrence> result;
  for (int index = 0; index < kMaximumExpansionCount && static_cast<int>(result.size()) < limit; ++index) {
    auto occurrence = occurrence_at(event, recurrence, index);
    if (!occurrence.ok()) return common::Result<std::vector<domain::EventOccurrence>>::failure(occurrence.error());
    auto start = domain::parse_local_date(*occurrence.value().occurrence_start_date);
    if (!start.ok()) return common::Result<std::vector<domain::EventOccurrence>>::failure(start.error());
    if (!(start.value() < range_end.value())) break;
    if (!(start.value() < range_start.value())) result.push_back(occurrence.value());
  }
  return common::Result<std::vector<domain::EventOccurrence>>::success(std::move(result));
}

common::Result<domain::EventOccurrence>
RecurrenceService::first_timed_occurrence_with_reminder_after(
    const domain::RecurringEventSchedule& event,
    const domain::Recurrence& recurrence,
    int advance_minutes,
    std::string_view after_at) const {
  const auto after = common::parse_iso8601_utc_epoch_seconds(after_at);
  if (event.is_all_day || advance_minutes < 0 || !after.has_value()) {
    return common::Result<domain::EventOccurrence>::failure(
        recurrence_invalid("rolling reminder search is invalid"));
  }
  for (int index = 0; index < kMaximumExpansionCount; ++index) {
    auto occurrence = occurrence_at(event, recurrence, index);
    if (!occurrence.ok()) return occurrence;
    const auto start = common::parse_iso8601_utc_epoch_seconds(*occurrence.value().occurrence_start_at);
    if (start.has_value() && *start - static_cast<std::int64_t>(advance_minutes) * 60 > *after) {
      return occurrence;
    }
  }
  return common::Result<domain::EventOccurrence>::failure(
      recurrence_invalid("occurrence expansion exceeded safe bound"));
}

}  // namespace excellent_calendar::application
