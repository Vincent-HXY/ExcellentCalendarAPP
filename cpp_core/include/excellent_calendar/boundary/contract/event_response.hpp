#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/domain/event.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value event_response_to_json(const domain::Event& event);

}  // namespace excellent_calendar::boundary::contract
