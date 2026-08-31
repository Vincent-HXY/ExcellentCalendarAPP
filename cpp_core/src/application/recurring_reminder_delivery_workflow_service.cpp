#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"

#include <algorithm>
#include <cstdint>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/error_code_metadata.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/application/anniversary_reminder_projection.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/habit.hpp"

namespace excellent_calendar::application {
namespace {

constexpr const char* kDeliveryNamespace = "74f9acf9-a4ce-59d1-9934-5cd7ce796976";
constexpr const char* kHabitOccurrenceNamespace =
    "395bbed4-6e85-5ac1-b192-5699a5c963e8";
constexpr const char* kHabitReminderNamespace =
    "e1f91a58-4138-5984-b14d-6cd94e527890";
constexpr const char* kHabitActionNamespace =
    "23e50bd1-fbd4-5338-b842-7547a97091cf";

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
  return domain::is_open_reminder(reminder);
}

std::string next_audit_timestamp(std::string_view previous,
                                 const std::string& now) {
  const auto previous_epoch = common::parse_iso8601_utc_epoch_seconds(previous);
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (previous_epoch.has_value() && now_epoch.has_value() &&
      *now_epoch <= *previous_epoch) {
    return common::format_epoch_seconds_utc_iso8601(*previous_epoch + 1);
  }
  return now;
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

const domain::Anniversary* find_anniversary(
    const repository::RecurringEventState& state,
    const std::string& id) {
  const auto found = std::find_if(
      state.anniversaries.begin(), state.anniversaries.end(),
      [&](const auto& value) { return value.id == id; });
  return found == state.anniversaries.end() ? nullptr : &*found;
}

const domain::Habit* find_habit(const repository::RecurringEventState& state,
                                const std::string& id) {
  const auto found = std::find_if(
      state.habits.begin(), state.habits.end(),
      [&](const auto& value) { return value.id == id; });
  return found == state.habits.end() ? nullptr : &*found;
}

const domain::HabitCheckIn* find_habit_check_in(
    const repository::RecurringEventState& state, const std::string& habit_id,
    const domain::LocalDate& date) {
  const auto found = std::find_if(
      state.habit_check_ins.begin(), state.habit_check_ins.end(),
      [&](const auto& value) {
        return value.habit_id == habit_id && value.check_date == date &&
               !value.deleted_at.has_value();
      });
  return found == state.habit_check_ins.end() ? nullptr : &*found;
}

const domain::HabitReminderTemplate* find_habit_template(
    const repository::RecurringEventState& state, const std::string& key) {
  const auto found = std::find_if(
      state.habit_reminder_templates.begin(),
      state.habit_reminder_templates.end(),
      [&](const auto& value) { return value.template_key == key; });
  return found == state.habit_reminder_templates.end() ? nullptr : &*found;
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
         previous.body == expected.body && previous.planned_at == expected.planned_at &&
         previous.covered_reminder_ids == expected.covered_reminder_ids;
}

bool same_adopted_prepared_payload(const domain::Notification& previous,
                                   const domain::Notification& expected) {
  return previous.kind == expected.kind &&
         previous.reminder_id == expected.reminder_id &&
         previous.target_type == expected.target_type &&
         previous.target_id == expected.target_id &&
         previous.occurrence_key == expected.occurrence_key &&
         previous.method == expected.method && previous.title == expected.title &&
         previous.body == expected.body && previous.planned_at == expected.planned_at &&
         previous.covered_reminder_ids == expected.covered_reminder_ids;
}

std::optional<std::string> effective_recovery_batch_id(
    const domain::Notification& notification) {
  return notification.recovery_batch_id.has_value()
             ? notification.recovery_batch_id
             : notification.resolved_by_recovery_batch_id;
}

std::string event_title(const repository::RecurringEventState& state,
                        const domain::Reminder& reminder) {
  if (reminder.target_type == domain::kReminderTargetHabit) {
    const auto* habit = find_habit(state, reminder.target_id);
    return habit != nullptr && !common::trim_ascii(habit->title).empty()
               ? habit->title
               : "习惯提醒";
  }
  if (reminder.target_type == domain::kReminderTargetAnniversary) {
    const auto* anniversary = find_anniversary(state, reminder.target_id);
    return anniversary != nullptr && !common::trim_ascii(anniversary->title).empty()
               ? anniversary->title
               : "纪念日提醒";
  }
  const auto* event = find_event(state, reminder.target_id);
  return event != nullptr && !common::trim_ascii(event->title).empty() ? event->title : "日程提醒";
}

std::optional<std::string> reminder_body(
    const repository::RecurringEventState& state,
    const domain::Reminder& reminder) {
  if (reminder.target_type == domain::kReminderTargetHabit) {
    const auto* habit = find_habit(state, reminder.target_id);
    if (habit == nullptr || !reminder.occurrence_date.has_value())
      return reminder.message;
    auto date = domain::parse_local_date(*reminder.occurrence_date);
    if (!date.ok()) return reminder.message;
    if (!habit->target_count_hundredths.has_value())
      return std::string("点击完成今天的挑战");
    std::int64_t completed = 0;
    if (const auto* check = find_habit_check_in(state, habit->id, date.value());
        check != nullptr && check->completed_count_hundredths.has_value())
      completed = *check->completed_count_hundredths;
    const auto remaining =
        std::max<std::int64_t>(0, *habit->target_count_hundredths - completed);
    return "今天还需完成 " + common::format_hundredths(remaining) + " " +
           habit->unit.value_or("");
  }
  if (reminder.target_type != domain::kReminderTargetAnniversary ||
      !reminder.advance_days.has_value()) {
    return reminder.message;
  }
  const auto title = event_title(state, reminder);
  if (*reminder.advance_days == 0) {
    return "今天是“" + title + "”";
  }
  return "距离“" + title + "”还有 " +
         std::to_string(*reminder.advance_days) + " 天";
}

common::Result<PrepareDeliveryResult::HabitNotificationActionPayload>
habit_action_payload(const repository::RecurringEventState& state,
                     const domain::Notification& notification) {
  if (notification.target_type != domain::kReminderTargetHabit ||
      !notification.reminder_id.has_value() ||
      !notification.occurrence_key.has_value() ||
      !notification.delivery_id.has_value()) {
    return common::Result<PrepareDeliveryResult::HabitNotificationActionPayload>::failure(
        attempt_invalid(notification.delivery_attempt_id.value_or(""),
                        "Habit action identity is missing"));
  }
  const auto* reminder = find_reminder(state, *notification.reminder_id);
  if (reminder == nullptr || !reminder->occurrence_date.has_value() ||
      reminder->occurrence_key != notification.occurrence_key) {
    return common::Result<PrepareDeliveryResult::HabitNotificationActionPayload>::failure(
        attempt_invalid(notification.delivery_attempt_id.value_or(""),
                        "Habit action Reminder identity is stale"));
  }
  const std::string name = "[\"habit_complete\",\"" +
      notification.target_id + "\",\"" + *reminder->occurrence_date +
      "\",\"" + *notification.occurrence_key + "\"]";
  auto action_id = common::generate_uuid_v5(kHabitActionNamespace, name);
  if (!action_id.ok())
    return common::Result<PrepareDeliveryResult::HabitNotificationActionPayload>::failure(
        action_id.error());
  return common::Result<PrepareDeliveryResult::HabitNotificationActionPayload>::success(
      {action_id.value(), "complete", notification.target_id,
       *reminder->occurrence_date, *notification.occurrence_key,
       *notification.reminder_id, *notification.delivery_id});
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
  if (command.timezone.has_value() &&
      common::trim_ascii(*command.timezone).empty()) return false;
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
  bool ordinary_complete = true;
  if (batch.summary_delivery_id.has_value()) {
    const auto notification = latest_for_delivery(
        state.notifications, *batch.summary_delivery_id);
    ordinary_complete = notification.has_value() &&
        (notification->status == domain::kNotificationStatusSent ||
         (notification->status == domain::kNotificationStatusFailed &&
          notification->failure_class == "permanent"));
  }
  if (!ordinary_complete) return false;
  return std::all_of(
      batch.anniversary_catch_up_groups.begin(),
      batch.anniversary_catch_up_groups.end(),
      [](const auto& group) { return group.status == "completed"; });
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

domain::ReminderRecoveryBatch::AnniversaryCatchUpGroup* find_anniversary_group(
    domain::ReminderRecoveryBatch& batch,
    const std::string& delivery_id) {
  const auto found = std::find_if(
      batch.anniversary_catch_up_groups.begin(),
      batch.anniversary_catch_up_groups.end(),
      [&](const auto& group) { return group.delivery_id == delivery_id; });
  return found == batch.anniversary_catch_up_groups.end() ? nullptr : &*found;
}

const domain::ReminderRecoveryBatch::AnniversaryCatchUpGroup* find_anniversary_group(
    const domain::ReminderRecoveryBatch& batch,
    const std::string& delivery_id) {
  const auto found = std::find_if(
      batch.anniversary_catch_up_groups.begin(),
      batch.anniversary_catch_up_groups.end(),
      [&](const auto& group) { return group.delivery_id == delivery_id; });
  return found == batch.anniversary_catch_up_groups.end() ? nullptr : &*found;
}

common::Result<common::Unit> validate_anniversary_timezone(
    const FinalizeDeliveryCommand& command,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  if (!command.timezone.has_value() ||
      common::trim_ascii(*command.timezone).empty()) {
    return common::Result<common::Unit>::failure(
        contract_error("timezone", "timezone is required for date-based delivery"));
  }
  if (!resolver) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "date-based timezone resolver is unavailable"}}));
  }
  return resolver->validate_timezone(*command.timezone);
}

