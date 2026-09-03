#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>
#include <sqlite/sqlite3.h>

#include "excellent_calendar/application/calendar_view_query_service.hpp"
#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/boundary/api/calendar_view_api.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/calendar_view_json.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/repository/calendar_query_repository.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_repository_adapters.hpp"

namespace {

using excellent_calendar::application::CalendarAnniversaryItem;
using excellent_calendar::application::CalendarDayItemPage;
using excellent_calendar::application::CalendarEventItem;
using excellent_calendar::application::CalendarHabitItem;
using excellent_calendar::application::CalendarListDayItemsQuery;
using excellent_calendar::application::CalendarRangeSummary;
using excellent_calendar::application::CalendarRangeSummaryQuery;
using excellent_calendar::application::CalendarSection;
using excellent_calendar::application::CalendarViewQueryService;
using excellent_calendar::application::RecurrenceService;
using excellent_calendar::common::Result;
using excellent_calendar::common::Unit;
using excellent_calendar::domain::Anniversary;
using excellent_calendar::domain::AnniversaryRecurrence;
using excellent_calendar::domain::Event;
using excellent_calendar::domain::EventOccurrenceState;
using excellent_calendar::domain::Habit;
using excellent_calendar::domain::HabitCheckIn;
using excellent_calendar::domain::HabitRecurrence;
using excellent_calendar::domain::LocalDate;
using excellent_calendar::domain::Recurrence;
using excellent_calendar::domain::Reminder;
using excellent_calendar::repository::CalendarQueryRepository;
using excellent_calendar::repository::CalendarQuerySnapshot;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

class TemporaryDirectory {
 public:
  explicit TemporaryDirectory(std::string prefix)
      : path_(std::filesystem::temp_directory_path() /
              (std::move(prefix) + "_" +
               excellent_calendar::common::generate_uuid_v4())) {
    std::filesystem::create_directories(path_);
  }

  ~TemporaryDirectory() {
    std::error_code ignored;
    std::filesystem::remove_all(path_, ignored);
  }

  const std::filesystem::path& path() const { return path_; }

 private:
  std::filesystem::path path_;
};

std::string sqlite_query_plan(const std::filesystem::path& database_path,
                              const std::string& query) {
  sqlite3* database = nullptr;
  require(sqlite3_open_v2(database_path.string().c_str(), &database,
                          SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK,
          "query-plan database must open");
  sqlite3_stmt* statement = nullptr;
  const std::string explain = "EXPLAIN QUERY PLAN " + query;
  const int prepared = sqlite3_prepare_v2(database, explain.c_str(), -1,
                                          &statement, nullptr);
  if (prepared != SQLITE_OK) {
    const std::string reason = sqlite3_errmsg(database);
    sqlite3_close_v2(database);
    throw std::runtime_error("query-plan prepare failed: " + reason);
  }
  std::string result;
  while (sqlite3_step(statement) == SQLITE_ROW) {
    if (!result.empty()) result += " | ";
    const auto* detail = sqlite3_column_text(statement, 3);
    if (detail != nullptr) {
      result += reinterpret_cast<const char*>(detail);
    }
  }
  sqlite3_finalize(statement);
  sqlite3_close_v2(database);
  return result;
}

void sqlite_execute_mutation(const std::filesystem::path& database_path,
                             const std::string& sql) {
  sqlite3* database = nullptr;
  require(sqlite3_open_v2(database_path.string().c_str(), &database,
                          SQLITE_OPEN_READWRITE, nullptr) == SQLITE_OK,
          "mutation database must open");
  char* error = nullptr;
  const int executed = sqlite3_exec(database, sql.c_str(), nullptr, nullptr,
                                    &error);
  const std::string reason = error == nullptr ? "" : error;
  if (error != nullptr) sqlite3_free(error);
  sqlite3_close_v2(database);
  require(executed == SQLITE_OK, "SQLite mutation failed: " + reason);
}

std::string uuid(int value, int family = 1) {
  std::ostringstream output;
  output << std::hex << std::setfill('0') << std::setw(8) << family
         << "-0000-4000-8000-" << std::setw(12) << value;
  return output.str();
}

class FakeCalendarQueryRepository final : public CalendarQueryRepository {
 public:
  Result<Unit> initialize() override { return Result<Unit>::success(Unit{}); }

  Result<CalendarQuerySnapshot> load_snapshot(
      const std::optional<std::array<
          std::int64_t,
          excellent_calendar::repository::kCalendarQueryContributingStores
              .size()>>& expected_generations = std::nullopt) override {
    ++load_calls;
    if (failure.has_value()) {
      return Result<CalendarQuerySnapshot>::failure(*failure);
    }
    if (expected_generations.has_value() &&
        *expected_generations != snapshot.generations) {
      return Result<CalendarQuerySnapshot>::failure(
          excellent_calendar::common::make_error(
              "CALENDAR_SNAPSHOT_EXPIRED",
              "Calendar snapshot no longer matches generations", {}, true));
    }
    return Result<CalendarQuerySnapshot>::success(snapshot);
  }

  CalendarQuerySnapshot snapshot;
  int load_calls = 0;
  std::optional<excellent_calendar::common::Error> failure;
};

std::shared_ptr<excellent_calendar::domain::LocalTimeResolver> resolver() {
  auto created = excellent_calendar::infrastructure::time::
      TzdbLocalTimeResolver::create(
          std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR));
  require(created.ok(), "bundled timezone resolver must initialize");
  return created.value();
}

Event timed_event(int id, std::string title, std::string start,
                  std::string end, std::string timezone = "Asia/Shanghai") {
  Event event;
  event.id = uuid(id, 10);
  event.title = std::move(title);
  event.start_at = std::move(start);
  event.end_at = std::move(end);
  event.is_all_day = false;
  event.status = std::string(
      excellent_calendar::domain::kEventStatusActive);
  event.timezone = std::move(timezone);
  event.source = "manual";
  event.created_at = "2026-01-01T00:00:00Z";
  event.updated_at = event.created_at;
  return event;
}

Event all_day_event(int id, std::string title, std::string start,
                    std::string end) {
  auto event = timed_event(id, std::move(title), "", "");
  event.is_all_day = true;
  event.start_date = std::move(start);
  event.end_date = std::move(end);
  return event;
}

Habit habit(int id, std::string title, LocalDate start, LocalDate end,
            std::optional<std::int64_t> target = std::nullopt,
            std::optional<std::string> unit = std::nullopt) {
  Habit value;
  value.id = uuid(id, 20);
  value.title = std::move(title);
  value.recurrence_id = uuid(id, 21);
  value.target_count_hundredths = target;
  value.unit = std::move(unit);
  value.start_date = start;
  value.end_date = end;
  value.is_active = true;
  value.created_at = "2026-01-01T00:00:00Z";
  value.updated_at = value.created_at;
  return value;
}

HabitRecurrence habit_recurrence(const Habit& owner) {
  HabitRecurrence value;
  value.id = owner.recurrence_id;
  value.created_at = "2026-01-01T00:00:00Z";
  value.updated_at = value.created_at;
  return value;
}

HabitCheckIn check_in(int id, const Habit& owner, LocalDate date,
                      std::string status,
                      std::optional<std::int64_t> completed = std::nullopt,
                      std::optional<std::int64_t> target = std::nullopt,
                      std::optional<std::string> unit = std::nullopt) {
  HabitCheckIn value;
  value.id = uuid(id, 22);
  value.habit_id = owner.id;
  value.check_date = date;
  value.status = std::move(status);
  value.completed_count_hundredths = completed;
  value.target_count_snapshot_hundredths = target;
  value.unit_snapshot = std::move(unit);
  value.completed_at = "2026-09-01T04:00:00Z";
  value.source = "manual";
  value.created_at = "2026-09-01T04:00:00Z";
  value.updated_at = value.created_at;
  return value;
}

Reminder open_reminder(int id, std::string target_type,
                       std::string target_id) {
  Reminder reminder;
  reminder.id = uuid(id, 30);
  reminder.target_type = std::move(target_type);
  reminder.target_id = std::move(target_id);
  reminder.remind_at = "2026-09-01T03:00:00Z";
  reminder.methods = {"popup"};
  reminder.is_enabled = true;
  reminder.status = std::string(
      excellent_calendar::domain::kReminderStatusPending);
  reminder.source = "manual";
  reminder.created_at = "2026-01-01T00:00:00Z";
  reminder.updated_at = reminder.created_at;
  return reminder;
}

std::shared_ptr<CalendarViewQueryService> service(
    const std::shared_ptr<FakeCalendarQueryRepository>& repository,
    const std::shared_ptr<excellent_calendar::domain::LocalTimeResolver>&
        time_resolver,
    std::string& clock) {
  auto recurrence = std::make_shared<RecurrenceService>(time_resolver);
  return std::make_shared<CalendarViewQueryService>(
      repository, time_resolver, recurrence, [&clock] { return clock; });
}

template <typename T>
std::vector<T> typed_items(const CalendarDayItemPage& page) {
  std::vector<T> result;
  for (const auto& item : page.items) {
    if (const auto* value = std::get_if<T>(&item)) result.push_back(*value);
  }
  return result;
}

const CalendarEventItem& event_named(const std::vector<CalendarEventItem>& items,
                                     const std::string& title) {
  const auto found =
      std::find_if(items.begin(), items.end(), [&](const auto& item) {
        return item.title == title;
      });
  require(found != items.end(), "expected Event item: " + title);
  return *found;
}

const CalendarHabitItem& habit_named(const std::vector<CalendarHabitItem>& items,
                                     const std::string& title) {
  const auto found =
      std::find_if(items.begin(), items.end(), [&](const auto& item) {
        return item.title == title;
      });
  require(found != items.end(), "expected Habit item: " + title);
  return *found;
}

void event_projection_and_snapshot_clock_test() {
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(1);
  repository->snapshot.events = {
      all_day_event(1, "Zulu multi-day", "2026-08-30", "2026-09-03"),
      all_day_event(2, "Alpha multi-day", "2026-08-31", "2026-09-03"),
      timed_event(3, "Cross midnight", "2026-08-31T15:00:00Z",
                  "2026-08-31T17:00:00Z"),
      timed_event(4, "Ends at day end", "2026-08-31T14:00:00Z",
                  "2026-09-01T16:00:00Z"),
      timed_event(5, "Later start", "2026-08-31T16:00:00Z",
                  "2026-08-31T18:00:00Z"),
      timed_event(6, "Already overdue", "2026-08-30T01:00:00Z",
                  "2026-08-30T02:00:00Z"),
      timed_event(7, "Future pending", "2026-09-01T18:00:00Z",
                  "2026-09-01T19:00:00Z"),
      timed_event(8, "Persisted completed", "2026-08-31T16:00:00Z",
                  "2026-08-31T17:00:00Z"),
  };
  repository->snapshot.events.back().status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  repository->snapshot.events.back().completed_at =
      "2026-08-31T17:00:00Z";

  std::string clock = "2026-08-31T16:00:00Z";
  auto calendar = service(repository, resolver(), clock);
  auto summary = calendar->range_summary(
      {{2026, 8, 31}, {2026, 9, 3}, "Asia/Shanghai"});
  require(summary.ok(), "range summary must succeed");
  require(summary.value().days.size() == 3U,
          "range summary must be gap-free");
  require(summary.value().days[0].has_open_event &&
              summary.value().days[1].has_open_event,
          "cross-day visible Events must conserve range dots");
  require(summary.value().snapshot_token.rfind("calsnap1.", 0) == 0,
          "range summary must return calsnap1 token");

  clock = "2026-09-02T16:00:00Z";
  auto first_day = calendar->list_day_items(
      {{2026, 8, 31}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 20});
  require(first_day.ok(), "first selected day must list Events");
  const auto first_items = typed_items<CalendarEventItem>(first_day.value());
  const auto& cross_first = event_named(first_items, "Cross midnight");
  require(cross_first.day_display == "starts_at" &&
              cross_first.display_local_time ==
                  std::optional<std::string>("23:00") &&
              cross_first.status == "in_progress",
          "first cross-day projection must use start display and token clock");

  auto second_day = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 20});
  require(second_day.ok(), "second selected day must list Events");
  const auto second_items = typed_items<CalendarEventItem>(second_day.value());
  require(second_items.size() >= 6U, "second day must contain all overlaps");
  require(second_items[0].title == "Alpha multi-day" &&
              second_items[1].title == "Zulu multi-day",
          "multi-day all-day Events must tie-break by title, not original start");
  const auto& cross_second = event_named(second_items, "Cross midnight");
  require(cross_second.day_display == "ends_at" &&
              cross_second.display_local_time ==
                  std::optional<std::string>("01:00") &&
              cross_second.status == "in_progress",
          "later cross-day projection must use end display and frozen clock");
  const auto& boundary_end = event_named(second_items, "Ends at day end");
  require(boundary_end.day_display == "ends_at" &&
              boundary_end.display_local_time ==
                  std::optional<std::string>("00:00"),
          "end equal to day_end must project as ends_at");
  require(event_named(second_items, "Later start").status == "in_progress",
          "clock at actual start must be in_progress");
  require(event_named(second_items, "Persisted completed").status ==
              "completed",
          "persisted non-recurring completion must win over clock state");

  repository->snapshot.generations[0] += 1;
  auto expired = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 20});
  require(!expired.ok() &&
              expired.error().code == "CALENDAR_SNAPSHOT_EXPIRED" &&
              expired.error().retryable,
          "changed generation must expire the snapshot inside repository read");
  require(repository->load_calls == 4,
          "each Calendar call must perform exactly one repository snapshot load");
}

