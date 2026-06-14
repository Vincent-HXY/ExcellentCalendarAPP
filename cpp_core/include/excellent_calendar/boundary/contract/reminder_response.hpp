#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value reminder_response_to_json(const domain::Reminder& reminder);

}  // namespace excellent_calendar::boundary::contract
