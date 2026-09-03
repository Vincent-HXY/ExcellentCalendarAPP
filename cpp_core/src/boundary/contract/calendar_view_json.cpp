#include "excellent_calendar/boundary/contract/calendar_view_json.hpp"

#include <optional>
#include <string>
#include <utility>

#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value nullable(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value nullable(const std::optional<int>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

picojson::value nullable(const std::optional<std::int64_t>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

picojson::value nullable(const std::optional<domain::LocalDate>& value) {
  return value.has_value()
             ? picojson::value(domain::format_local_date(*value))
             : picojson::value();
}

picojson::value event_item_json(
    const application::CalendarEventItem& item) {
  picojson::object value;
  value["event_id"] = picojson::value(item.event_id);
  value["title"] = picojson::value(item.title);
  value["is_all_day"] = picojson::value(item.is_all_day);
  value["is_recurring"] = picojson::value(item.is_recurring);
  value["recurrence_revision"] = nullable(item.recurrence_revision);
  value["occurrence_key"] = nullable(item.occurrence_key);
  value["occurrence_start_at"] = nullable(item.occurrence_start_at);
  value["occurrence_start_date"] = nullable(item.occurrence_start_date);
  value["start_at"] = nullable(item.start_at);
  value["end_at"] = nullable(item.end_at);
  value["start_date"] = nullable(item.start_date);
  value["end_date"] = nullable(item.end_date);
  value["day_display"] = picojson::value(item.day_display);
  value["display_local_time"] = nullable(item.display_local_time);
  value["status"] = picojson::value(item.status);
  value["has_active_reminder"] = picojson::value(item.has_active_reminder);
  return picojson::value(std::move(value));
}

picojson::value habit_item_json(
    const application::CalendarHabitItem& item) {
  picojson::object value;
  value["habit_id"] = picojson::value(item.habit_id);
  value["date"] = picojson::value(domain::format_local_date(item.date));
  value["title"] = picojson::value(item.title);
  value["status"] = picojson::value(item.status);
  value["check_in_id"] = nullable(item.check_in_id);
  value["completed_count_hundredths"] =
      nullable(item.completed_count_hundredths);
  value["target_count_hundredths"] =
      nullable(item.target_count_hundredths);
  value["unit"] = nullable(item.unit);
  value["has_active_reminder"] = picojson::value(item.has_active_reminder);
  return picojson::value(std::move(value));
}

picojson::value anniversary_item_json(
    const application::CalendarAnniversaryItem& item) {
  picojson::object value;
  value["anniversary_id"] = picojson::value(item.anniversary_id);
  value["occurrence_key"] = picojson::value(item.occurrence_key);
  value["occurrence_date"] =
      picojson::value(domain::format_local_date(item.occurrence_date));
  value["source_date"] =
      picojson::value(domain::format_local_date(item.source_date));
  value["title"] = picojson::value(item.title);
  value["is_repeating"] = picojson::value(item.is_repeating);
  value["years_elapsed"] =
      picojson::value(static_cast<double>(item.years_elapsed));
  value["importance"] = nullable(item.importance);
  value["has_active_reminder"] = picojson::value(item.has_active_reminder);
  return picojson::value(std::move(value));
}

}  // namespace

picojson::value calendar_range_summary_response_json(
    const application::CalendarRangeSummary& response) {
  picojson::array days;
  days.reserve(response.days.size());
  for (const auto& item : response.days) {
    picojson::object day;
    day["date"] = picojson::value(domain::format_local_date(item.date));
    day["has_open_event"] = picojson::value(item.has_open_event);
    day["has_pending_habit"] = picojson::value(item.has_pending_habit);
    day["has_anniversary"] = picojson::value(item.has_anniversary);
    days.emplace_back(std::move(day));
  }
  picojson::object data;
  data["range_start_date"] =
      picojson::value(domain::format_local_date(response.range_start_date));
  data["range_end_date"] =
      picojson::value(domain::format_local_date(response.range_end_date));
  data["timezone"] = picojson::value(response.timezone);
  data["snapshot_token"] = picojson::value(response.snapshot_token);
  data["days"] = picojson::value(std::move(days));
  return picojson::value(std::move(data));
}

picojson::value calendar_day_item_page_json(
    const application::CalendarDayItemPage& page) {
  picojson::array items;
  items.reserve(page.items.size());
  for (const auto& item : page.items) {
    if (const auto* event =
            std::get_if<application::CalendarEventItem>(&item)) {
      items.push_back(event_item_json(*event));
    } else if (const auto* habit =
                   std::get_if<application::CalendarHabitItem>(&item)) {
      items.push_back(habit_item_json(*habit));
    } else {
      items.push_back(anniversary_item_json(
          std::get<application::CalendarAnniversaryItem>(item)));
    }
  }
  picojson::object data;
  data["date"] = picojson::value(domain::format_local_date(page.date));
  data["timezone"] = picojson::value(page.timezone);
  data["section"] =
      picojson::value(application::calendar_section_to_string(page.section));
  data["snapshot_token"] = picojson::value(page.snapshot_token);
  data["page_size"] = picojson::value(static_cast<double>(page.page_size));
  data["items"] = picojson::value(std::move(items));
  data["has_more"] = picojson::value(page.has_more);
  data["next_cursor"] = nullable(page.next_cursor);
  return picojson::value(std::move(data));
}

}  // namespace excellent_calendar::boundary::contract