void cross_year_event_projection_test() {
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(9);
  repository->snapshot.events = {
      all_day_event(20, "Cross-year all-day", "2026-12-31", "2027-01-02"),
      timed_event(21, "Cross-year timed", "2026-12-31T15:00:00Z",
                  "2026-12-31T17:00:00Z"),
  };
  std::string clock = "2026-12-31T16:00:00Z";
  auto calendar = service(repository, resolver(), clock);
  auto summary = calendar->range_summary(
      {{2026, 12, 31}, {2027, 1, 2}, "Asia/Shanghai"});
  require(summary.ok() && summary.value().days.size() == 2U &&
              summary.value().days[0].has_open_event &&
              summary.value().days[1].has_open_event,
          "cross-month/year Event intervals must conserve both natural days");
  auto first = calendar->list_day_items(
      {{2026, 12, 31}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 20});
  auto second = calendar->list_day_items(
      {{2027, 1, 1}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 20});
  require(first.ok() && second.ok(), "cross-year daily pages must succeed");
  const auto first_items = typed_items<CalendarEventItem>(first.value());
  const auto second_items = typed_items<CalendarEventItem>(second.value());
  require(event_named(first_items, "Cross-year timed").day_display ==
              "starts_at" &&
              event_named(first_items, "Cross-year timed").display_local_time ==
                  std::optional<std::string>("23:00") &&
              event_named(second_items, "Cross-year timed").day_display ==
                  "ends_at" &&
              event_named(second_items, "Cross-year timed").display_local_time ==
                  std::optional<std::string>("01:00") &&
              event_named(first_items, "Cross-year all-day").day_display ==
                  "all_day" &&
              event_named(second_items, "Cross-year all-day").day_display ==
                  "all_day",
          "cross-year timed/all-day display must retain frozen day semantics");
}

