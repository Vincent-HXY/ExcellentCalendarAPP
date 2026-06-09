#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/event_service.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value event_list_response_to_json(const application::EventSearchResult& result);

}  // namespace excellent_calendar::boundary::contract
