#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace excellent_calendar::domain {

inline constexpr std::string_view kNotificationStatusPending = "pending";
inline constexpr std::string_view kNotificationStatusPrepared = "prepared";
inline constexpr std::string_view kNotificationStatusSent = "sent";
inline constexpr std::string_view kNotificationStatusFailed = "failed";
inline constexpr std::string_view kNotificationStatusCancelled = "cancelled";
inline constexpr std::string_view kNotificationStatusAbandoned = "abandoned";

struct Notification {
  std::string id;
  std::optional<std::string> delivery_id;
  std::optional<std::string> delivery_attempt_id;
  std::string kind = "reminder";
  std::optional<std::string> reminder_id;
  std::optional<std::string> recovery_batch_id;
  std::string target_type;
  std::string target_id;
  std::optional<std::string> occurrence_key;
  std::string method;
  std::string title;
  std::optional<std::string> body;
  std::string planned_at;
  std::optional<std::string> prepared_at;
  std::optional<std::string> finalized_at;
  std::optional<std::string> sent_at;
  std::string status;
  std::optional<std::string> failure_class;
  std::optional<std::string> error_code;
  std::optional<std::string> failure_reason;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> resolved_by_recovery_batch_id;
  std::optional<std::string> abandon_reason;
};

bool is_valid_notification_status(std::string_view value);

bool is_valid_notification_target_type(std::string_view value);

}  // namespace excellent_calendar::domain