void recurring_overlap_dst_and_state_test() {
  auto time_resolver = resolver();
  auto recurrence_service = std::make_shared<RecurrenceService>(time_resolver);
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(2);

  auto gap_event = timed_event(30, "DST gap daily", "2026-03-07T10:30:00Z",
                               "2026-03-07T11:30:00Z",
                               "America/Los_Angeles");
  gap_event.has_recurrence = true;
  gap_event.recurrence_id = uuid(30, 11);
  gap_event.recurrence_revision = 1;
  Recurrence gap_rule;
  gap_rule.id = *gap_event.recurrence_id;
  gap_rule.revision = 1;
  gap_rule.frequency = "daily";
  gap_rule.interval = 1;
  gap_rule.start_at = gap_event.start_at;
  gap_rule.timezone = "America/Los_Angeles";
  gap_rule.created_at = "2026-03-01T00:00:00Z";
  auto gap_occurrence = recurrence_service->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(gap_event),
      gap_rule, 1);
  require(gap_occurrence.ok() &&
              gap_occurrence.value().occurrence_start_at ==
                  std::optional<std::string>("2026-03-08T10:00:00Z"),
          "recurrence source must apply the documented DST gap shift");
  EventOccurrenceState skipped;
  skipped.event_id = gap_event.id;
  skipped.recurrence_revision = 1;
  skipped.occurrence_key = gap_occurrence.value().occurrence_key;
  skipped.occurrence_start_at =
      gap_occurrence.value().occurrence_start_at;
  skipped.status = "skipped";
  skipped.state_changed_at = "2026-03-08T09:00:00Z";
  skipped.created_at = skipped.state_changed_at;
  skipped.updated_at = skipped.state_changed_at;

  auto long_event = timed_event(31, "Long recurring overlap",
                                "2026-08-01T00:00:00Z",
                                "2026-08-03T00:00:00Z");
  long_event.has_recurrence = true;
  long_event.recurrence_id = uuid(31, 11);
  long_event.recurrence_revision = 1;
  Recurrence long_rule;
  long_rule.id = *long_event.recurrence_id;
  long_rule.revision = 1;
  long_rule.frequency = "daily";
  long_rule.interval = 1;
  long_rule.start_at = long_event.start_at;
  long_rule.timezone = "Asia/Shanghai";
  long_rule.created_at = "2026-08-01T00:00:00Z";

  auto fold_event = timed_event(32, "DST fold daily",
                                "2026-10-31T08:30:00Z",
                                "2026-10-31T09:30:00Z",
                                "America/Los_Angeles");
  fold_event.has_recurrence = true;
  fold_event.recurrence_id = uuid(32, 11);
  fold_event.recurrence_revision = 1;
  Recurrence fold_rule;
  fold_rule.id = *fold_event.recurrence_id;
  fold_rule.revision = 1;
  fold_rule.frequency = "daily";
  fold_rule.interval = 1;
  fold_rule.start_at = fold_event.start_at;
  fold_rule.timezone = "America/Los_Angeles";
  fold_rule.created_at = "2026-10-31T00:00:00Z";
  auto fold_occurrence = recurrence_service->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(fold_event),
      fold_rule, 1);
  require(fold_occurrence.ok() &&
              fold_occurrence.value().occurrence_start_at ==
                  std::optional<std::string>("2026-11-01T08:30:00Z") &&
              fold_occurrence.value().occurrence_end_at ==
                  std::optional<std::string>("2026-11-01T10:30:00Z"),
          "recurrence source must choose the earlier DST fold instant");

  repository->snapshot.events = {gap_event, long_event, fold_event};
  repository->snapshot.event_recurrences = {gap_rule, long_rule, fold_rule};
  repository->snapshot.event_occurrence_states = {skipped};
  std::string clock = "2026-03-08T09:30:00Z";
  auto calendar = std::make_shared<CalendarViewQueryService>(
      repository, time_resolver, recurrence_service,
      [&clock] { return clock; });
  auto gap_summary = calendar->range_summary(
      {{2026, 3, 8}, {2026, 3, 9}, "America/Los_Angeles"});
  require(gap_summary.ok(), "DST gap summary must succeed");
  auto gap_page = calendar->list_day_items(
      {{2026, 3, 8}, "America/Los_Angeles", CalendarSection::event,
       gap_summary.value().snapshot_token, std::nullopt, 20});
  require(gap_page.ok(), "DST gap page must succeed");
  const auto gap_items = typed_items<CalendarEventItem>(gap_page.value());
  const auto& gap = event_named(gap_items, "DST gap daily");
  require(gap.display_local_time == std::optional<std::string>("03:00") &&
              gap.status == "skipped" && gap.recurrence_revision == 1 &&
              gap.occurrence_key.has_value(),
          "Calendar recurrence must preserve gap-adjusted route identity and explicit state");

  clock = "2026-08-10T01:00:00Z";
  auto long_summary = calendar->range_summary(
      {{2026, 8, 10}, {2026, 8, 11}, "Asia/Shanghai"});
  require(long_summary.ok(), "long recurrence range must succeed");
  auto long_page = calendar->list_day_items(
      {{2026, 8, 10}, "Asia/Shanghai", CalendarSection::event,
       long_summary.value().snapshot_token, std::nullopt, 100});
  require(long_page.ok(), "long recurrence page must succeed");
  const auto long_items = typed_items<CalendarEventItem>(long_page.value());
  require(std::count_if(long_items.begin(), long_items.end(), [](const auto& item) {
            return item.title == "Long recurring overlap" &&
                   item.day_display != "starts_at";
          }) >= 1,
          "recurrence expansion must include occurrences starting before the selected day");

  clock = "2026-11-01T08:45:00Z";
  auto fold_summary = calendar->range_summary(
      {{2026, 11, 1}, {2026, 11, 2}, "America/Los_Angeles"});
  require(fold_summary.ok(), "DST fold summary must succeed");
  auto fold_page = calendar->list_day_items(
      {{2026, 11, 1}, "America/Los_Angeles", CalendarSection::event,
       fold_summary.value().snapshot_token, std::nullopt, 100});
  require(fold_page.ok(), "DST fold page must succeed");
  const auto fold_items = typed_items<CalendarEventItem>(fold_page.value());
  const auto& fold = event_named(fold_items, "DST fold daily");
  require(fold.display_local_time == std::optional<std::string>("01:30") &&
              fold.status == "in_progress",
          "Calendar must preserve earlier-fold local display and frozen Clock");
}

void completed_recurring_series_cutoff_test() {
  auto time_resolver = resolver();
  auto recurrence_service = std::make_shared<RecurrenceService>(time_resolver);
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(12);

  auto future = timed_event(40, "Completed future occurrence",
                            "2026-08-01T01:00:00Z",
                            "2026-08-01T02:00:00Z");
  future.has_recurrence = true;
  future.recurrence_id = uuid(40, 11);
  future.recurrence_revision = 1;
  future.status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  future.completed_at = "2026-08-15T03:00:00Z";

  auto overlaps_cutoff = timed_event(41, "Started before completion",
                                     "2026-08-15T02:00:00Z",
                                     "2026-08-15T04:00:00Z");
  overlaps_cutoff.has_recurrence = true;
  overlaps_cutoff.recurrence_id = uuid(41, 11);
  overlaps_cutoff.recurrence_revision = 1;
  overlaps_cutoff.status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  overlaps_cutoff.completed_at = "2026-08-15T03:00:00Z";

  auto exact_cutoff = timed_event(42, "Starts exactly at completion",
                                  "2026-08-15T03:00:00Z",
                                  "2026-08-15T04:00:00Z");
  exact_cutoff.has_recurrence = true;
  exact_cutoff.recurrence_id = uuid(42, 11);
  exact_cutoff.recurrence_revision = 1;
  exact_cutoff.status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  exact_cutoff.completed_at = "2026-08-15T03:00:00Z";

  auto all_day_after_midnight =
      all_day_event(43, "All-day completion day", "2026-08-15",
                    "2026-08-16");
  all_day_after_midnight.has_recurrence = true;
  all_day_after_midnight.recurrence_id = uuid(43, 11);
  all_day_after_midnight.recurrence_revision = 1;
  all_day_after_midnight.status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  all_day_after_midnight.completed_at = "2026-08-15T03:00:00Z";

  auto all_day_at_midnight =
      all_day_event(44, "All-day exact midnight", "2026-08-15",
                    "2026-08-16");
  all_day_at_midnight.has_recurrence = true;
  all_day_at_midnight.recurrence_id = uuid(44, 11);
  all_day_at_midnight.recurrence_revision = 1;
  all_day_at_midnight.status = std::string(
      excellent_calendar::domain::kEventStatusCompleted);
  all_day_at_midnight.completed_at = "2026-08-14T16:00:00Z";

  repository->snapshot.events = {future, overlaps_cutoff, exact_cutoff,
                                 all_day_after_midnight,
                                 all_day_at_midnight};
  for (const auto& event : repository->snapshot.events) {
    Recurrence rule;
    rule.id = *event.recurrence_id;
    rule.revision = 1;
    rule.frequency = "daily";
    rule.interval = 1;
    rule.start_at = event.is_all_day
                        ? std::nullopt
                        : std::optional<std::string>(event.start_at);
    rule.start_date = event.is_all_day ? event.start_date : std::nullopt;
    rule.timezone = event.timezone.value_or("Asia/Shanghai");
    rule.created_at = "2026-08-01T00:00:00Z";
    repository->snapshot.event_recurrences.push_back(std::move(rule));
  }

  std::string clock = "2026-09-01T04:00:00Z";
  auto calendar = std::make_shared<CalendarViewQueryService>(
      repository, time_resolver, recurrence_service,
      [&clock] { return clock; });
  auto summary = calendar->range_summary(
      {{2026, 8, 15}, {2026, 9, 2}, "Asia/Shanghai"});
  require(summary.ok(), "completed-series summary must succeed");
  require(std::none_of(summary.value().days.begin(), summary.value().days.end(),
                       [](const auto& day) { return day.has_open_event; }),
          "completed-series occurrences must never create an open Event dot");

  auto completion_day = calendar->list_day_items(
      {{2026, 8, 15}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 100});
  require(completion_day.ok(), "completed-series completion day must list");
  const auto completion_items =
      typed_items<CalendarEventItem>(completion_day.value());
  require(std::count_if(completion_items.begin(), completion_items.end(),
                        [](const auto& item) {
                          return item.title == "Started before completion";
                        }) == 1,
          "timed occurrence starting before completed_at must be retained");
  require(std::count_if(completion_items.begin(), completion_items.end(),
                        [](const auto& item) {
                          return item.title == "Starts exactly at completion";
                        }) == 0,
          "timed occurrence starting exactly at completed_at must be excluded");
  require(std::count_if(completion_items.begin(), completion_items.end(),
                        [](const auto& item) {
                          return item.title == "All-day completion day";
                        }) == 1 &&
              std::count_if(completion_items.begin(), completion_items.end(),
                            [](const auto& item) {
                              return item.title == "All-day exact midnight";
                            }) == 0,
          "all-day completion day must use recurrence-zone midnight as its cutoff anchor");

  auto future_day = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::event,
       summary.value().snapshot_token, std::nullopt, 100});
  require(future_day.ok() && future_day.value().items.empty(),
          "completed recurring series must not project future occurrences");
}

