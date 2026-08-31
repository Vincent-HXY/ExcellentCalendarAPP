#include <algorithm>
#include <iomanip>
#include <filesystem>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include <picojson/picojson.h>

#include "excellent_calendar/application/habit_service.hpp"
#include "excellent_calendar/boundary/api/habit_api.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/habit.hpp"

namespace {

using namespace excellent_calendar;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

class FakeResolver final : public domain::LocalTimeResolver {
 public:
  explicit FakeResolver(domain::LocalDate today = {2026, 9, 3})
      : today_(today) {}

  common::Result<common::Unit> validate_timezone(
      std::string_view timezone) const override {
    return timezone == "Asia/Shanghai"
               ? common::Result<common::Unit>::success(common::Unit{})
               : common::Result<common::Unit>::failure(common::make_error(
                     "TIMEZONE_ID_INVALID", "invalid timezone"));
  }
  common::Result<domain::LocalDateTime> to_local(
      std::string_view, std::string_view timezone) const override {
    auto valid = validate_timezone(timezone);
    return valid.ok()
               ? common::Result<domain::LocalDateTime>::success(
                     {today_.year, today_.month, today_.day, 20, 0, 0})
               : common::Result<domain::LocalDateTime>::failure(valid.error());
  }
  common::Result<domain::ResolvedLocalDateTime> resolve_local_datetime(
      const domain::LocalDateTime& local,
      std::string_view timezone) const override {
    auto valid = validate_timezone(timezone);
    if (!valid.ok())
      return common::Result<domain::ResolvedLocalDateTime>::failure(valid.error());
    return common::Result<domain::ResolvedLocalDateTime>::success(
        {local, local,
         domain::format_local_date(local_date(local)) + "T00:00:00Z",
         domain::LocalDateTimeResolution::exact});
  }
  common::Result<std::string> to_utc(
      const domain::LocalDateTime& local,
      std::string_view timezone) const override {
    auto value = resolve_local_datetime(local, timezone);
    return value.ok() ? common::Result<std::string>::success(value.value().utc_instant)
                      : common::Result<std::string>::failure(value.error());
  }
  std::string tzdb_version() const override { return "test"; }

 private:
  domain::LocalDate today_;

