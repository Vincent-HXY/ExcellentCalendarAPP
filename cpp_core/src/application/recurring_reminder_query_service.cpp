#include "excellent_calendar/application/recurring_reminder_query_service.hpp"

#include <algorithm>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace excellent_calendar::application {
namespace {

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error reminder_not_found(const std::string& id) {
  return common::make_error(
      "REMINDER_NOT_FOUND", "Reminder not found", {{"reminder_id", id}});
}

common::Error reminder_consumed(const std::string& id) {
  return common::make_error(
      "REMINDER_ALREADY_CONSUMED", "Reminder has already been consumed",
      {{"reminder_id", id}});
}

common::Error reminder_schedule_conflict(const domain::Reminder& reminder,
                                         const std::string& expected_remind_at) {
  return common::make_error(
      "REMINDER_SCHEDULE_CONFLICT",
      "Reminder schedule changed before the Android registration acknowledgement",
      {{"reminder_id", reminder.id},
       {"expected_remind_at", expected_remind_at},
       {"current_remind_at", reminder.remind_at}},
      true);
}

const domain::Reminder* find_reminder(const repository::RecurringEventState& state,
                                      const std::string& id) {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& reminder) { return reminder.id == id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

bool has_supported_method(const domain::Reminder& reminder,
                          const std::set<std::string>& supported) {
  return std::any_of(reminder.methods.begin(), reminder.methods.end(),
                     [&](const auto& method) { return supported.count(method) != 0U; });
}

}  // namespace

RecurringReminderQueryService::RecurringReminderQueryService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    ClockFn clock)
    : transaction_(std::move(transaction)), clock_(std::move(clock)) {}

common::Result<domain::Reminder> RecurringReminderQueryService::get_reminder(
    const std::string& reminder_id) const {
  if (!common::is_uuid(reminder_id)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("reminder_id", "reminder_id must be a UUID"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<domain::Reminder>::failure(loaded.error());
  const auto* reminder = find_reminder(loaded.value(), reminder_id);
  if (reminder == nullptr || reminder->deleted_at.has_value()) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(reminder_id));
  }
  return common::Result<domain::Reminder>::success(*reminder);
}

common::Result<std::vector<domain::RecurringReminderDraft>>
RecurringReminderQueryService::list_templates(
    const std::string& event_id,
    int recurrence_revision) const {
  if (!common::is_uuid(event_id) || recurrence_revision < 1) {
    return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
        contract_invalid("event_id", "event identity is invalid"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
        loaded.error());
  }
  std::map<std::string, domain::RecurringReminderDraft> unique;
  for (const auto& reminder : loaded.value().reminders) {
    if (reminder.target_id != event_id ||
        reminder.recurrence_revision != recurrence_revision ||
        !reminder.advance_minutes.has_value()) {
      continue;
    }
    const auto key = std::to_string(*reminder.advance_minutes) + ":" +
                     (reminder.methods.empty() ? "" : reminder.methods.front());
    unique[key] = domain::RecurringReminderDraft{
        *reminder.advance_minutes,
        reminder.methods,
        reminder.message,
        true,
        reminder.source};
  }
  std::vector<domain::RecurringReminderDraft> result;
  result.reserve(unique.size());
  for (const auto& [_, draft] : unique) result.push_back(draft);
  return common::Result<std::vector<domain::RecurringReminderDraft>>::success(
      std::move(result));
}

common::Result<std::vector<domain::Reminder>>
RecurringReminderQueryService::list_current_for_event(
    const std::string& event_id,
    int recurrence_revision) const {
  if (!common::is_uuid(event_id) || recurrence_revision < 1) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        contract_invalid("event_id", "event identity is invalid"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::Reminder>>::failure(loaded.error());
  }
  std::vector<domain::Reminder> result;
  for (const auto& reminder : loaded.value().reminders) {
    if (reminder.target_id == event_id &&
        reminder.recurrence_revision == recurrence_revision &&
        !reminder.deleted_at.has_value()) {
      result.push_back(reminder);
    }
  }
  std::sort(result.begin(), result.end(), [](const auto& left, const auto& right) {
    if (left.remind_at != right.remind_at) return left.remind_at < right.remind_at;
    return left.id < right.id;
  });
  return common::Result<std::vector<domain::Reminder>>::success(std::move(result));
}

