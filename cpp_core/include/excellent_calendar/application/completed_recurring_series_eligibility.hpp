#pragma once

#include <optional>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/recurrence.hpp"

namespace excellent_calendar::application {

/**
 * Returns the completed-at cutoff as a recurrence-timezone local date for
 * bounded occurrence seeking. Non-completed series have no cutoff.
 */
common::Result<std::optional<domain::LocalDate>>
completed_recurring_series_cutoff_local_date(
    const domain::Event& event, const domain::Recurrence& recurrence,
    const domain::LocalTimeResolver& resolver);

/**
 * Calendar/Search shared occurrence-existence rule for completed recurring
 * Event series. A timed occurrence uses occurrence_start_at; an all-day
 * occurrence uses recurrence-timezone local midnight. The anchor must be
 * strictly earlier than Event.completed_at.
 */
common::Result<bool> completed_recurring_series_occurrence_is_eligible(
    const domain::Event& event, const domain::EventOccurrence& occurrence,
    const domain::Recurrence& recurrence,
    const domain::LocalTimeResolver& resolver);

}  // namespace excellent_calendar::application
