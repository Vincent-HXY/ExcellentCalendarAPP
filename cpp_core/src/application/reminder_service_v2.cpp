#include "excellent_calendar/application/reminder_service_v2.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <set>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/event_status.hpp"

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

common::Error reminder_time_invalid(std::string field) {
  return common::make_error(
      "REMINDER_TIME_INVALID", "Reminder time is invalid", {{"field", std::move(field)}});
}

common::Error reminder_method_invalid() {
  return common::make_error(
      "REMINDER_METHOD_INVALID", "Reminder method is invalid", {{"field", "methods"}});
}

common::Error unsupported_method(const std::vector<std::string>& methods) {
  return common::make_error(
      "UNSUPPORTED_REMINDER_METHOD",
      "Reminder method is not supported in current version",
      {{"methods", methods.empty() ? "[]" : methods.front()}});
}

common::Error recovery_conflict(const std::string& batch_id) {
  return common::make_error(
      "RECOVERY_BATCH_CONFLICT", "Another incomplete recovery batch conflicts with this request",
      {{"recovery_batch_id", batch_id},
       {"reason", "Reminder belongs to an active recovery batch"}},
      true);
}

common::Error prepared_delivery_conflict(const std::string& reminder_id) {
  return common::make_error(
      "REMINDER_NOT_DELIVERABLE", "Reminder is not deliverable",
      {{"id", reminder_id}, {"reason", "a prepared delivery attempt is still active"}});
}

common::Error target_not_found(const std::string& type, const std::string& id) {
  return common::make_error(
      "REMINDER_TARGET_NOT_FOUND", "Reminder target does not exist",
      {{"target_type", type}, {"target_id", id}});
}

const domain::Event* event_target(const repository::RecurringEventState& state,
                                  const std::string& id) {
  const auto found = std::find_if(state.events.begin(), state.events.end(), [&](const auto& event) {
    return event.id == id && !event.deleted_at.has_value() &&
           event.status == domain::kEventStatusActive;
  });
  return found == state.events.end() ? nullptr : &*found;
}