common::Result<std::vector<domain::Reminder>>
RecurringReminderQueryService::list_for_event(
    const std::string& event_id,
    std::optional<int> recurrence_revision) const {
  if (!common::is_uuid(event_id) ||
      (recurrence_revision.has_value() && *recurrence_revision < 1)) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        contract_invalid("event_id", "event identity is invalid"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::Reminder>>::failure(loaded.error());
  }
  std::vector<domain::Reminder> result;
  for (const auto& reminder : loaded.value().reminders) {
    if (reminder.target_type == domain::kReminderTargetEvent &&
        reminder.target_id == event_id &&
        reminder.recurrence_revision == recurrence_revision &&
        !reminder.deleted_at.has_value()) {
      result.push_back(reminder);
    }
  }
  std::sort(result.begin(), result.end(), [](const auto& left, const auto& right) {
    if (left.remind_at != right.remind_at) return left.remind_at < right.remind_at;
    return left.id < right.id;
  });
  return common::Result<std::vector<domain::Reminder>>::success(std::move(result));
}

common::Result<RecurringSchedulableReminderPage>
RecurringReminderQueryService::list_schedulable(
    const ListRecurringSchedulableRemindersCommand& command) const {
  const auto from_epoch = command.from_at.has_value()
                              ? common::parse_iso8601_utc_epoch_seconds(*command.from_at)
                              : std::optional<std::int64_t>{};
  const auto to_epoch = command.to_at.has_value()
                            ? common::parse_iso8601_utc_epoch_seconds(*command.to_at)
                            : std::optional<std::int64_t>{};
  if ((command.from_at.has_value() && !from_epoch.has_value()) ||
      (command.to_at.has_value() && !to_epoch.has_value()) ||
      (from_epoch.has_value() && to_epoch.has_value() && *from_epoch > *to_epoch)) {
    return common::Result<RecurringSchedulableReminderPage>::failure(
        contract_invalid("range", "from_at/to_at range is invalid"));
  }
  if (command.cursor_remind_at.has_value() != command.cursor_reminder_id.has_value()) {
    return common::Result<RecurringSchedulableReminderPage>::failure(
        contract_invalid("cursor", "cursor requires remind_at and reminder_id"));
  }
  std::optional<std::int64_t> cursor_epoch;
  if (command.cursor_remind_at.has_value()) {
    cursor_epoch = common::parse_iso8601_utc_epoch_seconds(*command.cursor_remind_at);
    if (!cursor_epoch.has_value() || !common::is_uuid(*command.cursor_reminder_id)) {
      return common::Result<RecurringSchedulableReminderPage>::failure(
          contract_invalid("cursor", "cursor is invalid"));
    }
  }
  if (command.limit < 1 || command.limit > 500 || command.supported_methods.empty()) {
    return common::Result<RecurringSchedulableReminderPage>::failure(
        contract_invalid("limit", "limit or supported_methods is invalid"));
  }
  std::set<std::string> supported;
  for (const auto& method : command.supported_methods) {
    if (method != domain::kReminderMethodPopup || !supported.insert(method).second) {
      return common::Result<RecurringSchedulableReminderPage>::failure(common::make_error(
          "UNSUPPORTED_REMINDER_METHOD", "Reminder method is not supported in current version",
          {{"method", method}}));
    }
  }

  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<RecurringSchedulableReminderPage>::failure(loaded.error());
  }
  RecurringSchedulableReminderPage page;
  std::vector<domain::Reminder> candidates;
  for (const auto& reminder : loaded.value().reminders) {
    if (!reminder.is_enabled || reminder.deleted_at.has_value() ||
        reminder.recovery_batch_id.has_value()) {
      continue;
    }
    const bool eligible = reminder.status == domain::kReminderStatusPending ||
                          (command.include_scheduled &&
                           reminder.status == domain::kReminderStatusScheduled);
    if (!eligible) continue;
    const auto remind_epoch = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
    if (!remind_epoch.has_value()) {
      return common::Result<RecurringSchedulableReminderPage>::failure(common::make_error(
          "STORAGE_DATA_CORRUPTED", "Stored data is corrupted",
          {{"field", "remind_at"}}));
    }
    if ((from_epoch.has_value() && *remind_epoch < *from_epoch) ||
        (to_epoch.has_value() && *remind_epoch > *to_epoch) ||
        (cursor_epoch.has_value() &&
         (*remind_epoch < *cursor_epoch ||
          (*remind_epoch == *cursor_epoch &&
           reminder.id <= *command.cursor_reminder_id)))) {
      continue;
    }
    if (!has_supported_method(reminder, supported)) {
      page.unsupported_reminder_ids.push_back(reminder.id);
      continue;
    }
    candidates.push_back(reminder);
  }
  std::sort(candidates.begin(), candidates.end(), [](const auto& left, const auto& right) {
    if (left.remind_at != right.remind_at) return left.remind_at < right.remind_at;
    return left.id < right.id;
  });
  std::sort(page.unsupported_reminder_ids.begin(), page.unsupported_reminder_ids.end());
  page.has_more = candidates.size() > static_cast<std::size_t>(command.limit);
  if (page.has_more) candidates.resize(static_cast<std::size_t>(command.limit));
  page.items = std::move(candidates);
  if (page.has_more && !page.items.empty()) {
    page.next_cursor_remind_at = page.items.back().remind_at;
    page.next_cursor_reminder_id = page.items.back().id;
  }
  return common::Result<RecurringSchedulableReminderPage>::success(std::move(page));
}

