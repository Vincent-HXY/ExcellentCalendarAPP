#include "excellent_calendar/boundary/contract/reminder_response.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value optional_string_to_json(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(*value);
}

picojson::value optional_int_to_json(const std::optional<int>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(static_cast<double>(*value));
}

}  // namespace

ReminderResponse make_reminder_response(const domain::Reminder& reminder) {
  ReminderResponse response;
  response.id = reminder.id;
  response.target_type = reminder.target_type;
  response.target_id = reminder.target_id;
  response.remind_at = reminder.remind_at;
  response.methods = reminder.methods;
  response.advance_minutes = reminder.advance_minutes;
  response.message = reminder.message;
  response.is_enabled = reminder.is_enabled;
  response.status = reminder.status;
  response.scheduled_at = reminder.scheduled_at;
  response.last_triggered_at = reminder.last_triggered_at;
  response.failure_reason = reminder.failure_reason;
  response.cancellation_reason = reminder.cancellation_reason;
  response.created_at = reminder.created_at;
  response.updated_at = reminder.updated_at;
  response.deleted_at = reminder.deleted_at;
  return response;
}

picojson::value reminder_response_to_json(const ReminderResponse& reminder) {
  picojson::array methods;
  methods.reserve(reminder.methods.size());
  for (const auto& method : reminder.methods) {
    methods.push_back(picojson::value(method));
  }

  picojson::object object;
  object["id"] = picojson::value(reminder.id);
  object["target_type"] = picojson::value(reminder.target_type);
  object["target_id"] = picojson::value(reminder.target_id);
  object["remind_at"] = picojson::value(reminder.remind_at);
  object["methods"] = picojson::value(std::move(methods));
  object["advance_minutes"] = optional_int_to_json(reminder.advance_minutes);
  object["message"] = optional_string_to_json(reminder.message);
  object["is_enabled"] = picojson::value(reminder.is_enabled);
  object["status"] = picojson::value(reminder.status);
  object["scheduled_at"] = optional_string_to_json(reminder.scheduled_at);
  object["last_triggered_at"] = optional_string_to_json(reminder.last_triggered_at);
  object["failure_reason"] = optional_string_to_json(reminder.failure_reason);
  object["cancellation_reason"] = optional_string_to_json(reminder.cancellation_reason);
  object["created_at"] = picojson::value(reminder.created_at);
  object["updated_at"] = picojson::value(reminder.updated_at);
  object["deleted_at"] = optional_string_to_json(reminder.deleted_at);
  return picojson::value(std::move(object));
}

picojson::value reminder_response_to_json(const domain::Reminder& reminder) {
  return reminder_response_to_json(make_reminder_response(reminder));
}

}  // namespace excellent_calendar::boundary::contract
