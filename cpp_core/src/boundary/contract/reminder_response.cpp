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

picojson::value reminder_response_to_json(const domain::Reminder& reminder) {
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
  object["created_at"] = picojson::value(reminder.created_at);
  object["updated_at"] = picojson::value(reminder.updated_at);
  object["deleted_at"] = optional_string_to_json(reminder.deleted_at);
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
