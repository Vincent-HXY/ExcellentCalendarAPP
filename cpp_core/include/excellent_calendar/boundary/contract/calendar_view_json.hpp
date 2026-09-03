#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/calendar_view_query_service.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value calendar_range_summary_response_json(
    const application::CalendarRangeSummary& response);

picojson::value calendar_day_item_page_json(
    const application::CalendarDayItemPage& page);

}  // namespace excellent_calendar::boundary::contract
