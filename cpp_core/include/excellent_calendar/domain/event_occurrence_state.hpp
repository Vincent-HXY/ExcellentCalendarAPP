#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace excellent_calendar::domain {

inline constexpr std::string_view kOccurrenceScheduled = "scheduled";
inline constexpr std::string_view kOccurrenceCompleted = "completed";
inline constexpr std::string_view kOccurrenceSkipped = "skipped";
inline constexpr std::string_view kOccurrenceCancelled = "cancelled";

struct EventOccurrenceState {
  std::string event_id;
  int recurrence_revision = 1;
  std::string occurrence_key;
  std::optional<std::string> occurrence_start_at;
  std::optional<std::string> occurrence_start_date;
  std::string status;
  std::string state_changed_at;
  std::optional<std::string> reopened_at;
  std::string created_at;
  std::string updated_at;
};

bool is_valid_occurrence_status(std::string_view value);
bool is_terminal_occurrence_status(std::string_view value);

}  // namespace excellent_calendar::domain