void summary_conservation_and_range_boundaries_test() {
  auto time_resolver = resolver();
  auto recurrence_service = std::make_shared<RecurrenceService>(time_resolver);
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(8);

  auto recurring = timed_event(60, "Summary recurring",
                               "2026-09-01T00:00:00Z",
                               "2026-09-01T01:00:00Z");
  recurring.has_recurrence = true;
  recurring.recurrence_id = uuid(60, 11);
  recurring.recurrence_revision = 1;
  Recurrence rule;
  rule.id = *recurring.recurrence_id;
  rule.revision = 1;
  rule.frequency = "daily";
  rule.interval = 1;
  rule.start_at = recurring.start_at;
  rule.timezone = recurring.timezone.value_or("");
  rule.created_at = "2026-09-01T00:00:00Z";
  repository->snapshot.events = {recurring};
  repository->snapshot.event_recurrences = {rule};
  for (int index = 0; index < 3; ++index) {
    auto occurrence = recurrence_service->occurrence_at(
        excellent_calendar::domain::recurring_schedule_from_event(recurring),
        rule, index);
    require(occurrence.ok(), "summary fixture occurrence must expand");
    EventOccurrenceState state;
    state.event_id = recurring.id;
    state.recurrence_revision = 1;
    state.occurrence_key = occurrence.value().occurrence_key;
    state.occurrence_start_at = occurrence.value().occurrence_start_at;
    state.status = index == 0 ? "completed"
                             : index == 1 ? "cancelled" : "skipped";
    state.state_changed_at = "2026-09-01T02:00:00Z";
    state.created_at = state.state_changed_at;
    state.updated_at = state.state_changed_at;
    repository->snapshot.event_occurrence_states.push_back(std::move(state));
  }

  auto tracked = habit(60, "Summary Habit", {2026, 9, 1}, {2026, 9, 3},
                       100, "pages");
  repository->snapshot.habits = {tracked};
  repository->snapshot.habit_recurrences = {habit_recurrence(tracked)};
  repository->snapshot.habit_check_ins = {
      check_in(60, tracked, {2026, 9, 1}, "done", 100, 100, "pages"),
      check_in(61, tracked, {2026, 9, 2}, "partial", 1, 100, "pages"),
  };

  Anniversary anniversary;
  anniversary.id = uuid(60, 40);
  anniversary.title = "Summary Anniversary";
  anniversary.date = {2026, 9, 2};
  anniversary.calendar_type = "solar";
  anniversary.created_at = "2026-01-01T00:00:00Z";
  anniversary.updated_at = anniversary.created_at;
  repository->snapshot.anniversaries = {anniversary};

  std::string clock = "2026-09-01T04:00:00Z";
  auto calendar = std::make_shared<CalendarViewQueryService>(
      repository, time_resolver, recurrence_service,
      [&clock] { return clock; });
  auto summary = calendar->range_summary(
      {{2026, 9, 1}, {2026, 9, 4}, "Asia/Shanghai"});
  require(summary.ok() && summary.value().days.size() == 3U,
          "summary conservation fixture must produce three gap-free days");
  require(!summary.value().days[0].has_open_event &&
              !summary.value().days[1].has_open_event &&
              summary.value().days[2].has_open_event,
          "completed/cancelled/skipped occurrence states must drive Event dots");
  require(!summary.value().days[0].has_pending_habit &&
              summary.value().days[1].has_pending_habit &&
              summary.value().days[2].has_pending_habit,
          "done/partial/upcoming Habit states must drive pending dots");
  require(!summary.value().days[0].has_anniversary &&
              summary.value().days[1].has_anniversary &&
              !summary.value().days[2].has_anniversary,
          "one-time Anniversary must mark only its occurrence date");

  for (std::size_t index = 0; index < summary.value().days.size(); ++index) {
    const auto date = summary.value().days[index].date;
    auto event_page = calendar->list_day_items(
        {date, "Asia/Shanghai", CalendarSection::event,
         summary.value().snapshot_token, std::nullopt, 100});
    auto habit_page = calendar->list_day_items(
        {date, "Asia/Shanghai", CalendarSection::habit,
         summary.value().snapshot_token, std::nullopt, 100});
    auto anniversary_page = calendar->list_day_items(
        {date, "Asia/Shanghai", CalendarSection::anniversary,
         summary.value().snapshot_token, std::nullopt, 100});
    require(event_page.ok() && habit_page.ok() && anniversary_page.ok(),
            "daily lists used for summary conservation must succeed");
    const auto events = typed_items<CalendarEventItem>(event_page.value());
    const auto habits = typed_items<CalendarHabitItem>(habit_page.value());
    const auto anniversaries =
        typed_items<CalendarAnniversaryItem>(anniversary_page.value());
    const bool has_open_event =
        std::any_of(events.begin(), events.end(), [](const auto& item) {
          return item.status != "completed";
        });
    const bool has_pending_habit =
        std::any_of(habits.begin(), habits.end(), [](const auto& item) {
          return item.status != "done";
        });
    require(summary.value().days[index].has_open_event == has_open_event &&
                summary.value().days[index].has_pending_habit ==
                    has_pending_habit &&
                summary.value().days[index].has_anniversary ==
                    !anniversaries.empty(),
            "summary flags must conserve the corresponding complete daily list");
  }

  auto maximum = calendar->range_summary(
      {{2026, 9, 1}, {2026, 10, 13}, "Asia/Shanghai"});
  require(maximum.ok() && maximum.value().days.size() == 42U,
          "42 natural days must be accepted");
  auto too_large = calendar->range_summary(
      {{2026, 9, 1}, {2026, 10, 14}, "Asia/Shanghai"});
  require(!too_large.ok() &&
              too_large.error().code == "CALENDAR_RANGE_TOO_LARGE",
          "43 natural days must be rejected");
  auto empty = calendar->range_summary(
      {{2026, 9, 1}, {2026, 9, 1}, "Asia/Shanghai"});
  auto reversed = calendar->range_summary(
      {{2026, 9, 2}, {2026, 9, 1}, "Asia/Shanghai"});
  require(!empty.ok() && empty.error().code == "CALENDAR_RANGE_INVALID" &&
              !reversed.ok() &&
              reversed.error().code == "CALENDAR_RANGE_INVALID",
          "empty and reversed local-date ranges must be rejected");
}

