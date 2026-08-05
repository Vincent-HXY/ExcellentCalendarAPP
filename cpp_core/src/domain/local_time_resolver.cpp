#include "excellent_calendar/domain/local_time_resolver.hpp"

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <tuple>

namespace excellent_calendar::domain {
namespace {

bool is_leap_year(int year) {
  return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

int days_in_month(int year, int month) {
  static constexpr int values[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (month == 2 && is_leap_year(year)) return 29;
  return values[month - 1];
}

std::int64_t days_from_civil(int year, unsigned month, unsigned day) {
  year -= month <= 2;
  const int era = (year >= 0 ? year : year - 399) / 400;
  const auto yoe = static_cast<unsigned>(year - era * 400);
  const auto doy = (153U * (month + (month > 2 ? -3 : 9)) + 2U) / 5U + day - 1U;
  const auto doe = yoe * 365U + yoe / 4U - yoe / 100U + doy;
  return static_cast<std::int64_t>(era) * 146097 + static_cast<std::int64_t>(doe) - 719468;
}

LocalDate civil_from_days(std::int64_t days) {
  days += 719468;
  const auto era = (days >= 0 ? days : days - 146096) / 146097;
  const auto doe = static_cast<unsigned>(days - era * 146097);
  const auto yoe = (doe - doe / 1460U + doe / 36524U - doe / 146096U) / 365U;
  int year = static_cast<int>(yoe) + static_cast<int>(era) * 400;
  const auto doy = doe - (365U * yoe + yoe / 4U - yoe / 100U);
  const auto mp = (5U * doy + 2U) / 153U;
  const auto day = doy - (153U * mp + 2U) / 5U + 1U;
  const auto month = mp + (mp < 10U ? 3U : static_cast<unsigned>(-9));
  year += month <= 2U;
  return LocalDate{year, static_cast<int>(month), static_cast<int>(day)};
}

bool parse_fixed(std::string_view value, std::size_t start, std::size_t count, int& output) {
  output = 0;
  if (start + count > value.size()) return false;
  for (std::size_t index = 0; index < count; ++index) {
    const char digit = value[start + index];
    if (digit < '0' || digit > '9') return false;
    output = output * 10 + digit - '0';
  }
  return true;
}

}  // namespace

bool operator==(const LocalDate& left, const LocalDate& right) {
  return std::tie(left.year, left.month, left.day) ==
         std::tie(right.year, right.month, right.day);
}

bool operator<(const LocalDate& left, const LocalDate& right) {
  return std::tie(left.year, left.month, left.day) <
         std::tie(right.year, right.month, right.day);
}

bool operator==(const LocalDateTime& left, const LocalDateTime& right) {
  return std::tie(left.year, left.month, left.day, left.hour, left.minute, left.second) ==
         std::tie(right.year, right.month, right.day, right.hour, right.minute, right.second);
}

bool operator<(const LocalDateTime& left, const LocalDateTime& right) {
  return std::tie(left.year, left.month, left.day, left.hour, left.minute, left.second) <
         std::tie(right.year, right.month, right.day, right.hour, right.minute, right.second);
}

bool is_valid_local_date(const LocalDate& value) {
  return value.year >= 1 && value.year <= 9999 && value.month >= 1 && value.month <= 12 &&
         value.day >= 1 && value.day <= days_in_month(value.year, value.month);
}

bool is_valid_local_date_time(const LocalDateTime& value) {
  return is_valid_local_date(LocalDate{value.year, value.month, value.day}) &&
         value.hour >= 0 && value.hour <= 23 && value.minute >= 0 && value.minute <= 59 &&
         value.second >= 0 && value.second <= 59;
}

common::Result<LocalDate> parse_local_date(std::string_view value) {
  LocalDate result;
  if (value.size() != 10U || value[4] != '-' || value[7] != '-' ||
      !parse_fixed(value, 0, 4, result.year) || !parse_fixed(value, 5, 2, result.month) ||
      !parse_fixed(value, 8, 2, result.day) || !is_valid_local_date(result)) {
    return common::Result<LocalDate>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Local date is invalid", {{"field", "date"}}));
  }
  return common::Result<LocalDate>::success(result);
}

common::Result<LocalDateTime> parse_local_date_time(std::string_view value) {
  LocalDateTime result;
  if (value.size() != 19U || value[4] != '-' || value[7] != '-' || value[10] != 'T' ||
      value[13] != ':' || value[16] != ':' ||
      !parse_fixed(value, 0, 4, result.year) ||
      !parse_fixed(value, 5, 2, result.month) ||
      !parse_fixed(value, 8, 2, result.day) ||
      !parse_fixed(value, 11, 2, result.hour) ||
      !parse_fixed(value, 14, 2, result.minute) ||
      !parse_fixed(value, 17, 2, result.second) || !is_valid_local_date_time(result)) {
    return common::Result<LocalDateTime>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "Local date-time is invalid",
        {{"field", "local_datetime"}}));
  }
  return common::Result<LocalDateTime>::success(result);
}

std::string format_local_date(const LocalDate& value) {
  std::ostringstream output;
  output << std::setfill('0') << std::setw(4) << value.year << '-' << std::setw(2)
         << value.month << '-' << std::setw(2) << value.day;
  return output.str();
}

std::string format_local_date_time(const LocalDateTime& value) {
  std::ostringstream output;
  output << std::setfill('0') << std::setw(4) << value.year << '-' << std::setw(2)
         << value.month << '-' << std::setw(2) << value.day << 'T' << std::setw(2)
         << value.hour << ':' << std::setw(2) << value.minute << ':' << std::setw(2)
         << value.second;
  return output.str();
}

std::string local_date_time_resolution_to_string(LocalDateTimeResolution value) {
  switch (value) {
    case LocalDateTimeResolution::exact:
      return "exact";
    case LocalDateTimeResolution::gap_shifted:
      return "gap_shifted";
    case LocalDateTimeResolution::fold_earlier:
      return "fold_earlier";
  }
  return "exact";
}

LocalDate add_local_days(const LocalDate& value, int days) {
  return civil_from_days(days_from_civil(
      value.year, static_cast<unsigned>(value.month), static_cast<unsigned>(value.day)) + days);
}

LocalDate add_local_months_with_anchor(const LocalDate& value, int months, int anchor_day) {
  const auto absolute_month = static_cast<std::int64_t>(value.year) * 12 + value.month - 1 + months;
  const auto year = static_cast<int>(absolute_month / 12);
  const auto month = static_cast<int>(absolute_month % 12) + 1;
  return LocalDate{year, month, std::min(anchor_day, days_in_month(year, month))};
}

int local_days_between(const LocalDate& start, const LocalDate& end) {
  return static_cast<int>(days_from_civil(
                              end.year,
                              static_cast<unsigned>(end.month),
                              static_cast<unsigned>(end.day)) -
                          days_from_civil(
                              start.year,
                              static_cast<unsigned>(start.month),
                              static_cast<unsigned>(start.day)));
}

int iso_weekday(const LocalDate& value) {
  auto weekday = static_cast<int>((days_from_civil(
                                       value.year,
                                       static_cast<unsigned>(value.month),
                                       static_cast<unsigned>(value.day)) +
                                   3) %
                                  7);
  if (weekday < 0) weekday += 7;
  return weekday + 1;
}

}  // namespace excellent_calendar::domain
