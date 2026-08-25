#pragma once

#include <cstddef>
#include <memory>
#include <optional>
#include <string>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

common::Result<std::string> anniversary_occurrence_cutoff_utc(
    const domain::Reminder& reminder,
    const std::string& timezone,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver);

common::Result<std::size_t> reproject_open_anniversary_reminders(
    repository::RecurringEventState& state,
    const std::string& timezone,
    const std::string& now,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver);

common::Result<std::optional<domain::Reminder>> ensure_anniversary_successor(
    repository::RecurringEventState& state,
    const domain::Reminder& source,
    const std::string& timezone,
    const std::string& now,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver);

std::optional<domain::Reminder> find_persisted_anniversary_successor(
    const repository::RecurringEventState& state,
    const domain::Reminder& source);

}  // namespace excellent_calendar::application