void habit_and_anniversary_projection_test() {
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(3);
  const LocalDate start{2026, 8, 1};
  const LocalDate end{2026, 9, 30};
  auto absent = habit(1, "Absent with tombstone", start, end);
  auto partial = habit(2, "Partial boundary", start, end, 100, "pages");
  auto quantity_done = habit(3, "Quantity done over target", start, end, 100,
                             "pages");
  auto binary_done = habit(4, "Binary done", start, end);
  auto skipped = habit(5, "Skipped", start, end);
  auto starts_tomorrow =
      habit(6, "Starts tomorrow", {2026, 9, 2}, end);
  auto ended_yesterday = habit(7, "Ended yesterday", start, end);
  ended_yesterday.ended_date = LocalDate{2026, 8, 31};
  ended_yesterday.is_active = false;
  repository->snapshot.habits =
      {absent, partial, quantity_done, binary_done, skipped,
       starts_tomorrow, ended_yesterday};
  for (const auto& item : repository->snapshot.habits) {
    repository->snapshot.habit_recurrences.push_back(
        habit_recurrence(item));
  }
  auto tombstone = check_in(1, absent, {2026, 9, 1}, "done");
  tombstone.deleted_at = "2026-09-01T05:00:00Z";
  repository->snapshot.habit_check_ins = {
      tombstone,
      check_in(2, partial, {2026, 9, 1}, "partial", 1, 100, "pages"),
      check_in(3, quantity_done, {2026, 9, 1}, "done", 150, 100,
               "pages"),
      check_in(4, binary_done, {2026, 9, 1}, "done"),
      check_in(5, skipped, {2026, 9, 1}, "skipped"),
  };
  auto partial_reminder = open_reminder(
      1, std::string(excellent_calendar::domain::kReminderTargetHabit),
      partial.id);
  partial_reminder.occurrence_date = "2026-09-01";
  partial_reminder.local_time = "08:00";
  auto absent_reminder = open_reminder(
      2, std::string(excellent_calendar::domain::kReminderTargetHabit),
      absent.id);
  absent_reminder.occurrence_date = "2026-09-01";
  absent_reminder.local_time = "09:00";
  repository->snapshot.reminders = {partial_reminder, absent_reminder};

  std::string clock = "2026-09-01T04:00:00Z";
  auto calendar = service(repository, resolver(), clock);
  auto summary = calendar->range_summary(
      {{2026, 9, 1}, {2026, 9, 3}, "Asia/Shanghai"});
  require(summary.ok() && summary.value().days[0].has_pending_habit,
          "non-done Habit must conserve the range dot");
  auto today_page = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::habit,
       summary.value().snapshot_token, std::nullopt, 20});
  require(today_page.ok(), "Habit today page must succeed");
  const auto today = typed_items<CalendarHabitItem>(today_page.value());
  require(today[0].title == "Partial boundary" &&
              today[1].title == "Absent with tombstone",
          "same Habit status bucket must sort by active reminder local time");
  const auto& absent_item = habit_named(today, "Absent with tombstone");
  require(absent_item.status == "absent" &&
              !absent_item.check_in_id.has_value(),
          "deleted CheckIn must project today as absent without fake identity");
  const auto& partial_item = habit_named(today, "Partial boundary");
  require(partial_item.status == "partial" &&
              partial_item.completed_count_hundredths == 1 &&
              partial_item.target_count_hundredths == 100,
          "partial lower boundary must preserve exact integer hundredths");
  const auto& quantity_done_item =
      habit_named(today, "Quantity done over target");
  require(quantity_done_item.status == "done" &&
              quantity_done_item.completed_count_hundredths == 150 &&
              quantity_done_item.target_count_hundredths == 100,
          "quantity done must preserve over-target completion");
  const auto& binary_done_item = habit_named(today, "Binary done");
  require(binary_done_item.status == "done" &&
              !binary_done_item.completed_count_hundredths.has_value() &&
              !binary_done_item.target_count_hundredths.has_value() &&
              !binary_done_item.unit.has_value(),
          "binary done must keep all quantity fields null");
  require(std::none_of(today.begin(), today.end(), [](const auto& item) {
            return item.title == "Starts tomorrow" ||
                   item.title == "Ended yesterday";
          }),
          "Habit projection must stay inside start/effective-end boundaries");

  auto past_page = calendar->list_day_items(
      {{2026, 8, 31}, "Asia/Shanghai", CalendarSection::habit,
       summary.value().snapshot_token, std::nullopt, 20});
  require(past_page.ok() &&
              habit_named(typed_items<CalendarHabitItem>(past_page.value()),
                          "Absent with tombstone")
                      .status == "missed",
          "past eligible Habit day without an active CheckIn must be missed");

  auto future_page = calendar->list_day_items(
      {{2026, 9, 2}, "Asia/Shanghai", CalendarSection::habit,
       summary.value().snapshot_token, std::nullopt, 20});
  require(future_page.ok() &&
              std::all_of(future_page.value().items.begin(),
                          future_page.value().items.end(), [](const auto& item) {
                            return std::get<CalendarHabitItem>(item).status ==
                                   "upcoming";
                          }),
          "future eligible Habit days must project upcoming");

  Anniversary leap;
  leap.id = uuid(1, 40);
  leap.title = "Leap anniversary";
  leap.date = {2000, 2, 29};
  leap.calendar_type = "solar";
  leap.recurrence_id = uuid(1, 41);
  leap.importance = "important_urgent";
  leap.created_at = "2000-02-29T00:00:00Z";
  leap.updated_at = leap.created_at;
  AnniversaryRecurrence annual;
  annual.id = *leap.recurrence_id;
  annual.frequency = "yearly";
  annual.created_at = leap.created_at;
  repository->snapshot.anniversaries = {leap};
  repository->snapshot.anniversary_recurrences = {annual};
  auto source_summary = calendar->range_summary(
      {{2000, 2, 29}, {2000, 3, 1}, "Asia/Shanghai"});
  require(source_summary.ok() &&
              source_summary.value().days[0].has_anniversary,
          "2000 leap day must preserve the exact annual occurrence");
  auto source_page = calendar->list_day_items(
      {{2000, 2, 29}, "Asia/Shanghai", CalendarSection::anniversary,
       source_summary.value().snapshot_token, std::nullopt, 20});
  const auto source_items =
      source_page.ok()
          ? typed_items<CalendarAnniversaryItem>(source_page.value())
          : std::vector<CalendarAnniversaryItem>{};
  require(source_items.size() == 1U && source_items[0].years_elapsed == 0,
          "annual source occurrence must retain zero elapsed years");
  auto occurrence_key = excellent_calendar::domain::anniversary_occurrence_key(
      leap.id, {2100, 2, 28});
  require(occurrence_key.ok(), "anniversary occurrence identity must generate");
  auto anniversary_reminder = open_reminder(
      3, std::string(
             excellent_calendar::domain::kReminderTargetAnniversary),
      leap.id);
  anniversary_reminder.occurrence_key = occurrence_key.value();
  repository->snapshot.reminders.push_back(anniversary_reminder);
  auto leap_summary = calendar->range_summary(
      {{2100, 2, 28}, {2100, 3, 1}, "Asia/Shanghai"});
  require(leap_summary.ok() && leap_summary.value().days[0].has_anniversary,
          "2100 non-leap fallback must conserve Anniversary dot");
  auto leap_page = calendar->list_day_items(
      {{2100, 2, 28}, "Asia/Shanghai", CalendarSection::anniversary,
       leap_summary.value().snapshot_token, std::nullopt, 20});
  require(leap_page.ok(), "2100 Anniversary page must succeed");
  const auto leap_items = typed_items<CalendarAnniversaryItem>(leap_page.value());
  require(leap_items.size() == 1U && leap_items[0].years_elapsed == 100 &&
              leap_items[0].occurrence_date == LocalDate{2100, 2, 28} &&
              leap_items[0].has_active_reminder,
          "annual leap-day projection must preserve years and active reminder");

  Anniversary historic = leap;
  historic.id = uuid(2, 40);
  historic.title = "Historic leap anniversary";
  historic.date = {1896, 2, 29};
  historic.recurrence_id = uuid(2, 41);
  historic.created_at = "1896-02-29T00:00:00Z";
  historic.updated_at = historic.created_at;
  AnniversaryRecurrence historic_annual = annual;
  historic_annual.id = *historic.recurrence_id;
  historic_annual.created_at = historic.created_at;
  repository->snapshot.anniversaries.push_back(historic);
  repository->snapshot.anniversary_recurrences.push_back(historic_annual);
  auto historic_summary = calendar->range_summary(
      {{1900, 2, 28}, {1900, 3, 1}, "Etc/UTC"});
  require(historic_summary.ok(),
          "1900 summary must succeed: " +
              (historic_summary.ok()
                   ? std::string{}
                   : historic_summary.error().code + " " +
                         historic_summary.error().message + " " +
                         (historic_summary.error().details.count("reason")
                              ? historic_summary.error().details.at("reason")
                              : std::string{})));
  require(historic_summary.value().days[0].has_anniversary,
          "1900 non-leap fallback must preserve the annual occurrence");
  auto historic_page = calendar->list_day_items(
      {{1900, 2, 28}, "Etc/UTC", CalendarSection::anniversary,
       historic_summary.value().snapshot_token, std::nullopt, 20});
  const auto historic_items =
      historic_page.ok()
          ? typed_items<CalendarAnniversaryItem>(historic_page.value())
          : std::vector<CalendarAnniversaryItem>{};
  require(historic_items.size() == 1U &&
              historic_items[0].years_elapsed == 4 &&
              historic_items[0].occurrence_date == LocalDate{1900, 2, 28},
          "1900 fallback must use February 28 and exact elapsed years");
}

void keyset_pagination_test() {
  auto repository = std::make_shared<FakeCalendarQueryRepository>();
  repository->snapshot.generations.fill(4);
  for (int index = 0; index < 101; ++index) {
    Anniversary value;
    value.id = uuid(index + 1, 50);
    std::ostringstream title;
    title << "Item " << std::setfill('0') << std::setw(3) << index;
    value.title = title.str();
    value.date = {2026, 9, 1};
    value.calendar_type = "solar";
    value.created_at = "2026-01-01T00:00:00Z";
    value.updated_at = value.created_at;
    repository->snapshot.anniversaries.push_back(std::move(value));
  }
  std::string clock = "2026-09-01T00:00:00Z";
  auto calendar = service(repository, resolver(), clock);
  auto summary = calendar->range_summary(
      {{2026, 9, 1}, {2026, 9, 2}, "Asia/Shanghai"});
  require(summary.ok(), "pagination summary must succeed");

  std::optional<std::string> cursor;
  std::set<std::string> ids;
  std::string first_cursor;
  int pages = 0;
  do {
    auto page = calendar->list_day_items(
        {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::anniversary,
         summary.value().snapshot_token, cursor, 20});
    require(page.ok(), "keyset page must succeed");
    ++pages;
    for (const auto& item : typed_items<CalendarAnniversaryItem>(page.value())) {
      require(ids.insert(item.anniversary_id).second,
              "keyset pages must not duplicate an item");
    }
    if (pages == 1) {
      require(page.value().has_more && page.value().items.size() == 20U &&
                  page.value().next_cursor.has_value(),
              "20/21 boundary must emit a non-empty advancing cursor");
      first_cursor = *page.value().next_cursor;
      auto mismatch = calendar->list_day_items(
          {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::anniversary,
           summary.value().snapshot_token, page.value().next_cursor, 19});
      require(!mismatch.ok() &&
                  mismatch.error().code ==
                      "CALENDAR_CURSOR_QUERY_MISMATCH",
              "cursor must bind page size and every query condition");
    }
    cursor = page.value().next_cursor;
    if (!page.value().has_more) {
      require(!cursor.has_value(),
              "terminal page must have a null next cursor");
      break;
    }
  } while (pages < 10);
  require(pages == 6 && ids.size() == 101U,
          "101 items must paginate as 20/20/20/20/20/1 without gaps");

  auto malformed = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::anniversary,
       summary.value().snapshot_token,
       std::optional<std::string>("calcur1.aaaaaaaaaaaaaaaaaaaa"), 20});
  require(!malformed.ok() &&
              malformed.error().code == "CALENDAR_CURSOR_INVALID",
          "malformed cursor must fail explicitly");
  require(!first_cursor.empty(), "first page cursor must be observable");

  repository->snapshot.generations[6] += 1;
  auto expired_cursor = calendar->list_day_items(
      {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::anniversary,
       summary.value().snapshot_token, first_cursor, 20});
  require(!expired_cursor.ok() &&
              expired_cursor.error().code == "CALENDAR_SNAPSHOT_EXPIRED" &&
              expired_cursor.error().retryable,
          "cursor continuation must expire when its snapshot generation changes");
}

