#include "excellent_calendar/boundary/contract/anniversary_json.hpp"

#include <optional>
#include <utility>

#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value nullable(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

}  // namespace

picojson::value anniversary_response_json(const domain::Anniversary& anniversary) {
  picojson::object data;
  data["id"] = picojson::value(anniversary.id);
  data["title"] = picojson::value(anniversary.title);
  data["date"] = picojson::value(domain::format_local_date(anniversary.date));
  data["calendar_type"] = picojson::value(anniversary.calendar_type);
  data["category_id"] = nullable(anniversary.category_id);
  data["recurrence_id"] = nullable(anniversary.recurrence_id);
  data["note"] = nullable(anniversary.note);
  data["importance"] = nullable(anniversary.importance);
  data["created_at"] = picojson::value(anniversary.created_at);
  data["updated_at"] = picojson::value(anniversary.updated_at);
  data["deleted_at"] = nullable(anniversary.deleted_at);
  return picojson::value(std::move(data));
}

picojson::value anniversary_recurrence_response_json(
    const domain::AnniversaryRecurrence& recurrence) {
  picojson::object data;
  data["recurrence_id"] = picojson::value(recurrence.id);
  data["frequency"] = picojson::value(recurrence.frequency);
  data["interval"] = picojson::value(static_cast<double>(recurrence.interval));
  return picojson::value(std::move(data));
}

picojson::value anniversary_countdown_response_json(
    const domain::AnniversaryCountdown& countdown) {
  picojson::object data;
  data["relation"] = picojson::value(countdown.relation);
  data["days"] = picojson::value(static_cast<double>(countdown.days));
  data["target_occurrence_date"] =
      picojson::value(domain::format_local_date(countdown.target_occurrence_date));
  data["iso_weekday"] = picojson::value(static_cast<double>(countdown.iso_weekday));
  data["timezone"] = picojson::value(countdown.timezone);
  data["calculated_at"] = picojson::value(countdown.calculated_at);
  return picojson::value(std::move(data));
}

picojson::value anniversary_detail_response_json(
    const application::AnniversaryDetail& detail) {
  picojson::object data;
  data["anniversary"] = anniversary_response_json(detail.anniversary);
  data["recurrence"] = detail.recurrence.has_value()
                           ? anniversary_recurrence_response_json(*detail.recurrence)
                           : picojson::value();
  data["countdown"] = anniversary_countdown_response_json(detail.countdown);
  data["reminder_settings"] =
      anniversary_reminder_settings_response_json(detail.reminder_settings);
  return picojson::value(std::move(data));
}

picojson::value anniversary_reminder_settings_response_json(
    const application::AnniversaryReminderSettings& settings) {
  picojson::array templates;
  for (const auto& item : settings.templates) {
    picojson::object value;
    value["template_key"] = picojson::value(item.template_key);
    value["advance_days"] = picojson::value(static_cast<double>(item.advance_days));
    value["local_time"] = picojson::value(item.local_time);
    value["timezone_mode"] = picojson::value(item.timezone_mode);
    value["method"] = picojson::value(item.method);
    value["is_enabled"] = picojson::value(item.is_enabled);
    templates.emplace_back(std::move(value));
  }
  picojson::object data;
  data["reminders_enabled"] = picojson::value(settings.reminders_enabled);
  data["templates"] = picojson::value(std::move(templates));
  data["active_reminder_count"] =
      picojson::value(static_cast<double>(settings.active_reminder_count));
  data["schedule_reconciliation_required"] =
      picojson::value(settings.schedule_reconciliation_required);
  return picojson::value(std::move(data));
}

picojson::value anniversary_occurrence_list_response_json(
    const application::AnniversaryOccurrencePage& page) {
  picojson::array items;
  for (const auto& item : page.items) {
    picojson::object value;
    value["anniversary_id"] = picojson::value(item.anniversary_id);
    value["occurrence_key"] = picojson::value(item.occurrence_key);
    value["occurrence_date"] = picojson::value(domain::format_local_date(item.occurrence_date));
    value["source_date"] = picojson::value(domain::format_local_date(item.source_date));
    value["title"] = picojson::value(item.title);
    value["calendar_type"] = picojson::value(item.calendar_type);
    value["is_repeating"] = picojson::value(item.is_repeating);
    value["years_elapsed"] = picojson::value(static_cast<double>(item.years_elapsed));
    value["category_id"] = nullable(item.category_id);
    value["importance"] = nullable(item.importance);
    value["has_active_reminders"] = picojson::value(item.has_active_reminders);
    value["reminder_count"] = picojson::value(static_cast<double>(item.reminder_count));
    items.emplace_back(std::move(value));
  }
  picojson::object data;
  data["items"] = picojson::value(std::move(items));
  data["has_more"] = picojson::value(page.has_more);
  data["next_cursor"] = nullable(page.next_cursor);
  return picojson::value(std::move(data));
}

picojson::value anniversary_delete_commit_response_json(
    const application::AnniversaryDeleteResult& result) {
  picojson::object data;
  data["anniversary"] = anniversary_response_json(result.anniversary);
  data["schedule_reconciliation_required"] =
      picojson::value(result.schedule_reconciliation_required);
  return picojson::value(std::move(data));
}

picojson::value anniversary_list_response_json(
    const application::AnniversaryListPage& page) {
  picojson::array items;
  items.reserve(page.items.size());
  for (const auto& item : page.items) {
    picojson::object summary;
    summary["anniversary"] = anniversary_response_json(item.anniversary);
    summary["countdown"] = anniversary_countdown_response_json(item.countdown);
    items.emplace_back(std::move(summary));
  }
  picojson::object pagination;
  pagination["total"] = picojson::value(static_cast<double>(page.total));
  pagination["page"] = picojson::value(static_cast<double>(page.page));
  pagination["page_size"] = picojson::value(static_cast<double>(page.page_size));
  pagination["has_more"] = picojson::value(page.has_more);
  pagination["next_cursor"] = nullable(page.next_cursor);
  picojson::object data;
  data["items"] = picojson::value(std::move(items));
  data["pagination"] = picojson::value(std::move(pagination));
  return picojson::value(std::move(data));
}

}  // namespace excellent_calendar::boundary::contract
