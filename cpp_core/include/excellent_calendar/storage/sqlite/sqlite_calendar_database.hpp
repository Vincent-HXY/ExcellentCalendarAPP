#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/anniversary_transaction.hpp"
#include "excellent_calendar/repository/category_repository.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

struct sqlite3;

namespace excellent_calendar::storage::sqlite {

inline constexpr int kCalendarCoreSqliteStorageVersion = 5;
inline constexpr const char* kCalendarCoreSqliteFileName =
    "calendar_core.sqlite3";

/**
 * Process-owned SQLite database behind the existing Repository ports.
 *
 * The database stores one strict v3 storage record per row. Identity and
 * scheduling indexes are native SQLite indexes, while the existing codecs
 * remain the single field-level decoder during the compatibility migration.
 */
class SqliteCalendarDatabase final {
 public:
  using Operation = std::function<common::Result<common::Unit>()>;
  using MigrationFailureHook =
      std::function<common::Result<common::Unit>(std::string_view phase)>;

  static common::Result<std::shared_ptr<SqliteCalendarDatabase>> open(
      std::filesystem::path storage_directory,
      MigrationFailureHook migration_failure_hook = {});

  ~SqliteCalendarDatabase();

  SqliteCalendarDatabase(const SqliteCalendarDatabase&) = delete;
  SqliteCalendarDatabase& operator=(const SqliteCalendarDatabase&) = delete;

  common::Result<common::Unit> validate();
  common::Result<common::Unit> transaction(const Operation& operation);

  common::Result<repository::RecurringEventState> load_recurring_state();
  common::Result<repository::AnniversaryState> load_anniversary_state();
  common::Result<repository::AnniversaryOccurrenceSnapshot>
  load_anniversary_occurrence_snapshot();
  common::Result<repository::CategoryState> load_category_state();
  common::Result<repository::HabitState> load_habit_state();

  common::Result<std::vector<domain::Event>> load_legacy_events();
  common::Result<std::vector<domain::Reminder>> load_legacy_reminders();
  common::Result<std::vector<domain::Notification>> load_legacy_notifications();

  common::Result<common::Unit> write_recurring_changes(
      const repository::RecurringEventState& before,
      const repository::RecurringEventState& after);
  common::Result<common::Unit> write_anniversary_changes(
      const repository::AnniversaryState& before,
      const repository::AnniversaryState& after);
  common::Result<common::Unit> write_category_changes(
      const repository::CategoryState& before,
      const repository::CategoryState& after);
  common::Result<common::Unit> write_habit_changes(
      const repository::HabitState& before,
      const repository::HabitState& after);
  common::Result<common::Unit> write_legacy_events(
      const std::vector<domain::Event>& events);
  common::Result<common::Unit> write_legacy_reminders(
      const std::vector<domain::Reminder>& reminders);
  common::Result<common::Unit> write_legacy_notifications(
      const std::vector<domain::Notification>& notifications);

  const std::filesystem::path& storage_directory() const {
    return storage_directory_;
  }
  const std::filesystem::path& database_path() const { return database_path_; }

 private:
  SqliteCalendarDatabase(std::filesystem::path storage_directory,
                         std::filesystem::path database_path,
                         ::sqlite3* database);

  common::Result<common::Unit> configure_connection(bool enable_wal);
  common::Result<common::Unit> create_schema();
  common::Result<common::Unit> upgrade_v4_to_v5(
      bool fresh_database,
      const MigrationFailureHook& migration_failure_hook);
  common::Result<common::Unit> validate_v4_locked();
  common::Result<common::Unit> validate_locked();
  common::Result<repository::RecurringEventState> load_recurring_state_locked();
  common::Result<repository::AnniversaryState> load_anniversary_state_locked();
  common::Result<repository::CategoryState> load_category_state_locked();
  common::Result<repository::HabitState> load_habit_state_locked();
  common::Result<std::vector<domain::Event>> load_legacy_events_locked();
  common::Result<std::vector<domain::Reminder>> load_legacy_reminders_locked();
  common::Result<std::vector<domain::Notification>>
  load_legacy_notifications_locked();
  common::Result<common::Unit> write_recurring_changes_locked(
      const repository::RecurringEventState& before,
      const repository::RecurringEventState& after);
  common::Result<common::Unit> write_anniversary_changes_locked(
      const repository::AnniversaryState& before,
      const repository::AnniversaryState& after);
  common::Result<common::Unit> write_category_changes_locked(
      const repository::CategoryState& before,
      const repository::CategoryState& after);
  common::Result<common::Unit> write_habit_changes_locked(
      const repository::HabitState& before,
      const repository::HabitState& after);
  common::Result<common::Unit> write_legacy_events_locked(
      const std::vector<domain::Event>& events);
  common::Result<common::Unit> write_legacy_reminders_locked(
      const std::vector<domain::Reminder>& reminders);
  common::Result<common::Unit> write_legacy_notifications_locked(
      const std::vector<domain::Notification>& notifications);

  std::filesystem::path storage_directory_;
  std::filesystem::path database_path_;
  ::sqlite3* database_ = nullptr;
  mutable std::recursive_mutex mutex_;
  std::size_t transaction_depth_ = 0;
};

}  // namespace excellent_calendar::storage::sqlite
