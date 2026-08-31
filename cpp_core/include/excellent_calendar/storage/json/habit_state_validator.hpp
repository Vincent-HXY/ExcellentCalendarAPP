#pragma once

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"

namespace excellent_calendar::storage::json {

common::Result<common::Unit> validate_habit_state(
    const repository::HabitState& state);

}  // namespace excellent_calendar::storage::json
