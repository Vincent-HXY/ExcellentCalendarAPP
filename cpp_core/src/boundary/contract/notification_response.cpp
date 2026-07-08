#include "excellent_calendar/boundary/contract/notification_response.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value optional_to_json(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

}  // namespace

NotificationResponse make_notification_response(const domain::Notification& notification) {
  NotificationResponse response;
  response.id = notification.id;
  response.reminder_id = notification.reminder_id;
  response.target_type = notification.target_type;
  response.target_id = notification.target_id;
  response.method = notification.method;
  response.title = notification.title;
  response.body = notification.body;
  response.planned_at = notification.planned_at;
  response.sent_at = notification.sent_at;
  response.status = notification.status;
  response.failure_reason = notification.failure_reason;
  response.created_at = notification.created_at;
  response.updated_at = notification.updated_at;
  return response;
}

picojson::value notification_response_to_json(const NotificationResponse& response) {
  picojson::object object;
  object["id"] = picojson::value(response.id);
  object["reminder_id"] = optional_to_json(response.reminder_id);
  object["target_type"] = picojson::value(response.target_type);
  object["target_id"] = picojson::value(response.target_id);
  object["method"] = picojson::value(response.method);
  object["title"] = picojson::value(response.title);
  object["body"] = optional_to_json(response.body);
  object["planned_at"] = picojson::value(response.planned_at);
  object["sent_at"] = optional_to_json(response.sent_at);
  object["status"] = picojson::value(response.status);
  object["failure_reason"] = optional_to_json(response.failure_reason);
  object["created_at"] = picojson::value(response.created_at);
  object["updated_at"] = picojson::value(response.updated_at);
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
