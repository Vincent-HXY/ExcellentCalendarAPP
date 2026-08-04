#include "excellent_calendar/application/recurring_event_workflow_service.hpp"

#include <algorithm>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <tuple>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::application {
namespace {

constexpr int kMaximumExpansionCount = 1000000;

common::Error event_not_found(const std::string& id) {
  return common::make_error("EVENT_NOT_FOUND", "Event not found", {{"event_id", id}});
}

common::Error occurrence_not_found(const std::string& key) {
  return common::make_error(
      "OCCURRENCE_NOT_FOUND", "Occurrence does not exist in the requested recurrence revision",
      {{"occurrence_key", key}});
}

common::Error occurrence_invalid(std::string reason) {
  return common::make_error(
      "OCCURRENCE_OPERATION_INVALID", "Occurrence state transition is invalid",
      {{"reason", std::move(reason)}});
}

common::Error revision_conflict(int expected, int actual) {
  return common::make_error(
      "RECURRENCE_REVISION_CONFLICT",
      "Expected recurrence revision does not match the Event current revision",
      {{"expected", std::to_string(expected)}, {"actual", std::to_string(actual)}});
}

common::Error revision_conflict(const std::optional<int>& expected, int actual) {
  return common::make_error(
      "RECURRENCE_REVISION_CONFLICT",
      "Expected recurrence revision does not match the Event current revision",
      {{"expected", expected.has_value() ? std::to_string(*expected) : "null"},
       {"actual", std::to_string(actual)}});
}

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error event_time_invalid(std::string field) {
  return common::make_error(
      "EVENT_TIME_INVALID", "Event start time must be earlier than end time",
      {{"field", std::move(field)}});
}

common::Error reminder_time_invalid(std::string field) {
  return common::make_error(
      "REMINDER_TIME_INVALID", "Reminder time is invalid", {{"field", std::move(field)}});
}

common::Error reminder_method_invalid() {
  return common::make_error(
      "REMINDER_METHOD_INVALID", "Reminder method is invalid", {{"field", "methods"}});
}

common::Error unsupported_reminder_method() {
  return common::make_error(
      "UNSUPPORTED_REMINDER_METHOD",
      "Reminder method is not supported in current version",
      {{"methods", "ordinary Event v2 currently supports popup only"}});
}

common::Error recovery_conflict(const std::string& batch_id) {
  return common::make_error(
      "RECOVERY_BATCH_CONFLICT", "Another incomplete recovery batch conflicts with this request",
      {{"recovery_batch_id", batch_id},
       {"reason", "Event has a Reminder in an active recovery batch"}},
      true);
}

common::Error prepared_delivery_conflict(const std::string& event_id) {
  return common::make_error(
      "REMINDER_NOT_DELIVERABLE", "Reminder is not deliverable",
      {{"target_id", event_id}, {"reason", "a prepared delivery attempt is still active"}});
}

common::Error recurrence_target_invalid(std::string reason) {
  return common::make_error(
      "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid",
      {{"reason", std::move(reason)}});
}

common::Error all_day_reminder_unsupported() {
  return common::make_error(
      "ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED",
      "Recurring all-day Events do not support Reminder templates in Contract v2");
}

bool is_open(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
}

bool is_occurrence_reopen_deferred(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() &&
         reminder.status == domain::kReminderStatusCancelled &&
         reminder.cancellation_reason ==
             std::string(domain::kReminderCancellationReasonOccurrenceReopened);
}

std::optional<std::string> active_recovery_batch_for_event(
    const repository::RecurringEventState& state,
    const std::string& event_id) {
  for (const auto& reminder : state.reminders) {
    if (reminder.target_type != domain::kReminderTargetEvent ||
        reminder.target_id != event_id || !reminder.recovery_batch_id.has_value()) {
      continue;
    }
    const auto batch = std::find_if(
        state.recovery_batches.begin(), state.recovery_batches.end(), [&](const auto& candidate) {
          return candidate.id == *reminder.recovery_batch_id && candidate.status == "in_progress";
        });
    if (batch != state.recovery_batches.end()) return batch->id;
  }
  return std::nullopt;
}

bool event_has_prepared_delivery(const repository::RecurringEventState& state,
                                 const std::string& event_id) {
  return std::any_of(
      state.notifications.begin(), state.notifications.end(), [&](const auto& notification) {
        if (notification.kind != "reminder" || notification.status != "prepared" ||
            !notification.reminder_id.has_value()) {
          return false;
        }
        const auto reminder = std::find_if(
            state.reminders.begin(), state.reminders.end(), [&](const auto& candidate) {
              return candidate.id == *notification.reminder_id;
            });
        return reminder != state.reminders.end() &&
               reminder->target_type == domain::kReminderTargetEvent &&
               reminder->target_id == event_id;
      });
}

common::Result<common::Unit> ensure_event_mutation_is_available(
    const repository::RecurringEventState& state,
    const std::string& event_id,
    bool reject_prepared_delivery = false) {
  if (const auto batch_id = active_recovery_batch_for_event(state, event_id);
      batch_id.has_value()) {
    return common::Result<common::Unit>::failure(recovery_conflict(*batch_id));
  }
  if (reject_prepared_delivery && event_has_prepared_delivery(state, event_id)) {
    return common::Result<common::Unit>::failure(prepared_delivery_conflict(event_id));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

domain::Event* find_event(repository::RecurringEventState& state, const std::string& id) {
  const auto found = std::find_if(state.events.begin(), state.events.end(), [&](const auto& event) {
    return event.id == id;
  });
  return found == state.events.end() ? nullptr : &*found;
}

domain::Recurrence* find_recurrence(repository::RecurringEventState& state,
                                    const std::string& id,
                                    int revision) {
  const auto found = std::find_if(
      state.recurrences.begin(), state.recurrences.end(), [&](const auto& recurrence) {
        return recurrence.id == id && recurrence.revision == revision;
      });
  return found == state.recurrences.end() ? nullptr : &*found;
}

common::Result<domain::EventOccurrence> find_occurrence(
    const RecurrenceService& service,
    const domain::RecurringEventSchedule& schedule,
    const domain::Recurrence& recurrence,
    const OccurrenceOperationCommand& command) {
  if (command.occurrence_start_at.has_value() == command.occurrence_start_date.has_value()) {
    return common::Result<domain::EventOccurrence>::failure(
        occurrence_invalid("exactly one planned occurrence start must be supplied"));
  }
  for (int index = 0; index < kMaximumExpansionCount; ++index) {
    auto occurrence = service.occurrence_at(schedule, recurrence, index);
    if (!occurrence.ok()) return occurrence;
    bool equal = false;
    bool passed = false;
    if (command.occurrence_start_at.has_value()) {
      equal = occurrence.value().occurrence_start_at == command.occurrence_start_at;
      const auto actual = common::parse_iso8601_utc_epoch_seconds(
          *occurrence.value().occurrence_start_at);
      const auto requested = common::parse_iso8601_utc_epoch_seconds(*command.occurrence_start_at);
      if (!requested.has_value()) {
        return common::Result<domain::EventOccurrence>::failure(
            occurrence_invalid("planned occurrence start is invalid"));
      }
      passed = actual.has_value() && *actual > *requested;
    } else {
      equal = occurrence.value().occurrence_start_date == command.occurrence_start_date;
      passed = *occurrence.value().occurrence_start_date > *command.occurrence_start_date;
    }
    if (equal) {
      if (occurrence.value().occurrence_key != command.occurrence_key) {
        return common::Result<domain::EventOccurrence>::failure(
            occurrence_not_found(command.occurrence_key));
      }
      return occurrence;
    }
    if (passed) break;
  }
  return common::Result<domain::EventOccurrence>::failure(
      occurrence_not_found(command.occurrence_key));
}

common::Result<std::vector<domain::RecurringReminderDraft>> templates_for(
    const repository::RecurringEventState& state,
    const std::string& event_id,
    int revision) {
  std::map<std::string, domain::RecurringReminderDraft> unique;
  for (const auto& reminder : state.reminders) {
    if (reminder.target_id != event_id || reminder.recurrence_revision != revision ||
        !reminder.advance_minutes.has_value()) continue;
    const auto key = std::to_string(*reminder.advance_minutes) + ":popup";
    domain::RecurringReminderDraft candidate{
        *reminder.advance_minutes, reminder.methods, reminder.message, true, reminder.source};
    const auto existing = unique.find(key);
    if (existing != unique.end() &&
        (existing->second.message != candidate.message ||
         existing->second.source != candidate.source ||
         existing->second.methods != candidate.methods)) {
      return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
          common::make_error(
              "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
              {{"field", "reminders"},
               {"reason", "one recurring template identity has conflicting content"}}));
    }
    unique[key] = std::move(candidate);
  }
  std::vector<domain::RecurringReminderDraft> result;
  for (const auto& item : unique) result.push_back(item.second);
  return common::Result<std::vector<domain::RecurringReminderDraft>>::success(
      std::move(result));
}

common::Result<common::Unit> validate_drafts(
    bool is_all_day,
    const std::vector<domain::RecurringReminderDraft>& drafts) {
  if (is_all_day && !drafts.empty()) {
    return common::Result<common::Unit>::failure(all_day_reminder_unsupported());
  }
  std::set<std::string> identities;
  for (const auto& draft : drafts) {
    if (draft.advance_minutes < 0 || draft.methods != std::vector<std::string>{"popup"} ||
        !draft.is_enabled || !domain::is_valid_reminder_source(draft.source)) {
      return common::Result<common::Unit>::failure(common::make_error(
          "RECURRENCE_RULE_INVALID", "Recurrence rule is invalid",
          {{"field", "reminders"}, {"reason", "recurring Reminder template is invalid"}}));
    }
    if (!identities.insert(std::to_string(draft.advance_minutes) + ":popup").second) {
      return common::Result<common::Unit>::failure(common::make_error(
          "RECURRENCE_RULE_INVALID", "Recurrence rule is invalid",
          {{"field", "reminders"}, {"reason", "duplicate recurring Reminder template"}}));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_event_fields(
    const domain::Event& event,
    const RecurrenceService& recurrence_service) {
  if (common::trim_ascii(event.title).empty()) {
    return common::Result<common::Unit>::failure(
        common::make_error("EVENT_TITLE_EMPTY", "Event title cannot be empty"));
  }
  if (!event.timezone.has_value() || event.timezone->empty()) {
    return common::Result<common::Unit>::failure(
        contract_invalid("timezone", "Event timezone must be present"));
  }
  auto timezone = recurrence_service.validate_timezone(*event.timezone);
  if (!timezone.ok()) return timezone;
  if (!domain::is_valid_create_event_source(event.source)) {
    return common::Result<common::Unit>::failure(
        contract_invalid("source", "Event source is invalid"));
  }
  if (event.importance.has_value() && !domain::is_valid_importance(*event.importance)) {
    return common::Result<common::Unit>::failure(
        contract_invalid("importance", "Event importance is invalid"));
  }
  if (event.is_all_day) {
    if (!event.start_at.empty() || !event.end_at.empty() || !event.start_date.has_value() ||
        !event.end_date.has_value() || !domain::parse_local_date(*event.start_date).ok() ||
        !domain::parse_local_date(*event.end_date).ok() ||
        *event.start_date >= *event.end_date) {
      return common::Result<common::Unit>::failure(event_time_invalid("start_date"));
    }
  } else {
    const auto start = common::parse_iso8601_utc_epoch_seconds(event.start_at);
    const auto end = common::parse_iso8601_utc_epoch_seconds(event.end_at);
    if (!start.has_value() || !end.has_value() || *start >= *end ||
        event.start_date.has_value() || event.end_date.has_value()) {
      return common::Result<common::Unit>::failure(event_time_invalid("start_at"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<domain::RecurringReminderDraft> recurring_draft_from_input(
    const EventReminderDraftInput& input,
    const std::string& event_id,
    std::size_t index) {
  const auto field = "reminders[" + std::to_string(index) + "]";
  if (input.target_type != domain::kReminderTargetEvent ||
      (input.target_id.has_value() && input.target_id != event_id) ||
      input.remind_at_supplied || input.remind_at.has_value() ||
      !input.advance_minutes_supplied || !input.advance_minutes.has_value() ||
      !input.message_supplied ||
      *input.advance_minutes < 0 || input.methods != std::vector<std::string>{"popup"} ||
      !input.is_enabled || !domain::is_valid_reminder_source(input.source)) {
    return common::Result<domain::RecurringReminderDraft>::failure(
        contract_invalid(field, "recurring Reminder template is invalid"));
  }
  return common::Result<domain::RecurringReminderDraft>::success(
      {*input.advance_minutes, input.methods, input.message, true, input.source});
}

common::Result<std::vector<domain::RecurringReminderDraft>> recurring_drafts_from_inputs(
    const std::vector<EventReminderDraftInput>& inputs,
    const std::string& event_id,
    bool is_all_day) {
  std::vector<domain::RecurringReminderDraft> result;
  result.reserve(inputs.size());
  for (std::size_t index = 0; index < inputs.size(); ++index) {
    auto converted = recurring_draft_from_input(inputs[index], event_id, index);
    if (!converted.ok()) {
      return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
          converted.error());
    }
    result.push_back(converted.value());
  }
  auto valid = validate_drafts(is_all_day, result);
  return valid.ok()
             ? common::Result<std::vector<domain::RecurringReminderDraft>>::success(
                   std::move(result))
             : common::Result<std::vector<domain::RecurringReminderDraft>>::failure(valid.error());
}

bool templates_equal(std::vector<domain::RecurringReminderDraft> left,
                     std::vector<domain::RecurringReminderDraft> right) {
  const auto less = [](const auto& first, const auto& second) {
    return std::tie(first.advance_minutes, first.methods, first.message, first.source) <
           std::tie(second.advance_minutes, second.methods, second.message, second.source);
  };
  std::sort(left.begin(), left.end(), less);
  std::sort(right.begin(), right.end(), less);
  if (left.size() != right.size()) return false;
  for (std::size_t index = 0; index < left.size(); ++index) {
    if (left[index].advance_minutes != right[index].advance_minutes ||
        left[index].methods != right[index].methods ||
        left[index].message != right[index].message ||
        left[index].source != right[index].source ||
        left[index].is_enabled != right[index].is_enabled) {
      return false;
    }
  }
  return true;
}

bool schedule_equal(const domain::Event& left, const domain::Event& right) {
  return left.start_at == right.start_at && left.end_at == right.end_at &&
         left.start_date == right.start_date && left.end_date == right.end_date &&
         left.is_all_day == right.is_all_day && left.timezone == right.timezone;
}

bool rule_equal(const domain::EventRecurrenceRuleInput& left,
                const domain::EventRecurrenceRuleInput& right) {
  return left.frequency == right.frequency && left.interval == right.interval &&
         left.end_at == right.end_at && left.count == right.count;
}

domain::EventRecurrenceRuleInput rule_input_from(const domain::Recurrence& recurrence) {
  return {recurrence.frequency, recurrence.interval, recurrence.end_at, recurrence.count};
}

common::Result<domain::Reminder> ordinary_reminder_from_input(
    const EventReminderDraftInput& input,
    const domain::Event& event,
    const std::string& now,
    const std::string& reminder_id,
    std::size_t index) {
  const auto parent = "reminders[" + std::to_string(index) + "]";
  if (input.target_type != domain::kReminderTargetEvent ||
      (input.target_id.has_value() && input.target_id != event.id) || !input.is_enabled ||
      !domain::is_valid_reminder_source(input.source)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid(parent, "ordinary Event Reminder draft is invalid"));
  }
  std::set<std::string> methods;
  for (const auto& method : input.methods) {
    if (!domain::is_valid_reminder_method(method) || !methods.insert(method).second) {
      return common::Result<domain::Reminder>::failure(reminder_method_invalid());
    }
  }
  if (input.methods.empty()) {
    return common::Result<domain::Reminder>::failure(reminder_method_invalid());
  }
  if (input.methods != std::vector<std::string>{"popup"}) {
    return common::Result<domain::Reminder>::failure(unsupported_reminder_method());
  }
  if (input.remind_at.has_value() == input.advance_minutes.has_value() ||
      (input.advance_minutes.has_value() && *input.advance_minutes < 0)) {
    return common::Result<domain::Reminder>::failure(reminder_time_invalid(parent));
  }
  std::string remind_at;
  if (input.remind_at.has_value()) {
    remind_at = *input.remind_at;
  } else {
    if (event.is_all_day) {
      return common::Result<domain::Reminder>::failure(reminder_time_invalid(parent));
    }
    const auto start = common::parse_iso8601_utc_epoch_seconds(event.start_at);
    if (!start.has_value() ||
        *start < static_cast<std::int64_t>(*input.advance_minutes) * 60) {
      return common::Result<domain::Reminder>::failure(reminder_time_invalid(parent));
    }
    remind_at = common::format_epoch_seconds_utc_iso8601(
        *start - static_cast<std::int64_t>(*input.advance_minutes) * 60);
  }
  const auto remind_epoch = common::parse_iso8601_utc_epoch_seconds(remind_at);
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (!remind_epoch.has_value() || !now_epoch.has_value() || *remind_epoch <= *now_epoch) {
    return common::Result<domain::Reminder>::failure(reminder_time_invalid(parent));
  }
  domain::Reminder reminder;
  reminder.id = reminder_id;
  reminder.target_type = std::string(domain::kReminderTargetEvent);
  reminder.target_id = event.id;
  reminder.remind_at = remind_at;
  reminder.methods = input.methods;
  reminder.advance_minutes = input.advance_minutes;
  reminder.message = input.message;
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.source = input.source;
  reminder.created_at = now;
  reminder.updated_at = now;
  return common::Result<domain::Reminder>::success(std::move(reminder));
}

}  // namespace

RecurringEventWorkflowService::RecurringEventWorkflowService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    std::shared_ptr<RecurrenceService> recurrence_service,
    std::shared_ptr<RollingReminderService> rolling_reminder_service,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : transaction_(std::move(transaction)),
      recurrence_service_(std::move(recurrence_service)),
      rolling_reminder_service_(std::move(rolling_reminder_service)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Event> RecurringEventWorkflowService::create_event(
    const CreateEventV2Command& command) {
  const auto now = clock_();
  auto event = command.event;
  event.id = id_generator_();
  event.title = common::trim_ascii(event.title);
  event.status = std::string(domain::kEventStatusActive);
  event.completed_at = std::nullopt;
  event.deleted_at = std::nullopt;
  event.created_at = now;
  event.updated_at = now;
  event.has_recurrence = command.recurrence.has_value();
  event.recurrence_id = command.recurrence.has_value()
                            ? std::optional<std::string>(id_generator_())
                            : std::nullopt;
  event.recurrence_revision = command.recurrence.has_value()
                                  ? std::optional<int>(1)
                                  : std::nullopt;
  if (!common::is_iso8601_utc_datetime(now) || !common::is_uuid(event.id) ||
      (event.recurrence_id.has_value() && !common::is_uuid(*event.recurrence_id))) {
    return common::Result<domain::Event>::failure(common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "v2 Event workflow Clock or ID generator is invalid"}}));
  }
  auto event_valid = validate_event_fields(event, *recurrence_service_);
  if (!event_valid.ok()) return common::Result<domain::Event>::failure(event_valid.error());

  std::optional<domain::Recurrence> recurrence;
  std::vector<domain::Reminder> reminders;
  if (command.recurrence.has_value()) {
    auto derived = recurrence_service_->derive_recurrence(
        domain::recurring_schedule_from_event(event), *command.recurrence,
        *event.recurrence_id, 1, now);
    if (!derived.ok()) return common::Result<domain::Event>::failure(derived.error());
    recurrence = derived.value();
    auto drafts = recurring_drafts_from_inputs(command.reminders, event.id, event.is_all_day);
    if (!drafts.ok()) return common::Result<domain::Event>::failure(drafts.error());
    for (const auto& draft : drafts.value()) {
      auto reminder = rolling_reminder_service_->first_eligible_after(
          domain::recurring_schedule_from_event(event), *recurrence, draft, {}, now, now);
      if (!reminder.ok()) return common::Result<domain::Event>::failure(reminder.error());
      reminders.push_back(reminder.value());
    }
  } else {
    reminders.reserve(command.reminders.size());
    for (std::size_t index = 0; index < command.reminders.size(); ++index) {
      const auto reminder_id = id_generator_();
      if (!common::is_uuid(reminder_id)) {
        return common::Result<domain::Event>::failure(common::make_error(
            "NATIVE_INTERNAL_ERROR", "Native internal error",
            {{"reason", "ordinary Reminder ID generator is invalid"}}));
      }
      auto reminder = ordinary_reminder_from_input(
          command.reminders[index], event, now, reminder_id, index);
      if (!reminder.ok()) return common::Result<domain::Event>::failure(reminder.error());
      reminders.push_back(reminder.value());
    }
  }

  auto committed = transaction_->execute(
      "event_recurrence_and_first_reminder_create_or_update", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        if (find_event(state, event.id) != nullptr) {
          return common::Result<common::Unit>::failure(common::make_error(
              "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", "Event ID collision"}}));
        }
        state.events.push_back(event);
        if (recurrence.has_value()) state.recurrences.push_back(*recurrence);
        for (const auto& reminder : reminders) {
          if (reminder.recurrence_revision.has_value()) {
            auto inserted = rolling_reminder_service_->insert_idempotent(state, reminder);
            if (!inserted.ok()) return inserted;
          } else {
            const bool collision = std::any_of(
                state.reminders.begin(), state.reminders.end(), [&](const auto& existing) {
                  return existing.id == reminder.id;
                });
            if (collision) {
              return common::Result<common::Unit>::failure(common::make_error(
                  "NATIVE_INTERNAL_ERROR", "Native internal error",
                  {{"reason", "Reminder ID collision"}}));
            }
            state.reminders.push_back(reminder);
          }
        }
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(std::move(event))
                        : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::Event> RecurringEventWorkflowService::create_series(
    const CreateRecurringEventCommand& command) {
  std::vector<EventReminderDraftInput> reminders;
  reminders.reserve(command.reminders.size());
  for (const auto& draft : command.reminders) {
    reminders.push_back(EventReminderDraftInput{
        std::string(domain::kReminderTargetEvent), std::nullopt, std::nullopt,
        draft.advance_minutes, draft.methods, draft.message, draft.is_enabled, draft.source,
        false, true, true});
  }
  return create_event(CreateEventV2Command{
      command.event, command.recurrence, std::move(reminders)});
}

common::Result<domain::Event> RecurringEventWorkflowService::update_series(
    const UpdateRecurringEventSeriesCommand& command) {
  return update_event(command);
}

common::Result<domain::Event> RecurringEventWorkflowService::update_event(
    const UpdateEventV2Command& command) {
  if (!common::is_uuid(command.event_id)) {
    return common::Result<domain::Event>::failure(
        contract_invalid("UpdateEventRequest.id", "Event identity is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "event_recurrence_and_first_reminder_create_or_update", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* stored = find_event(state, command.event_id);
        if (stored == nullptr || stored->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        auto mutation_available = ensure_event_mutation_is_available(
            state, stored->id, true);
        if (!mutation_available.ok()) return mutation_available;
        auto replacement = *stored;
        if (command.title.supplied) replacement.title = common::trim_ascii(command.title.value);
        if (command.content.supplied) replacement.content = command.content.value;
        if (command.category_id.supplied) replacement.category_id = command.category_id.value;
        if (command.importance.supplied) replacement.importance = command.importance.value;
        if (command.location.supplied) replacement.location = command.location.value;
        if (command.source.supplied) replacement.source = command.source.value;
        if (command.time.supplied) {
          replacement.start_at = command.time.value.start_at.value_or("");
          replacement.end_at = command.time.value.end_at.value_or("");
          replacement.start_date = command.time.value.start_date;
          replacement.end_date = command.time.value.end_date;
          replacement.is_all_day = command.time.value.is_all_day;
          replacement.timezone = command.time.value.timezone;
        }
        auto fields_valid = validate_event_fields(replacement, *recurrence_service_);
        if (!fields_valid.ok()) return fields_valid;

        if (!stored->has_recurrence) {
          if (command.expected_recurrence_revision.supplied &&
              command.expected_recurrence_revision.value.has_value()) {
            return common::Result<common::Unit>::failure(
                recurrence_target_invalid("ordinary Event must not carry an expected revision"));
          }
          if (command.recurrence.supplied) {
            return common::Result<common::Unit>::failure(common::make_error(
                "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
                {{"feature", "event.update.add_recurrence"}}));
          }
          if (command.reminders.supplied) {
            return common::Result<common::Unit>::failure(common::make_error(
                "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
                {{"feature", "ordinary_event.embedded_reminder_update"}}));
          }
          const bool start_changed = stored->start_at != replacement.start_at ||
                                     stored->is_all_day != replacement.is_all_day;
          if (start_changed) {
            if (replacement.is_all_day) {
              const bool has_mutable_advance_reminder = std::any_of(
                  state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
                    return reminder.target_type == domain::kReminderTargetEvent &&
                           reminder.target_id == stored->id &&
                           !reminder.recurrence_revision.has_value() &&
                           reminder.advance_minutes.has_value() &&
                           !reminder.deleted_at.has_value() &&
                           (reminder.status == domain::kReminderStatusPending ||
                            reminder.status == domain::kReminderStatusScheduled);
                  });
              if (has_mutable_advance_reminder) {
                return common::Result<common::Unit>::failure(
                    reminder_time_invalid("reminders.advance_minutes"));
              }
            } else {
              const auto start = common::parse_iso8601_utc_epoch_seconds(
                  replacement.start_at);
              if (!start.has_value()) {
                return common::Result<common::Unit>::failure(
                    event_time_invalid("start_at"));
              }
              for (auto& reminder : state.reminders) {
                if (reminder.target_type != domain::kReminderTargetEvent ||
                    reminder.target_id != stored->id ||
                    reminder.recurrence_revision.has_value() ||
                    !reminder.advance_minutes.has_value() ||
                    reminder.deleted_at.has_value() ||
                    (reminder.status != domain::kReminderStatusPending &&
                     reminder.status != domain::kReminderStatusScheduled)) {
                  continue;
                }
                const auto offset =
                    static_cast<std::int64_t>(*reminder.advance_minutes) * 60;
                if (*start < offset) {
                  return common::Result<common::Unit>::failure(
                      reminder_time_invalid("reminders.advance_minutes"));
                }
                reminder.remind_at = common::format_epoch_seconds_utc_iso8601(
                    *start - offset);
                if (reminder.status == domain::kReminderStatusScheduled) {
                  reminder.status = std::string(domain::kReminderStatusPending);
                  reminder.scheduled_at = std::nullopt;
                }
                reminder.updated_at = now;
              }
            }
          }
          replacement.updated_at = now;
          *stored = replacement;
          result = replacement;
          return common::Result<common::Unit>::success(common::Unit{});
        }

        const int actual = stored->recurrence_revision.value_or(0);
        const auto expected = command.expected_recurrence_revision.supplied
                                  ? command.expected_recurrence_revision.value
                                  : std::optional<int>{};
        if (!expected.has_value() || *expected != actual) {
          return common::Result<common::Unit>::failure(revision_conflict(expected, actual));
        }
        auto* current_recurrence = find_recurrence(state, *stored->recurrence_id, actual);
        if (current_recurrence == nullptr) {
          return common::Result<common::Unit>::failure(common::make_error(
              "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
              {{"field", "Event.recurrence_id"}}));
        }
        auto current_templates = templates_for(state, stored->id, actual);
        if (!current_templates.ok()) return common::Result<common::Unit>::failure(current_templates.error());
        const auto next_rule = command.recurrence.supplied
                                   ? command.recurrence.value
                                   : rule_input_from(*current_recurrence);
        std::vector<domain::RecurringReminderDraft> next_templates = current_templates.value();
        if (command.reminders.supplied) {
          auto converted = recurring_drafts_from_inputs(
              command.reminders.value, stored->id, replacement.is_all_day);
          if (!converted.ok()) return common::Result<common::Unit>::failure(converted.error());
          next_templates = std::move(converted.value());
        } else {
          auto valid = validate_drafts(replacement.is_all_day, next_templates);
          if (!valid.ok()) return valid;
        }
        const bool creates_revision =
            !schedule_equal(*stored, replacement) ||
            !rule_equal(rule_input_from(*current_recurrence), next_rule) ||
            !templates_equal(current_templates.value(), next_templates);
        replacement.updated_at = now;
        if (!creates_revision) {
          *stored = replacement;
          result = replacement;
          return common::Result<common::Unit>::success(common::Unit{});
        }

        replacement.has_recurrence = true;
        replacement.recurrence_id = stored->recurrence_id;
        replacement.recurrence_revision = actual + 1;
        auto recurrence = recurrence_service_->derive_recurrence(
            domain::recurring_schedule_from_event(replacement), next_rule,
            *replacement.recurrence_id, actual + 1, now);
        if (!recurrence.ok()) return common::Result<common::Unit>::failure(recurrence.error());
        for (auto& reminder : state.reminders) {
          if (reminder.target_id == stored->id && reminder.recurrence_revision == actual &&
              (is_open(reminder) || is_occurrence_reopen_deferred(reminder))) {
            reminder.status = std::string(domain::kReminderStatusCancelled);
            reminder.is_enabled = false;
            reminder.scheduled_at = std::nullopt;
            reminder.cancellation_reason =
                std::string(domain::kReminderCancellationReasonSeriesUpdated);
            reminder.last_cancelled_at = now;
            reminder.updated_at = now;
          }
        }
        state.recurrences.push_back(recurrence.value());
        *stored = replacement;
        for (const auto& draft : next_templates) {
          auto next = rolling_reminder_service_->first_eligible_after(
              domain::recurring_schedule_from_event(replacement), recurrence.value(), draft,
              state.occurrence_states, now, now);
          if (!next.ok()) return common::Result<common::Unit>::failure(next.error());
          auto reminder = next.value();
          if (replacement.status != domain::kEventStatusActive) {
            reminder.status = std::string(domain::kReminderStatusCancelled);
            reminder.is_enabled = false;
            reminder.cancellation_reason =
                replacement.status == domain::kEventStatusCompleted
                    ? std::string(domain::kReminderCancellationReasonSeriesCompleted)
                    : std::string(domain::kReminderCancellationReasonSeriesCancelled);
            reminder.last_cancelled_at = now;
          }
          auto inserted = rolling_reminder_service_->insert_idempotent(state, reminder);
          if (!inserted.ok()) return inserted;
        }
        result = replacement;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) return common::Result<domain::Event>::failure(committed.error());
  return common::Result<domain::Event>::success(*result);
}

common::Result<domain::Event> RecurringEventWorkflowService::complete_event(
    const CompleteEventV2Command& command) {
  if (!common::is_uuid(command.event_id) ||
      !domain::is_valid_complete_event_source(command.source)) {
    return common::Result<domain::Event>::failure(
        contract_invalid("CompleteEventRequest", "event identity or source is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "series_complete_cancel_delete_or_reopen", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (event->has_recurrence) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("recurring Event requires event.complete_series"));
        }
        if (event->status == domain::kEventStatusCompleted) {
          result = *event;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        if (event->status != domain::kEventStatusActive) {
          return common::Result<common::Unit>::failure(
              contract_invalid("status", "only an active Event can be completed"));
        }
        event->status = std::string(domain::kEventStatusCompleted);
        event->completed_at = now;
        event->updated_at = now;
        for (auto& reminder : state.reminders) {
          if (reminder.target_type == domain::kReminderTargetEvent &&
              reminder.target_id == event->id && !reminder.recurrence_revision.has_value() &&
              is_open(reminder)) {
            reminder.status = std::string(domain::kReminderStatusCancelled);
            reminder.is_enabled = false;
            reminder.scheduled_at = std::nullopt;
            reminder.cancellation_reason =
                std::string(domain::kReminderCancellationReasonEventCompleted);
            reminder.last_cancelled_at = now;
            reminder.updated_at = now;
          }
        }
        result = *event;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(*result)
                        : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::Event> RecurringEventWorkflowService::reopen_event(
    const ReopenEventV2Command& command) {
  if (!common::is_uuid(command.event_id)) {
    return common::Result<domain::Event>::failure(
        contract_invalid("event_id", "event_id must be a UUID"));
  }
  const auto now = clock_();
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "series_complete_cancel_delete_or_reopen", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (event->has_recurrence) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("recurring Event requires event.reopen_series"));
        }
        if (event->status == domain::kEventStatusActive) {
          result = *event;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        if (event->status != domain::kEventStatusCompleted) {
          return common::Result<common::Unit>::failure(
              contract_invalid("status", "only a completed Event can be reopened"));
        }
        event->status = std::string(domain::kEventStatusActive);
        event->completed_at = std::nullopt;
        event->updated_at = now;
        for (auto& reminder : state.reminders) {
          const auto remind_epoch = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
          if (reminder.target_type == domain::kReminderTargetEvent &&
              reminder.target_id == event->id && !reminder.recurrence_revision.has_value() &&
              reminder.status == domain::kReminderStatusCancelled &&
              reminder.cancellation_reason ==
                  std::optional<std::string>(
                      std::string(domain::kReminderCancellationReasonEventCompleted)) &&
              remind_epoch.has_value() && now_epoch.has_value() && *remind_epoch > *now_epoch) {
            reminder.status = std::string(domain::kReminderStatusPending);
            reminder.is_enabled = true;
            reminder.scheduled_at = std::nullopt;
            reminder.failure_reason = std::nullopt;
            reminder.reactivated_at = now;
            ++reminder.reactivation_count;
            reminder.updated_at = now;
          }
        }
        result = *event;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(*result)
                        : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::Event> RecurringEventWorkflowService::delete_event(
    const DeleteEventV2Command& command) {
  if (!common::is_uuid(command.event_id) ||
      (command.delete_mode != "soft" && command.delete_mode != "hard")) {
    return common::Result<domain::Event>::failure(
        contract_invalid("DeleteEventRequest", "Event identity or delete_mode is invalid"));
  }
  if (command.delete_mode == "hard") {
    return common::Result<domain::Event>::failure(common::make_error(
        "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
        {{"feature", "event.hard_delete"}}));
  }
  const auto now = clock_();
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "series_complete_cancel_delete_or_reopen", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        if (event->has_recurrence) {
          const int actual = event->recurrence_revision.value_or(0);
          if (command.recurrence_delete_scope !=
                  std::optional<std::string>("all_occurrences") ||
              !command.expected_recurrence_revision.has_value()) {
            return common::Result<common::Unit>::failure(common::make_error(
                "EVENT_DELETE_SCOPE_INVALID", "Event delete scope is invalid"));
          }
          if (*command.expected_recurrence_revision != actual) {
            return common::Result<common::Unit>::failure(
                revision_conflict(command.expected_recurrence_revision, actual));
          }
          for (auto& reminder : state.reminders) {
            if (reminder.target_id == event->id &&
                reminder.recurrence_revision == actual &&
                (is_open(reminder) || is_occurrence_reopen_deferred(reminder))) {
              reminder.status = std::string(domain::kReminderStatusCancelled);
              reminder.is_enabled = false;
              reminder.scheduled_at = std::nullopt;
              reminder.cancellation_reason =
                  std::string(domain::kReminderCancellationReasonSeriesDeleted);
              reminder.last_cancelled_at = now;
              reminder.updated_at = now;
            }
          }
        } else {
          if (command.recurrence_delete_scope.has_value() ||
              command.expected_recurrence_revision.has_value()) {
            return common::Result<common::Unit>::failure(common::make_error(
                "EVENT_DELETE_SCOPE_INVALID", "Event delete scope is invalid"));
          }
          // Contract v2 has no event_deleted cancellation reason yet. Keep the
          // Reminder history and use the only generic user terminal reason.
          for (auto& reminder : state.reminders) {
            if (reminder.target_type == domain::kReminderTargetEvent &&
                reminder.target_id == event->id && !reminder.recurrence_revision.has_value() &&
                is_open(reminder)) {
              reminder.status = std::string(domain::kReminderStatusCancelled);
              reminder.is_enabled = false;
              reminder.scheduled_at = std::nullopt;
              reminder.cancellation_reason =
                  std::string(domain::kReminderCancellationReasonUserCancelled);
              reminder.last_cancelled_at = now;
              reminder.updated_at = now;
            }
          }
        }
        event->status = std::string(domain::kEventStatusCancelled);
        event->completed_at = std::nullopt;
        event->deleted_at = now;
        event->updated_at = now;
        result = *event;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(*result)
                        : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::EventOccurrenceState>
RecurringEventWorkflowService::transition_occurrence(
    const OccurrenceOperationCommand& command,
    std::string target_status,
    std::string cancellation_reason) {
  if (!common::is_uuid(command.event_id) || command.recurrence_revision < 1 ||
      !common::is_uuid(command.occurrence_key)) {
    return common::Result<domain::EventOccurrenceState>::failure(
        occurrence_invalid("occurrence identity is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::EventOccurrenceState> result;
  auto committed = transaction_->execute(
      "occurrence_state_and_reminder_transition", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (!event->has_recurrence || !event->recurrence_id.has_value() ||
            !event->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("occurrence operation requires a recurring Event"));
        }
        if (event->status != domain::kEventStatusActive) {
          return common::Result<common::Unit>::failure(
              occurrence_invalid("occurrence operation requires an active series"));
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        const int actual = event->recurrence_revision.value_or(0);
        if (actual != command.recurrence_revision) {
          return common::Result<common::Unit>::failure(
              revision_conflict(command.recurrence_revision, actual));
        }
        auto* recurrence = find_recurrence(state, *event->recurrence_id, actual);
        if (recurrence == nullptr) {
          return common::Result<common::Unit>::failure(common::make_error(
              "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
              {{"field", "Event.recurrence_id"}}));
        }
        auto occurrence = find_occurrence(
            *recurrence_service_, domain::recurring_schedule_from_event(*event), *recurrence, command);
        if (!occurrence.ok()) return common::Result<common::Unit>::failure(occurrence.error());
        auto found = std::find_if(
            state.occurrence_states.begin(), state.occurrence_states.end(), [&](const auto& item) {
              return item.event_id == command.event_id && item.recurrence_revision == actual &&
                     item.occurrence_key == command.occurrence_key;
            });
        if (found != state.occurrence_states.end()) {
          if (found->status == target_status) {
            result = *found;
            return common::Result<common::Unit>::success(common::Unit{});
          }
          if (domain::is_terminal_occurrence_status(found->status)) {
            return common::Result<common::Unit>::failure(
                occurrence_invalid("occurrence is already terminal; reopen it first"));
          }
          found->status = target_status;
          found->state_changed_at = now;
          found->updated_at = now;
          found->reopened_at = std::nullopt;
          result = *found;
        } else {
          domain::EventOccurrenceState created;
          created.event_id = event->id;
          created.recurrence_revision = actual;
          created.occurrence_key = occurrence.value().occurrence_key;
          created.occurrence_start_at = occurrence.value().occurrence_start_at;
          created.occurrence_start_date = occurrence.value().occurrence_start_date;
          created.status = target_status;
          created.state_changed_at = now;
          created.created_at = now;
          created.updated_at = now;
          state.occurrence_states.push_back(created);
          result = created;
        }

        for (auto& reminder : state.reminders) {
          if (reminder.target_id == event->id && reminder.recurrence_revision == actual &&
              reminder.occurrence_key == occurrence.value().occurrence_key && is_open(reminder)) {
            reminder.status = std::string(domain::kReminderStatusCancelled);
            reminder.is_enabled = false;
            reminder.scheduled_at = std::nullopt;
            reminder.cancellation_reason = cancellation_reason;
            reminder.last_cancelled_at = now;
            reminder.updated_at = now;
          }
        }
        auto templates = templates_for(state, event->id, actual);
        if (!templates.ok()) return common::Result<common::Unit>::failure(templates.error());
        for (const auto& draft : templates.value()) {
          auto ensured = rolling_reminder_service_->ensure_next_in_state(
              state, *event, *recurrence, draft, now, now);
          if (!ensured.ok()) return ensured;
        }
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok()
             ? common::Result<domain::EventOccurrenceState>::success(*result)
             : common::Result<domain::EventOccurrenceState>::failure(committed.error());
}

common::Result<domain::EventOccurrenceState>
RecurringEventWorkflowService::complete_occurrence(const OccurrenceOperationCommand& command) {
  return transition_occurrence(
      command, std::string(domain::kOccurrenceCompleted),
      std::string(domain::kReminderCancellationReasonOccurrenceCompleted));
}

common::Result<domain::EventOccurrenceState>
RecurringEventWorkflowService::skip_occurrence(const OccurrenceOperationCommand& command) {
  return transition_occurrence(
      command, std::string(domain::kOccurrenceSkipped),
      std::string(domain::kReminderCancellationReasonOccurrenceSkipped));
}

common::Result<domain::EventOccurrenceState>
RecurringEventWorkflowService::cancel_occurrence(const OccurrenceOperationCommand& command) {
  return transition_occurrence(
      command, std::string(domain::kOccurrenceCancelled),
      std::string(domain::kReminderCancellationReasonOccurrenceCancelled));
}

common::Result<domain::EventOccurrenceState>
RecurringEventWorkflowService::reopen_occurrence(const OccurrenceOperationCommand& command) {
  if (!common::is_uuid(command.event_id) || command.recurrence_revision < 1 ||
      !common::is_uuid(command.occurrence_key)) {
    return common::Result<domain::EventOccurrenceState>::failure(
        occurrence_invalid("occurrence identity is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::EventOccurrenceState> result;
  auto committed = transaction_->execute(
      "occurrence_state_and_reminder_transition", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (!event->has_recurrence || !event->recurrence_id.has_value() ||
            !event->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("occurrence operation requires a recurring Event"));
        }
        if (event->status != domain::kEventStatusActive) {
          return common::Result<common::Unit>::failure(
              occurrence_invalid("occurrence operation requires an active series"));
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        const int actual = event->recurrence_revision.value_or(0);
        if (actual != command.recurrence_revision) {
          return common::Result<common::Unit>::failure(
              revision_conflict(command.recurrence_revision, actual));
        }
        auto* recurrence = find_recurrence(state, *event->recurrence_id, actual);
        auto occurrence = recurrence == nullptr
                              ? common::Result<domain::EventOccurrence>::failure(
                                    common::make_error("STORAGE_DATA_CORRUPTED", "Storage data is corrupted"))
                              : find_occurrence(*recurrence_service_,
                                                domain::recurring_schedule_from_event(*event),
                                                *recurrence, command);
        if (!occurrence.ok()) return common::Result<common::Unit>::failure(occurrence.error());
        auto found = std::find_if(
            state.occurrence_states.begin(), state.occurrence_states.end(), [&](const auto& item) {
              return item.event_id == command.event_id && item.recurrence_revision == actual &&
                     item.occurrence_key == command.occurrence_key;
            });
        if (found != state.occurrence_states.end() &&
            found->status == domain::kOccurrenceScheduled && found->reopened_at.has_value()) {
          result = *found;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        if (found == state.occurrence_states.end() ||
            !domain::is_terminal_occurrence_status(found->status)) {
          return common::Result<common::Unit>::failure(
              occurrence_invalid("only a terminal occurrence can be reopened"));
        }
        const auto previous_status = found->status;
        std::string reversible_reason;
        if (previous_status == domain::kOccurrenceCompleted) {
          reversible_reason = std::string(domain::kReminderCancellationReasonOccurrenceCompleted);
        } else if (previous_status == domain::kOccurrenceSkipped) {
          reversible_reason = std::string(domain::kReminderCancellationReasonOccurrenceSkipped);
        } else {
          reversible_reason = std::string(domain::kReminderCancellationReasonOccurrenceCancelled);
        }
        const auto reopened = common::parse_iso8601_utc_epoch_seconds(now);
        for (auto& original : state.reminders) {
          const auto remind = common::parse_iso8601_utc_epoch_seconds(original.remind_at);
          if (original.target_id != event->id || original.recurrence_revision != actual ||
              original.occurrence_key != command.occurrence_key ||
              original.status != domain::kReminderStatusCancelled ||
              original.cancellation_reason != reversible_reason || !remind.has_value() ||
              !reopened.has_value() || *remind <= *reopened) {
            continue;
          }
          for (auto& candidate : state.reminders) {
            if (candidate.id == original.id || candidate.target_id != event->id ||
                candidate.recurrence_revision != actual ||
                candidate.occurrence_key == command.occurrence_key ||
                candidate.advance_minutes != original.advance_minutes ||
                candidate.methods != original.methods || !is_open(candidate)) {
              continue;
            }
            const auto candidate_remind =
                common::parse_iso8601_utc_epoch_seconds(candidate.remind_at);
            if (!candidate_remind.has_value()) {
              return common::Result<common::Unit>::failure(common::make_error(
                  "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
                  {{"field", "Reminder.remind_at"}}));
            }
            if (*candidate_remind <= *remind) {
              continue;
            }
            candidate.status = std::string(domain::kReminderStatusCancelled);
            candidate.is_enabled = false;
            candidate.scheduled_at = std::nullopt;
            candidate.cancellation_reason =
                std::string(domain::kReminderCancellationReasonOccurrenceReopened);
            candidate.last_cancelled_at = now;
            candidate.updated_at = now;
          }
        }
        found->status = std::string(domain::kOccurrenceScheduled);
        found->state_changed_at = now;
        found->reopened_at = now;
        found->updated_at = now;
        result = *found;
        for (auto& reminder : state.reminders) {
          const auto remind = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
          if (reminder.target_id == event->id && reminder.recurrence_revision == actual &&
              reminder.occurrence_key == command.occurrence_key &&
              reminder.status == domain::kReminderStatusCancelled &&
              reminder.cancellation_reason == reversible_reason && remind.has_value() &&
              reopened.has_value() && *remind > *reopened) {
            reminder.status = std::string(domain::kReminderStatusPending);
            reminder.is_enabled = true;
            reminder.scheduled_at = std::nullopt;
            reminder.failure_reason = std::nullopt;
            reminder.reactivated_at = now;
            ++reminder.reactivation_count;
            reminder.updated_at = now;
          }
        }
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok()
             ? common::Result<domain::EventOccurrenceState>::success(*result)
             : common::Result<domain::EventOccurrenceState>::failure(committed.error());
}

common::Result<domain::Event> RecurringEventWorkflowService::transition_series(
    const SeriesOperationCommand& command,
    std::string target_status,
    std::string cancellation_reason,
    bool reopen) {
  if (!common::is_uuid(command.event_id) || command.recurrence_revision < 1) {
    return common::Result<domain::Event>::failure(
        occurrence_invalid("series identity is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "series_complete_cancel_delete_or_reopen", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (!event->has_recurrence || !event->recurrence_id.has_value() ||
            !event->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("series operation requires a recurring Event"));
        }
        const int actual = event->recurrence_revision.value_or(0);
        if (actual != command.recurrence_revision) {
          return common::Result<common::Unit>::failure(
              revision_conflict(command.recurrence_revision, actual));
        }
        if (reopen && event->status == domain::kEventStatusActive) {
          result = *event;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        auto* recurrence = find_recurrence(state, *event->recurrence_id, actual);
        if (recurrence == nullptr) {
          return common::Result<common::Unit>::failure(common::make_error(
              "STORAGE_DATA_CORRUPTED", "Storage data is corrupted"));
        }
        if (reopen) {
          if (event->status != domain::kEventStatusCompleted) {
            return common::Result<common::Unit>::failure(
                occurrence_invalid("only a completed series can be reopened"));
          }
          event->status = std::string(domain::kEventStatusActive);
          event->completed_at = std::nullopt;
          event->updated_at = now;
          const auto reopened_at = common::parse_iso8601_utc_epoch_seconds(now);
          if (!reopened_at.has_value()) {
            return common::Result<common::Unit>::failure(common::make_error(
                "NATIVE_INTERNAL_ERROR", "Native internal error",
                {{"reason", "series reopen clock returned invalid UTC time"}}));
          }
          using TemplateKey = std::tuple<int, std::vector<std::string>>;
          std::map<TemplateKey, std::pair<std::int64_t, domain::Reminder*>>
              earliest_by_template;
          for (auto& reminder : state.reminders) {
            if (reminder.target_id != event->id ||
                reminder.recurrence_revision != actual ||
                reminder.status != domain::kReminderStatusCancelled ||
                reminder.cancellation_reason !=
                    std::string(domain::kReminderCancellationReasonSeriesCompleted)) {
              continue;
            }
            const auto remind_at =
                common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
            if (!remind_at.has_value() || !reminder.advance_minutes.has_value()) {
              return common::Result<common::Unit>::failure(common::make_error(
                  "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
                  {{"field", "Reminder.remind_at"}}));
            }
            if (*remind_at <= *reopened_at) {
              continue;
            }
            const TemplateKey key{*reminder.advance_minutes, reminder.methods};
            const auto earliest = earliest_by_template.find(key);
            if (earliest == earliest_by_template.end() ||
                *remind_at < earliest->second.first ||
                (*remind_at == earliest->second.first &&
                 reminder.id < earliest->second.second->id)) {
              earliest_by_template[key] = {*remind_at, &reminder};
            }
          }
          for (auto& reminder : state.reminders) {
            if (reminder.target_id != event->id ||
                reminder.recurrence_revision != actual ||
                reminder.status != domain::kReminderStatusCancelled ||
                reminder.cancellation_reason !=
                    std::string(domain::kReminderCancellationReasonSeriesCompleted) ||
                !reminder.advance_minutes.has_value()) {
              continue;
            }
            const auto remind_at =
                common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
            if (!remind_at.has_value() || *remind_at <= *reopened_at) {
              continue;
            }
            const TemplateKey key{*reminder.advance_minutes, reminder.methods};
            const auto earliest = earliest_by_template.find(key);
            if (earliest != earliest_by_template.end() &&
                earliest->second.second == &reminder) {
              reminder.status = std::string(domain::kReminderStatusPending);
              reminder.is_enabled = true;
              reminder.scheduled_at = std::nullopt;
              reminder.failure_reason = std::nullopt;
              reminder.reactivated_at = now;
              ++reminder.reactivation_count;
              reminder.updated_at = now;
            } else {
              reminder.is_enabled = false;
              reminder.scheduled_at = std::nullopt;
              reminder.cancellation_reason =
                  std::string(domain::kReminderCancellationReasonOccurrenceReopened);
              reminder.last_cancelled_at = now;
              reminder.updated_at = now;
            }
          }
          auto templates = templates_for(state, event->id, actual);
          if (!templates.ok()) return common::Result<common::Unit>::failure(templates.error());
          for (const auto& draft : templates.value()) {
            const TemplateKey key{draft.advance_minutes, draft.methods};
            if (earliest_by_template.find(key) != earliest_by_template.end()) {
              continue;
            }
            auto ensured = rolling_reminder_service_->ensure_next_in_state(
                state, *event, *recurrence, draft, now, now);
            if (!ensured.ok()) return ensured;
          }
        } else {
          if (event->status == target_status) {
            result = *event;
            return common::Result<common::Unit>::success(common::Unit{});
          }
          if (event->status != domain::kEventStatusActive) {
            return common::Result<common::Unit>::failure(
                occurrence_invalid("only an active series can enter a terminal state"));
          }
          event->status = target_status;
          event->completed_at = target_status == domain::kEventStatusCompleted
                                    ? std::optional<std::string>(now)
                                    : std::nullopt;
          event->updated_at = now;
          for (auto& reminder : state.reminders) {
            if (reminder.target_id == event->id && reminder.recurrence_revision == actual &&
                (is_open(reminder) || is_occurrence_reopen_deferred(reminder))) {
              reminder.status = std::string(domain::kReminderStatusCancelled);
              reminder.is_enabled = false;
              reminder.scheduled_at = std::nullopt;
              reminder.cancellation_reason = cancellation_reason;
              reminder.last_cancelled_at = now;
              reminder.updated_at = now;
            }
          }
        }
        result = *event;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(*result)
                        : common::Result<domain::Event>::failure(committed.error());
}

common::Result<domain::Event> RecurringEventWorkflowService::complete_series(
    const SeriesOperationCommand& command) {
  return transition_series(
      command, std::string(domain::kEventStatusCompleted),
      std::string(domain::kReminderCancellationReasonSeriesCompleted), false);
}

common::Result<domain::Event> RecurringEventWorkflowService::reopen_series(
    const SeriesOperationCommand& command) {
  return transition_series(
      command, std::string(domain::kEventStatusActive),
      std::string(domain::kReminderCancellationReasonSeriesCompleted), true);
}

common::Result<domain::Event> RecurringEventWorkflowService::cancel_series(
    const SeriesOperationCommand& command) {
  return transition_series(
      command, std::string(domain::kEventStatusCancelled),
      std::string(domain::kReminderCancellationReasonSeriesCancelled), false);
}

common::Result<domain::Event> RecurringEventWorkflowService::delete_series(
    const DeleteRecurringSeriesCommand& command) {
  if (!common::is_uuid(command.event_id) || command.recurrence_revision < 1 ||
      command.delete_mode != "soft" ||
      command.recurrence_delete_scope != "all_occurrences") {
    return common::Result<domain::Event>::failure(common::make_error(
        "EVENT_DELETE_SCOPE_INVALID", "Event delete scope is invalid"));
  }
  const auto now = clock_();
  std::optional<domain::Event> result;
  auto committed = transaction_->execute(
      "series_complete_cancel_delete_or_reopen", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        auto* event = find_event(state, command.event_id);
        if (event == nullptr || event->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(event_not_found(command.event_id));
        }
        if (!event->has_recurrence || !event->recurrence_id.has_value() ||
            !event->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(
              recurrence_target_invalid("series delete requires a recurring Event"));
        }
        const int actual = event->recurrence_revision.value_or(0);
        if (actual != command.recurrence_revision) {
          return common::Result<common::Unit>::failure(
              revision_conflict(command.recurrence_revision, actual));
        }
        auto mutation_available = ensure_event_mutation_is_available(state, event->id);
        if (!mutation_available.ok()) return mutation_available;
        event->status = std::string(domain::kEventStatusCancelled);
        event->completed_at = std::nullopt;
        event->deleted_at = now;
        event->updated_at = now;
        for (auto& reminder : state.reminders) {
          if (reminder.target_id == event->id &&
              reminder.recurrence_revision == command.recurrence_revision &&
              (is_open(reminder) || is_occurrence_reopen_deferred(reminder))) {
            reminder.status = std::string(domain::kReminderStatusCancelled);
            reminder.is_enabled = false;
            reminder.scheduled_at = std::nullopt;
            reminder.cancellation_reason =
                std::string(domain::kReminderCancellationReasonSeriesDeleted);
            reminder.last_cancelled_at = now;
            reminder.updated_at = now;
          }
        }
        result = *event;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return committed.ok() ? common::Result<domain::Event>::success(*result)
                        : common::Result<domain::Event>::failure(committed.error());
}

}  // namespace excellent_calendar::application
