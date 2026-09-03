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

// Migration-only reader for the frozen v2 envelopes. Production repositories
// must use decode_recurring_event_store(), which accepts strict v3 roots only.
common::Result<common::Unit> decode_recurring_event_store_v2_for_migration(
    std::string_view file_name,
    const picojson::value& root,
    repository::RecurringEventState& state);

common::Result<common::Unit> validate_recurring_event_state(
    const repository::RecurringEventState& state);

// Calendar intentionally projects a narrow read-only slice. This validator
// checks only the Event/Recurrence/OccurrenceState/Event-Reminder relations
// available to that slice.
common::Result<common::Unit> validate_calendar_recurring_event_slice(
    const repository::RecurringEventState& state);

// Recovery ownership is target-agnostic. Call this with the unfiltered
// Calendar Reminder slice plus recovery batch identities, before target-
// specific structural validation removes non-Event reminders.
common::Result<common::Unit>
validate_calendar_reminder_recovery_references(
    const repository::RecurringEventState& state);

}  // namespace excellent_calendar::storage::json
