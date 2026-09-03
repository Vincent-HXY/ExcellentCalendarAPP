#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/search_query_service.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value search_query_response_json(
    const application::SearchQueryResponse& response);

}  // namespace excellent_calendar::boundary::contract