  static domain::LocalDate local_date(const domain::LocalDateTime& value) {
    return {value.year, value.month, value.day};
  }
};

class MemoryHabitTransaction final : public repository::HabitTransaction {
 public:
  common::Result<common::Unit> initialize() override {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  common::Result<repository::HabitState> load() override {
    return common::Result<repository::HabitState>::success(state);
  }
  common::Result<common::Unit> execute(
      std::string_view, const Operation& operation) override {
    if (fail_next) {
      fail_next = false;
      return common::Result<common::Unit>::failure(common::make_error(
          "STORAGE_IO_ERROR", "injected repository failure", {}, true));
    }
    auto candidate = state;
    auto result = operation(candidate);
    if (result.ok()) state = std::move(candidate);
    return result;
  }

  repository::HabitState state;
  bool fail_next = false;
};

std::string next_uuid(int& counter) {
  std::ostringstream text;
  text << "00000000-0000-4000-8000-" << std::setw(12) << std::setfill('0')
       << counter++;
  return text.str();
}

application::CreateHabitCommand create_command(
    std::string title, domain::LocalDate start, domain::LocalDate end,
    std::optional<std::int64_t> target = std::nullopt,
    std::optional<std::string> unit = std::nullopt) {
  application::CreateHabitCommand command;
  command.title = std::move(title);
  command.target_count_hundredths = target;
  command.unit = std::move(unit);
  command.start_date = start;
  command.end_date = end;
  command.reminder = {false, std::nullopt, "follow_device", "popup"};
  command.timezone = "Asia/Shanghai";
  return command;
}

void test_lifecycle_check_in_statistics_and_locks() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 1;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });

  auto created = service.create(create_command(
      "\xE3\x80\x80\xF0\x9F\x93\x9A 阅读\xE3\x80\x80",
      {2026, 9, 1}, {2026, 9, 10}, 100, "页"));
  require(created.ok(), "quantitative Habit create must succeed");
  const auto habit_id = created.value().detail.habit.id;
  require(created.value().detail.habit.title == "📚 阅读",
          "title must trim Unicode boundary whitespace");
  auto day1 = service.check_in({habit_id, {2026, 9, 1}, "done", 100,
                                std::nullopt, "manual", std::nullopt,
                                std::nullopt, "Asia/Shanghai"});
  require(day1.ok(), "day-one done must succeed");
  const auto original_id = day1.value().check_in->id;
  const auto original_created_at = day1.value().check_in->created_at;
  auto day2 = service.check_in({habit_id, {2026, 9, 2}, "skipped",
                                std::nullopt, std::nullopt, "manual",
                                std::nullopt, std::nullopt, "Asia/Shanghai"});
  require(day2.ok(), "skipped check-in must succeed");
  auto day3 = service.check_in({habit_id, {2026, 9, 3}, "done", 125,
                                std::nullopt, "manual", std::nullopt,
                                std::nullopt, "Asia/Shanghai"});
  require(day3.ok(), "over-target done must preserve the true quantity");
  require(day3.value().statistics.done_days == 2 &&
              day3.value().statistics.skipped_days == 1 &&
              day3.value().statistics.current_streak == 2 &&
              day3.value().statistics.longest_streak == 2 &&
              *day3.value().statistics.total_completed_count_hundredths == 225,
          "done-skipped-done statistics must follow frozen semantics");

  auto cleared = service.clear_check_in(
      {habit_id, {2026, 9, 1}, "Asia/Shanghai"});
  require(cleared.ok() && !cleared.value().check_in.has_value() &&
              cleared.value().daily_status.status == "missed",
          "clear must project a tombstoned past day as missed");
  auto revived = service.check_in({habit_id, {2026, 9, 1}, "partial", 50,
                                   std::nullopt, "manual", std::nullopt,
                                   std::nullopt, "Asia/Shanghai"});
  require(revived.ok() && revived.value().check_in->id == original_id &&
              revived.value().check_in->created_at == original_created_at,
          "set after clear must revive the same CheckIn identity and audit origin");

  auto detail = service.detail(habit_id, "Asia/Shanghai", 30);
  require(detail.ok() && detail.value().has_ever_checked_in &&
              detail.value().latest_check_in_date ==
                  std::optional<domain::LocalDate>({2026, 9, 3}),
          "detail must retain has-ever/latest facts after clear and revive");
  auto update = application::UpdateHabitCommand{
      habit_id, detail.value().habit.updated_at, detail.value().habit.title,
      detail.value().habit.description, detail.value().habit.category_id, 200,
      std::optional<std::string>("页"), {2026, 9, 1}, {2026, 9, 10},
      std::nullopt, "Asia/Shanghai"};
  auto locked = service.update(update);
  require(!locked.ok() && locked.error().code == "HABIT_TARGET_LOCKED",
          "first CheckIn must permanently lock target and unit");
  auto future = service.check_in({habit_id, {2026, 9, 4}, "done", 100,
                                  std::nullopt, "manual", std::nullopt,
                                  std::nullopt, "Asia/Shanghai"});
  require(!future.ok() && future.error().code == "HABIT_CHECK_IN_FUTURE_DATE",
          "future CheckIn must be rejected in current timezone");

  auto binary_command =
      create_command("Binary skip", {2026, 9, 1}, {2026, 9, 10});
  binary_command.reminder = {
      true, std::optional<std::string>("09:00"), "follow_device", "popup"};
  auto binary = service.create(binary_command);
  require(binary.ok(), "binary skipped fixture must be created");
  const auto binary_id = binary.value().detail.habit.id;
  auto binary_skipped = service.check_in(
      {binary_id, {2026, 9, 3}, "skipped", std::nullopt, std::nullopt,
       "manual", std::nullopt, std::nullopt, "Asia/Shanghai"});
  const auto binary_reminder = std::find_if(
      transaction->state.reminders.begin(), transaction->state.reminders.end(),
      [&](const auto& reminder) {
        return reminder.target_id == binary_id &&
               reminder.occurrence_date ==
                   std::optional<std::string>("2026-09-03");
      });
  require(binary_skipped.ok() && binary_skipped.value().check_in.has_value() &&
              binary_skipped.value().check_in->status ==
                  domain::kHabitCheckInSkipped &&
              !binary_skipped.value().check_in
                   ->completed_count_hundredths.has_value() &&
              binary_reminder != transaction->state.reminders.end() &&
              binary_reminder->status == domain::kReminderStatusCancelled &&
              binary_reminder->cancellation_reason ==
                  std::optional<std::string>(
                      domain::kReminderCancellationReasonHabitSkipped),
          "binary Habit skipped must persist empty snapshots and cancel today's Reminder");
}

void test_bounds_overflow_and_atomic_failure() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 100;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });
  auto max_range = service.create(create_command(
      "400 days", {2026, 1, 1}, domain::add_local_days({2026, 1, 1}, 399)));
  require(max_range.ok(), "400-day inclusive challenge must succeed");
  const auto count_before = transaction->state.habits.size();
  auto too_long = service.create(create_command(
      "401 days", {2026, 1, 1}, domain::add_local_days({2026, 1, 1}, 400)));
  require(!too_long.ok() && too_long.error().code == "HABIT_CHALLENGE_TOO_LONG" &&
              transaction->state.habits.size() == count_before,
          "401-day challenge must fail without half state");

  transaction->fail_next = true;
  auto failed = service.create(create_command(
      "repository failure", {2026, 9, 3}, {2026, 9, 4}));
  require(!failed.ok() && failed.error().code == "STORAGE_IO_ERROR" &&
              transaction->state.habits.size() == count_before,
          "Repository failure must leave zero partial state");

  auto huge = service.create(create_command(
      "overflow", {2026, 9, 1}, {2026, 9, 3},
      domain::kHabitMaxHundredths, "次"));
  require(huge.ok(), "maximum exact target must be accepted");
  const auto id = huge.value().detail.habit.id;
  require(service.check_in({id, {2026, 9, 1}, "done",
                                domain::kHabitMaxHundredths, std::nullopt,
                                "manual", std::nullopt, std::nullopt,
                                "Asia/Shanghai"}).ok(),
          "first maximum accumulation must succeed");
  const auto before_overflow = transaction->state.check_ins.size();
  auto overflow = service.check_in({id, {2026, 9, 2}, "done",
                                    domain::kHabitMaxHundredths, std::nullopt,
                                    "manual", std::nullopt, std::nullopt,
                                    "Asia/Shanghai"});
  require(!overflow.ok() && overflow.error().code == "HABIT_STATISTICS_OVERFLOW" &&
              transaction->state.check_ins.size() == before_overflow,
          "statistics overflow must fail and rollback the CheckIn transaction");
}

