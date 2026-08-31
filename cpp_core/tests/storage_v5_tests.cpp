#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

#include <sqlite/sqlite3.h>

#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/repository/habit_transaction.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

namespace {

using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

struct TempDirectory {
  std::filesystem::path path = std::filesystem::temp_directory_path() /
      ("excellent_calendar_storage_v5_" +
       excellent_calendar::common::generate_uuid_v4());
  TempDirectory() { std::filesystem::create_directories(path); }
  ~TempDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path, error);
  }
};

int scalar(const std::filesystem::path& path, const std::string& sql) {
  sqlite3* database = nullptr;
  require(sqlite3_open_v2(path.string().c_str(), &database,
                          SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK,
          "must open SQLite fixture");
  sqlite3_stmt* statement = nullptr;
  require(sqlite3_prepare_v2(database, sql.c_str(), -1, &statement, nullptr) ==
              SQLITE_OK,
          "must prepare scalar query: " + sql);
  require(sqlite3_step(statement) == SQLITE_ROW,
          "scalar query must return a row: " + sql);
  const int result = sqlite3_column_int(statement, 0);
  sqlite3_finalize(statement);
  sqlite3_close_v2(database);
  return result;
}

void execute(const std::filesystem::path& path, const std::string& sql) {
  sqlite3* database = nullptr;
  require(sqlite3_open_v2(path.string().c_str(), &database,
                          SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK,
          "must open SQLite fixture for mutation");
  char* message = nullptr;
  const int code = sqlite3_exec(database, sql.c_str(), nullptr, nullptr, &message);
  const std::string error = message == nullptr ? "" : message;
  sqlite3_free(message);
  sqlite3_close_v2(database);
  require(code == SQLITE_OK, "SQLite fixture mutation failed: " + error);
}

excellent_calendar::repository::HabitState populated_state() {
  using namespace excellent_calendar;
  repository::HabitState state;
  const std::string now = "2026-09-01T00:00:00Z";
  domain::HabitRecurrence first_recurrence{
      "11111111-1111-4111-8111-111111111111", "daily", 1,
      "follow_device", now, now, std::nullopt};
  domain::HabitRecurrence second_recurrence{
      "22222222-2222-4222-8222-222222222222", "daily", 1,
      "follow_device", now, now, std::nullopt};
  state.recurrences = {first_recurrence, second_recurrence};
  domain::Habit first;
  first.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
  first.title = "upper-adjacent-a";
  first.recurrence_id = first_recurrence.id;
  first.target_count_hundredths = 9007199254740990LL;
  first.unit = "次";
  first.start_date = {2026, 9, 1};
  first.end_date = {2026, 9, 2};
  first.created_at = now;
  first.updated_at = now;
  domain::Habit second = first;
  second.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2";
  second.title = "upper-adjacent-b";
  second.recurrence_id = second_recurrence.id;
  second.target_count_hundredths = 9007199254740991LL;
  state.habits = {first, second};
  return state;
}

void test_fresh_schema_round_trip_and_idempotency() {
  TempDirectory directory;
  auto opened = SqliteCalendarDatabase::open(directory.path);
  require(opened.ok(), "fresh v5 open must succeed: " +
                           (opened.ok() ? std::string{} : opened.error().code +
                                " " + opened.error().message + " " +
                                (opened.error().details.count("reason")
                                     ? opened.error().details.at("reason")
                                     : std::string{})));
  const auto database_path =
      directory.path / excellent_calendar::storage::sqlite::kCalendarCoreSqliteFileName;
  require(scalar(database_path, "PRAGMA user_version") == 5,
          "fresh database must advertise v5");
  require(scalar(database_path,
                 "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") == 20,
          "v5 must contain exactly 20 canonical tables");
  require(scalar(database_path,
                 "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND sql IS NOT NULL") == 24,
          "v5 must contain exactly 24 canonical indexes");
  require(scalar(database_path, "SELECT COUNT(*) FROM store_generations") == 17,
          "v5 must contain 17 per-store generations");
  require(scalar(database_path,
                 "SELECT SUM(generation) FROM store_generations WHERE store_name IN "
                 "('habit_recurrences','habits','habit_check_ins','habit_reminder_templates')") == 0,
          "fresh Habit generations must all be zero");
  require(scalar(database_path, "SELECT COUNT(*) FROM schema_metadata") == 20,
          "v5 metadata must be exact");
  require(scalar(database_path,
                 "SELECT COUNT(*) FROM migration_history WHERE migration_id='calendar_core_fresh_sqlite_v5'") == 1,
          "fresh v5 history must be truthful");
  auto empty = opened.value()->load_habit_state();
  require(empty.ok() && empty.value().habits.empty() &&
              empty.value().recurrences.empty() &&
              empty.value().check_ins.empty() &&
              empty.value().reminder_templates.empty(),
          "fresh Habit Stores must be empty");
  auto next = populated_state();
  auto written = opened.value()->write_habit_changes(empty.value(), next);
  require(written.ok(), "Habit state write must succeed");
  auto loaded = opened.value()->load_habit_state();
  require(loaded.ok() && loaded.value().habits.size() == 2U,
          "Habit state must round-trip");
  require(*loaded.value().habits[0].target_count_hundredths ==
              9007199254740990LL &&
              *loaded.value().habits[1].target_count_hundredths ==
                  9007199254740991LL,
          "adjacent JSON-safe hundredths must not merge");
  opened.value().reset();
  auto reopened = SqliteCalendarDatabase::open(directory.path);
  require(reopened.ok(), "v5 reopen must succeed");
  require(scalar(database_path, "SELECT COUNT(*) FROM migration_history") == 1,
          "reopen must not append migration history");
}

void test_failure_is_atomic_and_checker_fails_closed() {
  TempDirectory failed_directory;
  auto failed = SqliteCalendarDatabase::open(
      failed_directory.path, [](std::string_view phase) {
        return phase == "v5_after_tables"
                   ? excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
                         excellent_calendar::common::make_error(
                             "STORAGE_IO_ERROR", "injected migration failure"))
                   : excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
                         excellent_calendar::common::Unit{});
      });
  require(!failed.ok(), "injected v5 migration must fail");
  require(!std::filesystem::exists(
              failed_directory.path /
              excellent_calendar::storage::sqlite::kCalendarCoreSqliteFileName),
          "failed fresh migration must publish no partial database");

  TempDirectory corrupted_directory;
  auto opened = SqliteCalendarDatabase::open(corrupted_directory.path);
  require(opened.ok(), "corruption fixture must initialize");
  const auto path = corrupted_directory.path /
      excellent_calendar::storage::sqlite::kCalendarCoreSqliteFileName;
  execute(path, "DROP INDEX ix_habit_check_ins_range; CREATE INDEX ix_habit_check_ins_range ON habit_check_ins(record_key)");
  auto invalid = opened.value()->validate();
  require(!invalid.ok() && invalid.error().code == "STORAGE_DATA_CORRUPTED",
          "same-name wrong Habit index must fail closed");
}