common::Result<domain::Reminder> RecurringReminderQueryService::mark_scheduled(
    const MarkRecurringReminderScheduledCommand& command) {
  if (!common::is_uuid(command.reminder_id) ||
      !common::is_iso8601_utc_datetime(command.expected_remind_at) ||
      !common::is_iso8601_utc_datetime(command.scheduled_at)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid(
            "MarkReminderScheduledRequest",
            "identity, expected_remind_at, or scheduled_at is invalid"));
  }
  const auto now = clock_();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<domain::Reminder>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Reminder query Clock returned invalid UTC time"}}));
  }
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState&, std::vector<domain::Reminder>& reminders) {
        const auto found = std::find_if(reminders.begin(), reminders.end(), [&](const auto& value) {
          return value.id == command.reminder_id;
        });
        if (found == reminders.end() || found->deleted_at.has_value() || !found->is_enabled ||
            found->status == domain::kReminderStatusCancelled) {
          return common::Result<common::Unit>::failure(
              reminder_not_found(command.reminder_id));
        }
        if (found->status == domain::kReminderStatusSent ||
            found->status == domain::kReminderStatusFailed ||
            found->status == domain::kReminderStatusExpired) {
          return common::Result<common::Unit>::failure(
              reminder_consumed(command.reminder_id));
        }
        if (found->status != domain::kReminderStatusPending &&
            found->status != domain::kReminderStatusScheduled) {
          return common::Result<common::Unit>::failure(
              contract_invalid("status", "Reminder cannot transition to scheduled"));
        }
        if (found->remind_at != command.expected_remind_at) {
          return common::Result<common::Unit>::failure(
              reminder_schedule_conflict(*found, command.expected_remind_at));
        }
        found->status = std::string(domain::kReminderStatusScheduled);
        found->scheduled_at = command.scheduled_at;
        found->failure_reason = std::nullopt;
        found->updated_at = now;
        output = *found;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!updated.ok()) return common::Result<domain::Reminder>::failure(updated.error());
  return common::Result<domain::Reminder>::success(*output);
}

}  // namespace excellent_calendar::application
