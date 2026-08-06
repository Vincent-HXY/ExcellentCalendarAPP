#pragma once

#include <optional>
#include <string>

#include <picojson/picojson.h>

#include "excellent_calendar/domain/notification.hpp"

namespace excellent_calendar::boundary::contract {

struct NotificationResponse {
  std::string id;
  std::optional<std::string> reminder_id;
  std::string target_type;
  std::string target_id;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::optional<std::string> sent_at;
  std::string status;
  std::optional<std::string> failure_reason;
  std::string created_at;
  std::string updated_at;
};

NotificationResponse make_notification_response(const domain::Notification& notification);

picojson::value notification_response_to_json(const NotificationResponse& response);

}  // namespace excellent_calendar::boundary::contract