void downgrade_fresh_v5_to_exact_v4(const std::filesystem::path& path) {
  execute(path,
      "DROP INDEX ux_habit_recurrence_owner;"
      "DROP INDEX ux_habit_check_in_identity;"
      "DROP INDEX ux_habit_active_template;"
      "DROP INDEX ux_habit_reminder_identity;"
      "DROP INDEX ux_habit_sent_display_per_day;"
      "DROP INDEX ix_habits_lifecycle;"
      "DROP INDEX ix_habit_check_ins_range;"
      "DROP INDEX ix_habit_templates_by_habit;"
      "DROP TABLE habit_check_ins; DROP TABLE habit_reminder_templates;"
      "DROP TABLE habits; DROP TABLE habit_recurrences;"
      "DELETE FROM store_generations WHERE store_name IN "
      "('habit_recurrences','habits','habit_check_ins','habit_reminder_templates');"
      "DELETE FROM schema_metadata WHERE key LIKE 'payload_codec_version.%';"
      "UPDATE schema_metadata SET value='4' WHERE key='storage_format_version';"
      "DELETE FROM migration_history;"
      "INSERT INTO migration_history(migration_id,source_format,source_version,target_version,completed_at) "
      "VALUES('calendar_core_fresh_sqlite_v4','none',0,4,'2026-08-28T00:00:00Z');"
      "UPDATE store_generations SET generation=7 WHERE store_name='categories';"
      "PRAGMA user_version=4;");
}

