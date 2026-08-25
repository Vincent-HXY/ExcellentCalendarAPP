#pragma once

#include <functional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::repository {

struct AnniversaryState {
  std::vector<domain::Anniversary> anniversaries;
  std::vector<domain::AnniversaryRecurrence> recurrences;
  std::vector<domain::AnniversaryReminderTemplate> reminder_templates;
  std::vector<domain::Reminder> reminders;
};

struct AnniversaryOccurrenceSnapshot {
  AnniversaryState state;
  // Opaque token derived atomically from the authoritative generations of
  // every Store that contributes to the occurrence projection.
  std::string generation;
};

class AnniversaryTransaction {
 public:
  using Operation = std::function<common::Result<common::Unit>(AnniversaryState&)>;

  virtual ~AnniversaryTransaction() = default;

  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<AnniversaryState> load() = 0;
  virtual common::Result<AnniversaryOccurrenceSnapshot>
  load_occurrence_snapshot() = 0;
  virtual common::Result<common::Unit> execute(
      std::string_view operation,
      std::string transaction_id,
      std::string prepared_at,
      const Operation& action) = 0;
};

}  // namespace excellent_calendar::repository
