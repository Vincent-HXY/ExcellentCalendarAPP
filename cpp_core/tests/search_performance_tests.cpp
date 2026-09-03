#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#endif

#include "excellent_calendar/application/search_query_service.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_repository_adapters.hpp"

namespace {

using Clock = std::chrono::steady_clock;
using excellent_calendar::domain::SearchTargetType;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

std::string uuid_for(std::uint64_t value, int family) {
  std::ostringstream output;
  output << std::hex << std::nouppercase << std::setfill('0')
         << std::setw(8) << static_cast<unsigned>(family) << "-0000-4"
         << std::setw(3) << static_cast<unsigned>(family) << "-8"
         << std::setw(3) << static_cast<unsigned>(family) << '-'
         << std::setw(12) << value;
  return output.str();
}

std::string file_bytes(const std::filesystem::path& path) {
  if (!std::filesystem::exists(path)) return {};
  std::ifstream input(path, std::ios::binary);
  std::ostringstream output;
  output << input.rdbuf();
  return output.str();
}

std::uint64_t peak_memory_bytes() {
#if defined(_WIN32)
  PROCESS_MEMORY_COUNTERS counters{};
  counters.cb = sizeof(counters);
  return GetProcessMemoryInfo(GetCurrentProcess(), &counters,
                              sizeof(counters))
             ? static_cast<std::uint64_t>(counters.PeakWorkingSetSize)
             : 0U;
#else
  std::ifstream input("/proc/self/status");
  std::string key;
  while (input >> key) {
    if (key == "VmHWM:") {
      std::uint64_t kib = 0;
      input >> kib;
      return kib * 1024U;
    }
    std::string rest;
    std::getline(input, rest);
  }
  return 0U;
#endif
}

struct SeededDatabase {
  std::filesystem::path directory;
  std::shared_ptr<excellent_calendar::storage::sqlite::SqliteCalendarDatabase>
      database;
};

SeededDatabase seed(std::size_t total) {
  SeededDatabase seeded;
  seeded.directory = std::filesystem::temp_directory_path() /
                     ("excellent_calendar_search_perf_" +
                      std::to_string(total) + "_" + uuid_for(total, 99));
  std::filesystem::create_directories(seeded.directory);
  auto opened = excellent_calendar::storage::sqlite::SqliteCalendarDatabase::open(
      seeded.directory);
  require(opened.ok(), "performance SQLite v5 database must open");
  seeded.database = opened.value();

  excellent_calendar::repository::CategoryState categories;
  for (int index = 0; index < 30; ++index) {
    excellent_calendar::domain::Category category;
    category.id = uuid_for(static_cast<std::uint64_t>(index + 1), 1);
    category.name = "项目分类 " + std::to_string(index);
    category.color = "#123456";
    category.sort_order = index;
    category.created_at = "2026-08-01T00:00:00Z";
    category.updated_at = category.created_at;
    categories.categories.push_back(std::move(category));
  }
  require(seeded.database
              ->write_category_changes({}, categories)
              .ok(),
          "performance Categories must seed");

  const std::size_t event_count = total / 3U;
  const std::size_t habit_count = total / 3U;
  const std::size_t anniversary_count = total - event_count - habit_count;
  excellent_calendar::repository::RecurringEventState recurring;
  recurring.events.reserve(event_count);
  recurring.anniversaries.reserve(anniversary_count);
  for (std::size_t index = 0; index < event_count; ++index) {
    excellent_calendar::domain::Event event;
    event.id = uuid_for(index + 1U, 2);
    event.title = "项目 Event " + std::to_string(index);
    event.content = "项目 performance content";
    event.start_at = index == 0U ? "1900-01-01T01:00:00Z"
                                 : "2026-09-02T01:00:00Z";
    event.end_at = index == 0U ? "1900-01-01T02:00:00Z"
                               : "2026-09-02T02:00:00Z";
    event.status = "active";
    event.timezone = "Asia/Shanghai";
    event.category_id = categories.categories[index % categories.categories.size()].id;
    event.source = "manual";
    event.created_at = "2026-08-01T00:00:00Z";
    event.updated_at = "2026-08-31T00:00:00Z";
    if (index == 0U) {
      excellent_calendar::domain::Recurrence recurrence;
      recurrence.id = uuid_for(1U, 3);
      recurrence.revision = 1;
      recurrence.frequency = "daily";
      recurrence.interval = 1;
      recurrence.start_at = event.start_at;
      recurrence.timezone = "Asia/Shanghai";
      recurrence.created_at = event.created_at;
      recurring.recurrences.push_back(recurrence);
      event.has_recurrence = true;
      event.recurrence_id = recurrence.id;
      event.recurrence_revision = 1;
    }
    recurring.events.push_back(std::move(event));
  }
  for (std::size_t index = 0; index < anniversary_count; ++index) {
    excellent_calendar::domain::Anniversary anniversary;
    anniversary.id = uuid_for(index + 1U, 4);
    anniversary.title = "项目 Anniversary " + std::to_string(index);
    anniversary.date = {2020, 9, static_cast<int>(index % 28U + 1U)};
    anniversary.calendar_type = "solar";
    anniversary.category_id =
        categories.categories[index % categories.categories.size()].id;
    anniversary.created_at = "2026-08-01T00:00:00Z";
    anniversary.updated_at = "2026-08-30T00:00:00Z";
    recurring.anniversaries.push_back(std::move(anniversary));
  }
  auto recurring_written =
      seeded.database->write_recurring_changes({}, recurring);
  require(recurring_written.ok(),
          "performance Event/Anniversary Stores must seed: " +
              (recurring_written.ok()
                   ? std::string()
                   : recurring_written.error().code + " " +
                         recurring_written.error().message + " " +
                         (recurring_written.error().details.empty()
                              ? std::string()
                              : recurring_written.error().details.begin()->second)));

  excellent_calendar::repository::HabitState habits;
  habits.habits.reserve(habit_count);
  habits.recurrences.reserve(habit_count);
  for (std::size_t index = 0; index < habit_count; ++index) {
    excellent_calendar::domain::HabitRecurrence recurrence;
    recurrence.id = uuid_for(index + 1U, 5);
    recurrence.frequency = "daily";
    recurrence.interval = 1;
    recurrence.timezone_mode = "follow_device";
    recurrence.created_at = "2026-08-01T00:00:00Z";
    recurrence.updated_at = recurrence.created_at;
    excellent_calendar::domain::Habit habit;
    habit.id = uuid_for(index + 1U, 6);
    habit.title = "项目 Habit " + std::to_string(index);
    habit.description = "项目 performance description";
    habit.category_id =
        categories.categories[index % categories.categories.size()].id;
    habit.recurrence_id = recurrence.id;
    habit.start_date = {2026, 8, 1};
    habit.end_date = {2026, 9, 30};
    habit.created_at = recurrence.created_at;
    habit.updated_at = "2026-08-29T00:00:00Z";
    habits.recurrences.push_back(std::move(recurrence));
    habits.habits.push_back(std::move(habit));
  }
  auto habits_written = seeded.database->write_habit_changes({}, habits);
  require(habits_written.ok(),
          "performance Habit Stores must seed: " +
              (habits_written.ok()
                   ? std::string()
                   : habits_written.error().code + " " +
                         habits_written.error().message));
  return seeded;
}

excellent_calendar::application::SearchQuery query() {
  excellent_calendar::application::SearchQuery value;
  value.query_generation = 1;
  value.keyword = "项目";
  value.timezone = "Asia/Shanghai";
  value.target_types = {SearchTargetType::event, SearchTargetType::habit,
                        SearchTargetType::anniversary};
  value.category_ids = std::nullopt;
  value.include_completed = true;
  value.sort_by = excellent_calendar::application::SearchSort::relevance;
  value.sections = {{SearchTargetType::event, 20, std::nullopt},
                    {SearchTargetType::habit, 20, std::nullopt},
                    {SearchTargetType::anniversary, 20, std::nullopt}};
  return value;
}

double elapsed_ms(const Clock::time_point& start) {
  return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

void run_scale(std::size_t total) {
  auto seeded = seed(total);
  auto resolver = excellent_calendar::infrastructure::time::
      TzdbLocalTimeResolver::create(EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(resolver.ok(), "performance TZDB must initialize");
  auto repository = std::make_shared<
      excellent_calendar::storage::sqlite::SqliteSearchQueryRepository>(
      seeded.database);
  require(repository->initialize().ok(), "performance repository must initialize");
  excellent_calendar::common::SearchHmacKey key{};
  excellent_calendar::application::SearchQueryService service(
      repository, resolver.value(),
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          resolver.value()),
      [] { return std::string("2026-09-01T00:00:00Z"); }, key);
  const auto request = query();
  const auto database_before = file_bytes(seeded.database->database_path());
  const auto wal_before = file_bytes(seeded.database->database_path().string() + "-wal");
  auto started = Clock::now();
  excellent_calendar::application::SearchQueryDiagnostics cold_diagnostics;
  auto cold = service.query(request, &cold_diagnostics);
  const auto cold_ms = elapsed_ms(started);
  require(cold.ok(),
          "cold performance Search query must succeed: " +
              (cold.ok() ? std::string()
                         : cold.error().code + " " + cold.error().message +
                               " " +
                               (cold.error().details.empty()
                                    ? std::string()
                                    : cold.error().details.begin()->second)));
  std::int64_t candidates = 0;
  for (const auto& section : cold.value().sections)
    candidates += section.total_count;
  require(candidates == static_cast<std::int64_t>(total),
          "performance candidate conservation must hold");
  std::vector<double> warm;
  std::size_t maximum_sql_statements = cold_diagnostics.sql_statements_executed;
  std::size_t maximum_recurrence_candidates =
      cold_diagnostics.recurrence_candidates_evaluated;
  for (int iteration = 0; iteration < 10; ++iteration) {
    started = Clock::now();
    excellent_calendar::application::SearchQueryDiagnostics diagnostics;
    auto response = service.query(request, &diagnostics);
    warm.push_back(elapsed_ms(started));
    require(response.ok(), "warm performance Search query must succeed");
    maximum_sql_statements =
        std::max(maximum_sql_statements, diagnostics.sql_statements_executed);
    maximum_recurrence_candidates = std::max(
        maximum_recurrence_candidates,
        diagnostics.recurrence_candidates_evaluated);
  }
  std::sort(warm.begin(), warm.end());
  const auto p50 = warm[warm.size() / 2U];
  const auto p95 = warm[static_cast<std::size_t>(
      std::ceil(static_cast<double>(warm.size()) * 0.95)) - 1U];
  require(database_before == file_bytes(seeded.database->database_path()) &&
              wal_before ==
                  file_bytes(seeded.database->database_path().string() + "-wal"),
          "performance Search reads must leave SQLite bytes unchanged");
  std::cout << "SEARCH_PERF scale=" << total << " cold_ms=" << cold_ms
             << " warm_p50_ms=" << p50 << " warm_p95_ms=" << p95
             << " peak_memory_bytes=" << peak_memory_bytes()
             << " sql_statements=" << maximum_sql_statements
             << " candidates=" << candidates
             << " recurrence_seek_observed_candidates="
             << maximum_recurrence_candidates << '\n';
  require(maximum_sql_statements > 0U,
          "performance diagnostics must measure executed SQL statements");
  if (total == 10000U)
    require(p95 <= 300.0, "10k core query P95 exceeds 300ms gate");
  repository.reset();
  seeded.database.reset();
  std::error_code ignored;
  std::filesystem::remove_all(seeded.directory, ignored);
}

}  // namespace

int main() {
#if !EXCELLENT_CALENDAR_SEARCH_PERFORMANCE_RELEASE
  std::cerr << "Search performance gate requires a Release build; configure "
               "with -DCMAKE_BUILD_TYPE=Release.\n";
  return 2;
#endif
  try {
    for (const auto scale : {1000U, 10000U, 50000U}) run_scale(scale);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Search performance tests failed: " << error.what() << '\n';
    return 1;
  }
}
