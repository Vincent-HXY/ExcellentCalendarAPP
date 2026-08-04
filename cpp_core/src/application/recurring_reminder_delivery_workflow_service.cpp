#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"

#include <algorithm>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/error_code_metadata.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/event_status.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kDeliveryNamespace = "74f9acf9-a4ce-59d1-9934-5cd7ce796976";

common::Error contract_error(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error reminder_not_found(const std::string& id) {
  return common::make_error("REMINDER_NOT_FOUND", "Reminder not found", {{"id", id}});
}

common::Error reminder_not_deliverable(const domain::Reminder& reminder) {
  return common::make_error(
      "REMINDER_NOT_DELIVERABLE", "Reminder is not deliverable",
      {{"id", reminder.id}, {"status", reminder.status}});
}

common::Error already_consumed(const std::string& id) {
  return common::make_error(
      "REMINDER_ALREADY_CONSUMED", "Reminder has already been consumed", {{"id", id}});
}

common::Error attempt_invalid(const std::string& id, std::string reason) {
  return common::make_error(
      "DELIVERY_ATTEMPT_INVALID",
      "Delivery attempt is missing, not prepared, or finalized with a conflicting outcome",
      {{"delivery_attempt_id", id}, {"reason", std::move(reason)}});
}

common::Error recovery_conflict(const std::string& id, std::string reason) {
  return common::make_error(
      "RECOVERY_BATCH_CONFLICT", "Another incomplete recovery batch conflicts with this request",
      {{"recovery_batch_id", id}, {"reason", std::move(reason)}}, true);
}

bool is_open(const domain::Reminder& reminder) {
  return !reminder.deleted_at.has_value() && reminder.is_enabled &&
         (reminder.status == domain::kReminderStatusPending ||
          reminder.status == domain::kReminderStatusScheduled);
}

bool is_consumed(const domain::Reminder& reminder) {
  return reminder.status == domain::kReminderStatusSent ||
         reminder.status == domain::kReminderStatusFailed ||
         reminder.status == domain::kReminderStatusCancelled ||
         reminder.status == domain::kReminderStatusExpired || reminder.deleted_at.has_value();
}

domain::Reminder* find_reminder(repository::RecurringEventState& state, const std::string& id) {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

const domain::Reminder* find_reminder(const repository::RecurringEventState& state,
                                      const std::string& id) {
  const auto found = std::find_if(state.reminders.begin(), state.reminders.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.reminders.end() ? nullptr : &*found;
}

domain::ReminderRecoveryBatch* find_batch(repository::RecurringEventState& state,
                                          const std::string& id) {
  const auto found = std::find_if(state.recovery_batches.begin(), state.recovery_batches.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.recovery_batches.end() ? nullptr : &*found;
}

const domain::ReminderRecoveryBatch* find_batch(const repository::RecurringEventState& state,
                                                const std::string& id) {
  const auto found = std::find_if(state.recovery_batches.begin(), state.recovery_batches.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.recovery_batches.end() ? nullptr : &*found;
}

const domain::Event* find_event(const repository::RecurringEventState& state,
                                const std::string& id) {
  const auto found = std::find_if(state.events.begin(), state.events.end(),
                                  [&](const auto& value) { return value.id == id; });
  return found == state.events.end() ? nullptr : &*found;
}

const domain::Recurrence* find_recurrence(const repository::RecurringEventState& state,
                                          const std::string& id,
                                          int revision) {
  const auto found = std::find_if(
      state.recurrences.begin(), state.recurrences.end(), [&](const auto& value) {
        return value.id == id && value.revision == revision;
      });
  return found == state.recurrences.end() ? nullptr : &*found;
}

bool contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

common::Result<std::string> reminder_delivery_id(const std::string& reminder_id,
                                                 const std::string& method) {
  return common::generate_uuid_v5(
      kDeliveryNamespace, "[\"" + reminder_id + "\",\"" + method + "\"]");
}

std::optional<domain::Notification> latest_for_delivery(
    const std::vector<domain::Notification>& notifications,
    const std::string& delivery_id) {
  std::optional<domain::Notification> result;
  for (const auto& item : notifications) {
    if (item.delivery_id == delivery_id) result = item;
  }
  return result;
}

bool same_prepared_payload(const domain::Notification& previous,
                           const domain::Notification& expected) {
  return previous.kind == expected.kind &&
         previous.reminder_id == expected.reminder_id &&
         previous.recovery_batch_id == expected.recovery_batch_id &&
         previous.target_type == expected.target_type &&
         previous.target_id == expected.target_id &&
         previous.occurrence_key == expected.occurrence_key &&
         previous.method == expected.method && previous.title == expected.title &&
         previous.body == expected.body && previous.planned_at == expected.planned_at;
}

bool same_adopted_prepared_payload(const domain::Notification& previous,
                                   const domain::Notification& expected) {
  return previous.kind == expected.kind &&
         previous.reminder_id == expected.reminder_id &&
         previous.target_type == expected.target_type &&
         previous.target_id == expected.target_id &&
         previous.occurrence_key == expected.occurrence_key &&
         previous.method == expected.method && previous.title == expected.title &&
         previous.body == expected.body && previous.planned_at == expected.planned_at;
}

std::optional<std::string> effective_recovery_batch_id(
    const domain::Notification& notification) {
  return notification.recovery_batch_id.has_value()
             ? notification.recovery_batch_id
             : notification.resolved_by_recovery_batch_id;
}

std::string event_title(const repository::RecurringEventState& state,
                        const domain::Reminder& reminder) {
  const auto* event = find_event(state, reminder.target_id);
  return event != nullptr && !common::trim_ascii(event->title).empty() ? event->title : "日程提醒";
}

std::string summary_body(const domain::ReminderRecoveryBatch& batch) {
  std::vector<std::string> parts;
  if (batch.older_skipped_reminder_count > 0) {
    parts.push_back("你有 " + std::to_string(batch.older_skipped_reminder_count) +
                    " 条超过三天的提醒未能及时送达，较早的提醒已自动跳过。");
  }
  if (batch.window_overflow_count > 0) {
    parts.push_back("另有 " + std::to_string(batch.window_overflow_count) +
                    " 条三天内提醒已合并展示。");
  }
  if (parts.empty()) return "提醒恢复已完成。";
  return parts.size() == 1U ? parts.front() : parts.front() + parts.back();
}

bool same_finalization(const domain::Notification& notification,
                       const FinalizeDeliveryCommand& command) {
  if (command.outcome == "sent") {
    return notification.status == domain::kNotificationStatusSent &&
           !command.failure_class.has_value() && !command.error_code.has_value();
  }
  return notification.status == domain::kNotificationStatusFailed &&
         notification.failure_class == command.failure_class &&
         notification.error_code == command.error_code;
}

bool valid_finalize_command(const FinalizeDeliveryCommand& command) {
  if (!common::is_uuid(command.delivery_attempt_id)) return false;
  if (command.outcome == "sent") {
    return !command.failure_class.has_value() && !command.error_code.has_value();
  }
  return command.outcome == "failed" && command.failure_class.has_value() &&
         (*command.failure_class == "retryable" || *command.failure_class == "permanent") &&
         command.error_code.has_value() && !common::trim_ascii(*command.error_code).empty();
}

void consume_reminder(domain::Reminder& reminder,
                      const FinalizeDeliveryCommand& command,
                      const std::string& now) {
  reminder.scheduled_at = std::nullopt;
  reminder.updated_at = now;
  if (command.outcome == "sent") {
    reminder.status = std::string(domain::kReminderStatusSent);
    reminder.last_triggered_at = now;
    reminder.failure_reason = std::nullopt;
  } else if (command.failure_class == "permanent") {
    reminder.status = std::string(domain::kReminderStatusFailed);
    reminder.failure_reason = command.error_code;
  } else {
    reminder.status = std::string(domain::kReminderStatusPending);
    reminder.failure_reason = command.error_code;
  }
}

std::optional<domain::Reminder> find_open_successor(
    const repository::RecurringEventState& state,
    const domain::Reminder& reminder) {
  if (!reminder.recurrence_revision.has_value() || !reminder.advance_minutes.has_value()) {
    return std::nullopt;
  }
  const domain::Reminder* successor = nullptr;
  for (const auto& candidate : state.reminders) {
    if (candidate.id == reminder.id || candidate.target_id != reminder.target_id ||
        candidate.recurrence_revision != reminder.recurrence_revision ||
        candidate.advance_minutes != reminder.advance_minutes || candidate.methods != reminder.methods ||
        candidate.remind_at <= reminder.remind_at || !is_open(candidate)) continue;
    if (successor == nullptr || candidate.remind_at < successor->remind_at ||
        (candidate.remind_at == successor->remind_at && candidate.id < successor->id)) {
      successor = &candidate;
    }
  }
  return successor == nullptr ? std::nullopt : std::optional<domain::Reminder>(*successor);
}

common::Result<std::optional<domain::Reminder>> ensure_successor(
    repository::RecurringEventState& state,
    const domain::Reminder& source_reminder,
    const std::string& now,
    const RollingReminderService& rolling) {
  const auto reminder = source_reminder;
  if (!reminder.recurrence_revision.has_value() || !reminder.advance_minutes.has_value()) {
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  }
  const auto* event = find_event(state, reminder.target_id);
  if (event == nullptr || event->deleted_at.has_value() ||
      event->status != domain::kEventStatusActive || !event->recurrence_id.has_value() ||
      event->recurrence_revision != reminder.recurrence_revision) {
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  }
  const auto* recurrence = find_recurrence(
      state, *event->recurrence_id, *reminder.recurrence_revision);
  if (recurrence == nullptr) {
    return common::Result<std::optional<domain::Reminder>>::failure(common::make_error(
        "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
        {{"reason", "current recurrence revision is missing"}}));
  }
  auto ensured = rolling.ensure_next_in_state(
      state, *event, *recurrence, rolling.template_from(reminder), reminder.remind_at, now);
  if (!ensured.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(ensured.error());
  }
  return common::Result<std::optional<domain::Reminder>>::success(
      find_open_successor(state, reminder));
}

bool batch_is_complete(const repository::RecurringEventState& state,
                       const domain::ReminderRecoveryBatch& batch) {
  for (const auto& id : batch.detail_reminder_ids) {
    const auto* reminder = find_reminder(state, id);
    if (reminder == nullptr || !is_consumed(*reminder)) return false;
  }
  for (const auto& id : batch.summary_reminder_ids) {
    const auto* reminder = find_reminder(state, id);
    if (reminder == nullptr || !is_consumed(*reminder)) return false;
  }
  if (!batch.summary_delivery_id.has_value()) return true;
  const auto notification = latest_for_delivery(state.notifications, *batch.summary_delivery_id);
  return notification.has_value() &&
         (notification->status == domain::kNotificationStatusSent ||
          (notification->status == domain::kNotificationStatusFailed &&
           notification->failure_class == "permanent"));
}

void complete_batch_if_ready(repository::RecurringEventState& state,
                             domain::ReminderRecoveryBatch* batch,
                             const std::string& now) {
  if (batch != nullptr && batch->status == domain::kRecoveryInProgress &&
      batch_is_complete(state, *batch)) {
    batch->status = std::string(domain::kRecoveryCompleted);
    batch->completed_at = now;
  }
}

}  // namespace

RecurringReminderDeliveryWorkflowService::RecurringReminderDeliveryWorkflowService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    std::shared_ptr<RollingReminderService> rolling_reminder_service,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : transaction_(std::move(transaction)),
      rolling_reminder_service_(std::move(rolling_reminder_service)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<PrepareDeliveryResult>
RecurringReminderDeliveryWorkflowService::prepare_delivery(
    const PrepareDeliveryCommand& command) {
  const auto now = clock_();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<PrepareDeliveryResult>::failure(
        common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                           {{"reason", "delivery clock returned invalid UTC time"}}));
  }
  std::optional<PrepareDeliveryResult> output;
  auto prepared = transaction_->prepare_notification(
      [&](const repository::RecurringEventState& state,
          std::vector<domain::Notification>& notifications) {
        std::string delivery_id;
        domain::Notification notification;
        if (command.kind == "reminder") {
          if (!command.reminder_id.has_value() || !command.expected_remind_at.has_value() ||
              !common::is_uuid(*command.reminder_id) ||
              !common::is_iso8601_utc_datetime(*command.expected_remind_at)) {
            return common::Result<common::Unit>::failure(
                contract_error("reminder_id", "reminder delivery identity is invalid"));
          }
          const auto* reminder = find_reminder(state, *command.reminder_id);
          if (reminder == nullptr) {
            return common::Result<common::Unit>::failure(reminder_not_found(*command.reminder_id));
          }
          if (reminder->status == domain::kReminderStatusSent ||
              (reminder->status == domain::kReminderStatusFailed &&
               !is_open(*reminder)) ||
              reminder->status == domain::kReminderStatusExpired) {
            return common::Result<common::Unit>::failure(already_consumed(reminder->id));
          }
          if (!is_open(*reminder)) {
            return common::Result<common::Unit>::failure(reminder_not_deliverable(*reminder));
          }
          if (command.method != domain::kReminderMethodPopup ||
              !contains(reminder->methods, command.method)) {
            return common::Result<common::Unit>::failure(common::make_error(
                "UNSUPPORTED_REMINDER_METHOD",
                "Reminder method is not supported in current version", {{"method", command.method}}));
          }
          if (reminder->remind_at != *command.expected_remind_at) {
            return common::Result<common::Unit>::failure(common::make_error(
                "REMINDER_NOT_DUE", "Reminder is not due yet",
                {{"id", reminder->id}, {"expected_remind_at", reminder->remind_at}}, true));
          }
          const auto remind_at = common::parse_iso8601_utc_epoch_seconds(reminder->remind_at);
          const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
          if (!remind_at.has_value() || !now_epoch.has_value() || *remind_at > *now_epoch) {
            return common::Result<common::Unit>::failure(common::make_error(
                "REMINDER_NOT_DUE", "Reminder is not due yet",
                {{"id", reminder->id}, {"expected_remind_at", reminder->remind_at}}, true));
          }
          if (reminder->recovery_batch_id != command.recovery_batch_id) {
            return common::Result<common::Unit>::failure(
                recovery_conflict(command.recovery_batch_id.value_or(""),
                                  "Reminder recovery batch does not match request"));
          }
          if (command.recovery_batch_id.has_value()) {
            const auto* batch = find_batch(state, *command.recovery_batch_id);
            if (batch == nullptr || batch->status != domain::kRecoveryInProgress ||
                !contains(batch->detail_reminder_ids, reminder->id)) {
              return common::Result<common::Unit>::failure(
                  recovery_conflict(*command.recovery_batch_id,
                                    "detail Reminder is not in an active recovery batch"));
            }
          }
          auto generated = reminder_delivery_id(reminder->id, command.method);
          if (!generated.ok()) return common::Result<common::Unit>::failure(generated.error());
          delivery_id = generated.value();
          notification.kind = "reminder";
          notification.reminder_id = reminder->id;
          notification.recovery_batch_id = command.recovery_batch_id;
          notification.target_type = reminder->target_type;
          notification.target_id = reminder->target_id;
          notification.occurrence_key = reminder->occurrence_key;
          notification.method = command.method;
          notification.title = event_title(state, *reminder);
          notification.body = reminder->message;
          notification.planned_at = reminder->remind_at;
        } else if (command.kind == "recovery_summary") {
          if (command.reminder_id.has_value() || !command.recovery_batch_id.has_value() ||
              command.expected_remind_at.has_value() || command.method != domain::kReminderMethodPopup ||
              !common::is_uuid(*command.recovery_batch_id)) {
            return common::Result<common::Unit>::failure(
                contract_error("kind", "recovery summary identity is invalid"));
          }
          const auto* batch = find_batch(state, *command.recovery_batch_id);
          if (batch == nullptr || batch->status != domain::kRecoveryInProgress ||
              !batch->summary_delivery_id.has_value()) {
            return common::Result<common::Unit>::failure(
                recovery_conflict(*command.recovery_batch_id, "recovery summary is not deliverable"));
          }
          delivery_id = *batch->summary_delivery_id;
          notification.kind = "recovery_summary";
          notification.recovery_batch_id = batch->id;
          notification.target_type = "reminder_recovery_batch";
          notification.target_id = batch->id;
          notification.method = std::string(domain::kReminderMethodPopup);
          notification.title = "提醒恢复摘要";
          notification.body = summary_body(*batch);
          notification.planned_at = batch->started_at;
        } else {
          return common::Result<common::Unit>::failure(
              contract_error("kind", "delivery kind is invalid"));
        }

        const auto previous = latest_for_delivery(notifications, delivery_id);
        if (previous.has_value()) {
          if (previous->status == domain::kNotificationStatusPrepared) {
            const bool adopted_by_requested_batch =
                command.kind == "reminder" && command.recovery_batch_id.has_value() &&
                previous->resolved_by_recovery_batch_id == command.recovery_batch_id;
            const bool payload_matches =
                adopted_by_requested_batch
                    ? same_adopted_prepared_payload(*previous, notification)
                    : same_prepared_payload(*previous, notification);
            if (!payload_matches) {
              return common::Result<common::Unit>::failure(attempt_invalid(
                  previous->delivery_attempt_id.value_or(delivery_id),
                  "prepared attempt payload no longer matches the current Reminder"));
            }
            output = PrepareDeliveryResult{*previous, true};
            return common::Result<common::Unit>::success(common::Unit{});
          }
          if (previous->status == domain::kNotificationStatusSent ||
              previous->failure_class == "permanent") {
            return common::Result<common::Unit>::failure(already_consumed(delivery_id));
          }
        }

        notification.id = id_generator_();
        notification.delivery_id = delivery_id;
        notification.delivery_attempt_id = id_generator_();
        if (!common::is_uuid(notification.id) ||
            !common::is_uuid(*notification.delivery_attempt_id)) {
          return common::Result<common::Unit>::failure(common::make_error(
              "NATIVE_INTERNAL_ERROR", "Native internal error",
              {{"reason", "delivery ID generator returned invalid UUID"}}));
        }
        notification.status = std::string(domain::kNotificationStatusPrepared);
        notification.prepared_at = now;
        notification.created_at = now;
        notification.updated_at = now;
        notifications.push_back(notification);
        output = PrepareDeliveryResult{notification, false};
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!prepared.ok()) return common::Result<PrepareDeliveryResult>::failure(prepared.error());
  if (!output.has_value()) {
    return common::Result<PrepareDeliveryResult>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "prepare delivery returned no result"}}));
  }
  return common::Result<PrepareDeliveryResult>::success(std::move(*output));
}