void test_ended_progress_and_deleted_detail_errors() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto active_resolver = std::make_shared<FakeResolver>(
      domain::LocalDate{2026, 9, 3});
  int counter = 250;
  application::HabitService active_service(
      transaction, active_resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });

  auto created = active_service.create(create_command(
      "Frozen ended progress", {2026, 9, 1}, {2026, 9, 10}));
  require(created.ok(), "early-ended progress fixture must be created");
  const auto id = created.value().detail.habit.id;
  auto ended = active_service.end(
      {id, created.value().detail.habit.updated_at, "Asia/Shanghai"});
  require(ended.ok() && ended.value().detail.lifecycle_status == "ended_early" &&
              ended.value().detail.challenge_time_progress > 0.299 &&
              ended.value().detail.challenge_time_progress < 0.301,
          "early end must freeze progress at the inclusive ended date");

  auto future_resolver = std::make_shared<FakeResolver>(
      domain::LocalDate{2026, 9, 20});
  application::HabitService future_service(
      transaction, future_resolver, [] { return "2026-09-20T12:00:00Z"; },
      [&] { return next_uuid(counter); });
  auto future_detail = future_service.detail(id, "Asia/Shanghai", 30);
  require(future_detail.ok() &&
              future_detail.value().challenge_time_progress > 0.299 &&
              future_detail.value().challenge_time_progress < 0.301,
          "early-ended progress must not become complete after the natural end date");

  auto removed = future_service.remove(
      {id, future_detail.value().habit.updated_at, "Asia/Shanghai"});
  require(removed.ok(), "ended Habit must remain explicitly deletable");
  auto deleted_detail = future_service.detail(id, "Asia/Shanghai", 30);
  require(!deleted_detail.ok() &&
              deleted_detail.error().code == "HABIT_TARGET_DELETED",
          "detail must distinguish a tombstoned Habit from a missing Habit");
  auto missing_detail = future_service.detail(
      "ffffffff-ffff-4fff-8fff-ffffffffffff", "Asia/Shanghai", 30);
  require(!missing_detail.ok() && missing_detail.error().code == "HABIT_NOT_FOUND",
          "detail must preserve not-found for an unknown Habit identity");
}

void test_template_change_daily_display_transitions() {
  const auto run_case = [](std::string state_kind,
                           std::string expected_date) {
    auto transaction = std::make_shared<MemoryHabitTransaction>();
    auto resolver = std::make_shared<FakeResolver>();
    int counter = state_kind == "pending" ? 300 : state_kind == "prepared" ? 400 : 500;
    application::HabitService service(
        transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
        [&] { return next_uuid(counter); });
    auto command = create_command("Reminder transition", {2026, 9, 3},
                                  {2026, 9, 10});
    command.reminder = {true, std::optional<std::string>("09:00"),
                        "follow_device", "popup"};
    auto created = service.create(command);
    require(created.ok() && transaction->state.reminders.size() == 1U,
            state_kind + " transition fixture must create a Reminder");
    const auto habit_id = created.value().detail.habit.id;
    const auto original_template =
        transaction->state.reminder_templates.front().template_key;
    auto& old_reminder = transaction->state.reminders.front();
    if (state_kind == "prepared") {
      domain::Notification notification;
      notification.id = next_uuid(counter);
      notification.delivery_id = next_uuid(counter);
      notification.delivery_attempt_id = next_uuid(counter);
      notification.kind = "reminder";
      notification.reminder_id = old_reminder.id;
      notification.target_type = std::string(domain::kReminderTargetHabit);
      notification.target_id = habit_id;
      notification.occurrence_key = old_reminder.occurrence_key;
      notification.method = "popup";
      notification.title = "Reminder transition";
      notification.planned_at = old_reminder.remind_at;
      notification.prepared_at = "2026-09-03T12:00:00Z";
      notification.status = "prepared";
      notification.created_at = "2026-09-03T12:00:00Z";
      notification.updated_at = "2026-09-03T12:00:00Z";
      transaction->state.notifications.push_back(notification);
    } else if (state_kind == "sent") {
      old_reminder.status = "sent";
      old_reminder.last_triggered_at = "2026-09-03T12:00:00Z";
      old_reminder.updated_at = "2026-09-03T12:00:00Z";
    }
    auto changed = service.set_reminder(
        {habit_id, created.value().detail.habit.updated_at,
         {true, std::optional<std::string>("10:00"), "follow_device", "popup"},
         "Asia/Shanghai"});
    require(changed.ok(), state_kind + " template change must succeed");
    const auto active = std::find_if(
        transaction->state.reminder_templates.begin(),
        transaction->state.reminder_templates.end(), [](const auto& value) {
          return !value.deleted_at.has_value();
        });
    require(active != transaction->state.reminder_templates.end() &&
                active->template_key != original_template,
            state_kind + " change must create a new template UUIDv4 key");
    const auto current = std::find_if(
        transaction->state.reminders.begin(), transaction->state.reminders.end(),
        [&](const auto& value) {
          return value.template_key == active->template_key &&
                 value.status == "pending";
        });
    require(current != transaction->state.reminders.end() &&
                current->occurrence_date ==
                    std::optional<std::string>(expected_date),
            state_kind + " change must choose the frozen same-day/next-day transition");
    if (state_kind == "prepared") {
      require(transaction->state.notifications.front().status == "abandoned" &&
                  !transaction->state.notifications.front()
                       .recovery_batch_id.has_value() &&
                  !transaction->state.notifications.front()
                       .resolved_by_recovery_batch_id.has_value(),
              "prepared template replacement must abandon without Recovery fields");
    }
  };
  run_case("pending", "2026-09-03");
  run_case("prepared", "2026-09-04");
  run_case("sent", "2026-09-04");
}