common::Result<common::Unit> validate_methods(const std::vector<std::string>& methods) {
  std::set<std::string> unique;
  for (const auto& method : methods) {
    if (!domain::is_valid_reminder_method(method) || !unique.insert(method).second) {
      return common::Result<common::Unit>::failure(reminder_method_invalid());
    }
  }
  if (methods.empty()) {
    return common::Result<common::Unit>::failure(reminder_method_invalid());
  }
  // Contract v2 still exposes the broader enum, but the current native scheduler and
  // delivery workflow implement popup only. Persisting ring/wechat or a multi-method
  // Reminder would create a task that can never reach its specified terminal state.
  if (methods != std::vector<std::string>{"popup"}) {
    return common::Result<common::Unit>::failure(unsupported_method(methods));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

std::optional<std::string> active_recovery_batch_id(
    const repository::RecurringEventState& state,
    const domain::Reminder& reminder) {
  if (!reminder.recovery_batch_id.has_value()) return std::nullopt;
  const auto found = std::find_if(
      state.recovery_batches.begin(), state.recovery_batches.end(), [&](const auto& batch) {
        return batch.id == *reminder.recovery_batch_id && batch.status == "in_progress";
      });
  return found == state.recovery_batches.end()
             ? std::nullopt
             : std::optional<std::string>(found->id);
}

bool has_prepared_delivery(const repository::RecurringEventState& state,
                           const std::string& reminder_id) {
  return std::any_of(
      state.notifications.begin(), state.notifications.end(), [&](const auto& notification) {
        return notification.kind == "reminder" &&
               notification.reminder_id == std::optional<std::string>(reminder_id) &&
               notification.status == "prepared";
      });
}

common::Result<std::string> resolve_remind_at(
    const domain::Event& event,
    const std::optional<std::string>& absolute,
    const std::optional<int>& advance_minutes,
    const std::string& now) {
  if (absolute.has_value() == advance_minutes.has_value() ||
      (advance_minutes.has_value() && *advance_minutes < 0)) {
    return common::Result<std::string>::failure(reminder_time_invalid("remind_at"));
  }
  std::string result;
  if (absolute.has_value()) {
    result = *absolute;
  } else {
    if (event.is_all_day) {
      return common::Result<std::string>::failure(reminder_time_invalid("advance_minutes"));
    }
    const auto start = common::parse_iso8601_utc_epoch_seconds(event.start_at);
    if (!start.has_value() || *start < static_cast<std::int64_t>(*advance_minutes) * 60) {
      return common::Result<std::string>::failure(reminder_time_invalid("advance_minutes"));
    }
    result = common::format_epoch_seconds_utc_iso8601(
        *start - static_cast<std::int64_t>(*advance_minutes) * 60);
  }
  const auto instant = common::parse_iso8601_utc_epoch_seconds(result);
  const auto current = common::parse_iso8601_utc_epoch_seconds(now);
  if (!instant.has_value() || !current.has_value() || *instant <= *current) {
    return common::Result<std::string>::failure(reminder_time_invalid("remind_at"));
  }
  return common::Result<std::string>::success(std::move(result));
}

domain::Reminder* find_reminder(std::vector<domain::Reminder>& reminders,
                                const std::string& id) {
  const auto found = std::find_if(reminders.begin(), reminders.end(), [&](const auto& reminder) {
    return reminder.id == id;
  });
  return found == reminders.end() ? nullptr : &*found;
}

bool vector_contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

bool reminder_has_method(const domain::Reminder& reminder,
                         const std::vector<std::string>& methods) {
  return methods.empty() || std::any_of(
      reminder.methods.begin(), reminder.methods.end(), [&](const auto& method) {
        return vector_contains(methods, method);
      });
}

int compare_reminders(const domain::Reminder& left,
                      const domain::Reminder& right,
                      const std::string& sort_by) {
  if (sort_by == "created_at") return left.created_at.compare(right.created_at);
  if (sort_by == "updated_at") return left.updated_at.compare(right.updated_at);
  if (sort_by == "status") return left.status.compare(right.status);
  if (sort_by == "target_type") return left.target_type.compare(right.target_type);
  return left.remind_at.compare(right.remind_at);
}

}  // namespace

ReminderServiceV2::ReminderServiceV2(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : transaction_(std::move(transaction)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Reminder> ReminderServiceV2::create(
    const CreateReminderV2Command& command) {
  if (!domain::is_valid_reminder_target_type(command.target_type) ||
      !common::is_uuid(command.target_id) || !command.is_enabled ||
      !domain::is_valid_reminder_source(command.source)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("CreateReminderRequest", "Reminder fields are invalid"));
  }
  if (!domain::is_supported_reminder_target_type(command.target_type)) {
    return common::Result<domain::Reminder>::failure(common::make_error(
        "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
        {{"feature", "reminder.target_type." + command.target_type}}));
  }
  auto methods = validate_methods(command.methods);
  if (!methods.ok()) return common::Result<domain::Reminder>::failure(methods.error());
  const auto now = clock_();
  const auto id = id_generator_();
  if (!common::is_iso8601_utc_datetime(now) || !common::is_uuid(id)) {
    return common::Result<domain::Reminder>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Reminder v2 Clock or ID generator is invalid"}}));
  }
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state, std::vector<domain::Reminder>& reminders) {
        const auto* event = event_target(state, command.target_id);
        if (event == nullptr) {
          return common::Result<common::Unit>::failure(
              target_not_found(command.target_type, command.target_id));
        }
        if (event->has_recurrence) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid",
              {{"reason", "recurring Event reminders must be changed through event.update"}}));
        }
        auto remind_at = resolve_remind_at(
            *event, command.remind_at, command.advance_minutes, now);
        if (!remind_at.ok()) return common::Result<common::Unit>::failure(remind_at.error());
        if (find_reminder(reminders, id) != nullptr) {
          return common::Result<common::Unit>::failure(common::make_error(
              "NATIVE_INTERNAL_ERROR", "Native internal error",
              {{"reason", "Reminder ID collision"}}));
        }
        domain::Reminder reminder;
        reminder.id = id;
        reminder.target_type = command.target_type;
        reminder.target_id = command.target_id;
        reminder.remind_at = remind_at.value();
        reminder.methods = command.methods;
        reminder.advance_minutes = command.advance_minutes;
        reminder.message = command.message;
        reminder.is_enabled = true;
        reminder.status = std::string(domain::kReminderStatusPending);
        reminder.source = command.source;
        reminder.created_at = now;
        reminder.updated_at = now;
        reminders.push_back(reminder);
        output = reminder;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return updated.ok() ? common::Result<domain::Reminder>::success(*output)
                      : common::Result<domain::Reminder>::failure(updated.error());
}