common::Result<std::optional<domain::Reminder>> ensure_habit_successor(
    repository::RecurringEventState& state,
    const domain::Reminder& source,
    const std::string& timezone,
    const std::string& now,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver) {
  if (!source.occurrence_date.has_value() || !source.template_key.has_value() ||
      !source.occurrence_key.has_value() || !resolver)
    return common::Result<std::optional<domain::Reminder>>::failure(
        attempt_invalid(source.id, "Habit successor identity is missing"));
  const auto* habit = find_habit(state, source.target_id);
  const auto* reminder_template = find_habit_template(state, *source.template_key);
  auto source_date = domain::parse_local_date(*source.occurrence_date);
  if (!source_date.ok() || habit == nullptr || reminder_template == nullptr)
    return common::Result<std::optional<domain::Reminder>>::failure(
        attempt_invalid(source.id, "Habit successor facts are missing"));
  if (habit->deleted_at.has_value() || !habit->is_active ||
      reminder_template->deleted_at.has_value() ||
      !reminder_template->is_enabled)
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  const auto date = domain::add_local_days(source_date.value(), 1);
  if (domain::habit_effective_end_date(*habit) < date)
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  const auto* check = find_habit_check_in(state, habit->id, date);
  if (check != nullptr && (check->status == domain::kHabitCheckInDone ||
                           check->status == domain::kHabitCheckInSkipped))
    return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
  const auto date_text = domain::format_local_date(date);
  const std::string occurrence_name = "[\"" + habit->id + "\",\"" +
      reminder_template->template_key + "\",\"" + date_text + "\"]";
  const std::string reminder_name = "[\"habit\",\"" + habit->id +
      "\",\"" + reminder_template->template_key + "\",\"" +
      date_text + "\"]";
  auto occurrence_id = common::generate_uuid_v5(kHabitOccurrenceNamespace,
                                                  occurrence_name);
  auto reminder_id = common::generate_uuid_v5(kHabitReminderNamespace,
                                               reminder_name);
  if (!occurrence_id.ok())
    return common::Result<std::optional<domain::Reminder>>::failure(
        occurrence_id.error());
  if (!reminder_id.ok())
    return common::Result<std::optional<domain::Reminder>>::failure(
        reminder_id.error());
  const auto existing = std::find_if(
      state.reminders.begin(), state.reminders.end(),
      [&](const auto& value) { return value.id == reminder_id.value(); });
  if (existing != state.reminders.end())
    return common::Result<std::optional<domain::Reminder>>::success(*existing);
  const int hour = (reminder_template->local_time[0] - '0') * 10 +
                   reminder_template->local_time[1] - '0';
  const int minute = (reminder_template->local_time[3] - '0') * 10 +
                     reminder_template->local_time[4] - '0';
  auto resolved = resolver->resolve_local_datetime(
      domain::LocalDateTime{date.year, date.month, date.day, hour, minute, 0},
      timezone);
  if (!resolved.ok())
    return common::Result<std::optional<domain::Reminder>>::failure(
        resolved.error());
  domain::Reminder reminder;
  reminder.id = reminder_id.value();
  reminder.target_type = std::string(domain::kReminderTargetHabit);
  reminder.target_id = habit->id;
  reminder.occurrence_key = occurrence_id.value();
  reminder.remind_at = resolved.value().utc_instant;
  reminder.methods = {std::string(domain::kReminderMethodPopup)};
  reminder.message = habit->target_count_hundredths
                         ? std::optional<std::string>("完成今天的目标")
                         : std::optional<std::string>("点击完成今天的挑战");
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.source = "auto";
  reminder.created_at = now;
  reminder.updated_at = now;
  reminder.template_key = reminder_template->template_key;
  reminder.occurrence_date = date_text;
  reminder.local_time = reminder_template->local_time;
  reminder.timezone_mode = "follow_device";
  state.reminders.push_back(reminder);
  return common::Result<std::optional<domain::Reminder>>::success(reminder);
}