void test_reconciliation_lifecycle_and_terminal_failures() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 600;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });

  auto upcoming_command = create_command(
      "Upcoming reminder", {2026, 9, 5}, {2026, 9, 10});
  upcoming_command.reminder = {
      true, std::optional<std::string>("09:00"), "follow_device", "popup"};
  auto upcoming = service.create(upcoming_command);
  require(upcoming.ok() && transaction->state.reminders.size() == 1U &&
              transaction->state.reminders.front().occurrence_date ==
                  std::optional<std::string>("2026-09-05"),
          "upcoming fixture must materialize the first challenge date");
  const auto upcoming_reminder_id = transaction->state.reminders.front().id;
  auto reconciled = service.reconcile_reminders(
      {"Asia/Shanghai", "app_start", std::nullopt, 100});
  const auto upcoming_reminder = std::find_if(
      transaction->state.reminders.begin(), transaction->state.reminders.end(),
      [&](const auto& item) { return item.id == upcoming_reminder_id; });
  require(reconciled.ok() &&
              upcoming_reminder != transaction->state.reminders.end() &&
              upcoming_reminder->status == domain::kReminderStatusPending &&
              upcoming_reminder->is_enabled &&
              reconciled.value().unchanged_count == 1 &&
              reconciled.value().cancelled_count == 0,
          "reconciliation must preserve the first future Reminder for an upcoming Habit");

  upcoming_reminder->status = std::string(domain::kReminderStatusScheduled);
  upcoming_reminder->scheduled_at = "2026-09-03T12:00:00Z";
  upcoming_reminder->remind_at = "2026-09-05T02:00:00Z";
  auto corrected = service.reconcile_reminders(
      {"Asia/Shanghai", "time_changed", std::nullopt, 100});
  const auto corrected_reminder = std::find_if(
      transaction->state.reminders.begin(), transaction->state.reminders.end(),
      [&](const auto& item) { return item.id == upcoming_reminder_id; });
  require(corrected.ok() &&
              corrected_reminder != transaction->state.reminders.end() &&
              corrected_reminder->status == domain::kReminderStatusPending &&
              !corrected_reminder->scheduled_at.has_value() &&
              corrected_reminder->remind_at == "2026-09-05T00:00:00Z",
          "time reconciliation must reproject the upcoming startDate Reminder");

  transaction->state.reminders.front().status =
      std::string(domain::kReminderStatusFailed);
  transaction->state.reminders.front().failure_reason = "PERMANENT_TEST_FAILURE";
  auto failed_reconciled = service.reconcile_reminders(
      {"Asia/Shanghai", "manual_retry", std::nullopt, 100});
  auto detail = service.detail(upcoming.value().detail.habit.id,
                               "Asia/Shanghai", 30);
  require(failed_reconciled.ok() && detail.ok() &&
              transaction->state.reminders.front().status ==
                  domain::kReminderStatusFailed &&
              detail.value().reminder_settings.active_reminder_count == 0 &&
              !detail.value().reminder_settings.schedule_reconciliation_required,
          "reconcile and detail must keep a permanently failed Reminder terminal");

  auto active_transaction = std::make_shared<MemoryHabitTransaction>();
  application::HabitService active_service(
      active_transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });
  auto active_command = create_command(
      "Failed audit", {2026, 9, 1}, {2026, 9, 10});
  active_command.reminder = {
      true, std::optional<std::string>("09:00"), "follow_device", "popup"};
  auto active = active_service.create(active_command);
  require(active.ok(), "failed audit fixture must be created");
  active_transaction->state.reminders.front().status =
      std::string(domain::kReminderStatusFailed);
  active_transaction->state.reminders.front().failure_reason =
      "PERMANENT_TEST_FAILURE";
  auto ended = active_service.end(
      {active.value().detail.habit.id, active.value().detail.habit.updated_at,
       "Asia/Shanghai"});
  require(ended.ok() &&
              active_transaction->state.reminders.front().status ==
                  domain::kReminderStatusFailed,
          "ending a Habit must preserve a permanently failed Reminder audit");
  auto removed = active_service.remove(
      {ended.value().detail.habit.id, ended.value().detail.habit.updated_at,
       "Asia/Shanghai"});
  require(removed.ok() &&
              active_transaction->state.reminders.front().status ==
                  domain::kReminderStatusFailed,
          "deleting a Habit must preserve a permanently failed Reminder audit");
}