void test_exact_schema_and_v4_gates_reject_unknown_state_without_migration() {
  const auto require_v5_rejected = [](const std::string& mutation,
                                      const std::string& label) {
    TempDirectory directory;
    auto opened = SqliteCalendarDatabase::open(directory.path);
    require(opened.ok(), label + " fixture must initialize");
    const auto path = opened.value()->database_path();
    execute(path, mutation);
    auto invalid = opened.value()->validate();
    require(!invalid.ok() && invalid.error().code == "STORAGE_DATA_CORRUPTED",
            "v5 checker must reject unexpected " + label);
  };
  require_v5_rejected("CREATE TABLE unexpected_v5(value INTEGER)", "table");
  require_v5_rejected("CREATE INDEX ix_unexpected_v5 ON habits(record_key)",
                      "index");
  require_v5_rejected(
      "CREATE TRIGGER tr_unexpected_v5 AFTER INSERT ON habits BEGIN SELECT 1; END",
      "trigger");
  require_v5_rejected(
      "INSERT INTO schema_metadata(key,value) VALUES('unknown_metadata','x')",
      "metadata");
  require_v5_rejected(
      "INSERT INTO store_generations(store_name,generation) VALUES('unknown_generation',0)",
      "generation");

  const auto require_v4_rejected = [](const std::string& mutation,
                                      const std::string& label) {
    TempDirectory directory;
    auto opened = SqliteCalendarDatabase::open(directory.path);
    require(opened.ok(), label + " v4 fixture source must initialize");
    const auto path = opened.value()->database_path();
    opened.value().reset();
    downgrade_fresh_v5_to_exact_v4(path);
    execute(path, mutation);
    auto rejected = SqliteCalendarDatabase::open(directory.path);
    require(!rejected.ok() &&
                rejected.error().code == "STORAGE_DATA_CORRUPTED" &&
                scalar(path, "PRAGMA user_version") == 4 &&
                scalar(path,
                       "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name LIKE 'habit_%'") == 0 &&
                scalar(path,
                       "SELECT COUNT(*) FROM migration_history WHERE migration_id='calendar_core_sqlite_v4_to_v5_habit_v1'") == 0,
            "invalid v4 " + label +
                " must fail closed before any migration write");
  };
  require_v4_rejected("CREATE TABLE unexpected_v4(value INTEGER)", "table");
  require_v4_rejected(
      "CREATE INDEX ix_unexpected_v4 ON store_generations(store_name)",
      "index");
  require_v4_rejected(
      "CREATE TRIGGER tr_unexpected_v4 AFTER UPDATE ON store_generations BEGIN SELECT 1; END",
      "trigger");
  require_v4_rejected(
      "INSERT INTO schema_metadata(key,value) VALUES('unknown_metadata','x')",
      "metadata");
  require_v4_rejected(
      "INSERT INTO store_generations(store_name,generation) VALUES('unknown_generation',0)",
      "generation");
}