std::optional<domain::Reminder> find_persisted_habit_successor(
    const repository::RecurringEventState& state,
    const domain::Reminder& source) {
  if (!source.occurrence_date.has_value() || !source.template_key.has_value())
    return std::nullopt;
  auto date = domain::parse_local_date(*source.occurrence_date);
  if (!date.ok()) return std::nullopt;
  const auto expected_date =
      domain::format_local_date(domain::add_local_days(date.value(), 1));
  const auto found = std::find_if(
      state.reminders.begin(), state.reminders.end(), [&](const auto& value) {
        return value.target_type == domain::kReminderTargetHabit &&
               value.target_id == source.target_id &&
               value.template_key == source.template_key &&
               value.occurrence_date == expected_date;
      });
  return found == state.reminders.end()
             ? std::nullopt
             : std::optional<domain::Reminder>(*found);
}

}  // namespace

RecurringReminderDeliveryWorkflowService::RecurringReminderDeliveryWorkflowService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    std::shared_ptr<RollingReminderService> rolling_reminder_service,
    ClockFn clock,
    IdGeneratorFn id_generator,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver)
    : transaction_(std::move(transaction)),
      rolling_reminder_service_(std::move(rolling_reminder_service)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)),
      local_time_resolver_(std::move(local_time_resolver)) {}

