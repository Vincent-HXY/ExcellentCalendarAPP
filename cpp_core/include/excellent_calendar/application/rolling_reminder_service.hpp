#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

class RollingReminderService {
 public:
  explicit RollingReminderService(std::shared_ptr<RecurrenceService> recurrence_service);

  common::Result<domain::Reminder> create_for_occurrence(
      const domain::EventOccurrence& occurrence,
      const domain::RecurringReminderDraft& draft,
      std::string created_at,
      std::optional<std::string> recovery_batch_id = std::nullopt,
      bool allow_past = false) const;

  common::Result<domain::Reminder> first_eligible_after(
      const domain::RecurringEventSchedule& event,
      const domain::Recurrence& recurrence,
      const domain::RecurringReminderDraft& draft,
      const std::vector<domain::EventOccurrenceState>& occurrence_states,
      std::string_view after_at,
      std::string created_at) const;

  domain::RecurringReminderDraft template_from(const domain::Reminder& reminder) const;

  common::Result<common::Unit> insert_idempotent(
      repository::RecurringEventState& state,
      const domain::Reminder& reminder) const;

  common::Result<common::Unit> ensure_next_in_state(
      repository::RecurringEventState& state,
      const domain::Event& event,
      const domain::Recurrence& recurrence,
      const domain::RecurringReminderDraft& draft,
      std::string after_at,
      const std::string& now) const;

 private:
  std::shared_ptr<RecurrenceService> recurrence_service_;
};

}  // namespace excellent_calendar::application
