#include "excellent_calendar/domain/anniversary.hpp"

#include <algorithm>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::domain {
namespace {

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

LocalDate occurrence_in_year(const LocalDate& anchor, int year) {
  return add_local_months_with_anchor(LocalDate{year, anchor.month, 1}, 0, anchor.day);
}

}  // namespace

common::Result<common::Unit> validate_anniversary_input(
    std::string_view title,
    const LocalDate& date,
    std::string_view calendar_type,
    const std::optional<std::string>& category_id,
    const std::optional<std::string>& importance) {
  if (common::trim_ascii(title).empty()) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_TITLE_EMPTY", "Anniversary title cannot be empty",
        {{"field", "title"}}));
  }
  if (!is_valid_local_date(date)) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_DATE_INVALID", "Anniversary date is invalid",
        {{"field", "date"}}));
  }
  if (calendar_type != kAnniversaryCalendarSolar) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_CALENDAR_UNSUPPORTED",
        "Anniversary calendar type is not supported in the current version",
        {{"calendar_type", std::string(calendar_type)}}));
  }
  if (category_id.has_value() && !common::is_uuid(*category_id)) {
    return common::Result<common::Unit>::failure(
        contract_invalid("category_id", "category_id must be a UUID or null"));
  }
  if (importance.has_value() && !is_valid_importance(*importance)) {
    return common::Result<common::Unit>::failure(
        contract_invalid("importance", "importance is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_anniversary(const Anniversary& anniversary) {
  auto input = validate_anniversary_input(
      anniversary.title, anniversary.date, anniversary.calendar_type,
      anniversary.category_id, anniversary.importance);
  if (!input.ok()) return input;
  if (!common::is_uuid(anniversary.id) ||
      (anniversary.recurrence_id.has_value() &&
       !common::is_uuid(*anniversary.recurrence_id))) {
    return common::Result<common::Unit>::failure(
        contract_invalid("anniversary", "Anniversary identity is invalid"));
  }
  if (!common::is_iso8601_utc_datetime(anniversary.created_at) ||
      !common::is_iso8601_utc_datetime(anniversary.updated_at) ||
      (anniversary.deleted_at.has_value() &&
       !common::is_iso8601_utc_datetime(*anniversary.deleted_at))) {
    return common::Result<common::Unit>::failure(
        contract_invalid("anniversary", "Anniversary lifecycle timestamp is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_anniversary_recurrence(
    const AnniversaryRecurrence& recurrence) {
  if (!common::is_uuid(recurrence.id) ||
      recurrence.frequency != kAnniversaryRecurrenceYearly ||
      recurrence.interval != 1 ||
      !common::is_iso8601_utc_datetime(recurrence.created_at) ||
      (recurrence.deleted_at.has_value() &&
       !common::is_iso8601_utc_datetime(*recurrence.deleted_at))) {
    return common::Result<common::Unit>::failure(common::make_error(
        "RECURRENCE_RULE_INVALID", "Recurrence rule is invalid",
        {{"field", "recurrence"}}));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<AnniversaryCountdown> calculate_anniversary_countdown(
    const LocalDate& anniversary_date,
    bool repeats_yearly,
    const LocalDate& today,
    std::string timezone,
    std::string calculated_at) {
  if (!is_valid_local_date(anniversary_date) || !is_valid_local_date(today)) {
    return common::Result<AnniversaryCountdown>::failure(common::make_error(
        "ANNIVERSARY_DATE_INVALID", "Anniversary date is invalid",
        {{"field", "date"}}));
  }
  if (timezone.empty() || !common::is_iso8601_utc_datetime(calculated_at)) {
    return common::Result<AnniversaryCountdown>::failure(
        contract_invalid("countdown", "Countdown context is invalid"));
  }

  LocalDate target = anniversary_date;
  if (repeats_yearly) {
    int target_year = std::max(today.year, anniversary_date.year);
    target = occurrence_in_year(anniversary_date, target_year);
    if (target < today) {
      target = occurrence_in_year(anniversary_date, target_year + 1);
    }
  }

  const int signed_days = local_days_between(today, target);
  AnniversaryCountdown countdown;
  countdown.days = signed_days < 0 ? -signed_days : signed_days;
  countdown.relation = signed_days == 0
                           ? std::string(kAnniversaryCountdownToday)
                           : signed_days > 0
                                 ? std::string(kAnniversaryCountdownRemaining)
                                 : std::string(kAnniversaryCountdownElapsed);
  countdown.target_occurrence_date = target;
  countdown.iso_weekday = iso_weekday(target);
  countdown.timezone = std::move(timezone);
  countdown.calculated_at = std::move(calculated_at);
  return common::Result<AnniversaryCountdown>::success(std::move(countdown));
}

}  // namespace excellent_calendar::domain
