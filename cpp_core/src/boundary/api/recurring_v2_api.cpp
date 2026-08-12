#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"

namespace excellent_calendar::boundary::api {

std::string initialize_recurring_runtime_v2_json(std::string_view request_json) {
  return initialize_runtime_v2_json(request_json);
}

std::string create_recurring_event_v2(std::string_view request_json) {
  return create_event_v2(request_json);
}

std::string update_recurring_event_v2(std::string_view request_json) {
  return update_event_v2(request_json);
}

std::string delete_recurring_event_v2(std::string_view request_json) {
  return delete_event_v2(request_json);
}

std::string get_recurring_event_detail_v2(std::string_view request_json) {
  return get_event_detail_v2(request_json);
}

std::string get_reminder_v2(std::string_view request_json) {
  return get_recurring_reminder_v2(request_json);
}

std::string list_schedulable_reminders_v2(std::string_view request_json) {
  return list_schedulable_recurring_reminders_v2(request_json);
}

std::string mark_reminder_scheduled_v2(std::string_view request_json) {
  return mark_recurring_reminder_scheduled_v2(request_json);
}

std::string prepare_reminder_delivery_v2(std::string_view request_json) {
  return prepare_recurring_reminder_delivery_v2(request_json);
}

std::string finalize_reminder_delivery_v2(std::string_view request_json) {
  return finalize_recurring_reminder_delivery_v2(request_json);
}

std::string plan_reminder_recovery_v2(std::string_view request_json) {
  return plan_recurring_reminder_recovery_v2(request_json);
}

}  // namespace excellent_calendar::boundary::api
