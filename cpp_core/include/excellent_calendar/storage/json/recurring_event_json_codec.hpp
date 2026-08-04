#pragma once

#include <string_view>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::storage::json {

common::Result<picojson::value> encode_recurring_event_store(
    std::string_view file_name,
    const repository::RecurringEventState& state);

common::Result<common::Unit> decode_recurring_event_store(
    std::string_view file_name,
    const picojson::value& root,
    repository::RecurringEventState& state);

common::Result<common::Unit> validate_recurring_event_state(
    const repository::RecurringEventState& state);

}  // namespace excellent_calendar::storage::json
