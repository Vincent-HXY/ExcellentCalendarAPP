// Isolated executable linked to the unchanged production v5 checker.
#include <filesystem>
#include <iostream>
#include <string>
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

int main(int argc, char** argv) {
  if (argc != 3) return 64;
  const std::string mode = argv[1];
  const std::filesystem::path directory = argv[2];
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  if (mode != "create" && mode != "check") return 64;
  if (mode == "check" && !std::filesystem::is_regular_file(directory / "calendar_core.sqlite3")) return 65;
  if (mode == "create" && std::filesystem::exists(directory / "calendar_core.sqlite3")) return 65;
  auto opened = SqliteCalendarDatabase::open(directory);
  if (!opened.ok()) {
    std::cout << "REJECT " << opened.error().code << '\n';
    return 2;
  }
  auto result = opened.value()->validate();
  if (!result.ok()) {
    std::cout << "REJECT " << result.error().code << '\n';
    return 2;
  }
  if (mode == "create") {
    // Quantitative safe-integer boundary rows exercise the real Habit codec,
    // aggregate owner validation and per-store generations, not synthetic SQL.
    using namespace excellent_calendar;
    auto before = opened.value()->load_habit_state();
    if (!before.ok()) return 3;
    auto after = before.value();
    const std::string now = "2026-09-05T00:00:00Z";
    after.recurrences.push_back({"11111111-1111-4111-8111-111111111111", "daily", 1, "follow_device", now, now, std::nullopt});
    domain::Habit habit;
    habit.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
    habit.title = "迁移保留：Unicode 与 MAX";
    habit.recurrence_id = after.recurrences[0].id;
    habit.target_count_hundredths = 9007199254740991LL;
    habit.unit = "次";
    habit.start_date = {2026, 9, 5};
    habit.end_date = {2026, 9, 6};
    habit.created_at = now;
    habit.updated_at = now;
    after.habits.push_back(habit);
    if (!opened.value()->write_habit_changes(before.value(), after).ok()) return 3;
    if (!opened.value()->validate().ok()) return 3;
  }
  opened.value().reset();
  std::cout << "V5_VALID\n";
  return 0;
}
