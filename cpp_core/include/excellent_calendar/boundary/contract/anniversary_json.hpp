#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/anniversary_types.hpp"
#include "excellent_calendar/domain/anniversary.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value anniversary_response_json(const domain::Anniversary& anniversary);

picojson::value anniversary_recurrence_response_json(
    const domain::AnniversaryRecurrence& recurrence);

picojson::value anniversary_countdown_response_json(
    const domain::AnniversaryCountdown& countdown);

picojson::value anniversary_detail_response_json(
    const application::AnniversaryDetail& detail);

picojson::value anniversary_list_response_json(
    const application::AnniversaryListPage& page);

}  // namespace excellent_calendar::boundary::contract
