#include "excellent_calendar/boundary/api/calendar_view_api.hpp"

#include <optional>
#include <set>
#include <string>
#include <utility>

#include <picojson/picojson.h>

#include "excellent_calendar/application/calendar_view_query_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/calendar_view_json.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "recurring_v2_api_internal.hpp"

namespace excellent_calendar::boundary::api {
namespace {

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

common::Result<domain::LocalDate> required_date(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto value = detail::require_string(object, key, parent);
  if (!value.ok()) return fail<domain::LocalDate>(value.error());
  auto parsed = domain::parse_local_date(value.value());
  return parsed.ok()
             ? parsed
             : fail<domain::LocalDate>(detail::contract_error(
                   parent + "." + key,
                   "date must be a valid YYYY-MM-DD value"));
}

common::Result<std::string> required_timezone(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto value = detail::require_string(object, key, parent);
  if (!value.ok()) return value;
  return value.value().size() <= 255U
             ? value
             : fail<std::string>(detail::contract_error(
                   parent + "." + key,
                   "timezone must contain at most 255 characters"));
}

common::Result<application::CalendarRangeSummaryQuery> parse_range_query(
    const picojson::object& object) {
  constexpr const char* parent = "CalendarRangeSummaryRequest";
  auto known = detail::reject_unknown(
      object, {"range_start_date", "range_end_date", "timezone"}, parent);
  if (!known.ok())
    return fail<application::CalendarRangeSummaryQuery>(known.error());
  auto start = required_date(object, "range_start_date", parent);
  auto end = required_date(object, "range_end_date", parent);
  auto timezone = required_timezone(object, "timezone", parent);
  if (!start.ok())
    return fail<application::CalendarRangeSummaryQuery>(start.error());
  if (!end.ok())
    return fail<application::CalendarRangeSummaryQuery>(end.error());
  if (!timezone.ok())
    return fail<application::CalendarRangeSummaryQuery>(timezone.error());
  return common::Result<application::CalendarRangeSummaryQuery>::success(
      {start.value(), end.value(), timezone.value()});
}

common::Result<application::CalendarSection> parse_section(
    const picojson::object& object, const std::string& parent) {
  auto value = detail::require_string(object, "section", parent);
  if (!value.ok()) return fail<application::CalendarSection>(value.error());
  if (value.value() == "event") {
    return common::Result<application::CalendarSection>::success(
        application::CalendarSection::event);
  }
  if (value.value() == "habit") {
    return common::Result<application::CalendarSection>::success(
        application::CalendarSection::habit);
  }
  if (value.value() == "anniversary") {
    return common::Result<application::CalendarSection>::success(
        application::CalendarSection::anniversary);
  }
  return fail<application::CalendarSection>(detail::contract_error(
      parent + ".section", "section enum value is unknown"));
}

common::Result<application::CalendarListDayItemsQuery>
parse_list_day_items_query(const picojson::object& object) {
  constexpr const char* parent = "CalendarListDayItemsRequest";
  auto known = detail::reject_unknown(
      object,
      {"date", "timezone", "section", "snapshot_token", "cursor",
       "page_size"},
      parent);
  if (!known.ok())
    return fail<application::CalendarListDayItemsQuery>(known.error());
  auto date = required_date(object, "date", parent);
  auto timezone = required_timezone(object, "timezone", parent);
  auto section = parse_section(object, parent);
  auto snapshot = detail::require_string(object, "snapshot_token", parent);
  auto cursor = detail::nullable_string(object, "cursor", parent, true);
  auto page_size = detail::require_int(object, "page_size", parent);
  if (!date.ok())
    return fail<application::CalendarListDayItemsQuery>(date.error());
  if (!timezone.ok())
    return fail<application::CalendarListDayItemsQuery>(timezone.error());
  if (!section.ok())
    return fail<application::CalendarListDayItemsQuery>(section.error());
  if (!snapshot.ok())
    return fail<application::CalendarListDayItemsQuery>(snapshot.error());
  if (!cursor.ok())
    return fail<application::CalendarListDayItemsQuery>(cursor.error());
  if (!page_size.ok())
    return fail<application::CalendarListDayItemsQuery>(page_size.error());
  return common::Result<application::CalendarListDayItemsQuery>::success(
      {date.value(), timezone.value(), section.value(), snapshot.value(),
       cursor.value(), page_size.value()});
}

}  // namespace

std::string calendar_range_summary_v2(std::string_view request_json) {
  return detail::respond_v2([&]() -> common::Result<picojson::value> {
    auto object = detail::parse_object(request_json);
    if (!object.ok()) return fail<picojson::value>(object.error());
    auto query = parse_range_query(object.value());
    if (!query.ok()) return fail<picojson::value>(query.error());
    auto service = current_calendar_view_query_service();
    if (!service) {
      return fail<picojson::value>(
          storage_not_initialized_error("calendar.range_summary"));
    }
    auto result = service->range_summary(query.value());
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::calendar_range_summary_response_json(
                         result.value()))
               : fail<picojson::value>(result.error());
  });
}

std::string calendar_list_day_items_v2(std::string_view request_json) {
  return detail::respond_v2([&]() -> common::Result<picojson::value> {
    auto object = detail::parse_object(request_json);
    if (!object.ok()) return fail<picojson::value>(object.error());
    auto query = parse_list_day_items_query(object.value());
    if (!query.ok()) return fail<picojson::value>(query.error());
    auto service = current_calendar_view_query_service();
    if (!service) {
      return fail<picojson::value>(
          storage_not_initialized_error("calendar.list_day_items"));
    }
    auto result = service->list_day_items(query.value());
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::calendar_day_item_page_json(result.value()))
               : fail<picojson::value>(result.error());
  });
}

}  // namespace excellent_calendar::boundary::api
