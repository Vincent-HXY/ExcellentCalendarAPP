#include <algorithm>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/habit_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"
#include "excellent_calendar/storage/json/habit_state_validator.hpp"

namespace {

using namespace excellent_calendar;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

class FakeResolver final : public domain::LocalTimeResolver {
 public:
  explicit FakeResolver(domain::LocalDate today = {2026, 9, 1})
      : today_(today) {}

  common::Result<common::Unit> validate_timezone(
      std::string_view timezone) const override {
    return timezone == "Asia/Shanghai"
               ? common::Result<common::Unit>::success(common::Unit{})
               : common::Result<common::Unit>::failure(common::make_error(
                     "TIMEZONE_ID_INVALID", "invalid timezone"));
  }
  common::Result<domain::LocalDateTime> to_local(
      std::string_view utc, std::string_view timezone) const override {
    auto valid = validate_timezone(timezone);
    if (!valid.ok())
      return common::Result<domain::LocalDateTime>::failure(valid.error());
    auto parsed = common::parse_iso8601_utc_epoch_seconds(utc);
    if (!parsed)
      return common::Result<domain::LocalDateTime>::failure(common::make_error(
          "NATIVE_INTERNAL_ERROR", "invalid fake instant"));
    return common::Result<domain::LocalDateTime>::success(
        {today_.year, today_.month, today_.day, 9, 0, 0});
  }
  common::Result<domain::ResolvedLocalDateTime> resolve_local_datetime(
      const domain::LocalDateTime& local,
      std::string_view timezone) const override {
    auto valid = validate_timezone(timezone);
    if (!valid.ok())
      return common::Result<domain::ResolvedLocalDateTime>::failure(valid.error());
    std::ostringstream instant;
    instant << std::setfill('0') << std::setw(4) << local.year << '-'
            << std::setw(2) << local.month << '-' << std::setw(2) << local.day
            << "T01:00:00Z";
    return common::Result<domain::ResolvedLocalDateTime>::success(
        {local, local, instant.str(), domain::LocalDateTimeResolution::exact});
  }
  common::Result<std::string> to_utc(
      const domain::LocalDateTime& local,
      std::string_view timezone) const override {
    auto resolved = resolve_local_datetime(local, timezone);
    return resolved.ok()
               ? common::Result<std::string>::success(resolved.value().utc_instant)
               : common::Result<std::string>::failure(resolved.error());
  }
  std::string tzdb_version() const override { return "test"; }