common::Result<FinalizeDeliveryResult>
RecurringReminderDeliveryWorkflowService::finalize_delivery(
    const FinalizeDeliveryCommand& command) {
  if (!valid_finalize_command(command)) {
    return common::Result<FinalizeDeliveryResult>::failure(
        contract_error("outcome", "delivery finalization shape is invalid"));
  }
  if (command.outcome == "failed") {
    const auto retryable = common::contract_error_retryable(*command.error_code);
    if (!retryable.has_value()) {
      return common::Result<FinalizeDeliveryResult>::failure(
          contract_error("error_code", "must be declared in error_codes.yaml"));
    }
    const bool submitted_retryable = *command.failure_class == "retryable";
    if (*retryable != submitted_retryable) {
      return common::Result<FinalizeDeliveryResult>::failure(contract_error(
          "failure_class", "must match error_code retryable metadata"));
    }
  }
  const auto now = clock_();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<FinalizeDeliveryResult>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "delivery clock returned invalid UTC time"}}));
  }
  std::optional<FinalizeDeliveryResult> output;
  auto committed = transaction_->execute(
      "delivery_finalize_notification_reminder_and_successor", id_generator_(), now,
      [&](repository::RecurringEventState& state) {
        const auto found = std::find_if(
            state.notifications.begin(), state.notifications.end(), [&](const auto& item) {
              return item.delivery_attempt_id == command.delivery_attempt_id;
            });
        if (found == state.notifications.end()) {
          return common::Result<common::Unit>::failure(
              attempt_invalid(command.delivery_attempt_id, "attempt is missing"));
        }
        auto& notification = *found;
        if (notification.status != domain::kNotificationStatusPrepared) {
          if (!same_finalization(notification, command)) {
            return common::Result<common::Unit>::failure(
                attempt_invalid(command.delivery_attempt_id, "finalized outcome conflicts"));
          }
          output = FinalizeDeliveryResult{notification, std::nullopt, std::nullopt,
                                          std::nullopt, true};
          if (notification.reminder_id.has_value()) {
            const auto* reminder = find_reminder(state, *notification.reminder_id);
            if (reminder != nullptr) {
              output->reminder = *reminder;
              output->successor = find_open_successor(state, *reminder);
            }
          }
          if (const auto batch_id = effective_recovery_batch_id(notification);
              batch_id.has_value()) {
            const auto* batch = find_batch(state, *batch_id);
            if (batch != nullptr) output->recovery_batch = *batch;
          }
          return common::Result<common::Unit>::success(common::Unit{});
        }

        notification.status = command.outcome == "sent"
                                  ? std::string(domain::kNotificationStatusSent)
                                  : std::string(domain::kNotificationStatusFailed);
        notification.failure_class = command.failure_class;
        notification.error_code = command.error_code;
        notification.abandon_reason = std::nullopt;
        notification.finalized_at = now;
        notification.sent_at = command.outcome == "sent" ? std::optional<std::string>(now)
                                                         : std::nullopt;
        notification.updated_at = now;
        output = FinalizeDeliveryResult{notification, std::nullopt, std::nullopt,
                                        std::nullopt, false};

        domain::ReminderRecoveryBatch* batch = nullptr;
        if (const auto batch_id = effective_recovery_batch_id(notification);
            batch_id.has_value()) {
          batch = find_batch(state, *batch_id);
          if (batch == nullptr) {
            return common::Result<common::Unit>::failure(
                recovery_conflict(*batch_id, "batch is missing"));
          }
        }

        if (notification.kind == "reminder") {
          if (!notification.reminder_id.has_value()) {
            return common::Result<common::Unit>::failure(
                attempt_invalid(command.delivery_attempt_id, "Reminder identity is missing"));
          }
          auto* reminder = find_reminder(state, *notification.reminder_id);
          if (reminder == nullptr) {
            return common::Result<common::Unit>::failure(reminder_not_found(*notification.reminder_id));
          }
          if (!is_consumed(*reminder)) {
            consume_reminder(*reminder, command, now);
            if (command.outcome == "sent" || command.failure_class == "permanent") {
              auto successor = ensure_successor(
                  state, *reminder, now, *rolling_reminder_service_);
              if (!successor.ok()) return common::Result<common::Unit>::failure(successor.error());
              output->successor = successor.value();
            }
          }
          const auto* finalized = find_reminder(state, *notification.reminder_id);
          if (finalized == nullptr) {
            return common::Result<common::Unit>::failure(
                reminder_not_found(*notification.reminder_id));
          }
          output->reminder = *finalized;
        } else if (notification.kind == "recovery_summary") {
          if (batch == nullptr) {
            return common::Result<common::Unit>::failure(
                attempt_invalid(command.delivery_attempt_id, "summary batch is missing"));
          }
          if (command.outcome == "sent" || command.failure_class == "permanent") {
            for (const auto& id : batch->summary_reminder_ids) {
              auto* reminder = find_reminder(state, id);
              if (reminder == nullptr) {
                return common::Result<common::Unit>::failure(reminder_not_found(id));
              }
              if (is_consumed(*reminder)) continue;
              consume_reminder(*reminder, command, now);
              auto successor = ensure_successor(
                  state, *reminder, now, *rolling_reminder_service_);
              if (!successor.ok()) return common::Result<common::Unit>::failure(successor.error());
            }
          }
        } else {
          return common::Result<common::Unit>::failure(
              attempt_invalid(command.delivery_attempt_id, "notification kind is invalid"));
        }

        complete_batch_if_ready(state, batch, now);
        if (batch != nullptr) output->recovery_batch = *batch;
        output->notification = notification;
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!committed.ok()) return common::Result<FinalizeDeliveryResult>::failure(committed.error());
  if (!output.has_value()) {
    return common::Result<FinalizeDeliveryResult>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "finalize delivery returned no result"}}));
  }
  return common::Result<FinalizeDeliveryResult>::success(std::move(*output));
}

}  // namespace excellent_calendar::application
