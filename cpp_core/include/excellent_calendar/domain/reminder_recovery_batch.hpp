#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace excellent_calendar::domain {

inline constexpr std::string_view kRecoveryInProgress = "in_progress";
inline constexpr std::string_view kRecoveryCompleted = "completed";

struct ReminderRecoveryBatch {
  std::string id;
  std::string recovery_request_id;
  std::string trigger_source;
  std::string started_at;
  std::string window_start_at;
  std::vector<std::string> detail_reminder_ids;
  std::vector<std::string> summary_reminder_ids;
  int older_skipped_occurrence_count = 0;
  int older_skipped_reminder_count = 0;
  int window_overflow_count = 0;
  std::optional<std::string> summary_delivery_id;
  std::string status;
  std::optional<std::string> completed_at;
};

bool is_valid_recovery_trigger_source(std::string_view value);

}  // namespace excellent_calendar::domain
