#include "excellent_calendar/application/rolling_reminder_service.hpp"

#include <algorithm>
#include <cstdint>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kReminderNamespace = "57b84799-6049-567e-8f29-ae597c333140";
constexpr int kMaximumExpansionCount = 1000000;

common::Error invalid(std::string reason, std::string field = "reminder") {
  return common::make_error(
      "RECURRENCE_RULE_INVALID", "Recurrence rule is invalid",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

bool terminal_occurrence(const std::vector<domain::EventOccurrenceState>& states,
                         const domain::EventOccurrence& occurrence) {
  return std::any_of(states.begin(), states.end(), [&](const auto& state) {
    return state.event_id == occurrence.event_id &&
           state.recurrence_revision == occurrence.recurrence_revision &&
           state.occurrence_key == occurrence.occurrence_key &&
           domain::is_terminal_occurrence_status(state.status);
  });
}

bool is_open(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
}

bool same_business_content(const domain::Reminder& left, const domain::Reminder& right) {
  return left.target_type == right.target_type && left.target_id == right.target_id &&
         left.recurrence_revision == right.recurrence_revision &&
         left.occurrence_key == right.occurrence_key &&
         left.occurrence_start_at == right.occurrence_start_at &&
         left.remind_at == right.remind_at && left.advance_minutes == right.advance_minutes &&
         left.methods == right.methods && left.message == right.message &&
         left.source == right.source;
}

std::string canonical_reminder_name(const domain::EventOccurrence& occurrence,
                                    int advance_minutes) {
  return "[\"" + occurrence.event_id + "\"," +
         std::to_string(occurrence.recurrence_revision) + ",\"" +
         occurrence.occurrence_key + "\"," + std::to_string(advance_minutes) +
         ",[\"popup\"]]";
}

}  // namespace

RollingReminderService::RollingReminderService(
    std::shared_ptr<RecurrenceService> recurrence_service)
    : recurrence_service_(std::move(recurrence_service)) {}

common::Result<domain::Reminder> RollingReminderService::create_for_occurrence(
    const domain::EventOccurrence& occurrence,
    const domain::RecurringReminderDraft& draft,
    std::string created_at,
    std::optional<std::string> recovery_batch_id,
    bool allow_past) const {
  if (!occurrence.occurrence_start_at.has_value() || draft.advance_minutes < 0 ||
      draft.methods != std::vector<std::string>{"popup"} || !draft.is_enabled) {
    return common::Result<domain::Reminder>::failure(
        invalid("recurring Reminder template must be enabled popup with nonnegative advance"));
  }
  const auto occurrence_start =
      common::parse_iso8601_utc_epoch_seconds(*occurrence.occurrence_start_at);
  const auto now = common::parse_iso8601_utc_epoch_seconds(created_at);
  if (!occurrence_start.has_value() || !now.has_value()) {
    return common::Result<domain::Reminder>::failure(invalid("Reminder time is invalid"));
  }
  const auto remind_epoch =
      *occurrence_start - static_cast<std::int64_t>(draft.advance_minutes) * 60;
  if (!allow_past && remind_epoch <= *now) {
    return common::Result<domain::Reminder>::failure(common::make_error(
        "REMINDER_TIME_INVALID", "Reminder time is invalid", {{"field", "remind_at"}}));
  }
  if (allow_past && !recovery_batch_id.has_value()) {
    return common::Result<domain::Reminder>::failure(
        invalid("past recurring Reminder requires a recovery batch"));
  }
  auto id = common::generate_uuid_v5(
      kReminderNamespace, canonical_reminder_name(occurrence, draft.advance_minutes));
  if (!id.ok()) return common::Result<domain::Reminder>::failure(id.error());

  domain::Reminder reminder;
  reminder.id = id.value();
  reminder.target_type = std::string(domain::kReminderTargetEvent);
  reminder.target_id = occurrence.event_id;
  reminder.recurrence_revision = occurrence.recurrence_revision;
  reminder.occurrence_key = occurrence.occurrence_key;
  reminder.occurrence_start_at = occurrence.occurrence_start_at;
  reminder.remind_at = common::format_epoch_seconds_utc_iso8601(remind_epoch);
  reminder.methods = {"popup"};
  reminder.advance_minutes = draft.advance_minutes;
  reminder.message = draft.message;
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.recovery_batch_id = std::move(recovery_batch_id);
  reminder.source = draft.source;
  reminder.created_at = created_at;
  reminder.updated_at = std::move(created_at);
  return common::Result<domain::Reminder>::success(std::move(reminder));
}

common::Result<domain::Reminder> RollingReminderService::first_eligible_after(
    const domain::RecurringEventSchedule& event,
    const domain::Recurrence& recurrence,
    const domain::RecurringReminderDraft& draft,
    const std::vector<domain::EventOccurrenceState>& occurrence_states,
    std::string_view after_at,
    std::string created_at) const {
  const auto after = common::parse_iso8601_utc_epoch_seconds(after_at);
  const auto created = common::parse_iso8601_utc_epoch_seconds(created_at);
  if (!after.has_value() || !created.has_value() || event.is_all_day ||
      draft.advance_minutes < 0) {
    return common::Result<domain::Reminder>::failure(invalid("rolling Reminder search is invalid"));
  }
  for (int index = 0; index < kMaximumExpansionCount; ++index) {
    auto occurrence = recurrence_service_->occurrence_at(event, recurrence, index);
    if (!occurrence.ok()) return common::Result<domain::Reminder>::failure(occurrence.error());
    const auto occurrence_start =
        common::parse_iso8601_utc_epoch_seconds(*occurrence.value().occurrence_start_at);
    if (!occurrence_start.has_value()) {
      return common::Result<domain::Reminder>::failure(invalid("expanded occurrence is invalid"));
    }
    const auto remind_epoch =
        *occurrence_start - static_cast<std::int64_t>(draft.advance_minutes) * 60;
    if (remind_epoch <= *after || remind_epoch <= *created ||
        terminal_occurrence(occurrence_states, occurrence.value())) {
      continue;
    }
    return create_for_occurrence(occurrence.value(), draft, std::move(created_at));
  }
  return common::Result<domain::Reminder>::failure(
      invalid("occurrence expansion exceeded safe bound"));
}

domain::RecurringReminderDraft RollingReminderService::template_from(
    const domain::Reminder& reminder) const {
  return domain::RecurringReminderDraft{
      reminder.advance_minutes.value_or(0), reminder.methods, reminder.message,
      reminder.is_enabled, reminder.source};
}

common::Result<common::Unit> RollingReminderService::insert_idempotent(
    repository::RecurringEventState& state,
    const domain::Reminder& reminder) const {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(), [&](const auto& item) {
    return item.id == reminder.id;
  });
  if (found == state.reminders.end()) {
    state.reminders.push_back(reminder);
    return common::Result<common::Unit>::success(common::Unit{});
  }
  if (!same_business_content(*found, reminder)) {
    return common::Result<common::Unit>::failure(common::make_error(
        "REMINDER_IDEMPOTENCY_CONFLICT",
        "Deterministic Reminder ID already exists with different business content",
        {{"reminder_id", reminder.id}}));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> RollingReminderService::ensure_next_in_state(
    repository::RecurringEventState& state,
    const domain::Event& event,
    const domain::Recurrence& recurrence,
    const domain::RecurringReminderDraft& draft,
    std::string after_at,
    const std::string& now) const {
  for (int attempts = 0; attempts < kMaximumExpansionCount; ++attempts) {
    auto candidate = first_eligible_after(
        domain::recurring_schedule_from_event(event), recurrence, draft,
        state.occurrence_states, after_at, now);
    if (!candidate.ok()) return common::Result<common::Unit>::failure(candidate.error());
    const auto found = std::find_if(
        state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
          return reminder.id == candidate.value().id;
        });
    if (found == state.reminders.end()) {
      state.reminders.push_back(candidate.value());
      return common::Result<common::Unit>::success(common::Unit{});
    }
    if (!same_business_content(*found, candidate.value())) {
      return common::Result<common::Unit>::failure(common::make_error(
          "REMINDER_IDEMPOTENCY_CONFLICT",
          "Deterministic Reminder ID already exists with different business content",
          {{"reminder_id", candidate.value().id}}));
    }
    if (is_open(*found)) return common::Result<common::Unit>::success(common::Unit{});
    const auto found_remind_at =
        common::parse_iso8601_utc_epoch_seconds(found->remind_at);
    const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
    if (!found->deleted_at.has_value() &&
        found->status == domain::kReminderStatusCancelled &&
        found->cancellation_reason ==
            std::string(domain::kReminderCancellationReasonOccurrenceReopened) &&
        found_remind_at.has_value() && now_epoch.has_value() &&
        *found_remind_at > *now_epoch) {
      found->status = std::string(domain::kReminderStatusPending);
      found->is_enabled = true;
      found->scheduled_at = std::nullopt;
      found->reactivated_at = now;
      ++found->reactivation_count;
      found->updated_at = now;
      return common::Result<common::Unit>::success(common::Unit{});
    }
    after_at = candidate.value().remind_at;
  }
  return common::Result<common::Unit>::failure(common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error",
      {{"reason", "rolling Reminder expansion exceeded safe bound"}}));
}

}  // namespace excellent_calendar::application
