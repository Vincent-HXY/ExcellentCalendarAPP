#pragma once

#include <functional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"

namespace excellent_calendar::repository {

struct RecurringEventState {
  std::vector<domain::Event> events;
  std::vector<domain::Recurrence> recurrences;
  std::vector<domain::EventOccurrenceState> occurrence_states;
  std::vector<domain::Reminder> reminders;
  std::vector<domain::Notification> notifications;
  std::vector<domain::ReminderRecoveryBatch> recovery_batches;
};

class RecurringEventTransaction {
 public:
  using Operation = std::function<common::Result<common::Unit>(RecurringEventState&)>;
  using NotificationPrepareOperation = std::function<common::Result<common::Unit>(
      const RecurringEventState&, std::vector<domain::Notification>&)>;
  using ReminderUpdateOperation = std::function<common::Result<common::Unit>(
      const RecurringEventState&, std::vector<domain::Reminder>&)>;

  virtual ~RecurringEventTransaction() = default;

  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<RecurringEventState> load() = 0;
  virtual common::Result<common::Unit> prepare_notification(
      const NotificationPrepareOperation& action) = 0;
  /** Atomically replaces only reminders.json for a single-entity Reminder transition. */
  virtual common::Result<common::Unit> update_reminders(
      const ReminderUpdateOperation& action) = 0;
  virtual common::Result<common::Unit> execute(std::string_view operation,
                                               std::string transaction_id,
                                               std::string prepared_at,
                                               const Operation& action) = 0;
};

}  // namespace excellent_calendar::repository
