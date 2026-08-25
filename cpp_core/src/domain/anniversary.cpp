#include "excellent_calendar/domain/anniversary.hpp"

#include <algorithm>
#include <set>

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

bool valid_local_time(std::string_view value) {
  if (value.size() != 5U || value[2] != ':') return false;
  const auto digit = [](char value) { return value >= '0' && value <= '9'; };
  if (!digit(value[0]) || !digit(value[1]) || !digit(value[3]) || !digit(value[4])) {
    return false;
  }
  const int hour = (value[0] - '0') * 10 + value[1] - '0';
  const int minute = (value[3] - '0') * 10 + value[4] - '0';
  return hour <= 23 && minute <= 59;
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

common::Result<common::Unit> validate_anniversary_reminder_template(
    const AnniversaryReminderTemplate& reminder_template) {
  if (!common::is_uuid(reminder_template.template_key) ||
      !common::is_uuid(reminder_template.anniversary_id) ||
      reminder_template.advance_days < 0 || reminder_template.advance_days > 365 ||
      !valid_local_time(reminder_template.local_time) ||
      reminder_template.timezone_mode != kAnniversaryReminderTimezoneFollowDevice ||
      reminder_template.method != kAnniversaryReminderMethodPopup ||
      !common::is_iso8601_utc_datetime(reminder_template.created_at) ||
      !common::is_iso8601_utc_datetime(reminder_template.updated_at) ||
      (reminder_template.deleted_at.has_value() &&
       !common::is_iso8601_utc_datetime(*reminder_template.deleted_at))) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_REMINDER_CONFIG_INVALID",
        "Anniversary reminder configuration is invalid",
        {{"field", "reminder_template"}}));
  }
  auto expected = anniversary_reminder_template_key(
      reminder_template.anniversary_id, reminder_template.advance_days,
      reminder_template.local_time);
  if (!expected.ok() || expected.value() != reminder_template.template_key) {
    return common::Result<common::Unit>::failure(common::make_error(
        "ANNIVERSARY_REMINDER_CONFIG_INVALID",
        "Anniversary reminder configuration is invalid",
        {{"field", "template_key"}, {"reason", "identity does not match content"}}));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

LocalDate anniversary_occurrence_in_year(const LocalDate& source_date, int year) {
  return add_local_months_with_anchor(LocalDate{year, source_date.month, 1}, 0,
                                      source_date.day);
}

common::Result<std::string> anniversary_occurrence_key(
    std::string_view anniversary_id,
    const LocalDate& occurrence_date) {
  if (!common::is_uuid(anniversary_id) || !is_valid_local_date(occurrence_date)) {
    return common::Result<std::string>::failure(
        contract_invalid("anniversary_occurrence", "identity input is invalid"));
  }
  const std::string name = "[\"" + std::string(anniversary_id) + "\",\"" +
                           format_local_date(occurrence_date) + "\"]";
  return common::generate_uuid_v5(kAnniversaryOccurrenceNamespace, name);
}

common::Result<std::string> anniversary_reminder_template_key(
    std::string_view anniversary_id,
    int advance_days,
    std::string_view local_time) {
  if (!common::is_uuid(anniversary_id) || advance_days < 0 || advance_days > 365 ||
      !valid_local_time(local_time)) {
    return common::Result<std::string>::failure(common::make_error(
        "ANNIVERSARY_REMINDER_CONFIG_INVALID",
        "Anniversary reminder configuration is invalid",
        {{"field", "reminder_template"}}));
  }
  const std::string name = "[\"" + std::string(anniversary_id) + "\"," +
                           std::to_string(advance_days) + ",\"" +
                           std::string(local_time) + "\",\"follow_device\",\"popup\"]";
  return common::generate_uuid_v5(kAnniversaryReminderTemplateNamespace, name);
}

common::Result<std::string> anniversary_reminder_id(
    std::string_view anniversary_id,
    std::string_view occurrence_key,
    std::string_view template_key) {
  if (!common::is_uuid(anniversary_id) || !common::is_uuid(occurrence_key) ||
      !common::is_uuid(template_key)) {
    return common::Result<std::string>::failure(
        contract_invalid("anniversary_reminder", "identity input is invalid"));
  }
  const std::string name = "[\"anniversary\",\"" + std::string(anniversary_id) +
                           "\",\"" + std::string(occurrence_key) + "\",\"" +
                           std::string(template_key) + "\"]";
  return common::generate_uuid_v5(kAnniversaryReminderNamespace, name);
}

common::Result<std::string> anniversary_catch_up_delivery_id(
    std::string_view anniversary_id,
    std::string_view occurrence_key,
    std::vector<std::string> covered_reminder_ids) {
  if (!common::is_uuid(anniversary_id) || !common::is_uuid(occurrence_key) ||
      covered_reminder_ids.empty() || covered_reminder_ids.size() > 5U) {
    return common::Result<std::string>::failure(common::make_error(
        "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT",
        "Anniversary aggregate delivery does not match the frozen RecoveryBatch membership"));
  }
  std::sort(covered_reminder_ids.begin(), covered_reminder_ids.end());
  if (std::adjacent_find(covered_reminder_ids.begin(), covered_reminder_ids.end()) !=
      covered_reminder_ids.end() ||
      std::any_of(covered_reminder_ids.begin(), covered_reminder_ids.end(),
                  [](const auto& id) { return !common::is_uuid(id); })) {
    return common::Result<std::string>::failure(common::make_error(
        "ANNIVERSARY_AGGREGATE_MEMBERSHIP_CONFLICT",
        "Anniversary aggregate delivery does not match the frozen RecoveryBatch membership"));
  }
  std::string members = "[";
  for (std::size_t index = 0; index < covered_reminder_ids.size(); ++index) {
    if (index != 0U) members += ',';
    members += "\"" + covered_reminder_ids[index] + "\"";
  }
  members += ']';
  const std::string name = "[\"anniversary_catch_up\",\"" +
                           std::string(anniversary_id) + "\",\"" +
                           std::string(occurrence_key) + "\"," + members +
                           ",\"popup\"]";
  return common::generate_uuid_v5(kAnniversaryCatchUpDeliveryNamespace, name);
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
    target = anniversary_occurrence_in_year(anniversary_date, target_year);
    if (target < today) {
      target = anniversary_occurrence_in_year(anniversary_date, target_year + 1);
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
