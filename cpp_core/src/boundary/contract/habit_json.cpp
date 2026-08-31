#include "excellent_calendar/boundary/contract/habit_json.hpp"

#include <cstdint>
#include <optional>
#include <utility>

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value nullable(const std::optional<std::string>& value) {
  return value ? picojson::value(*value) : picojson::value();
}

picojson::value nullable_int64(const std::optional<std::int64_t>& value) {
  return value ? picojson::value(static_cast<double>(*value)) : picojson::value();
}

picojson::value nullable_double(const std::optional<double>& value) {
  return value ? picojson::value(*value) : picojson::value();
}

picojson::value reminder_template_json(
    const domain::HabitReminderTemplate& value) {
  picojson::object data;
  data["template_key"] = picojson::value(value.template_key);
  data["habit_id"] = picojson::value(value.habit_id);
  data["local_time"] = picojson::value(value.local_time);
  data["timezone_mode"] = picojson::value(value.timezone_mode);
  data["method"] = picojson::value(value.method);
  data["is_enabled"] = picojson::value(value.is_enabled);
  data["created_at"] = picojson::value(value.created_at);
  data["updated_at"] = picojson::value(value.updated_at);
  data["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(data));
}

picojson::value summary_json(const application::HabitSummary& value) {
  picojson::object data;
  data["habit"] = habit_response_json(value.habit);
  data["lifecycle_status"] = picojson::value(value.lifecycle_status);
  data["today"] = value.today ? habit_daily_status_response_json(*value.today)
                              : picojson::value();
  data["statistics"] = habit_statistics_response_json(value.statistics);
  data["reminder_settings"] =
      habit_reminder_settings_response_json(value.reminder_settings);
  data["challenge_time_progress"] =
      picojson::value(value.challenge_time_progress);
  data["remaining_days"] = picojson::value(static_cast<double>(value.remaining_days));
  return picojson::value(std::move(data));
}

}  // namespace

