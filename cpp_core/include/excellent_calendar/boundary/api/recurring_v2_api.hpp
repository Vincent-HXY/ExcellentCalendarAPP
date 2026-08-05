#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

// Unified Contract v2 boundary. Existing names are retained as source-compatible wrappers.
std::string initialize_runtime_v2_json(std::string_view request_json);
std::string resolve_local_datetime_v2(std::string_view request_json);
std::string localize_instants_v2(std::string_view request_json);
std::string create_event_v2(std::string_view request_json);
std::string update_event_v2(std::string_view request_json);
std::string delete_event_v2(std::string_view request_json);
std::string search_events_v2(std::string_view request_json);
std::string get_event_detail_v2(std::string_view request_json);
std::string complete_event_v2(std::string_view request_json);
std::string reopen_event_v2(std::string_view request_json);

std::string initialize_recurring_runtime_v2_json(std::string_view request_json);
std::string create_recurring_event_v2(std::string_view request_json);
std::string update_recurring_event_v2(std::string_view request_json);
std::string delete_recurring_event_v2(std::string_view request_json);
std::string get_recurring_event_detail_v2(std::string_view request_json);
std::string list_event_occurrences_v2(std::string_view request_json);
std::string complete_event_occurrence_v2(std::string_view request_json);
std::string reopen_event_occurrence_v2(std::string_view request_json);
std::string skip_event_occurrence_v2(std::string_view request_json);
std::string cancel_event_occurrence_v2(std::string_view request_json);
std::string complete_event_series_v2(std::string_view request_json);
std::string reopen_event_series_v2(std::string_view request_json);
std::string cancel_event_series_v2(std::string_view request_json);
std::string list_schedulable_recurring_reminders_v2(std::string_view request_json);
std::string get_recurring_reminder_v2(std::string_view request_json);
std::string mark_recurring_reminder_scheduled_v2(std::string_view request_json);
std::string prepare_recurring_reminder_delivery_v2(std::string_view request_json);
std::string finalize_recurring_reminder_delivery_v2(std::string_view request_json);
std::string plan_recurring_reminder_recovery_v2(std::string_view request_json);

std::string create_reminder_v2(std::string_view request_json);
std::string update_reminder_v2(std::string_view request_json);
std::string cancel_reminder_v2(std::string_view request_json);
std::string list_reminders_v2(std::string_view request_json);
std::string enable_reminder_v2(std::string_view request_json);
std::string disable_reminder_v2(std::string_view request_json);

std::string get_reminder_v2(std::string_view request_json);
std::string list_schedulable_reminders_v2(std::string_view request_json);
std::string mark_reminder_scheduled_v2(std::string_view request_json);
std::string prepare_reminder_delivery_v2(std::string_view request_json);
std::string finalize_reminder_delivery_v2(std::string_view request_json);
std::string plan_reminder_recovery_v2(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
