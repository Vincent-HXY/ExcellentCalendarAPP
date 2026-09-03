#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"

namespace excellent_calendar::application {

struct HabitReminderPlan {
  bool is_enabled = false;
  std::optional<std::string> local_time;
  std::string timezone_mode = "follow_device";
  std::string method = "popup";
};

struct CreateHabitCommand {
  std::string title;
  std::optional<std::string> description;
  std::optional<std::string> category_id;
  std::string recurrence_frequency = "daily";
  int recurrence_interval = 1;
  std::string recurrence_timezone_mode = "follow_device";
  std::optional<std::int64_t> target_count_hundredths;
  std::optional<std::string> unit;
  domain::LocalDate start_date;
  domain::LocalDate end_date;
  HabitReminderPlan reminder;
  std::string timezone;
};

struct UpdateHabitCommand {
  std::string id;
  std::string expected_updated_at;
  std::string title;
  std::optional<std::string> description;
  std::optional<std::string> category_id;
  std::optional<std::int64_t> target_count_hundredths;
  std::optional<std::string> unit;
  domain::LocalDate start_date;
  domain::LocalDate end_date;
  std::optional<HabitReminderPlan> reminder;
  std::string timezone;
};

struct HabitIdentityCommand {
  std::string id;
  std::string expected_updated_at;
  std::string timezone;
};

struct HabitCheckInCommand {
  std::string habit_id;
  domain::LocalDate check_date;
  std::string status;
  std::optional<std::int64_t> completed_count_hundredths;
  std::optional<std::string> note;
  std::string source = "manual";
  std::optional<std::string> occurrence_key;
  std::optional<std::string> action_id;
  std::string timezone;
};

struct ClearHabitCheckInCommand {
  std::string habit_id;
  domain::LocalDate check_date;
  std::string timezone;
};

struct SetHabitReminderCommand {
  std::string habit_id;
  std::string expected_updated_at;
  HabitReminderPlan reminder;
  std::string timezone;
};

struct HabitDailyStatus {
  domain::LocalDate date;
  std::string status;
  bool is_final = false;
  std::optional<domain::HabitCheckIn> check_in;
  std::optional<double> completion_ratio;
};

/** Shared read projection used by Habit and CalendarView. */
HabitDailyStatus project_habit_daily_status(
    const repository::HabitState& state,
    const domain::Habit& habit,
    const domain::LocalDate& date,
    const domain::LocalDate& today);

/**
 * Request-scoped authoritative Habit daily-status projector.
 *
 * The supplied CheckIn vector must outlive the projector. Active CheckIns are
 * indexed once so multi-day consumers do not repeatedly scan the full store.
 */
class HabitDailyStatusProjector {
 public:
  explicit HabitDailyStatusProjector(
      const std::vector<domain::HabitCheckIn>& check_ins);

  HabitDailyStatus project(const domain::Habit& habit,
                           const domain::LocalDate& date,
                           const domain::LocalDate& today) const;