common::Result<domain::Reminder> ReminderServiceV2::update(
    const UpdateReminderV2Command& command) {
  if (!common::is_uuid(command.reminder_id)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("reminder_id", "reminder_id must be a UUID"));
  }
  const auto now = clock_();
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state, std::vector<domain::Reminder>& reminders) {
        auto* reminder = find_reminder(reminders, command.reminder_id);
        if (reminder == nullptr || reminder->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(reminder_not_found(command.reminder_id));
        }
        if (reminder->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid",
              {{"reason", "recurring Reminder templates must be changed through event.update"}}));
        }
        if (reminder->status == domain::kReminderStatusSent ||
            reminder->status == domain::kReminderStatusFailed ||
            reminder->status == domain::kReminderStatusCancelled ||
            reminder->status == domain::kReminderStatusExpired) {
          return common::Result<common::Unit>::failure(reminder_consumed(command.reminder_id));
        }
        const auto target_type = command.target_type.supplied
                                     ? command.target_type.value
                                     : reminder->target_type;
        const auto target_id = command.target_id.supplied
                                   ? command.target_id.value
                                   : reminder->target_id;
        if (!domain::is_valid_reminder_target_type(target_type) || !common::is_uuid(target_id)) {
          return common::Result<common::Unit>::failure(
              contract_invalid("target", "Reminder target is invalid"));
        }
        if (!domain::is_supported_reminder_target_type(target_type)) {
          return common::Result<common::Unit>::failure(common::make_error(
              "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
              {{"feature", "reminder.target_type." + target_type}}));
        }
        const auto* event = event_target(state, target_id);
        if (event == nullptr) {
          return common::Result<common::Unit>::failure(target_not_found(target_type, target_id));
        }
        if (event->has_recurrence) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid"));
        }
        auto methods_value = command.methods.supplied ? command.methods.value : reminder->methods;
        auto methods_valid = validate_methods(methods_value);
        if (!methods_valid.ok()) return methods_valid;
        auto source = command.source.supplied ? command.source.value : reminder->source;
        if (!domain::is_valid_reminder_source(source)) {
          return common::Result<common::Unit>::failure(
              contract_invalid("source", "Reminder source is invalid"));
        }
        std::optional<std::string> absolute = reminder->advance_minutes.has_value()
                                                  ? std::optional<std::string>{}
                                                  : std::optional<std::string>{reminder->remind_at};
        std::optional<int> advance = reminder->advance_minutes;
        if (command.remind_at.supplied) {
          absolute = command.remind_at.value;
          if (absolute.has_value() && !command.advance_minutes.supplied) {
            advance = std::nullopt;
          }
        }
        if (command.advance_minutes.supplied) {
          advance = command.advance_minutes.value;
          if (advance.has_value() && !command.remind_at.supplied) {
            absolute = std::nullopt;
          }
        }

        const bool target_changed = target_type != reminder->target_type ||
                                    target_id != reminder->target_id;
        const bool time_patch_supplied = command.remind_at.supplied ||
                                         command.advance_minutes.supplied;
        auto resolved_remind_at = reminder->remind_at;
        if (target_changed || time_patch_supplied) {
          auto remind_at = resolve_remind_at(*event, absolute, advance, now);
          if (!remind_at.ok()) {
            return common::Result<common::Unit>::failure(remind_at.error());
          }
          resolved_remind_at = remind_at.value();
        }
        const bool schedule_changed =
            target_changed || resolved_remind_at != reminder->remind_at ||
            advance != reminder->advance_minutes || methods_value != reminder->methods;
        const auto next_message = command.message.supplied
                                      ? command.message.value
                                      : reminder->message;
        const bool content_changed = next_message != reminder->message ||
                                     source != reminder->source;
        if (!schedule_changed && !content_changed) {
          output = *reminder;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        if (const auto batch_id = active_recovery_batch_id(state, *reminder);
            batch_id.has_value()) {
          return common::Result<common::Unit>::failure(recovery_conflict(*batch_id));
        }
        if (has_prepared_delivery(state, reminder->id)) {
          return common::Result<common::Unit>::failure(
              prepared_delivery_conflict(reminder->id));
        }
        reminder->target_type = target_type;
        reminder->target_id = target_id;
        reminder->remind_at = std::move(resolved_remind_at);
        reminder->advance_minutes = advance;
        reminder->methods = std::move(methods_value);
        reminder->message = next_message;
        reminder->source = std::move(source);
        if (schedule_changed) {
          reminder->status = std::string(domain::kReminderStatusPending);
          reminder->scheduled_at = std::nullopt;
          reminder->failure_reason = std::nullopt;
        }
        reminder->updated_at = now;
        output = *reminder;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return updated.ok() ? common::Result<domain::Reminder>::success(*output)
                      : common::Result<domain::Reminder>::failure(updated.error());
}

