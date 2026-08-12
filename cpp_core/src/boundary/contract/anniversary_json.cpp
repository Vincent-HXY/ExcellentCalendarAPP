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
