#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/repository/calendar_query_repository.hpp"

namespace excellent_calendar::application {

enum class CalendarSection { event, habit, anniversary };

std::string calendar_section_to_string(CalendarSection section);

struct CalendarRangeSummaryQuery {
  domain::LocalDate range_start_date;
  domain::LocalDate range_end_date;
  std::string timezone;
};

struct CalendarRangeDaySummary {
  domain::LocalDate date;
  bool has_open_event = false;
  bool has_pending_habit = false;
  bool has_anniversary = false;
};

struct CalendarRangeSummary {
  domain::LocalDate range_start_date;
  domain::LocalDate range_end_date;
  std::string timezone;
  std::string snapshot_token;
  std::vector<CalendarRangeDaySummary> days;
};

struct CalendarEventItem {
  std::string event_id;
  std::string title;
  bool is_all_day = false;
  bool is_recurring = false;
  std::optional<int> recurrence_revision;
  std::optional<std::string> occurrence_key;
  std::optional<std::string> occurrence_start_at;
  std::optional<domain::LocalDate> occurrence_start_date;
  std::optional<std::string> start_at;
  std::optional<std::string> end_at;
  std::optional<domain::LocalDate> start_date;
  std::optional<domain::LocalDate> end_date;
  std::string day_display;
  std::optional<std::string> display_local_time;
  std::string status;
  bool has_active_reminder = false;
};

struct CalendarHabitItem {
  std::string habit_id;
  domain::LocalDate date;
  std::string title;
  std::string status;
  std::optional<std::string> check_in_id;
  std::optional<std::int64_t> completed_count_hundredths;
  std::optional<std::int64_t> target_count_hundredths;
  std::optional<std::string> unit;
  bool has_active_reminder = false;
};

struct CalendarAnniversaryItem {
  std::string anniversary_id;
  std::string occurrence_key;
  domain::LocalDate occurrence_date;
  domain::LocalDate source_date;
  std::string title;
  bool is_repeating = false;
  int years_elapsed = 0;
  std::optional<std::string> importance;
  bool has_active_reminder = false;
};

using CalendarDayItem =
    std::variant<CalendarEventItem, CalendarHabitItem,
                 CalendarAnniversaryItem>;

struct CalendarListDayItemsQuery {
  domain::LocalDate date;
  std::string timezone;
  CalendarSection section = CalendarSection::event;
  std::string snapshot_token;
  std::optional<std::string> cursor;
  int page_size = 20;
};

struct CalendarDayItemPage {
  domain::LocalDate date;
  std::string timezone;
  CalendarSection section = CalendarSection::event;
  std::string snapshot_token;
  int page_size = 20;
  std::vector<CalendarDayItem> items;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

class CalendarViewQueryService {
 public:
  using ClockFn = std::function<std::string()>;

  CalendarViewQueryService(
      std::shared_ptr<repository::CalendarQueryRepository> repository,
      std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
      std::shared_ptr<RecurrenceService> recurrence_service,
      ClockFn clock);

  common::Result<CalendarRangeSummary> range_summary(
      const CalendarRangeSummaryQuery& query) const;
  common::Result<CalendarDayItemPage> list_day_items(
      const CalendarListDayItemsQuery& query) const;

 private:
  std::shared_ptr<repository::CalendarQueryRepository> repository_;
  std::shared_ptr<domain::LocalTimeResolver> local_time_resolver_;
  std::shared_ptr<RecurrenceService> recurrence_service_;
  ClockFn clock_;
};

}  // namespace excellent_calendar::application