void pagination_cardinality_boundaries_test() {
  const std::array<int, 8> counts{0, 1, 19, 20, 21, 40, 41, 100};
  auto time_resolver = resolver();
  for (const int count : counts) {
    auto repository = std::make_shared<FakeCalendarQueryRepository>();
    repository->snapshot.generations.fill(20 + count);
    for (int index = 0; index < count; ++index) {
      Anniversary item;
      item.id = uuid(index + 1, 51);
      item.title = "Boundary " + std::to_string(index);
      item.date = {2026, 9, 1};
      item.calendar_type = "solar";
      item.created_at = "2026-01-01T00:00:00Z";
      item.updated_at = item.created_at;
      repository->snapshot.anniversaries.push_back(std::move(item));
    }
    std::string clock = "2026-09-01T00:00:00Z";
    auto calendar = service(repository, time_resolver, clock);
    auto summary = calendar->range_summary(
        {{2026, 9, 1}, {2026, 9, 2}, "Asia/Shanghai"});
    require(summary.ok(), "pagination boundary summary must succeed");
    std::optional<std::string> cursor;
    std::set<std::string> ids;
    int pages = 0;
    while (true) {
      const auto previous_cursor = cursor;
      auto page = calendar->list_day_items(
          {{2026, 9, 1}, "Asia/Shanghai", CalendarSection::anniversary,
           summary.value().snapshot_token, cursor, 20});
      require(page.ok(), "pagination boundary page must succeed");
      ++pages;
      for (const auto& item :
           typed_items<CalendarAnniversaryItem>(page.value())) {
        require(ids.insert(item.anniversary_id).second,
                "pagination boundary must not duplicate an item");
      }
      if (!page.value().has_more) {
        require(!page.value().next_cursor.has_value(),
                "terminal boundary page must not return a cursor");
        break;
      }
      require(!page.value().items.empty() &&
                  page.value().next_cursor.has_value() &&
                  page.value().next_cursor != previous_cursor,
              "non-terminal boundary page must expose a strictly advancing cursor");
      cursor = page.value().next_cursor;
      require(pages <= 6, "pagination boundary must terminate");
    }
    const int expected_pages = std::max(1, (count + 19) / 20);
    require(static_cast<int>(ids.size()) == count && pages == expected_pages,
            "0/1/19/20/21/40/41/100 cardinality must paginate without gaps");
  }
}

void real_sqlite_snapshot_and_plan_test() {
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  using excellent_calendar::storage::sqlite::SqliteCalendarQueryRepository;
  TemporaryDirectory directory("excellent_calendar_view_sqlite");
  auto opened = SqliteCalendarDatabase::open(directory.path());
  require(opened.ok(), "Calendar SQLite fixture must initialize");
  auto repository =
      std::make_shared<SqliteCalendarQueryRepository>(opened.value());
  require(repository->initialize().ok(),
          "Calendar SQLite query repository must initialize");
  auto initial = repository->load_snapshot();
  require(initial.ok() && initial.value().events.empty(),
          "fresh Calendar SQLite snapshot must be empty");

  auto before = opened.value()->load_recurring_state();
  require(before.ok(), "real SQLite mutation must read authoritative state");
  auto after = before.value();
  after.events.push_back(timed_event(
      900, "SQLite generation mutation", "2026-08-31T16:00:00Z",
      "2026-08-31T17:00:00Z"));
  auto written = opened.value()->write_recurring_changes(before.value(), after);
  require(written.ok(), "real SQLite Event mutation must commit");

  auto expired = repository->load_snapshot(initial.value().generations);
  require(!expired.ok() &&
              expired.error().code == "CALENDAR_SNAPSHOT_EXPIRED" &&
              expired.error().retryable,
          "expected generations must be checked inside the real read transaction");
  auto current = repository->load_snapshot();
  require(current.ok() && current.value().events.size() == 1U &&
              current.value().events.front().title ==
                  "SQLite generation mutation" &&
              current.value().generations[0] ==
                  initial.value().generations[0] + 1,
          "real SQLite snapshot must return the committed fact and generation");
  for (std::size_t index = 1; index < current.value().generations.size();
       ++index) {
    require(current.value().generations[index] ==
                initial.value().generations[index],
            "an unrelated Calendar generation must not advance");
  }

  const auto database_path = opened.value()->database_path();
  for (const auto table :
       excellent_calendar::repository::kCalendarQueryContributingStores) {
    const auto plan = sqlite_query_plan(
        database_path,
        "SELECT record_key, position, payload_json FROM " +
            std::string(table) + " ORDER BY position ASC");
    require(plan.find("USING INDEX") != std::string::npos,
            "Calendar fact scan must use the canonical position index: " +
                std::string(table) + " => " + plan);
  }
  const auto generation_plan = sqlite_query_plan(
      database_path,
      "SELECT generation FROM store_generations WHERE store_name='events'");
  require(generation_plan.find("PRIMARY KEY") != std::string::npos,
          "generation lookup must use the store_generations primary key: " +
              generation_plan);
}

void real_sqlite_recovery_batch_reference_test() {
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  using excellent_calendar::storage::sqlite::SqliteCalendarQueryRepository;
  TemporaryDirectory directory("excellent_calendar_view_recovery");
  auto opened = SqliteCalendarDatabase::open(directory.path());
  require(opened.ok(), "Calendar recovery fixture must initialize");
  auto repository =
      std::make_shared<SqliteCalendarQueryRepository>(opened.value());
  require(repository->initialize().ok(),
          "Calendar recovery query repository must initialize");

  auto before = opened.value()->load_recurring_state();
  require(before.ok(), "Calendar recovery fixture must load full state");
  auto after = before.value();
  auto event = timed_event(901, "Recovery-owned Event",
                           "2026-09-01T01:00:00Z",
                           "2026-09-01T02:00:00Z");
  auto reminder = open_reminder(
      901, std::string(excellent_calendar::domain::kReminderTargetEvent),
      event.id);
  const auto batch_id = uuid(901, 31);
  reminder.recovery_batch_id = batch_id;
  excellent_calendar::domain::ReminderRecoveryBatch batch;
  batch.id = batch_id;
  batch.recovery_request_id = uuid(901, 32);
  batch.trigger_source = "app_start";
  batch.started_at = "2026-09-01T00:00:00Z";
  batch.window_start_at = "2026-08-29T00:00:00Z";
  batch.detail_reminder_ids = {reminder.id};
  batch.status =
      std::string(excellent_calendar::domain::kRecoveryInProgress);
  after.events.push_back(event);
  after.reminders.push_back(reminder);
  after.recovery_batches.push_back(batch);
  auto written = opened.value()->write_recurring_changes(before.value(), after);
  require(written.ok(), "valid recovery-owned Reminder must commit");

  auto valid_snapshot = repository->load_snapshot();
  require(valid_snapshot.ok() && valid_snapshot.value().events.size() == 1U &&
              valid_snapshot.value().reminders.size() == 1U,
          "valid recovery batch reference must not block Calendar loading");

  sqlite_execute_mutation(opened.value()->database_path(),
                          "DELETE FROM reminder_recovery_batches");
  auto orphan_snapshot = repository->load_snapshot();
  require(!orphan_snapshot.ok() &&
              orphan_snapshot.error().code == "STORAGE_DATA_CORRUPTED" &&
              orphan_snapshot.error().details.find("reason") !=
                  orphan_snapshot.error().details.end() &&
              orphan_snapshot.error().details.at("reason") ==
                  "Reminder recovery batch is missing",
          "a true orphan recovery batch reference must remain corrupted: " +
              (orphan_snapshot.ok()
                   ? std::string("unexpected success")
                   : orphan_snapshot.error().code + " / " +
                         orphan_snapshot.error().message));
}

