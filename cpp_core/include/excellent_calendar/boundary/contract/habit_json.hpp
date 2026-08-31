#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/habit_service.hpp"

namespace excellent_calendar::boundary::contract {

picojson::value habit_response_json(const domain::Habit& habit);
picojson::value habit_recurrence_response_json(
    const domain::HabitRecurrence& recurrence);
picojson::value habit_check_in_response_json(
    const domain::HabitCheckIn& check_in);
picojson::value habit_daily_status_response_json(
    const application::HabitDailyStatus& status);
picojson::value habit_statistics_response_json(
    const application::HabitStatistics& statistics);
picojson::value habit_reminder_settings_response_json(
    const application::HabitReminderSettings& settings);
picojson::value habit_detail_response_json(
    const application::HabitDetail& detail);
picojson::value habit_list_response_json(
    const application::HabitListPage& page);
picojson::value habit_mutation_commit_response_json(
    const application::HabitMutationCommit& result);
picojson::value habit_check_in_commit_response_json(
    const application::HabitCheckInCommit& result);
picojson::value habit_delete_commit_response_json(
    const application::HabitDeleteCommit& result);
picojson::value habit_daily_status_list_response_json(
    const application::HabitDailyStatusList& result);
picojson::value habit_reconcile_response_json(
    const application::ReconcileHabitRemindersResult& result);

}  // namespace excellent_calendar::boundary::contract