 private:
  std::unordered_map<std::string, const domain::HabitCheckIn*>
      active_check_ins_;
};

struct HabitStatistics {
  domain::LocalDate as_of_date;
  int elapsed_eligible_days = 0;
  int done_days = 0;
  int skipped_days = 0;
  int partial_days = 0;
  int missed_days = 0;
  int current_streak = 0;
  int longest_streak = 0;
  double completion_rate_7_days = 0.0;
  double completion_rate_30_days = 0.0;
  double completion_rate_all = 0.0;
  std::optional<double> quantity_progress_rate_7_days;
  std::optional<double> quantity_progress_rate_30_days;
  std::optional<double> quantity_progress_rate_all;
  std::optional<std::int64_t> total_completed_count_hundredths;
  std::optional<std::int64_t>
      average_completed_count_per_eligible_day_hundredths;
};

struct HabitReminderSettings {
  bool is_enabled = false;
  std::optional<domain::HabitReminderTemplate> reminder_template;
  int active_reminder_count = 0;
  bool schedule_reconciliation_required = false;
};

struct HabitDetail {
  domain::Habit habit;
  domain::HabitRecurrence recurrence;
  std::string lifecycle_status;
  HabitStatistics statistics;
  HabitReminderSettings reminder_settings;
  std::optional<HabitDailyStatus> today;
  std::vector<HabitDailyStatus> history;
  std::optional<domain::LocalDate> history_start_date;
  std::optional<domain::LocalDate> history_end_date;
  bool has_earlier_history = false;
  bool has_ever_checked_in = false;
  std::optional<domain::LocalDate> latest_check_in_date;
  double challenge_time_progress = 0.0;
  int remaining_days = 0;
};

struct HabitSummary {
  domain::Habit habit;
  std::string lifecycle_status;
  std::optional<HabitDailyStatus> today;
  HabitStatistics statistics;
  HabitReminderSettings reminder_settings;
  double challenge_time_progress = 0.0;
  int remaining_days = 0;
};

struct HabitTodayProgress {
  domain::LocalDate as_of_date;
  std::int64_t active_count = 0;
  std::int64_t done_count = 0;
  std::int64_t eligible_count = 0;
  std::int64_t skipped_count = 0;
  std::int64_t partial_count = 0;
  std::int64_t absent_count = 0;
};

struct ListHabitsQuery {
  std::string timezone;
  std::vector<std::string> lifecycle_statuses;
  std::vector<std::string> category_ids;
  std::int64_t page = 1;
  int page_size = 50;
  std::optional<std::string> cursor;
};

struct HabitListPage {
  std::vector<HabitSummary> items;
  std::int64_t total = 0;
  std::int64_t page = 1;
  int page_size = 50;
  bool has_more = false;
  std::optional<std::string> next_cursor;
  HabitTodayProgress today_progress;
};

struct HabitMutationCommit {
  HabitDetail detail;
  bool schedule_reconciliation_required = false;
};

struct HabitCheckInCommit {
  std::optional<domain::HabitCheckIn> check_in;
  HabitDailyStatus daily_status;
  HabitStatistics statistics;
  HabitReminderSettings reminder_settings;
  bool schedule_reconciliation_required = false;
  bool idempotent_replay = false;
};

struct HabitDeleteCommit {
  std::string habit_id;
  std::string deleted_at;
  bool schedule_reconciliation_required = false;
};

struct HabitDailyStatusList {
  std::string habit_id;
  domain::LocalDate start_date;
  domain::LocalDate end_date;
  std::vector<HabitDailyStatus> items;
};

struct ReconcileHabitRemindersCommand {
  std::string timezone;
  std::string trigger_source;
  std::optional<std::string> cursor;
  int limit = 100;
};

struct ReconcileHabitRemindersResult {
  int request_limit = 100;
  int processed_count = 0;
  int materialized_count = 0;
  int expired_count = 0;
  int cancelled_count = 0;
  int unchanged_count = 0;
  bool schedule_reconciliation_required = false;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

class HabitService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  HabitService(std::shared_ptr<repository::HabitTransaction> transaction,
               std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
               ClockFn clock,
               IdGeneratorFn id_generator);

  common::Result<HabitMutationCommit> create(const CreateHabitCommand& command);
  common::Result<HabitMutationCommit> update(const UpdateHabitCommand& command);
  common::Result<HabitListPage> list(const ListHabitsQuery& query);
  common::Result<HabitDetail> detail(std::string id, std::string timezone,
                                     int history_page_size);
  common::Result<HabitMutationCommit> end(const HabitIdentityCommand& command);
  common::Result<HabitDeleteCommit> remove(const HabitIdentityCommand& command);
  common::Result<HabitCheckInCommit> check_in(const HabitCheckInCommand& command);
  common::Result<HabitCheckInCommit> clear_check_in(
      const ClearHabitCheckInCommand& command);
  common::Result<HabitDailyStatusList> list_daily_statuses(
      std::string habit_id, domain::LocalDate start_date,
      domain::LocalDate end_date, std::string timezone);
  common::Result<HabitMutationCommit> set_reminder(
      const SetHabitReminderCommand& command);
  common::Result<ReconcileHabitRemindersResult> reconcile_reminders(
      const ReconcileHabitRemindersCommand& command);

 private:
  common::Result<domain::LocalDate> today(std::string_view timezone,
                                         std::string_view now) const;
  common::Result<HabitDetail> project_detail(
      const repository::HabitState& state, const domain::Habit& habit,
      const domain::LocalDate& today, int history_page_size) const;

  std::shared_ptr<repository::HabitTransaction> transaction_;
  std::shared_ptr<domain::LocalTimeResolver> local_time_resolver_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