void real_sqlite_anniversary_recovery_batch_reference_test() {
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  using excellent_calendar::storage::sqlite::SqliteCalendarQueryRepository;
  TemporaryDirectory directory("excellent_calendar_view_anniversary_recovery");
  auto opened = SqliteCalendarDatabase::open(directory.path());
  require(opened.ok(), "Calendar Anniversary recovery fixture must initialize");
  auto repository =
      std::make_shared<SqliteCalendarQueryRepository>(opened.value());
  require(repository->initialize().ok(),
          "Calendar Anniversary recovery query repository must initialize");

  auto before = opened.value()->load_recurring_state();
  require(before.ok(),
          "Calendar Anniversary recovery fixture must load full state");
  auto after = before.value();

  Anniversary anniversary;
  anniversary.id = uuid(902, 40);
  anniversary.title = "Recovery-owned Anniversary";
  anniversary.date = {2026, 9, 1};
  anniversary.calendar_type = "solar";
  anniversary.reminders_enabled = true;
  anniversary.created_at = "2026-01-01T00:00:00Z";
  anniversary.updated_at = anniversary.created_at;

  auto template_key =
      excellent_calendar::domain::anniversary_reminder_template_key(
          anniversary.id, 0, "09:00");
  require(template_key.ok(),
          "Calendar Anniversary recovery template key must derive");
  excellent_calendar::domain::AnniversaryReminderTemplate reminder_template;
  reminder_template.template_key = template_key.value();
  reminder_template.anniversary_id = anniversary.id;
  reminder_template.advance_days = 0;
  reminder_template.local_time = "09:00";
  reminder_template.created_at = anniversary.created_at;
  reminder_template.updated_at = anniversary.updated_at;

  auto occurrence_key =
      excellent_calendar::domain::anniversary_occurrence_key(
          anniversary.id, anniversary.date);
  require(occurrence_key.ok(),
          "Calendar Anniversary recovery occurrence key must derive");
  auto reminder = open_reminder(
      902,
      std::string(excellent_calendar::domain::kReminderTargetAnniversary),
      anniversary.id);
  reminder.occurrence_key = occurrence_key.value();
  reminder.template_key = template_key.value();
  reminder.occurrence_date = "2026-09-01";
  reminder.advance_days = 0;
  reminder.local_time = "09:00";
  reminder.timezone_mode = "follow_device";

  const auto batch_id = uuid(902, 31);
  reminder.recovery_batch_id = batch_id;
  excellent_calendar::domain::ReminderRecoveryBatch batch;
  batch.id = batch_id;
  batch.recovery_request_id = uuid(902, 32);
  batch.trigger_source = "app_start";
  batch.started_at = "2026-09-01T00:00:00Z";
  batch.window_start_at = "2026-08-29T00:00:00Z";
  batch.status = std::string(excellent_calendar::domain::kRecoveryInProgress);
  excellent_calendar::domain::ReminderRecoveryBatch::AnniversaryCatchUpGroup
      group;
  group.anniversary_id = anniversary.id;
  group.occurrence_key = occurrence_key.value();
  group.occurrence_date = "2026-09-01";
  group.covered_reminder_ids = {reminder.id};
  group.delivery_id = uuid(902, 33);
  batch.anniversary_catch_up_groups = {group};

  after.anniversaries.push_back(anniversary);
  after.anniversary_reminder_templates.push_back(reminder_template);
  after.reminders.push_back(reminder);
  after.recovery_batches.push_back(batch);
  auto written = opened.value()->write_recurring_changes(before.value(), after);
  require(written.ok(),
          "valid recovery-owned Anniversary Reminder must commit: " +
              (written.ok() ? std::string() : written.error().message));

  auto valid_snapshot = repository->load_snapshot();
  require(valid_snapshot.ok() &&
              valid_snapshot.value().anniversaries.size() == 1U &&
              valid_snapshot.value().reminders.size() == 1U,
          "valid Anniversary recovery batch reference must not block Calendar");

  sqlite_execute_mutation(opened.value()->database_path(),
                          "DELETE FROM reminder_recovery_batches");
  auto orphan_snapshot = repository->load_snapshot();
  require(!orphan_snapshot.ok() &&
              orphan_snapshot.error().code == "STORAGE_DATA_CORRUPTED" &&
              orphan_snapshot.error().details.find("reason") !=
                  orphan_snapshot.error().details.end() &&
              orphan_snapshot.error().details.at("reason") ==
                  "Reminder recovery batch is missing",
          "an orphan Anniversary recovery batch reference must be corrupted: " +
              (orphan_snapshot.ok()
                   ? std::string("unexpected success")
                   : orphan_snapshot.error().code + " / " +
                         orphan_snapshot.error().message));
}

struct BenchmarkSpec {
  std::string label;
  int event_count = 0;
  int recurring_event_count = 0;
  int habit_count = 0;
  int anniversary_count = 0;
  int reminder_count = 0;
};

excellent_calendar::repository::RecurringEventState benchmark_state(
    const BenchmarkSpec& spec) {
  excellent_calendar::repository::RecurringEventState state;
  const std::string created = "2026-08-01T00:00:00Z";
  state.events.reserve(static_cast<std::size_t>(spec.event_count));
  state.recurrences.reserve(
      static_cast<std::size_t>(spec.recurring_event_count));
  for (int index = 0; index < spec.event_count; ++index) {
    auto event = timed_event(index + 1, "Benchmark Event " +
                                            std::to_string(index),
                             "2026-08-31T16:00:00Z",
                             "2026-08-31T17:00:00Z");
    event.id = uuid(index + 1, 60);
    event.created_at = created;
    event.updated_at = created;
    if (index < spec.recurring_event_count) {
      event.has_recurrence = true;
      event.recurrence_id = uuid(index + 1, 61);
      event.recurrence_revision = 1;
      Recurrence recurrence;
      recurrence.id = *event.recurrence_id;
      recurrence.revision = 1;
      recurrence.frequency = "daily";
      recurrence.interval = 1;
      recurrence.start_at = event.start_at;
      recurrence.timezone = "Asia/Shanghai";
      recurrence.created_at = created;
      state.recurrences.push_back(std::move(recurrence));
    }
    state.events.push_back(std::move(event));
  }

  const int ordinary_count = spec.event_count - spec.recurring_event_count;
  require(ordinary_count > 0,
          "benchmark requires ordinary Event Reminder targets");
  state.reminders.reserve(static_cast<std::size_t>(spec.reminder_count));
  for (int index = 0; index < spec.reminder_count; ++index) {
    const auto& target = state.events[static_cast<std::size_t>(
        spec.recurring_event_count + index % ordinary_count)];
    auto reminder = open_reminder(index + 1, "event", target.id);
    reminder.id = uuid(index + 1, 62);
    reminder.advance_minutes = 0;
    reminder.created_at = created;
    reminder.updated_at = created;
    state.reminders.push_back(std::move(reminder));
  }

  state.habits.reserve(static_cast<std::size_t>(spec.habit_count));
  state.habit_recurrences.reserve(
      static_cast<std::size_t>(spec.habit_count));
  state.habit_check_ins.reserve(static_cast<std::size_t>(spec.habit_count));
  for (int index = 0; index < spec.habit_count; ++index) {
    auto value = habit(index + 1, "Benchmark Habit " +
                                      std::to_string(index),
                       {2026, 8, 1}, {2026, 10, 31});
    value.id = uuid(index + 1, 70);
    value.recurrence_id = uuid(index + 1, 71);
    value.created_at = created;
    value.updated_at = created;
    value.first_check_in_at = "2026-09-01T04:00:00Z";
    auto recurrence = habit_recurrence(value);
    recurrence.created_at = created;
    recurrence.updated_at = created;
    auto completed = check_in(index + 1, value, {2026, 9, 1}, "done");
    completed.created_at = created;
    completed.updated_at = created;
    state.habits.push_back(std::move(value));
    state.habit_recurrences.push_back(std::move(recurrence));
    state.habit_check_ins.push_back(std::move(completed));
  }

  state.anniversaries.reserve(
      static_cast<std::size_t>(spec.anniversary_count));
  for (int index = 0; index < spec.anniversary_count; ++index) {
    Anniversary anniversary;
    anniversary.id = uuid(index + 1, 80);
    anniversary.title = "Benchmark Anniversary " + std::to_string(index);
    anniversary.date = {2026, 9, 1};
    anniversary.calendar_type = "solar";
    anniversary.created_at = created;
    anniversary.updated_at = created;
    state.anniversaries.push_back(std::move(anniversary));
  }
  return state;
}

double percentile95(std::vector<double> samples) {
  require(!samples.empty(), "latency sample set must not be empty");
  std::sort(samples.begin(), samples.end());
  const auto rank = static_cast<std::size_t>(
      std::ceil(0.95 * static_cast<double>(samples.size())));
  return samples[std::max<std::size_t>(1U, rank) - 1U];
}

template <typename Operation>
double measured_milliseconds(Operation&& operation) {
  const auto started = std::chrono::steady_clock::now();
  operation();
  const auto ended = std::chrono::steady_clock::now();
  return std::chrono::duration<double, std::milli>(ended - started).count();
}

