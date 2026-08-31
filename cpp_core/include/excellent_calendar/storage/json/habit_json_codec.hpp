#pragma once

#include <string_view>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"

namespace excellent_calendar::storage::json {

inline constexpr std::string_view kHabitRecurrencesStoreFile =
    "habit_recurrences.json";
inline constexpr std::string_view kHabitsStoreFile = "habits.json";
inline constexpr std::string_view kHabitCheckInsStoreFile =
    "habit_check_ins.json";
inline constexpr std::string_view kHabitReminderTemplatesStoreFile =
    "habit_reminder_templates.json";

common::Result<picojson::value> encode_habit_store(
    std::string_view file_name,
    const repository::HabitState& state);
common::Result<common::Unit> decode_habit_store(
    std::string_view file_name,
    const picojson::value& root,
    repository::HabitState& state);

}  // namespace excellent_calendar::storage::json