common::Result<PrepareDeliveryResult>
RecurringReminderDeliveryWorkflowService::prepare_delivery(
    const PrepareDeliveryCommand& command) {
  const auto now = clock_();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<PrepareDeliveryResult>::failure(
        common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                           {{"reason", "delivery clock returned invalid UTC time"}}));
  }
  if (command.kind == "reminder" && command.reminder_id.has_value() &&
      common::is_uuid(*command.reminder_id)) {
    auto snapshot = transaction_->load();
    if (!snapshot.ok()) {
      return common::Result<PrepareDeliveryResult>::failure(snapshot.error());
    }
    const auto* reminder = find_reminder(snapshot.value(), *command.reminder_id);
    if (reminder != nullptr &&
        reminder->target_type == domain::kReminderTargetHabit) {
      if (!command.timezone.has_value()) {
        return common::Result<PrepareDeliveryResult>::failure(contract_error(
            "timezone", "current device timezone is required for Habit delivery"));
      }
      auto timezone_valid =
          local_time_resolver_->validate_timezone(*command.timezone);
      if (!timezone_valid.ok()) {
        return common::Result<PrepareDeliveryResult>::failure(
            timezone_valid.error());
      }
      auto local_now = local_time_resolver_->to_local(now, *command.timezone);
      if (!local_now.ok()) {
        return common::Result<PrepareDeliveryResult>::failure(
            local_now.error());
      }
      const domain::LocalDate today{local_now.value().year,
                                    local_now.value().month,
                                    local_now.value().day};
      auto occurrence = reminder->occurrence_date.has_value()
                            ? domain::parse_local_date(
                                  *reminder->occurrence_date)
                            : common::Result<domain::LocalDate>::failure(
                                  contract_error("occurrence_date", "missing"));
      if (occurrence.ok() && !(occurrence.value() == today)) {
        if (occurrence.value() < today && is_open(*reminder)) {
          const auto transaction_id = id_generator_();
          if (!common::is_uuid(transaction_id)) {
            return common::Result<PrepareDeliveryResult>::failure(
                common::make_error(
                    "NATIVE_INTERNAL_ERROR", "Native internal error",
                    {{"reason", "delivery ID generator returned invalid UUID"}}));
          }
          bool expired = false;
          auto committed = transaction_->execute(
              "habit_expire_elapsed_delivery_attempt", transaction_id, now,
              [&](repository::RecurringEventState& state) {
                auto* current = find_reminder(state, *command.reminder_id);
                if (current == nullptr ||
                    current->target_type != domain::kReminderTargetHabit ||
                    !current->occurrence_date.has_value() ||
                    !is_open(*current)) {
                  return common::Result<common::Unit>::success(common::Unit{});
                }
                auto current_occurrence =
                    domain::parse_local_date(*current->occurrence_date);
                if (!current_occurrence.ok()) {
                  return common::Result<common::Unit>::failure(
                      current_occurrence.error());
                }
                if (!(current_occurrence.value() < today)) {
                  return common::Result<common::Unit>::success(common::Unit{});
                }
                current->status = std::string(domain::kReminderStatusExpired);
                current->is_enabled = false;
                current->scheduled_at = std::nullopt;
                current->expiration_reason = std::string(
                    domain::kReminderExpirationReasonHabitOccurrenceElapsed);
                current->expired_at = now;
                current->updated_at =
                    next_audit_timestamp(current->updated_at, now);
                for (auto& notification : state.notifications) {
                  if (notification.reminder_id != current->id ||
                      notification.status !=
                          domain::kNotificationStatusPrepared) {
                    continue;
                  }
                  notification.status =
                      std::string(domain::kNotificationStatusAbandoned);
                  notification.abandon_reason = "habit_occurrence_elapsed";
                  notification.finalized_at = now;
                  notification.sent_at = std::nullopt;
                  notification.recovery_batch_id = std::nullopt;
                  notification.resolved_by_recovery_batch_id = std::nullopt;
                  notification.updated_at =
                      next_audit_timestamp(notification.updated_at, now);
                }
                expired = true;
                return common::Result<common::Unit>::success(common::Unit{});
              });
          if (!committed.ok()) {
            return common::Result<PrepareDeliveryResult>::failure(
                committed.error());
          }
          if (expired) {
            return common::Result<PrepareDeliveryResult>::failure(
                common::make_error(
                    "REMINDER_NOT_DELIVERABLE", "Reminder is not deliverable",
                    {{"id", *command.reminder_id},
                     {"status", std::string(domain::kReminderStatusExpired)}}));
          }
        } else {
          return common::Result<PrepareDeliveryResult>::failure(
              reminder_not_deliverable(*reminder));
        }
      }
    }
  }
  std::optional<PrepareDeliveryResult> output;
  auto prepared = transaction_->prepare_notification(
      [&](const repository::RecurringEventState& state,
          std::vector<domain::Notification>& notifications) {
        std::string delivery_id;
        domain::Notification notification;
        if (command.kind == "reminder") {
          if (!command.reminder_id.has_value() || !command.expected_remind_at.has_value() ||
              command.delivery_id.has_value() ||
              !common::is_uuid(*command.reminder_id) ||
              !common::is_iso8601_utc_datetime(*command.expected_remind_at)) {
            return common::Result<common::Unit>::failure(
                contract_error("reminder_id", "reminder delivery identity is invalid"));
          }
          const auto* reminder = find_reminder(state, *command.reminder_id);
          if (reminder == nullptr) {
            return common::Result<common::Unit>::failure(reminder_not_found(*command.reminder_id));
          }
          if (reminder->target_type == domain::kReminderTargetHabit) {
            const auto* habit = find_habit(state, reminder->target_id);
            auto occurrence_date = reminder->occurrence_date
                                       ? domain::parse_local_date(*reminder->occurrence_date)
                                       : common::Result<domain::LocalDate>::failure(
                                             contract_error("occurrence_date", "missing"));
            const auto* habit_template = reminder->template_key
                                             ? find_habit_template(
                                                   state, *reminder->template_key)
                                             : nullptr;
            const auto* check = occurrence_date.ok()
                                    ? find_habit_check_in(
                                          state, reminder->target_id,
                                          occurrence_date.value())
                                    : nullptr;
            if (command.recovery_batch_id.has_value() || habit == nullptr ||
                habit->deleted_at.has_value() || !habit->is_active ||
                habit_template == nullptr ||
                habit_template->deleted_at.has_value() ||
                !habit_template->is_enabled || !occurrence_date.ok() ||
                (check != nullptr &&
                 (check->status == domain::kHabitCheckInDone ||
                  check->status == domain::kHabitCheckInSkipped))) {
              return common::Result<common::Unit>::failure(
                  reminder_not_deliverable(*reminder));
            }
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
          const bool supported_method = command.method == domain::kReminderMethodPopup ||
                                        command.method == domain::kReminderMethodRing;
          if (!supported_method || !contains(reminder->methods, command.method)) {
            return common::Result<common::Unit>::failure(common::make_error(
                "UNSUPPORTED_REMINDER_METHOD",
                "Reminder method is not supported in current version", {{"method", command.method}}));
          }
          if (command.method == domain::kReminderMethodRing) {
            const auto* event = find_event(state, reminder->target_id);
            if (reminder->target_type != domain::kReminderTargetEvent ||
                reminder->recurrence_revision.has_value() ||
                reminder->occurrence_key.has_value() ||
                reminder->occurrence_start_at.has_value() || event == nullptr ||
                event->deleted_at.has_value() || event->status != domain::kEventStatusActive ||
                event->is_all_day || event->has_recurrence ||
                event->recurrence_id.has_value() || event->recurrence_revision.has_value()) {
              return common::Result<common::Unit>::failure(
                  reminder_not_deliverable(*reminder));
            }
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
          notification.body = reminder_body(state, *reminder);
          notification.planned_at = reminder->remind_at;
        } else if (command.kind == "recovery_summary") {
          if (command.reminder_id.has_value() || !command.recovery_batch_id.has_value() ||
              command.delivery_id.has_value() || command.expected_remind_at.has_value() ||
              command.method != domain::kReminderMethodPopup ||
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
        } else if (command.kind == "anniversary_catch_up") {
          if (command.reminder_id.has_value() ||
              !command.recovery_batch_id.has_value() ||
              !command.delivery_id.has_value() ||
              command.expected_remind_at.has_value() ||
              command.method != domain::kReminderMethodPopup ||
              !common::is_uuid(*command.recovery_batch_id) ||
              !common::is_uuid(*command.delivery_id)) {
            return common::Result<common::Unit>::failure(
                contract_error("kind", "Anniversary catch-up identity is invalid"));
          }
          const auto* batch = find_batch(state, *command.recovery_batch_id);
          if (batch == nullptr || batch->status != domain::kRecoveryInProgress) {
            return common::Result<common::Unit>::failure(recovery_conflict(
                *command.recovery_batch_id,
                "Anniversary catch-up batch is not deliverable"));
          }
          const auto* group = find_anniversary_group(*batch, *command.delivery_id);
          if (group == nullptr || group->status != "pending") {
            return common::Result<common::Unit>::failure(recovery_conflict(
                *command.recovery_batch_id,
                "Anniversary catch-up membership is missing or completed"));
          }
          for (const auto& id : group->covered_reminder_ids) {
            const auto* reminder = find_reminder(state, id);
            if (reminder == nullptr || !is_open(*reminder) ||
                reminder->target_type != domain::kReminderTargetAnniversary ||
                reminder->target_id != group->anniversary_id ||
                reminder->occurrence_key != group->occurrence_key ||
                reminder->occurrence_date != group->occurrence_date ||
                reminder->recovery_batch_id != batch->id) {
              return common::Result<common::Unit>::failure(
                  attempt_invalid(*command.delivery_id,
                                  "Anniversary catch-up membership is stale"));
            }
          }
          const auto* anniversary = find_anniversary(state, group->anniversary_id);
          if (anniversary == nullptr || anniversary->deleted_at.has_value() ||
              !anniversary->reminders_enabled) {
            return common::Result<common::Unit>::failure(
                attempt_invalid(*command.delivery_id,
                                "Anniversary catch-up target is stale"));
          }
          delivery_id = group->delivery_id;
          notification.kind = "anniversary_catch_up";
          notification.recovery_batch_id = batch->id;
          notification.target_type = std::string(domain::kReminderTargetAnniversary);
          notification.target_id = group->anniversary_id;
          notification.occurrence_key = group->occurrence_key;
          notification.covered_reminder_ids = group->covered_reminder_ids;
          notification.method = std::string(domain::kReminderMethodPopup);
          notification.title = anniversary->title;
          notification.body = "你有 " +
                              std::to_string(group->covered_reminder_ids.size()) +
                              " 条纪念日提醒待查看";
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
            output = PrepareDeliveryResult{*previous, true, std::nullopt};
            if (previous->target_type == domain::kReminderTargetHabit) {
              auto action = habit_action_payload(state, *previous);
              if (!action.ok()) return common::Result<common::Unit>::failure(action.error());
              output->habit_action_payload = std::move(action.value());
            }
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
        output = PrepareDeliveryResult{notification, false, std::nullopt};
        if (notification.target_type == domain::kReminderTargetHabit) {
          auto action = habit_action_payload(state, notification);
          if (!action.ok()) return common::Result<common::Unit>::failure(action.error());
          output->habit_action_payload = std::move(action.value());
        }
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
              output->successor =
                  reminder->target_type == domain::kReminderTargetAnniversary
                      ? find_persisted_anniversary_successor(state, *reminder)
                      : reminder->target_type == domain::kReminderTargetHabit
                            ? find_persisted_habit_successor(state, *reminder)
                      : find_open_successor(state, *reminder);
            }
          }
          if (const auto batch_id = effective_recovery_batch_id(notification);
              batch_id.has_value()) {
            const auto* batch = find_batch(state, *batch_id);
            if (batch != nullptr) output->recovery_batch = *batch;
          }
          if (notification.kind == "anniversary_catch_up") {
            for (const auto& id : notification.covered_reminder_ids) {
              const auto* reminder = find_reminder(state, id);
              if (reminder == nullptr) {
                return common::Result<common::Unit>::failure(reminder_not_found(id));
              }
              output->covered_reminders.push_back(*reminder);
              const auto successor =
                  find_persisted_anniversary_successor(state, *reminder);
              if (successor.has_value() &&
                  std::none_of(output->successors.begin(), output->successors.end(),
                               [&](const auto& item) { return item.id == successor->id; })) {
                output->successors.push_back(*successor);
              }
            }
          }
          return common::Result<common::Unit>::success(common::Unit{});
        }

        domain::Reminder* single_reminder = nullptr;
        if (notification.kind == "reminder" && notification.reminder_id.has_value()) {
          single_reminder = find_reminder(state, *notification.reminder_id);
          if (single_reminder == nullptr) {
            return common::Result<common::Unit>::failure(
                reminder_not_found(*notification.reminder_id));
          }
        }
        const bool anniversary_attempt =
            notification.kind == "anniversary_catch_up" ||
            (single_reminder != nullptr &&
             single_reminder->target_type == domain::kReminderTargetAnniversary);
        const bool habit_attempt =
            single_reminder != nullptr &&
            single_reminder->target_type == domain::kReminderTargetHabit;
        if (anniversary_attempt || habit_attempt) {
          auto timezone_valid =
              validate_anniversary_timezone(command, local_time_resolver_);
          if (!timezone_valid.ok()) return timezone_valid;
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
          auto* reminder = single_reminder;
          if (reminder == nullptr) {
            return common::Result<common::Unit>::failure(reminder_not_found(*notification.reminder_id));
          }
          if (!is_consumed(*reminder)) {
            consume_reminder(*reminder, command, now);
            if (command.outcome == "sent" || command.failure_class == "permanent") {
              if (command.outcome == "sent" &&
                  reminder->target_type == domain::kReminderTargetAnniversary) {
                reminder->fulfillment_delivery_id = notification.delivery_id;
              }
              auto successor =
                  reminder->target_type == domain::kReminderTargetAnniversary
                      ? ensure_anniversary_successor(
                            state, *reminder, *command.timezone, now,
                            local_time_resolver_)
                      : reminder->target_type == domain::kReminderTargetHabit
                            ? ensure_habit_successor(
                                  state, *reminder, *command.timezone, now,
                                  local_time_resolver_)
                      : ensure_successor(
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
        } else if (notification.kind == "anniversary_catch_up") {
          if (batch == nullptr || !notification.delivery_id.has_value()) {
            return common::Result<common::Unit>::failure(attempt_invalid(
                command.delivery_attempt_id,
                "Anniversary catch-up batch identity is missing"));
          }
          auto* group = find_anniversary_group(*batch, *notification.delivery_id);
          if (group == nullptr ||
              group->covered_reminder_ids != notification.covered_reminder_ids) {
            return common::Result<common::Unit>::failure(attempt_invalid(
                command.delivery_attempt_id,
                "Anniversary catch-up membership conflicts with batch"));
          }
          for (const auto& id : group->covered_reminder_ids) {
            auto* reminder = find_reminder(state, id);
            if (reminder == nullptr ||
                reminder->target_type != domain::kReminderTargetAnniversary ||
                reminder->target_id != group->anniversary_id ||
                reminder->occurrence_key != group->occurrence_key ||
                reminder->recovery_batch_id != batch->id) {
              return common::Result<common::Unit>::failure(attempt_invalid(
                  command.delivery_attempt_id,
                  "Anniversary catch-up covered Reminder is stale"));
            }
            if (!is_consumed(*reminder)) {
              consume_reminder(*reminder, command, now);
              if (command.outcome == "sent") {
                reminder->fulfillment_delivery_id = notification.delivery_id;
              }
              if (command.outcome == "sent" ||
                  command.failure_class == "permanent") {
                auto successor = ensure_anniversary_successor(
                    state, *reminder, *command.timezone, now,
                    local_time_resolver_);
                if (!successor.ok()) {
                  return common::Result<common::Unit>::failure(successor.error());
                }
                if (successor.value().has_value() &&
                    std::none_of(output->successors.begin(), output->successors.end(),
                                 [&](const auto& item) {
                                   return item.id == successor.value()->id;
                                 })) {
                  output->successors.push_back(*successor.value());
                }
              }
            }
            const auto* finalized_reminder = find_reminder(state, id);
            if (finalized_reminder == nullptr) {
              return common::Result<common::Unit>::failure(reminder_not_found(id));
            }
            output->covered_reminders.push_back(*finalized_reminder);
          }
          if (command.outcome == "sent" || command.failure_class == "permanent") {
            group->status = "completed";
            group->completed_at = now;
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