void test_clear_restore_date_boundary() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 700;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });

  auto command = create_command("Clear boundary", {2026, 9, 1},
                                {2026, 9, 10});
  command.reminder = {
      true, std::optional<std::string>("09:00"), "follow_device", "popup"};
  auto created = service.create(command);
  require(created.ok(), "clear boundary fixture must be created");
  const auto id = created.value().detail.habit.id;
  require(service.check_in({id, {2026, 9, 1}, "done", std::nullopt,
                                std::nullopt, "manual", std::nullopt,
                                std::nullopt, "Asia/Shanghai"}).ok(),
          "historical CheckIn fixture must succeed");
  const auto reminder_count = transaction->state.reminders.size();
  auto cleared = service.clear_check_in(
      {id, {2026, 9, 1}, "Asia/Shanghai"});
  require(cleared.ok() &&
              transaction->state.reminders.size() == reminder_count &&
              std::none_of(transaction->state.reminders.begin(),
                           transaction->state.reminders.end(),
                           [](const auto& reminder) {
                             return reminder.occurrence_date ==
                                        std::optional<std::string>("2026-09-01") &&
                                    reminder.is_enabled;
                           }),
          "clearing a historical CheckIn must not restore an expired occurrence");

}

void test_reconciliation_cursor_seeks_after_deleted_habit() {
  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 850;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });
  for (const auto* title : {"Cursor A", "Cursor B", "Cursor C"}) {
    auto command = create_command(title, {2026, 9, 1}, {2026, 9, 10});
    command.reminder = {
        true, std::optional<std::string>("09:00"), "follow_device", "popup"};
    require(service.create(command).ok(),
            "cursor fixture Habit must be created");
  }
  auto first = service.reconcile_reminders(
      {"Asia/Shanghai", "manual_retry", std::nullopt, 1});
  require(first.ok() && first.value().has_more &&
              first.value().next_cursor.has_value(),
          "first reconciliation page must expose a continuation");
  const auto cursor = *first.value().next_cursor;
  const std::string prefix = "habit-r1:";
  const auto deleted_id = cursor.substr(prefix.size());
  transaction->state.habits.erase(
      std::remove_if(transaction->state.habits.begin(),
                     transaction->state.habits.end(),
                     [&](const auto& habit) { return habit.id == deleted_id; }),
      transaction->state.habits.end());
  transaction->state.reminder_templates.erase(
      std::remove_if(transaction->state.reminder_templates.begin(),
                     transaction->state.reminder_templates.end(),
                     [&](const auto& reminder_template) {
                       return reminder_template.habit_id == deleted_id;
                     }),
      transaction->state.reminder_templates.end());

  auto resumed = service.reconcile_reminders(
      {"Asia/Shanghai", "manual_retry", cursor, 1});
  require(resumed.ok() && resumed.value().processed_count == 1,
          "a persisted seek-after cursor must survive deletion of its boundary Habit");
}