common::Result<domain::Reminder> ReminderServiceV2::cancel(
    const ReminderIdV2Command& command) {
  if (!common::is_uuid(command.reminder_id)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("reminder_id", "reminder_id must be a UUID"));
  }
  const auto now = clock_();
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state, std::vector<domain::Reminder>& reminders) {
        auto* reminder = find_reminder(reminders, command.reminder_id);
        if (reminder == nullptr || reminder->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(reminder_not_found(command.reminder_id));
        }
        if (reminder->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid"));
        }
        if (reminder->status == domain::kReminderStatusCancelled) {
          output = *reminder;
          return common::Result<common::Unit>::success(common::Unit{});
        }
        if (reminder->status == domain::kReminderStatusSent ||
            reminder->status == domain::kReminderStatusFailed ||
            reminder->status == domain::kReminderStatusExpired) {
          return common::Result<common::Unit>::failure(reminder_consumed(command.reminder_id));
        }
        if (const auto batch_id = active_recovery_batch_id(state, *reminder);
            batch_id.has_value()) {
          return common::Result<common::Unit>::failure(recovery_conflict(*batch_id));
        }
        reminder->status = std::string(domain::kReminderStatusCancelled);
        reminder->is_enabled = false;
        reminder->scheduled_at = std::nullopt;
        reminder->cancellation_reason =
            std::string(domain::kReminderCancellationReasonUserCancelled);
        reminder->last_cancelled_at = now;
        reminder->updated_at = now;
        output = *reminder;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return updated.ok() ? common::Result<domain::Reminder>::success(*output)
                      : common::Result<domain::Reminder>::failure(updated.error());
}

