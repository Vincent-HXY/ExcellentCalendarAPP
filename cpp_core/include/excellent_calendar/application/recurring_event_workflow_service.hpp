#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

template <typename T>
struct FieldPatch {
  bool supplied = false;
  T value{};
};

struct EventTimeReplacement {
  std::optional<std::string> start_at;
  std::optional<std::string> end_at;
  std::optional<std::string> start_date;
  std::optional<std::string> end_date;
  bool is_all_day = false;
  std::string timezone;
};

/** Boundary-neutral embedded Reminder input. Core selects ordinary/template rules
 * after loading the target Event in the workflow transaction. */
struct EventReminderDraftInput {
  std::string target_type;
  std::optional<std::string> target_id;
  std::optional<std::string> remind_at;
  std::optional<int> advance_minutes;
  std::vector<std::string> methods;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string source;
  // Presence is part of the Contract shape. In particular, recurring templates
  // forbid remind_at and require advance_minutes plus an explicitly supplied
  // (possibly null) message.
  bool remind_at_supplied = false;
  bool advance_minutes_supplied = false;
  bool message_supplied = false;
};

struct CreateEventV2Command {
  domain::Event event;
  std::optional<domain::EventRecurrenceRuleInput> recurrence;
  std::vector<EventReminderDraftInput> reminders;
};

struct CreateRecurringEventCommand {
  domain::Event event;
  domain::EventRecurrenceRuleInput recurrence;
  std::vector<domain::RecurringReminderDraft> reminders;
};

struct UpdateRecurringEventSeriesCommand {
  std::string event_id;
  FieldPatch<std::optional<int>> expected_recurrence_revision;
  FieldPatch<std::string> title;
  FieldPatch<std::optional<std::string>> content;
  FieldPatch<std::optional<std::string>> category_id;
  FieldPatch<std::optional<std::string>> importance;
  FieldPatch<std::optional<std::string>> location;
  FieldPatch<std::string> source;
  FieldPatch<EventTimeReplacement> time;
  FieldPatch<domain::EventRecurrenceRuleInput> recurrence;
  FieldPatch<std::vector<EventReminderDraftInput>> reminders;
};

using UpdateEventV2Command = UpdateRecurringEventSeriesCommand;

struct DeleteEventV2Command {
  std::string event_id;
  std::string delete_mode;
  std::optional<std::string> recurrence_delete_scope;
  std::optional<int> expected_recurrence_revision;
  std::optional<std::string> reason;
};

struct CompleteEventV2Command {
  std::string event_id;
  std::string source;
  std::optional<std::string> note;
};

struct ReopenEventV2Command {
  std::string event_id;
};

struct OccurrenceOperationCommand {
  std::string event_id;
  int recurrence_revision = 0;
  std::string occurrence_key;
  std::optional<std::string> occurrence_start_at;
  std::optional<std::string> occurrence_start_date;
};

struct SeriesOperationCommand {
  std::string event_id;
  int recurrence_revision = 0;
};

struct DeleteRecurringSeriesCommand {
  std::string event_id;
  int recurrence_revision = 0;
  std::string delete_mode;
  std::string recurrence_delete_scope;
};

class RecurringEventWorkflowService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  RecurringEventWorkflowService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      std::shared_ptr<RecurrenceService> recurrence_service,
      std::shared_ptr<RollingReminderService> rolling_reminder_service,
      ClockFn clock,
      IdGeneratorFn id_generator);

  /** Unified Contract v2 Event entry points (ordinary and recurring). */
  common::Result<domain::Event> create_event(const CreateEventV2Command& command);
  common::Result<domain::Event> update_event(const UpdateEventV2Command& command);
  common::Result<domain::Event> delete_event(const DeleteEventV2Command& command);
  common::Result<domain::Event> complete_event(const CompleteEventV2Command& command);
  common::Result<domain::Event> reopen_event(const ReopenEventV2Command& command);

  common::Result<domain::Event> create_series(const CreateRecurringEventCommand& command);
  common::Result<domain::Event> update_series(const UpdateRecurringEventSeriesCommand& command);

  common::Result<domain::EventOccurrenceState> complete_occurrence(
      const OccurrenceOperationCommand& command);
  common::Result<domain::EventOccurrenceState> reopen_occurrence(
      const OccurrenceOperationCommand& command);
  common::Result<domain::EventOccurrenceState> skip_occurrence(
      const OccurrenceOperationCommand& command);
  common::Result<domain::EventOccurrenceState> cancel_occurrence(
      const OccurrenceOperationCommand& command);

  common::Result<domain::Event> complete_series(const SeriesOperationCommand& command);
  common::Result<domain::Event> reopen_series(const SeriesOperationCommand& command);
  common::Result<domain::Event> cancel_series(const SeriesOperationCommand& command);
  common::Result<domain::Event> delete_series(const DeleteRecurringSeriesCommand& command);

 private:
  common::Result<domain::EventOccurrenceState> transition_occurrence(
      const OccurrenceOperationCommand& command,
      std::string target_status,
      std::string cancellation_reason);

  common::Result<domain::Event> transition_series(
      const SeriesOperationCommand& command,
      std::string target_status,
      std::string cancellation_reason,
      bool reopen);

  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  std::shared_ptr<RecurrenceService> recurrence_service_;
  std::shared_ptr<RollingReminderService> rolling_reminder_service_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