void test_date_update_reprojects_the_open_reminder_chain() {
  const auto run_case = [](domain::LocalDate original_start,
                           domain::LocalDate replacement_start,
                           domain::LocalDate replacement_end,
                           std::string expected_date, bool scheduled) {
    auto transaction = std::make_shared<MemoryHabitTransaction>();
    auto resolver = std::make_shared<FakeResolver>();
    int counter = original_start.day * 100 + replacement_start.day;
    application::HabitService service(
        transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
        [&] { return next_uuid(counter); });
    auto command = create_command("Date reproject", original_start,
                                  {2026, 9, 10});
    command.reminder = {
        true, std::optional<std::string>("09:00"), "follow_device", "popup"};
    auto created = service.create(command);
    require(created.ok() && transaction->state.reminders.size() == 1U,
            "date-reprojection fixture must create one Reminder");
    const auto old_id = transaction->state.reminders.front().id;
    if (scheduled) {
      transaction->state.reminders.front().status =
          std::string(domain::kReminderStatusScheduled);
      transaction->state.reminders.front().scheduled_at =
          "2026-09-03T11:00:00Z";
    }
    auto updated = service.update({
        created.value().detail.habit.id,
        created.value().detail.habit.updated_at,
        "Date reproject",
        std::nullopt,
        std::nullopt,
        std::nullopt,
        std::nullopt,
        replacement_start,
        replacement_end,
        std::nullopt,
        "Asia/Shanghai"});
    require(updated.ok(), "a legal date update must commit with an enabled template");
    const auto current = std::find_if(
        transaction->state.reminders.begin(), transaction->state.reminders.end(),
        [&](const auto& reminder) {
          return reminder.status == domain::kReminderStatusPending &&
                 reminder.is_enabled && reminder.occurrence_date == expected_date;
        });
    require(current != transaction->state.reminders.end(),
            "date update must materialize the first legal occurrence");
    if (current->id != old_id) {
      const auto old = std::find_if(
          transaction->state.reminders.begin(), transaction->state.reminders.end(),
          [&](const auto& reminder) { return reminder.id == old_id; });
      require(old != transaction->state.reminders.end() &&
                  old->status == domain::kReminderStatusCancelled,
              "date update must terminate the previous open occurrence");
    }
  };

  run_case({2026, 9, 3}, {2026, 9, 5}, {2026, 9, 10}, "2026-09-05", false);
  run_case({2026, 9, 5}, {2026, 9, 1}, {2026, 9, 10}, "2026-09-03", true);
  run_case({2026, 9, 5}, {2026, 9, 3}, {2026, 9, 3}, "2026-09-03", false);

  auto transaction = std::make_shared<MemoryHabitTransaction>();
  auto resolver = std::make_shared<FakeResolver>();
  int counter = 950;
  application::HabitService service(
      transaction, resolver, [] { return "2026-09-03T12:00:00Z"; },
      [&] { return next_uuid(counter); });
  auto command = create_command("End-only shrink", {2026, 9, 3},
                                {2026, 9, 10});
  command.reminder = {
      true, std::optional<std::string>("09:00"), "follow_device", "popup"};
  auto created = service.create(command);
  require(created.ok(), "end-only shrink fixture must be created");
  const auto reminder_id = transaction->state.reminders.front().id;
  transaction->state.reminders.front().status =
      std::string(domain::kReminderStatusScheduled);
  transaction->state.reminders.front().scheduled_at =
      "2026-09-03T11:00:00Z";
  auto updated = service.update({
      created.value().detail.habit.id,
      created.value().detail.habit.updated_at,
      "End-only shrink",
      std::nullopt,
      std::nullopt,
      std::nullopt,
      std::nullopt,
      {2026, 9, 3},
      {2026, 9, 3},
      std::nullopt,
      "Asia/Shanghai"});
  require(updated.ok() && transaction->state.reminders.front().id == reminder_id &&
              transaction->state.reminders.front().status ==
                  domain::kReminderStatusScheduled,
          "an end-only shrink must preserve an already scheduled first legal occurrence");
}

picojson::object successful_data(const std::string& json,
                                 const std::string& operation) {
  picojson::value root;
  require(picojson::parse(root, json).empty() && root.is<picojson::object>(),
          operation + " must return a NativeResult object");
  const auto& envelope = root.get<picojson::object>();
  require(envelope.at("ok").get<bool>(), operation + " must succeed: " + json);
  require(envelope.at("data").is<picojson::object>(),
          operation + " data must be an object");
  return envelope.at("data").get<picojson::object>();
}