picojson::value habit_response_json(const domain::Habit& value) {
  picojson::object data;
  data["id"] = picojson::value(value.id);
  data["title"] = picojson::value(value.title);
  data["description"] = nullable(value.description);
  data["category_id"] = nullable(value.category_id);
  data["recurrence_id"] = picojson::value(value.recurrence_id);
  data["target_count_hundredths"] = nullable_int64(value.target_count_hundredths);
  data["unit"] = nullable(value.unit);
  data["start_date"] = picojson::value(domain::format_local_date(value.start_date));
  data["end_date"] = picojson::value(domain::format_local_date(value.end_date));
  data["ended_date"] = value.ended_date
                            ? picojson::value(domain::format_local_date(*value.ended_date))
                            : picojson::value();
  data["is_active"] = picojson::value(value.is_active);
  data["created_at"] = picojson::value(value.created_at);
  data["updated_at"] = picojson::value(value.updated_at);
  data["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(data));
}

picojson::value habit_recurrence_response_json(
    const domain::HabitRecurrence& value) {
  picojson::object data;
  data["id"] = picojson::value(value.id);
  data["frequency"] = picojson::value(value.frequency);
  data["interval"] = picojson::value(static_cast<double>(value.interval));
  data["timezone_mode"] = picojson::value(value.timezone_mode);
  data["created_at"] = picojson::value(value.created_at);
  data["updated_at"] = picojson::value(value.updated_at);
  data["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(data));
}

picojson::value habit_check_in_response_json(const domain::HabitCheckIn& value) {
  picojson::object data;
  data["id"] = picojson::value(value.id);
  data["habit_id"] = picojson::value(value.habit_id);
  data["check_date"] = picojson::value(domain::format_local_date(value.check_date));
  data["status"] = picojson::value(value.status);
  data["completed_count_hundredths"] = nullable_int64(value.completed_count_hundredths);
  data["target_count_snapshot_hundredths"] =
      nullable_int64(value.target_count_snapshot_hundredths);
  data["unit_snapshot"] = nullable(value.unit_snapshot);
  data["completed_at"] = nullable(value.completed_at);
  data["note"] = nullable(value.note);
  data["source"] = picojson::value(value.source);
  data["created_at"] = picojson::value(value.created_at);
  data["updated_at"] = picojson::value(value.updated_at);
  data["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(data));
}

picojson::value habit_daily_status_response_json(
    const application::HabitDailyStatus& value) {
  picojson::object data;
  data["date"] = picojson::value(domain::format_local_date(value.date));
  data["status"] = picojson::value(value.status);
  data["is_final"] = picojson::value(value.is_final);
  data["check_in"] = value.check_in ? habit_check_in_response_json(*value.check_in)
                                    : picojson::value();
  data["completion_ratio"] = nullable_double(value.completion_ratio);
  return picojson::value(std::move(data));
}

picojson::value habit_statistics_response_json(
    const application::HabitStatistics& value) {
  picojson::object data;
  data["as_of_date"] = picojson::value(domain::format_local_date(value.as_of_date));
  data["elapsed_eligible_days"] = picojson::value(static_cast<double>(value.elapsed_eligible_days));
  data["done_days"] = picojson::value(static_cast<double>(value.done_days));
  data["skipped_days"] = picojson::value(static_cast<double>(value.skipped_days));
  data["partial_days"] = picojson::value(static_cast<double>(value.partial_days));
  data["missed_days"] = picojson::value(static_cast<double>(value.missed_days));
  data["current_streak"] = picojson::value(static_cast<double>(value.current_streak));
  data["longest_streak"] = picojson::value(static_cast<double>(value.longest_streak));
  data["completion_rate_7_days"] = picojson::value(value.completion_rate_7_days);
  data["completion_rate_30_days"] = picojson::value(value.completion_rate_30_days);
  data["completion_rate_all"] = picojson::value(value.completion_rate_all);
  data["quantity_progress_rate_7_days"] = nullable_double(value.quantity_progress_rate_7_days);
  data["quantity_progress_rate_30_days"] = nullable_double(value.quantity_progress_rate_30_days);
  data["quantity_progress_rate_all"] = nullable_double(value.quantity_progress_rate_all);
  data["total_completed_count_hundredths"] = nullable_int64(value.total_completed_count_hundredths);
  data["average_completed_count_per_eligible_day_hundredths"] =
      nullable_int64(value.average_completed_count_per_eligible_day_hundredths);
  return picojson::value(std::move(data));
}

picojson::value habit_reminder_settings_response_json(
    const application::HabitReminderSettings& value) {
  picojson::object data;
  data["is_enabled"] = picojson::value(value.is_enabled);
  data["template"] = value.reminder_template
                         ? reminder_template_json(*value.reminder_template)
                         : picojson::value();
  data["active_reminder_count"] =
      picojson::value(static_cast<double>(value.active_reminder_count));
  data["schedule_reconciliation_required"] =
      picojson::value(value.schedule_reconciliation_required);
  return picojson::value(std::move(data));
}

picojson::value habit_detail_response_json(const application::HabitDetail& value) {
  picojson::array history;
  for (const auto& item : value.history)
    history.push_back(habit_daily_status_response_json(item));
  picojson::object data;
  data["habit"] = habit_response_json(value.habit);
  data["recurrence"] = habit_recurrence_response_json(value.recurrence);
  data["lifecycle_status"] = picojson::value(value.lifecycle_status);
  data["statistics"] = habit_statistics_response_json(value.statistics);
  data["reminder_settings"] = habit_reminder_settings_response_json(value.reminder_settings);
  data["today"] = value.today ? habit_daily_status_response_json(*value.today)
                              : picojson::value();
  data["history"] = picojson::value(std::move(history));
  data["history_start_date"] = value.history_start_date
                                    ? picojson::value(domain::format_local_date(*value.history_start_date))
                                    : picojson::value();
  data["history_end_date"] = value.history_end_date
                                  ? picojson::value(domain::format_local_date(*value.history_end_date))
                                  : picojson::value();
  data["has_earlier_history"] = picojson::value(value.has_earlier_history);
  data["has_ever_checked_in"] = picojson::value(value.has_ever_checked_in);
  data["latest_check_in_date"] = value.latest_check_in_date
                                      ? picojson::value(domain::format_local_date(*value.latest_check_in_date))
                                      : picojson::value();
  data["challenge_time_progress"] = picojson::value(value.challenge_time_progress);
  data["remaining_days"] = picojson::value(static_cast<double>(value.remaining_days));
  return picojson::value(std::move(data));
}

picojson::value habit_list_response_json(const application::HabitListPage& value) {
  picojson::array items;
  for (const auto& item : value.items) items.push_back(summary_json(item));
  picojson::object pagination;
  pagination["total"] = picojson::value(static_cast<double>(value.total));
  pagination["page"] = picojson::value(static_cast<double>(value.page));
  pagination["page_size"] = picojson::value(static_cast<double>(value.page_size));
  pagination["has_more"] = picojson::value(value.has_more);
  pagination["next_cursor"] = nullable(value.next_cursor);
  picojson::object progress;
  progress["as_of_date"] = picojson::value(domain::format_local_date(value.today_progress.as_of_date));
  progress["active_count"] = picojson::value(static_cast<double>(value.today_progress.active_count));
  progress["done_count"] = picojson::value(static_cast<double>(value.today_progress.done_count));
  progress["eligible_count"] = picojson::value(static_cast<double>(value.today_progress.eligible_count));
  progress["skipped_count"] = picojson::value(static_cast<double>(value.today_progress.skipped_count));
  progress["partial_count"] = picojson::value(static_cast<double>(value.today_progress.partial_count));
  progress["absent_count"] = picojson::value(static_cast<double>(value.today_progress.absent_count));
  picojson::object data;
  data["items"] = picojson::value(std::move(items));
  data["pagination"] = picojson::value(std::move(pagination));
  data["today_progress"] = picojson::value(std::move(progress));
  return picojson::value(std::move(data));
}

picojson::value habit_mutation_commit_response_json(
    const application::HabitMutationCommit& value) {
  picojson::object data;
  data["data_saved"] = picojson::value(true);
  data["detail"] = habit_detail_response_json(value.detail);
  data["schedule_reconciliation_required"] =
      picojson::value(value.schedule_reconciliation_required);
  return picojson::value(std::move(data));
}

picojson::value habit_check_in_commit_response_json(
    const application::HabitCheckInCommit& value) {
  picojson::object data;
  data["data_saved"] = picojson::value(true);
  data["check_in"] = value.check_in ? habit_check_in_response_json(*value.check_in)
                                    : picojson::value();
  data["daily_status"] = habit_daily_status_response_json(value.daily_status);
  data["statistics"] = habit_statistics_response_json(value.statistics);
  data["reminder_settings"] = habit_reminder_settings_response_json(value.reminder_settings);
  data["schedule_reconciliation_required"] = picojson::value(value.schedule_reconciliation_required);
  data["idempotent_replay"] = picojson::value(value.idempotent_replay);
  return picojson::value(std::move(data));
}

picojson::value habit_delete_commit_response_json(
    const application::HabitDeleteCommit& value) {
  picojson::object data;
  data["data_saved"] = picojson::value(true);
  data["habit_id"] = picojson::value(value.habit_id);
  data["deleted_at"] = picojson::value(value.deleted_at);
  data["schedule_reconciliation_required"] = picojson::value(value.schedule_reconciliation_required);
  return picojson::value(std::move(data));
}

picojson::value habit_daily_status_list_response_json(
    const application::HabitDailyStatusList& value) {
  picojson::array items;
  for (const auto& item : value.items) items.push_back(habit_daily_status_response_json(item));
  picojson::object data;
  data["habit_id"] = picojson::value(value.habit_id);
  data["start_date"] = picojson::value(domain::format_local_date(value.start_date));
  data["end_date"] = picojson::value(domain::format_local_date(value.end_date));
  data["items"] = picojson::value(std::move(items));
  return picojson::value(std::move(data));
}

picojson::value habit_reconcile_response_json(
    const application::ReconcileHabitRemindersResult& value) {
  picojson::object data;
  data["request_limit"] = picojson::value(static_cast<double>(value.request_limit));
  data["processed_count"] = picojson::value(static_cast<double>(value.processed_count));
  data["materialized_count"] = picojson::value(static_cast<double>(value.materialized_count));
  data["expired_count"] = picojson::value(static_cast<double>(value.expired_count));
  data["cancelled_count"] = picojson::value(static_cast<double>(value.cancelled_count));
  data["unchanged_count"] = picojson::value(static_cast<double>(value.unchanged_count));
  data["schedule_reconciliation_required"] = picojson::value(value.schedule_reconciliation_required);
  data["has_more"] = picojson::value(value.has_more);
  data["next_cursor"] = nullable(value.next_cursor);
  return picojson::value(std::move(data));
}

}  // namespace excellent_calendar::boundary::contract