common::Result<domain::Reminder> ReminderServiceV2::enable(
    const ReminderIdV2Command& command) {
  if (!common::is_uuid(command.reminder_id)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("reminder_id", "reminder_id must be a UUID"));
  }
  const auto now = clock_();
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state, std::vector<domain::Reminder>& reminders) {
        auto* reminder = find_reminder(reminders, command.reminder_id);
        if (reminder == nullptr || reminder->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(reminder_not_found(command.reminder_id));
        }
        if (reminder->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid"));
        }
        if (reminder->status == domain::kReminderStatusSent ||
            reminder->status == domain::kReminderStatusFailed ||
            reminder->status == domain::kReminderStatusCancelled ||
            reminder->status == domain::kReminderStatusExpired) {
          return common::Result<common::Unit>::failure(reminder_consumed(command.reminder_id));
        }
        if (const auto batch_id = active_recovery_batch_id(state, *reminder);
            batch_id.has_value()) {
          return common::Result<common::Unit>::failure(recovery_conflict(*batch_id));
        }
        if (event_target(state, reminder->target_id) == nullptr) {
          return common::Result<common::Unit>::failure(
              target_not_found(reminder->target_type, reminder->target_id));
        }
        const auto remind_at = common::parse_iso8601_utc_epoch_seconds(reminder->remind_at);
        const auto current = common::parse_iso8601_utc_epoch_seconds(now);
        if (!remind_at.has_value() || !current.has_value() || *remind_at <= *current) {
          return common::Result<common::Unit>::failure(reminder_time_invalid("remind_at"));
        }
        reminder->is_enabled = true;
        reminder->status = std::string(domain::kReminderStatusPending);
        reminder->scheduled_at = std::nullopt;
        reminder->updated_at = now;
        output = *reminder;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return updated.ok() ? common::Result<domain::Reminder>::success(*output)
                      : common::Result<domain::Reminder>::failure(updated.error());
}