void test_all_boundary_endpoints_against_real_v5_runtime() {
  const auto directory = std::filesystem::temp_directory_path() /
      ("excellent_calendar_habit_boundary_" + common::generate_uuid_v4());
  std::filesystem::create_directories(directory);
  struct Cleanup {
    std::filesystem::path path;
    ~Cleanup() {
      (void)boundary::api::initialize_runtime("");
      std::error_code error;
      std::filesystem::remove_all(path, error);
    }
  } cleanup{directory};
  auto initialized = boundary::api::initialize_recurring_runtime(
      directory.string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok() && initialized.value().storage_format_version == 5,
          "Habit Boundary runtime must initialize real SQLite v5");
  const auto resolver = boundary::api::current_local_time_resolver();
  const auto now = common::utc_now_iso8601();
  auto local = resolver->to_local(now, "Asia/Shanghai");
  require(local.ok(), "test must resolve current local date");
  domain::LocalDate today{local.value().year, local.value().month,
                          local.value().day};
  const auto today_text = domain::format_local_date(today);
  const auto end_text = domain::format_local_date(domain::add_local_days(today, 5));
  const std::string create_json =
      "{\"title\":\"Boundary habit\",\"description\":null,"
      "\"category_id\":null,\"recurrence\":{\"frequency\":\"daily\","
      "\"interval\":1,\"timezone_mode\":\"follow_device\"},"
      "\"target_count_hundredths\":null,\"unit\":null,\"start_date\":\"" +
      today_text + "\",\"end_date\":\"" + end_text +
      "\",\"reminder\":{\"is_enabled\":false,\"local_time\":null,"
      "\"timezone_mode\":\"follow_device\",\"method\":\"popup\"},"
      "\"timezone\":\"Asia/Shanghai\"}";
  auto created = successful_data(boundary::api::create_habit_v2(create_json),
                                 "habit.create");
  auto detail = created.at("detail").get<picojson::object>();
  auto habit = detail.at("habit").get<picojson::object>();
  const auto id = habit.at("id").get<std::string>();
  auto updated_at = habit.at("updated_at").get<std::string>();

  successful_data(boundary::api::list_habits_v2(
                      "{\"timezone\":\"Asia/Shanghai\"}"),
                  "habit.list");
  successful_data(boundary::api::get_habit_detail_v2(
                      "{\"id\":\"" + id +
                      "\",\"timezone\":\"Asia/Shanghai\","
                      "\"history_page_size\":30}"),
                  "habit.detail");
  const std::string update_json =
      "{\"id\":\"" + id + "\",\"expected_updated_at\":\"" +
      updated_at + "\",\"title\":\"Boundary habit updated\","
      "\"description\":null,\"category_id\":null,"
      "\"target_count_hundredths\":null,\"unit\":null,"
      "\"start_date\":\"" + today_text + "\",\"end_date\":\"" +
      end_text + "\",\"timezone\":\"Asia/Shanghai\"}";
  auto updated = successful_data(boundary::api::update_habit_v2(update_json),
                                 "habit.update");
  updated_at = updated.at("detail").get<picojson::object>()
                   .at("habit").get<picojson::object>()
                   .at("updated_at").get<std::string>();
  const std::string check_json =
      "{\"habit_id\":\"" + id + "\",\"check_date\":\"" + today_text +
      "\",\"status\":\"done\",\"completed_count_hundredths\":null,"
      "\"note\":null,\"source\":\"manual\",\"occurrence_key\":null,"
      "\"action_id\":null,\"timezone\":\"Asia/Shanghai\"}";
  successful_data(boundary::api::check_in_habit_v2(check_json),
                  "habit.check_in");
  successful_data(boundary::api::clear_habit_check_in_v2(
                      "{\"habit_id\":\"" + id + "\",\"check_date\":\"" +
                      today_text + "\",\"timezone\":\"Asia/Shanghai\"}"),
                  "habit.clear_check_in");
  successful_data(boundary::api::list_habit_daily_statuses_v2(
                      "{\"habit_id\":\"" + id + "\",\"start_date\":\"" +
                      today_text + "\",\"end_date\":\"" + today_text +
                      "\",\"timezone\":\"Asia/Shanghai\"}"),
                  "habit.list_daily_statuses");
  auto reminder = successful_data(boundary::api::set_habit_reminder_v2(
      "{\"habit_id\":\"" + id + "\",\"expected_updated_at\":\"" +
      updated_at + "\",\"reminder\":{\"is_enabled\":true,"
      "\"local_time\":\"23:59\",\"timezone_mode\":\"follow_device\","
      "\"method\":\"popup\"},\"timezone\":\"Asia/Shanghai\"}"),
      "habit.set_reminder");
  updated_at = reminder.at("detail").get<picojson::object>()
                   .at("habit").get<picojson::object>()
                   .at("updated_at").get<std::string>();
  successful_data(boundary::api::reconcile_habit_reminders_v2(
                      "{\"timezone\":\"Asia/Shanghai\","
                      "\"trigger_source\":\"manual_retry\",\"cursor\":null,"
                      "\"limit\":100}"),
                  "habit.reconcile_reminders");
  auto ended = successful_data(boundary::api::end_habit_v2(
      "{\"id\":\"" + id + "\",\"expected_updated_at\":\"" + updated_at +
      "\",\"timezone\":\"Asia/Shanghai\"}"), "habit.end");
  updated_at = ended.at("detail").get<picojson::object>()
                   .at("habit").get<picojson::object>()
                   .at("updated_at").get<std::string>();
  successful_data(boundary::api::delete_habit_v2(
                      "{\"id\":\"" + id + "\",\"expected_updated_at\":\"" +
                      updated_at + "\",\"timezone\":\"Asia/Shanghai\"}"),
                  "habit.delete");

  const auto invalid_decimal = boundary::api::create_habit_v2(
      "{\"title\":\"bad\",\"description\":null,\"category_id\":null,"
      "\"recurrence\":{\"frequency\":\"daily\",\"interval\":1,"
      "\"timezone_mode\":\"follow_device\"},"
      "\"target_count_hundredths\":1.25,\"unit\":\"x\","
      "\"start_date\":\"" + today_text + "\",\"end_date\":\"" + end_text +
      "\",\"reminder\":{\"is_enabled\":false,\"local_time\":null,"
      "\"timezone_mode\":\"follow_device\",\"method\":\"popup\"},"
      "\"timezone\":\"Asia/Shanghai\"}");
  picojson::value invalid_root;
  require(picojson::parse(invalid_root, invalid_decimal).empty() &&
              !invalid_root.get<picojson::object>().at("ok").get<bool>() &&
              invalid_root.get<picojson::object>().at("error")
                      .get<picojson::object>().at("code").get<std::string>() ==
                  "CONTRACT_VALIDATION_FAILED",
          "Boundary must strictly reject decimal fixed-point input");

  for (const auto* invalid_number : {"1.0", "1e2"}) {
    const auto invalid_lexical = boundary::api::create_habit_v2(
        "{\"title\":\"bad lexical\",\"description\":null,\"category_id\":null,"
        "\"recurrence\":{\"frequency\":\"daily\",\"interval\":1,"
        "\"timezone_mode\":\"follow_device\"},"
        "\"target_count_hundredths\":" + std::string(invalid_number) +
        ",\"unit\":\"x\",\"start_date\":\"" + today_text +
        "\",\"end_date\":\"" + end_text +
        "\",\"reminder\":{\"is_enabled\":false,\"local_time\":null,"
        "\"timezone_mode\":\"follow_device\",\"method\":\"popup\"},"
        "\"timezone\":\"Asia/Shanghai\"}");
    picojson::value invalid_value;
    require(picojson::parse(invalid_value, invalid_lexical).empty() &&
                !invalid_value.get<picojson::object>().at("ok").get<bool>() &&
                invalid_value.get<picojson::object>().at("error")
                        .get<picojson::object>().at("code").get<std::string>() ==
                    "CONTRACT_VALIDATION_FAILED",
            std::string("Boundary must reject fixed-point token ") + invalid_number);
  }

  const auto invalid_completed = boundary::api::check_in_habit_v2(
      "{\"habit_id\":\"" + id + "\",\"check_date\":\"" + today_text +
      "\",\"status\":\"done\",\"completed_count_hundredths\":1e2,"
      "\"note\":null,\"source\":\"manual\",\"occurrence_key\":null,"
      "\"action_id\":null,\"timezone\":\"Asia/Shanghai\"}");
  picojson::value invalid_completed_value;
  require(picojson::parse(invalid_completed_value, invalid_completed).empty() &&
              !invalid_completed_value.get<picojson::object>()
                   .at("ok").get<bool>(),
          "all inbound _hundredths fields must reject exponent tokens");

  std::vector<double> adjacent_values;
  for (const auto* safe_integer : {"9007199254740990", "9007199254740991"}) {
    auto accepted = successful_data(boundary::api::create_habit_v2(
        "{\"title\":\"safe integer\",\"description\":null,"
        "\"category_id\":null,\"recurrence\":{\"frequency\":\"daily\","
        "\"interval\":1,\"timezone_mode\":\"follow_device\"},"
        "\"target_count_hundredths\":" + std::string(safe_integer) +
        ",\"unit\":\"x\",\"start_date\":\"" + today_text +
        "\",\"end_date\":\"" + end_text +
        "\",\"reminder\":{\"is_enabled\":false,\"local_time\":null,"
        "\"timezone_mode\":\"follow_device\",\"method\":\"popup\"},"
        "\"timezone\":\"Asia/Shanghai\"}"),
        "habit.create safe integer");
    adjacent_values.push_back(
        accepted.at("detail").get<picojson::object>()
            .at("habit").get<picojson::object>()
            .at("target_count_hundredths").get<double>());
  }
  require(adjacent_values.size() == 2U &&
              adjacent_values[0] == 9007199254740990.0 &&
              adjacent_values[1] == 9007199254740991.0 &&
              adjacent_values[0] != adjacent_values[1],
          "adjacent JSON-safe integer hundredths must survive Boundary and SQLite round-trip");

  successful_data(boundary::api::create_habit_v2(
      "{\"title\":\"non-hundredths decimal spelling\","
      "\"description\":null,\"category_id\":null,"
      "\"recurrence\":{\"frequency\":\"daily\",\"interval\":1.0,"
      "\"timezone_mode\":\"follow_device\"},"
      "\"target_count_hundredths\":null,\"unit\":null,"
      "\"start_date\":\"" + today_text + "\",\"end_date\":\"" +
      end_text +
      "\",\"reminder\":{\"is_enabled\":false,\"local_time\":null,"
      "\"timezone_mode\":\"follow_device\",\"method\":\"popup\"},"
      "\"timezone\":\"Asia/Shanghai\"}"),
      "non-hundredths integer field compatibility");
}

}  // namespace

int main() {
  try {
    test_lifecycle_check_in_statistics_and_locks();
    test_bounds_overflow_and_atomic_failure();
    test_ended_progress_and_deleted_detail_errors();
    test_template_change_daily_display_transitions();
    test_reconciliation_lifecycle_and_terminal_failures();
    test_clear_restore_date_boundary();
    test_reconciliation_cursor_seeks_after_deleted_habit();
    test_date_update_reprojects_the_open_reminder_chain();
    test_all_boundary_endpoints_against_real_v5_runtime();
    std::cout << "habit_core_tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "habit_core_tests failed: " << error.what() << '\n';
    return 1;
  }
}
