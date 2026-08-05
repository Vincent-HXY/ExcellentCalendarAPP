#pragma once

#include <string>
#include <string_view>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::domain {

struct LocalDate {
  int year = 0;
  int month = 0;
  int day = 0;
};

struct LocalDateTime {
  int year = 0;
  int month = 0;
  int day = 0;
  int hour = 0;
  int minute = 0;
  int second = 0;
};

enum class LocalDateTimeResolution {
  exact,
  gap_shifted,
  fold_earlier,
};

struct ResolvedLocalDateTime {
  LocalDateTime requested_local_datetime;
  LocalDateTime resolved_local_datetime;
  std::string utc_instant;
  LocalDateTimeResolution resolution = LocalDateTimeResolution::exact;
};

bool operator==(const LocalDate& left, const LocalDate& right);
bool operator<(const LocalDate& left, const LocalDate& right);
bool operator==(const LocalDateTime& left, const LocalDateTime& right);
bool operator<(const LocalDateTime& left, const LocalDateTime& right);

bool is_valid_local_date(const LocalDate& value);
bool is_valid_local_date_time(const LocalDateTime& value);
common::Result<LocalDate> parse_local_date(std::string_view value);
common::Result<LocalDateTime> parse_local_date_time(std::string_view value);
std::string format_local_date(const LocalDate& value);
std::string format_local_date_time(const LocalDateTime& value);
std::string local_date_time_resolution_to_string(LocalDateTimeResolution value);
LocalDate add_local_days(const LocalDate& value, int days);
LocalDate add_local_months_with_anchor(const LocalDate& value, int months, int anchor_day);
int local_days_between(const LocalDate& start, const LocalDate& end);
int iso_weekday(const LocalDate& value);

class LocalTimeResolver {
 public:
  virtual ~LocalTimeResolver() = default;

  virtual common::Result<common::Unit> validate_timezone(std::string_view timezone) const = 0;
  virtual common::Result<LocalDateTime> to_local(std::string_view utc_instant,
                                                std::string_view timezone) const = 0;
  virtual common::Result<ResolvedLocalDateTime> resolve_local_datetime(
      const LocalDateTime& local,
      std::string_view timezone) const = 0;
  virtual common::Result<std::string> to_utc(const LocalDateTime& local,
                                             std::string_view timezone) const = 0;
  virtual std::string tzdb_version() const = 0;
};

}  // namespace excellent_calendar::domain