void run_sqlite_benchmark(const BenchmarkSpec& spec) {
  using excellent_calendar::storage::sqlite::SqliteCalendarDatabase;
  using excellent_calendar::storage::sqlite::SqliteCalendarQueryRepository;
  TemporaryDirectory directory("excellent_calendar_view_" + spec.label);
  auto opened = SqliteCalendarDatabase::open(directory.path());
  require(opened.ok(), spec.label + " benchmark database must initialize");
  auto empty = opened.value()->load_recurring_state();
  require(empty.ok(), spec.label + " benchmark must read empty state");
  auto seeded = benchmark_state(spec);
  auto written = opened.value()->write_recurring_changes(empty.value(), seeded);
  require(written.ok(), spec.label + " benchmark seed must commit: " +
                            (written.ok()
                                 ? std::string{}
                                 : written.error().code + " " +
                                       written.error().message + " " +
                                       (written.error().details.count("reason")
                                            ? written.error().details.at(
                                                  "reason")
                                            : std::string{})));

  auto query_repository =
      std::make_shared<SqliteCalendarQueryRepository>(opened.value());
  require(query_repository->initialize().ok(),
          spec.label + " benchmark repository must initialize");
  auto time_resolver = resolver();
  auto recurrence = std::make_shared<RecurrenceService>(time_resolver);
  auto calendar = std::make_shared<CalendarViewQueryService>(
      query_repository, time_resolver, recurrence,
      [] { return std::string("2026-09-01T04:00:00Z"); });
  const CalendarRangeSummaryQuery range{{2026, 9, 1}, {2026, 10, 13},
                                        "Asia/Shanghai"};
  auto warm = calendar->range_summary(range);
  require(warm.ok() && warm.value().days.size() == 42U,
          spec.label + " benchmark warm range query must succeed");
  const auto token = warm.value().snapshot_token;
  const auto day_query = [&](CalendarSection section) {
    return CalendarListDayItemsQuery{{2026, 9, 1}, "Asia/Shanghai", section,
                                     token, std::nullopt, 20};
  };
  for (const auto section : {CalendarSection::event, CalendarSection::habit,
                             CalendarSection::anniversary}) {
    auto page = calendar->list_day_items(day_query(section));
    require(page.ok(), spec.label + " benchmark warm page must succeed");
  }

  constexpr int kWarmSamples = 7;
  std::vector<double> range_samples;
  std::vector<double> event_samples;
  std::vector<double> three_section_samples;
  range_samples.reserve(kWarmSamples);
  event_samples.reserve(kWarmSamples);
  three_section_samples.reserve(kWarmSamples);
  CalendarRangeSummary last_summary;
  CalendarDayItemPage last_event;
  CalendarDayItemPage last_habit;
  CalendarDayItemPage last_anniversary;
  for (int sample = 0; sample < kWarmSamples; ++sample) {
    range_samples.push_back(measured_milliseconds([&] {
      auto result = calendar->range_summary(range);
      require(result.ok(), spec.label + " measured range query must succeed");
      last_summary = std::move(result.value());
    }));
    event_samples.push_back(measured_milliseconds([&] {
      auto result = calendar->list_day_items(day_query(CalendarSection::event));
      require(result.ok(), spec.label + " measured Event page must succeed");
      last_event = std::move(result.value());
    }));
    three_section_samples.push_back(measured_milliseconds([&] {
      auto event = calendar->list_day_items(day_query(CalendarSection::event));
      auto habit = calendar->list_day_items(day_query(CalendarSection::habit));
      auto anniversary = calendar->list_day_items(
          day_query(CalendarSection::anniversary));
      require(event.ok() && habit.ok() && anniversary.ok(),
              spec.label + " measured three-section query must succeed");
      last_event = std::move(event.value());
      last_habit = std::move(habit.value());
      last_anniversary = std::move(anniversary.value());
    }));
  }

  const auto range_p95 = percentile95(range_samples);
  const auto event_p95 = percentile95(event_samples);
  const auto three_p95 = percentile95(three_section_samples);
  const auto range_bytes = excellent_calendar::boundary::contract::
      calendar_range_summary_response_json(last_summary)
                               .serialize()
                               .size();
  const auto event_bytes = excellent_calendar::boundary::contract::
      calendar_day_item_page_json(last_event)
                               .serialize()
                               .size();
  const auto first_screen_bytes =
      event_bytes +
      excellent_calendar::boundary::contract::calendar_day_item_page_json(
          last_habit)
          .serialize()
          .size() +
      excellent_calendar::boundary::contract::calendar_day_item_page_json(
          last_anniversary)
          .serialize()
          .size();
  require(range_bytes <= 32U * 1024U && event_bytes <= 128U * 1024U &&
              first_screen_bytes <= 384U * 1024U,
          spec.label + " Calendar payload must remain below frozen caps");
  // Host debug builds are substitute evidence rather than the Android device
  // release gate. This generous ceiling still catches accidental unbounded
  // recurrence expansion or item/Reminder N+1 regressions in CI.
  require(range_p95 < 15000.0 && event_p95 < 15000.0 &&
              three_p95 < 45000.0,
          spec.label + " Calendar host benchmark exceeded safety ceiling");
  std::cout << "calendar_view_benchmark label=" << spec.label
            << " sqlite=" << sqlite3_libversion()
            << " samples=" << kWarmSamples
            << " event_rows=" << spec.event_count
            << " recurrence_rows=" << spec.recurring_event_count
            << " occurrence_state_rows=0"
            << " recurring_occurrences_42d="
            << spec.recurring_event_count * 42
            << " habit_rows=" << spec.habit_count
            << " habit_recurrence_rows=" << spec.habit_count
            << " habit_check_in_rows=" << spec.habit_count
            << " anniversary_rows=" << spec.anniversary_count
            << " anniversary_recurrence_rows=0"
            << " reminder_rows=" << spec.reminder_count
            << " range42_p95_ms="
            << std::fixed << std::setprecision(2) << range_p95
            << " event20_p95_ms=" << event_p95
            << " three_sections_p95_ms=" << three_p95
            << " range_payload_bytes=" << range_bytes
            << " event_payload_bytes=" << event_bytes
            << " three_sections_payload_bytes=" << first_screen_bytes
            << '\n';
}

void real_sqlite_performance_test() {
  run_sqlite_benchmark({"typical", 500, 100, 100, 100, 500});
  run_sqlite_benchmark({"stress", 5000, 1000, 400, 1000, 5000});
}

picojson::object parse_native_result(const std::string& json) {
  picojson::value value;
  require(picojson::parse(value, json).empty() &&
              value.is<picojson::object>(),
          "endpoint must return a NativeResult object");
  return value.get<picojson::object>();
}

std::string failure_code(const std::string& json) {
  const auto result = parse_native_result(json);
  require(!result.at("ok").get<bool>() && result.at("data").is<picojson::null>(),
          "expected failed NativeResult");
  return result.at("error")
      .get<picojson::object>()
      .at("code")
      .get<std::string>();
}

void real_runtime_endpoint_test() {
  using excellent_calendar::boundary::api::calendar_list_day_items_v2;
  using excellent_calendar::boundary::api::calendar_range_summary_v2;
  using excellent_calendar::boundary::api::initialize_recurring_runtime;
  TemporaryDirectory directory("excellent_calendar_view_endpoint");
  struct RuntimeClear {
    ~RuntimeClear() {
      (void)excellent_calendar::boundary::api::initialize_recurring_runtime(
          "", EXCELLENT_CALENDAR_TEST_TZDB_DIR);
    }
  } runtime_clear;
  auto initialized = initialize_recurring_runtime(
      directory.path().string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok() && initialized.value().storage_format_version == 5,
          "Calendar endpoint runtime must initialize real SQLite v5");
  auto summary = parse_native_result(calendar_range_summary_v2(
      R"({"range_start_date":"2026-09-01","range_end_date":"2026-09-02","timezone":"Asia/Shanghai"})"));
  require(summary.at("ok").get<bool>() &&
              summary.at("error").is<picojson::null>(),
          "Calendar range endpoint must return successful NativeResult v2");
  const auto summary_data = summary.at("data").get<picojson::object>();
  const auto token = summary_data.at("snapshot_token").get<std::string>();
  require(token.rfind("calsnap1.", 0U) == 0U &&
              summary_data.at("days").get<picojson::array>().size() == 1U,
          "Calendar range endpoint must serialize token and gap-free days");

  picojson::object request;
  request["date"] = picojson::value("2026-09-01");
  request["timezone"] = picojson::value("Asia/Shanghai");
  request["section"] = picojson::value("event");
  request["snapshot_token"] = picojson::value(token);
  request["cursor"] = picojson::value();
  request["page_size"] = picojson::value(20.0);
  auto page = parse_native_result(
      calendar_list_day_items_v2(picojson::value(request).serialize()));
  require(page.at("ok").get<bool>() && page.at("error").is<picojson::null>(),
          "Calendar list endpoint must return successful NativeResult v2");
  const auto page_data = page.at("data").get<picojson::object>();
  require(page_data.at("snapshot_token").get<std::string>() == token &&
              page_data.at("items").get<picojson::array>().empty() &&
              !page_data.at("has_more").get<bool>() &&
              page_data.at("next_cursor").is<picojson::null>(),
          "Calendar list endpoint must preserve snapshot and terminal paging shape");
}

void boundary_validation_test() {
  using excellent_calendar::boundary::api::calendar_list_day_items_v2;
  using excellent_calendar::boundary::api::calendar_range_summary_v2;
  require(failure_code(calendar_range_summary_v2("[]")) ==
              "CONTRACT_VALIDATION_FAILED",
          "non-object JSON must fail Contract validation");
  require(failure_code(calendar_range_summary_v2(
              R"({"range_start_date":"2026-09-01","range_end_date":"2026-09-02","timezone":"Asia/Shanghai","version":2})")) ==
              "CONTRACT_VALIDATION_FAILED",
          "extra or request-version field must be rejected");
  require(failure_code(calendar_range_summary_v2(
              R"({"range_start_date":null,"range_end_date":"2026-09-02","timezone":"Asia/Shanghai"})")) ==
              "CONTRACT_VALIDATION_FAILED",
          "explicit null required date must be rejected");
  require(failure_code(calendar_list_day_items_v2(
              R"({"date":"2026-09-01","timezone":"Asia/Shanghai","section":"unknown","snapshot_token":"calsnap1.aaaaaaaaaaaaaaaaaaaa","cursor":null,"page_size":20})")) ==
              "CONTRACT_VALIDATION_FAILED",
          "unknown section must be rejected at Boundary");
  require(failure_code(calendar_list_day_items_v2(
              R"({"date":"2026-09-01","timezone":"Asia/Shanghai","section":"event","snapshot_token":"calsnap1.aaaaaaaaaaaaaaaaaaaa","cursor":null,"page_size":20.5})")) ==
              "CONTRACT_VALIDATION_FAILED",
          "non-integer page size must be rejected at Boundary");
}

}  // namespace

int main() {
  try {
    event_projection_and_snapshot_clock_test();
    cross_year_event_projection_test();
    recurring_overlap_dst_and_state_test();
    completed_recurring_series_cutoff_test();
    summary_conservation_and_range_boundaries_test();
    habit_and_anniversary_projection_test();
    keyset_pagination_test();
    pagination_cardinality_boundaries_test();
    real_sqlite_snapshot_and_plan_test();
    real_sqlite_recovery_batch_reference_test();
    real_sqlite_anniversary_recovery_batch_reference_test();
    real_runtime_endpoint_test();
    boundary_validation_test();
    real_sqlite_performance_test();
    std::cout << "calendar_view_query_tests: PASS\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "calendar_view_query_tests: FAIL: " << error.what() << '\n';
    return 1;
  }
}