void test_habit_record_identity_and_recurrence_ownership_are_strict() {
  const auto require_invalid_write = [](
      const std::function<void(excellent_calendar::repository::HabitState&)>&
          mutate,
      const std::string& label) {
    TempDirectory directory;
    auto opened = SqliteCalendarDatabase::open(directory.path);
    require(opened.ok(), label + " fixture must initialize");
    auto empty = opened.value()->load_habit_state();
    require(empty.ok(), label + " fixture must load");
    auto candidate = populated_state();
    mutate(candidate);
    auto written = opened.value()->write_habit_changes(empty.value(), candidate);
    auto after = opened.value()->load_habit_state();
    require(!written.ok() && after.ok() && after.value().habits.empty() &&
                after.value().recurrences.empty(),
            label + " must be rejected atomically");
  };

  require_invalid_write(
      [](auto& state) {
        state.habits.front().id = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1";
      },
      "non-canonical Habit UUIDv4");
  require_invalid_write(
      [](auto& state) {
        state.habits.front().id = "aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaa1";
      },
      "canonical lowercase non-v4 Habit UUID");
  require_invalid_write(
      [](auto& state) {
        state.recurrences.push_back(
            {"33333333-3333-4333-8333-333333333333", "daily", 1,
             "follow_device", "2026-09-01T00:00:00Z",
             "2026-09-01T00:00:00Z", std::nullopt});
      },
      "orphan active HabitRecurrence");
  require_invalid_write(
      [](auto& state) {
        state.habits.back().recurrence_id =
            state.habits.front().recurrence_id;
      },
      "shared active HabitRecurrence");

  TempDirectory tombstone_directory;
  auto opened = SqliteCalendarDatabase::open(tombstone_directory.path);
  require(opened.ok(), "tombstoned recurrence fixture must initialize");
  auto empty = opened.value()->load_habit_state();
  auto candidate = populated_state();
  candidate.recurrences.push_back(
      {"33333333-3333-4333-8333-333333333333", "daily", 1,
       "follow_device", "2026-09-01T00:00:00Z", "2026-09-01T00:00:00Z",
       std::optional<std::string>("2026-09-01T00:00:00Z")});
  auto written = opened.value()->write_habit_changes(empty.value(), candidate);
  require(written.ok(),
          "unowned tombstoned HabitRecurrence must remain a legal audit record");
}

void test_existing_v4_upgrade_rollback_and_preservation() {
  TempDirectory directory;
  auto fresh = SqliteCalendarDatabase::open(directory.path);
  require(fresh.ok(), "v4 fixture source must initialize");
  const auto path = fresh.value()->database_path();
  fresh.value().reset();
  downgrade_fresh_v5_to_exact_v4(path);
  auto failed = SqliteCalendarDatabase::open(
      directory.path, [](std::string_view phase) {
        return phase == "v5_after_metadata"
                   ? excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
                         excellent_calendar::common::make_error(
                             "STORAGE_IO_ERROR", "injected v4-to-v5 failure"))
                   : excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
                         excellent_calendar::common::Unit{});
      });
  require(!failed.ok(), "existing v4 migration failure must surface");
  require(scalar(path, "PRAGMA user_version") == 4 &&
              scalar(path,
                     "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name LIKE 'habit_%'") == 0 &&
              scalar(path,
                     "SELECT generation FROM store_generations WHERE store_name='categories'") == 7,
          "failed v4-to-v5 transaction must leave a complete unchanged v4");
  auto upgraded = SqliteCalendarDatabase::open(directory.path);
  require(upgraded.ok(), "unchanged v4 must upgrade on retry: " +
                             (upgraded.ok() ? std::string{} :
                                  upgraded.error().code + " " +
                                  upgraded.error().message + " " +
                                  (upgraded.error().details.count("reason")
                                       ? upgraded.error().details.at("reason")
                                       : std::string{})));
  require(scalar(path, "PRAGMA user_version") == 5 &&
              scalar(path,
                     "SELECT generation FROM store_generations WHERE store_name='categories'") == 7 &&
              scalar(path,
                     "SELECT COUNT(*) FROM migration_history WHERE migration_id='calendar_core_fresh_sqlite_v4'") == 1 &&
              scalar(path,
                     "SELECT COUNT(*) FROM migration_history WHERE migration_id='calendar_core_sqlite_v4_to_v5_habit_v1'") == 1,
          "successful v4-to-v5 retry must preserve inherited facts and append one suffix");
  upgraded.value().reset();
  auto reopened = SqliteCalendarDatabase::open(directory.path);
  require(reopened.ok() && scalar(path, "SELECT COUNT(*) FROM migration_history") == 2,
          "repeated v5 initialization must be idempotent");
}

}  // namespace

int main() {
  try {
    test_fresh_schema_round_trip_and_idempotency();
    test_failure_is_atomic_and_checker_fails_closed();
    test_exact_schema_and_v4_gates_reject_unknown_state_without_migration();
    test_habit_record_identity_and_recurrence_ownership_are_strict();
    test_existing_v4_upgrade_rollback_and_preservation();
    std::cout << "storage_v5_tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "storage_v5_tests failed: " << error.what() << '\n';
    return 1;
  }
}
