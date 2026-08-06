#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace excellent_calendar::domain {

inline constexpr std::string_view kNotificationStatusPending = "pending";
inline constexpr std::string_view kNotificationStatusSent = "sent";
inline constexpr std::string_view kNotificationStatusFailed = "failed";
inline constexpr std::string_view kNotificationStatusCancelled = "cancelled";

struct Notification {
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

bool is_valid_notification_status(std::string_view value);

bool is_valid_notification_target_type(std::string_view value);

}  // namespace excellent_calendar::domain