common::Result<domain::Reminder> ReminderServiceV2::disable(
    const ReminderIdV2Command& command) {
  if (!common::is_uuid(command.reminder_id)) {
    return common::Result<domain::Reminder>::failure(
        contract_invalid("reminder_id", "reminder_id must be a UUID"));
  }
  const auto now = clock_();
  std::optional<domain::Reminder> output;
  auto updated = transaction_->update_reminders(
      [&](const repository::RecurringEventState& state, std::vector<domain::Reminder>& reminders) {
        auto* reminder = find_reminder(reminders, command.reminder_id);
        if (reminder == nullptr || reminder->deleted_at.has_value()) {
          return common::Result<common::Unit>::failure(reminder_not_found(command.reminder_id));
        }
        if (reminder->recurrence_revision.has_value()) {
          return common::Result<common::Unit>::failure(common::make_error(
              "RECURRENCE_TARGET_INVALID", "Recurrence target is invalid"));
        }
        if (reminder->status == domain::kReminderStatusSent ||
            reminder->status == domain::kReminderStatusFailed ||
            reminder->status == domain::kReminderStatusCancelled ||
            reminder->status == domain::kReminderStatusExpired) {
          return common::Result<common::Unit>::failure(reminder_consumed(command.reminder_id));
        }
        if (const auto batch_id = active_recovery_batch_id(state, *reminder);
            batch_id.has_value()) {
          return common::Result<common::Unit>::failure(recovery_conflict(*batch_id));
        }
        reminder->is_enabled = false;
        reminder->status = std::string(domain::kReminderStatusPending);
        reminder->scheduled_at = std::nullopt;
        reminder->updated_at = now;
        output = *reminder;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  return updated.ok() ? common::Result<domain::Reminder>::success(*output)
                      : common::Result<domain::Reminder>::failure(updated.error());
}

common::Result<ReminderListPageV2> ReminderServiceV2::list(
    const ReminderListQueryV2& query) const {
  if (query.page < 1 || query.page_size < 1 || query.page_size > 200 ||
      (query.sort_by != "remind_at" && query.sort_by != "created_at" &&
       query.sort_by != "updated_at" && query.sort_by != "status" &&
       query.sort_by != "target_type") ||
      (query.sort_direction != "asc" && query.sort_direction != "desc")) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "pagination_or_sort"}}));
  }
  if (query.cursor.has_value()) {
    return common::Result<ReminderListPageV2>::failure(common::make_error(
        "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
        {{"feature", "reminder.list.cursor"}}));
  }
  if (query.target_type.has_value() &&
      !domain::is_valid_reminder_target_type(*query.target_type)) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "target_type"}}));
  }
  if (query.target_id.has_value() && !common::is_uuid(*query.target_id)) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "target_id"}}));
  }
  if (query.recurrence_revision.has_value() && *query.recurrence_revision < 1) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "recurrence_revision"}}));
  }
  if (query.occurrence_key.has_value() && !common::is_uuid(*query.occurrence_key)) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "occurrence_key"}}));
  }
  for (const auto& method : query.methods) {
    if (!domain::is_valid_reminder_method(method)) {
      return common::Result<ReminderListPageV2>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                             {{"field", "methods"}}));
    }
  }
  for (const auto& status : query.status) {
    if (!domain::is_valid_reminder_status(status)) {
      return common::Result<ReminderListPageV2>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                             {{"field", "status"}}));
    }
  }
  const auto from = query.remind_at_from.has_value()
                        ? common::parse_iso8601_utc_epoch_seconds(*query.remind_at_from)
                        : std::optional<std::int64_t>{};
  const auto to = query.remind_at_to.has_value()
                      ? common::parse_iso8601_utc_epoch_seconds(*query.remind_at_to)
                      : std::optional<std::int64_t>{};
  if ((query.remind_at_from.has_value() && !from.has_value()) ||
      (query.remind_at_to.has_value() && !to.has_value()) ||
      (from.has_value() && to.has_value() && *from > *to)) {
    return common::Result<ReminderListPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "remind_at"}}));
  }

  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<ReminderListPageV2>::failure(loaded.error());
  std::vector<domain::Reminder> filtered;
  for (const auto& reminder : loaded.value().reminders) {
    if (!query.include_deleted && reminder.deleted_at.has_value()) continue;
    if (query.target_type.has_value() && reminder.target_type != *query.target_type) continue;
    if (query.target_id.has_value() && reminder.target_id != *query.target_id) continue;
    if (query.recurrence_revision.has_value() &&
        reminder.recurrence_revision != query.recurrence_revision) continue;
    if (query.occurrence_key.has_value() && reminder.occurrence_key != query.occurrence_key) continue;
    const auto instant = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
    if (!instant.has_value()) {
      return common::Result<ReminderListPageV2>::failure(common::make_error(
          "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
          {{"field", "Reminder.remind_at"}}));
    }
    if (from.has_value() && *instant < *from) continue;
    if (to.has_value() && *instant > *to) continue;
    if (!reminder_has_method(reminder, query.methods)) continue;
    if (!query.status.empty() && !vector_contains(query.status, reminder.status)) continue;
    if (query.is_enabled.has_value() && reminder.is_enabled != *query.is_enabled) continue;
    filtered.push_back(reminder);
  }
  std::stable_sort(filtered.begin(), filtered.end(), [&](const auto& left, const auto& right) {
    const int comparison = compare_reminders(left, right, query.sort_by);
    if (comparison == 0) {
      return query.sort_direction == "desc" ? left.id > right.id : left.id < right.id;
    }
    return query.sort_direction == "desc" ? comparison > 0 : comparison < 0;
  });
  ReminderListPageV2 page;
  page.total = static_cast<int>(filtered.size());
  page.page = query.page;
  page.page_size = query.page_size;
  const auto page_index = static_cast<std::size_t>(query.page - 1);
  const auto page_size = static_cast<std::size_t>(query.page_size);
  const auto offset = page_index > std::numeric_limits<std::size_t>::max() / page_size
                          ? std::numeric_limits<std::size_t>::max()
                          : page_index * page_size;
  page.has_more = offset < filtered.size() && page_size < filtered.size() - offset;
  if (offset < filtered.size()) {
    const auto end = offset + std::min(page_size, filtered.size() - offset);
    page.items.assign(filtered.begin() + static_cast<std::ptrdiff_t>(offset),
                      filtered.begin() + static_cast<std::ptrdiff_t>(end));
  }
  return common::Result<ReminderListPageV2>::success(std::move(page));
}

}  // namespace excellent_calendar::application
