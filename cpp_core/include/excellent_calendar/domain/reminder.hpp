#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace excellent_calendar::domain {

inline constexpr std::string_view kReminderTargetEvent = "event";
inline constexpr std::string_view kReminderTargetHabit = "habit";
inline constexpr std::string_view kReminderTargetAnniversary = "anniversary";

inline constexpr std::string_view kReminderMethodRing = "ring";
inline constexpr std::string_view kReminderMethodPopup = "popup";
inline constexpr std::string_view kReminderMethodWechat = "wechat";

inline constexpr std::string_view kReminderStatusPending = "pending";
inline constexpr std::string_view kReminderStatusScheduled = "scheduled";
inline constexpr std::string_view kReminderStatusSent = "sent";
inline constexpr std::string_view kReminderStatusFailed = "failed";
inline constexpr std::string_view kReminderStatusCancelled = "cancelled";

inline constexpr std::string_view kReminderCancellationReasonUserCancelled = "user_cancelled";
inline constexpr std::string_view kReminderCancellationReasonEventCompleted = "event_completed";

struct Reminder {
  std::string id;
  std::string target_type;
  std::string target_id;
  std::string remind_at;
  std::vector<std::string> methods;
  std::optional<int> advance_minutes;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string status;
  std::optional<std::string> scheduled_at;
  std::optional<std::string> last_triggered_at;
  std::optional<std::string> failure_reason;
  std::optional<std::string> cancellation_reason;
  std::string source;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

bool is_valid_reminder_target_type(std::string_view value);

bool is_supported_reminder_target_type(std::string_view value);

bool is_valid_reminder_method(std::string_view value);

bool is_valid_reminder_status(std::string_view value);

bool is_valid_reminder_cancellation_reason(std::string_view value);

bool is_valid_reminder_source(std::string_view value);

}  // namespace excellent_calendar::domain
