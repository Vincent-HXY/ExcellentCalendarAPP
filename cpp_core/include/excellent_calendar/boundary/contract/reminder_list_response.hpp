#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/reminder_service.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value reminder_list_response_to_json(const application::ReminderListResult& result);

}  // namespace excellent_calendar::boundary::contract