 private:
  domain::LocalDate today_;
};

class MemoryRecurringTransaction final
    : public repository::RecurringEventTransaction {
 public:
  common::Result<common::Unit> initialize() override {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  common::Result<repository::RecurringEventState> load() override {
    return common::Result<repository::RecurringEventState>::success(state);
  }
  common::Result<common::Unit> prepare_notification(
      const NotificationPrepareOperation& operation) override {
    auto notifications = state.notifications;
    auto result = operation(state, notifications);
    if (result.ok()) state.notifications = std::move(notifications);
    return result;
  }
  common::Result<common::Unit> update_reminders(
      const ReminderUpdateOperation& operation) override {
    auto reminders = state.reminders;
    auto result = operation(state, reminders);
    if (result.ok()) state.reminders = std::move(reminders);
    return result;
  }
  common::Result<common::Unit> execute(
      std::string_view, std::string, std::string,
      const Operation& operation) override {
    auto candidate = state;
    auto result = operation(candidate);
    if (result.ok()) state = std::move(candidate);
    return result;
  }
  repository::RecurringEventState state;
};

class HabitTransactionView final : public repository::HabitTransaction {
 public:
  explicit HabitTransactionView(
      std::shared_ptr<MemoryRecurringTransaction> recurring)
      : recurring_(std::move(recurring)) {}

  common::Result<common::Unit> initialize() override {
    return common::Result<common::Unit>::success(common::Unit{});
  }

  common::Result<repository::HabitState> load() override {
    return common::Result<repository::HabitState>::success(snapshot());
  }

  common::Result<common::Unit> execute(
      std::string_view, const Operation& operation) override {
    auto candidate = snapshot();
    auto changed = operation(candidate);
    if (!changed.ok()) return changed;
    auto valid = storage::json::validate_habit_state(candidate);
    if (!valid.ok()) return valid;
    recurring_->state.habit_recurrences = std::move(candidate.recurrences);
    recurring_->state.habits = std::move(candidate.habits);
    recurring_->state.habit_check_ins = std::move(candidate.check_ins);
    recurring_->state.habit_reminder_templates =
        std::move(candidate.reminder_templates);
    recurring_->state.reminders = std::move(candidate.reminders);
    recurring_->state.notifications = std::move(candidate.notifications);
    return common::Result<common::Unit>::success(common::Unit{});
  }

 private:
  repository::HabitState snapshot() const {
    repository::HabitState result;
    result.recurrences = recurring_->state.habit_recurrences;
    result.habits = recurring_->state.habits;
    result.check_ins = recurring_->state.habit_check_ins;
    result.reminder_templates = recurring_->state.habit_reminder_templates;
    result.reminders = recurring_->state.reminders;
    result.notifications = recurring_->state.notifications;
    return result;
  }

  std::shared_ptr<MemoryRecurringTransaction> recurring_;
};

std::string next_uuid(int& counter) {
  std::ostringstream text;
  text << "99999999-9999-4999-8999-" << std::setw(12) << std::setfill('0')
       << counter++;
  return text.str();
}

repository::RecurringEventState fixture_state() {
  repository::RecurringEventState state;
  const std::string created = "2026-08-28T00:00:00Z";
  domain::HabitRecurrence recurrence{
      "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "daily", 1,
      "follow_device", created, created, std::nullopt};
  domain::Habit habit;
  habit.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  habit.title = "📚 阅读";
  habit.recurrence_id = recurrence.id;
  habit.start_date = {2026, 9, 1};
  habit.end_date = {2026, 9, 10};
  habit.created_at = created;
  habit.updated_at = created;
  domain::HabitReminderTemplate reminder_template;
  reminder_template.template_key = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  reminder_template.habit_id = habit.id;
  reminder_template.local_time = "09:00";
  reminder_template.created_at = created;
  reminder_template.updated_at = created;
  domain::Reminder reminder;
  reminder.id = "7ba217aa-5b7a-5c96-ad04-edc464faf74a";
  reminder.target_type = std::string(domain::kReminderTargetHabit);
  reminder.target_id = habit.id;
  reminder.occurrence_key = "4c75dd26-d1f8-5d5b-bf0c-34329c9e5705";
  reminder.remind_at = "2026-09-01T01:00:00Z";
  reminder.methods = {"popup"};
  reminder.message = "今天完成阅读";
  reminder.is_enabled = true;
  reminder.status = "pending";
  reminder.source = "auto";
  reminder.created_at = created;
  reminder.updated_at = created;
  reminder.template_key = reminder_template.template_key;
  reminder.occurrence_date = "2026-09-01";
  reminder.local_time = "09:00";
  reminder.timezone_mode = "follow_device";
  state.habit_recurrences.push_back(recurrence);
  state.habits.push_back(habit);
  state.habit_reminder_templates.push_back(reminder_template);
  state.reminders.push_back(reminder);
  return state;
}

void test_prepare_action_finalize_successor_and_recovery_exclusion() {
  auto transaction = std::make_shared<MemoryRecurringTransaction>();
  transaction->state = fixture_state();
  auto resolver = std::make_shared<FakeResolver>();
  auto recurrence = std::make_shared<application::RecurrenceService>(resolver);
  auto rolling = std::make_shared<application::RollingReminderService>(recurrence);
  int counter = 1;
  auto ids = [&] { return next_uuid(counter); };

  application::ReminderRecoveryWorkflowService recovery(
      transaction, recurrence, rolling,
      [] { return "2026-09-01T01:00:00Z"; }, ids, resolver);
  auto planned = recovery.plan_recovery(
      {"dddddddd-dddd-4ddd-8ddd-dddddddddddd", "app_start",
       "Asia/Shanghai"});
  require(planned.ok() && planned.value().detail_reminders.empty() &&
              !transaction->state.reminders.front().recovery_batch_id.has_value(),
          "ordinary recovery must explicitly leave Habit reminders out");

  application::RecurringReminderDeliveryWorkflowService delivery(
      transaction, rolling, [] { return "2026-09-01T01:00:00Z"; }, ids,
      resolver);
  application::PrepareDeliveryCommand command;
  command.kind = "reminder";
  command.reminder_id = transaction->state.reminders.front().id;
  command.method = "popup";
  command.expected_remind_at = "2026-09-01T01:00:00Z";
  command.timezone = "Asia/Shanghai";
  auto prepared = delivery.prepare_delivery(command);
  require(prepared.ok() && prepared.value().habit_action_payload.has_value(),
          "Habit prepare must return a strong direct-complete action");
  const auto& action = *prepared.value().habit_action_payload;
  require(action.action_id == "c50c46ef-5339-5758-9ec6-08b54f2a75f5" &&
              action.action_type == "complete" &&
              action.occurrence_key ==
                  "4c75dd26-d1f8-5d5b-bf0c-34329c9e5705" &&
              prepared.value().notification.title == "📚 阅读" &&
              prepared.value().notification.body ==
                  std::optional<std::string>("点击完成今天的挑战"),
          "Habit prepare payload must match frozen identity and copy");
  const auto json = boundary::contract::prepare_delivery_response_v2_to_json(
      prepared.value());
  const auto& object = json.get<picojson::object>();
  require(object.at("tap_payload").get<picojson::object>().at("route").get<std::string>() ==
              "habit.detail" &&
              object.at("habit_action_payload").is<picojson::object>(),
          "Boundary prepare must expose Habit route and action payload");
  auto replay = delivery.prepare_delivery(command);
  require(replay.ok() && replay.value().idempotent_replay &&
              replay.value().notification.delivery_attempt_id ==
                  prepared.value().notification.delivery_attempt_id,
          "prepare replay must reuse the original attempt");

  auto finalized = delivery.finalize_delivery(
      {*prepared.value().notification.delivery_attempt_id, "sent",
       std::nullopt, std::nullopt, "Asia/Shanghai"});
  require(finalized.ok() && finalized.value().successor.has_value() &&
              finalized.value().reminder->status == "sent" &&
              finalized.value().successor->occurrence_date ==
                  std::optional<std::string>("2026-09-02"),
          "sent finalization must atomically consume and create first legal successor");
  auto finalized_replay = delivery.finalize_delivery(
      {*prepared.value().notification.delivery_attempt_id, "sent",
       std::nullopt, std::nullopt, "Asia/Shanghai"});
  require(finalized_replay.ok() && finalized_replay.value().idempotent_replay &&
              finalized_replay.value().successor.has_value() &&
              finalized_replay.value().successor->id ==
                  finalized.value().successor->id,
          "finalize replay must return the persisted successor");

  auto habit_transaction = std::make_shared<HabitTransactionView>(transaction);
  application::HabitService habit_service(
      habit_transaction, resolver, [] { return "2026-09-01T01:00:01Z"; }, ids);
  const auto ended = habit_service.end(
      {transaction->state.habits.front().id,
       transaction->state.habits.front().updated_at, "Asia/Shanghai"});
  const auto successor = std::find_if(
      transaction->state.reminders.begin(), transaction->state.reminders.end(),
      [&](const auto& reminder) {
        return reminder.id == finalized.value().successor->id;
      });
  require(ended.ok() && successor != transaction->state.reminders.end() &&
              successor->status == domain::kReminderStatusCancelled &&
              successor->cancellation_reason ==
                  std::optional<std::string>(
                      domain::kReminderCancellationReasonHabitEnded),
          "sent-to-successor-to-end must atomically preserve the sent audit and cancel the future successor");
}

void test_partial_copy_uses_remaining_quantity() {
  auto transaction = std::make_shared<MemoryRecurringTransaction>();
  transaction->state = fixture_state();
  auto& habit = transaction->state.habits.front();
  habit.target_count_hundredths = 100;
  habit.unit = "页";
  domain::HabitCheckIn check;
  check.id = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
  check.habit_id = habit.id;
  check.check_date = {2026, 9, 1};
  check.status = "partial";
  check.completed_count_hundredths = 25;
  check.target_count_snapshot_hundredths = 100;
  check.unit_snapshot = "页";
  check.completed_at = "2026-09-01T00:30:00Z";
  check.source = "manual";
  check.created_at = "2026-09-01T00:30:00Z";
  check.updated_at = "2026-09-01T00:30:00Z";
  transaction->state.habit_check_ins.push_back(check);
  auto resolver = std::make_shared<FakeResolver>();
  auto recurrence = std::make_shared<application::RecurrenceService>(resolver);
  auto rolling = std::make_shared<application::RollingReminderService>(recurrence);
  int counter = 100;
  application::RecurringReminderDeliveryWorkflowService delivery(
      transaction, rolling, [] { return "2026-09-01T01:00:00Z"; },
      [&] { return next_uuid(counter); }, resolver);
  application::PrepareDeliveryCommand command;
  command.kind = "reminder";
  command.reminder_id = transaction->state.reminders.front().id;
  command.method = "popup";
  command.expected_remind_at = "2026-09-01T01:00:00Z";
  command.timezone = "Asia/Shanghai";
  auto prepared = delivery.prepare_delivery(command);
  require(prepared.ok() && prepared.value().notification.body ==
                               std::optional<std::string>(
                                   "今天还需完成 0.75 页"),
          "partial must keep the Reminder and generate exact remaining copy");
}

void test_permanent_failure_is_terminal_while_successor_rolls_forward() {
  auto transaction = std::make_shared<MemoryRecurringTransaction>();
  transaction->state = fixture_state();
  auto resolver = std::make_shared<FakeResolver>();
  auto recurrence = std::make_shared<application::RecurrenceService>(resolver);
  auto rolling = std::make_shared<application::RollingReminderService>(recurrence);
  int counter = 300;
  auto ids = [&] { return next_uuid(counter); };
  application::RecurringReminderDeliveryWorkflowService delivery(
      transaction, rolling, [] { return "2026-09-01T01:00:00Z"; }, ids,
      resolver);
  application::PrepareDeliveryCommand command;
  command.kind = "reminder";
  command.reminder_id = transaction->state.reminders.front().id;
  command.method = "popup";
  command.expected_remind_at = "2026-09-01T01:00:00Z";
  command.timezone = "Asia/Shanghai";
  auto prepared = delivery.prepare_delivery(command);
  require(prepared.ok(), "permanent-failure fixture must prepare");
  auto failed = delivery.finalize_delivery(
      {*prepared.value().notification.delivery_attempt_id, "failed",
       "permanent", "EVENT_NOT_FOUND", "Asia/Shanghai"});
  require(failed.ok() && failed.value().reminder.has_value() &&
              failed.value().reminder->status ==
                  domain::kReminderStatusFailed &&
              failed.value().successor.has_value() &&
              failed.value().successor->status ==
                  domain::kReminderStatusPending,
          "permanent failure must consume only the source and create the next-day successor");

  auto habit_transaction = std::make_shared<HabitTransactionView>(transaction);
  application::HabitService habit_service(
      habit_transaction, resolver, [] { return "2026-09-01T01:00:01Z"; }, ids);
  auto reconciled = habit_service.reconcile_reminders(
      {"Asia/Shanghai", "manual_retry", std::nullopt, 100});
  const auto source = std::find_if(
      transaction->state.reminders.begin(), transaction->state.reminders.end(),
      [&](const auto& reminder) {
        return reminder.id == failed.value().reminder->id;
      });
  require(reconciled.ok() && source != transaction->state.reminders.end() &&
              source->status == domain::kReminderStatusFailed &&
              source->reactivation_count == 0,
          "reconciliation must never revive a permanently failed Reminder");
}

void test_prepare_expires_elapsed_habit_attempt_before_display() {
  auto transaction = std::make_shared<MemoryRecurringTransaction>();
  transaction->state = fixture_state();
  auto day_one_resolver = std::make_shared<FakeResolver>();
  auto recurrence =
      std::make_shared<application::RecurrenceService>(day_one_resolver);
  auto rolling =
      std::make_shared<application::RollingReminderService>(recurrence);
  int counter = 400;
  application::RecurringReminderDeliveryWorkflowService day_one_delivery(
      transaction, rolling, [] { return "2026-09-01T01:00:00Z"; },
      [&] { return next_uuid(counter); }, day_one_resolver);
  application::PrepareDeliveryCommand command;
  command.kind = "reminder";
  command.reminder_id = transaction->state.reminders.front().id;
  command.method = "popup";
  command.expected_remind_at = "2026-09-01T01:00:00Z";
  command.timezone = "Asia/Shanghai";
  auto prepared = day_one_delivery.prepare_delivery(command);
  require(prepared.ok(), "same-day Habit delivery must prepare");

  auto day_two_resolver =
      std::make_shared<FakeResolver>(domain::LocalDate{2026, 9, 2});
  auto day_two_recurrence =
      std::make_shared<application::RecurrenceService>(day_two_resolver);
  auto day_two_rolling =
      std::make_shared<application::RollingReminderService>(day_two_recurrence);
  application::RecurringReminderDeliveryWorkflowService day_two_delivery(
      transaction, day_two_rolling,
      [] { return "2026-09-02T00:01:00Z"; },
      [&] { return next_uuid(counter); }, day_two_resolver);
  auto elapsed = day_two_delivery.prepare_delivery(command);
  require(!elapsed.ok() && elapsed.error().code == "REMINDER_NOT_DELIVERABLE" &&
              transaction->state.reminders.front().status ==
                  domain::kReminderStatusExpired &&
              transaction->state.reminders.front().expiration_reason ==
                  std::optional<std::string>(
                      domain::kReminderExpirationReasonHabitOccurrenceElapsed) &&
              transaction->state.notifications.size() == 1U &&
              transaction->state.notifications.front().status ==
                  domain::kNotificationStatusAbandoned &&
              transaction->state.notifications.front().abandon_reason ==
                  std::optional<std::string>("habit_occurrence_elapsed") &&
              !transaction->state.notifications.front()
                   .recovery_batch_id.has_value(),
          "prepare must atomically expire an elapsed Habit Reminder and abandon its prepared attempt");
}

void test_hundredths_copy_formats_without_floating_point_or_wire_units() {
  require(common::format_hundredths(500) == "5" &&
              common::format_hundredths(150) == "1.5" &&
              common::format_hundredths(125) == "1.25" &&
              common::format_hundredths(1) == "0.01" &&
              common::format_hundredths(domain::kHabitMaxHundredths) ==
                  "90071992547409.91",
          "hundredths copy formatter must preserve exact decimal text");
}

}  // namespace

int main() {
  try {
    test_prepare_action_finalize_successor_and_recovery_exclusion();
    test_partial_copy_uses_remaining_quantity();
    test_prepare_expires_elapsed_habit_attempt_before_display();
    test_hundredths_copy_formats_without_floating_point_or_wire_units();
    test_permanent_failure_is_terminal_while_successor_rolls_forward();
    std::cout << "habit_reminder_tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "habit_reminder_tests failed: " << error.what() << '\n';
    return 1;
  }
}
