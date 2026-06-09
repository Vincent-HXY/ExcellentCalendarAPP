#include "excellent_calendar/boundary/contract/event_response.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value optional_string_to_json(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(*value);
}

}  // namespace

picojson::value event_response_to_json(const domain::Event& event) {
  picojson::object object;
  object["id"] = picojson::value(event.id);
  object["title"] = picojson::value(event.title);
  object["content"] = optional_string_to_json(event.content);
  object["start_at"] = picojson::value(event.start_at);
  object["end_at"] = picojson::value(event.end_at);
  object["is_all_day"] = picojson::value(event.is_all_day);
  object["has_recurrence"] = picojson::value(event.has_recurrence);
  object["status"] = picojson::value(event.status);
  object["completed_at"] = optional_string_to_json(event.completed_at);
  object["recurrence_id"] = optional_string_to_json(event.recurrence_id);
  object["category_id"] = optional_string_to_json(event.category_id);
  object["importance"] = optional_string_to_json(event.importance);
  object["location"] = optional_string_to_json(event.location);
  object["timezone"] = optional_string_to_json(event.timezone);
  object["source"] = picojson::value(event.source);
  object["created_at"] = picojson::value(event.created_at);
  object["updated_at"] = picojson::value(event.updated_at);
  object["deleted_at"] = optional_string_to_json(event.deleted_at);
  return picojson::value(object);
}

}  // namespace excellent_calendar::boundary::contract
