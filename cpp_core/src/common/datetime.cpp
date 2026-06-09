#include "excellent_calendar/common/datetime.hpp"

#include <cctype>
#include <string>

namespace excellent_calendar::common {
namespace {

bool read_digit(std::string_view value, std::size_t index, int& digit) {
  if (index >= value.size() || !std::isdigit(static_cast<unsigned char>(value[index]))) {
    return false;
  }
  digit = value[index] - '0';
  return true;
}

bool read_fixed_int(std::string_view value, std::size_t start, std::size_t count, int& result) {
  int number = 0;
  for (std::size_t offset = 0; offset < count; ++offset) {
    int digit = 0;
    if (!read_digit(value, start + offset, digit)) {
      return false;
    }
    number = number * 10 + digit;
  }
  result = number;
  return true;
}

bool is_leap_year(int year) {
  return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
}

int days_in_month(int year, int month) {
  static constexpr int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (month == 2 && is_leap_year(year)) {
    return 29;
  }
  return days[month - 1];
}

// Howard Hinnant's civil calendar conversion, returning days since 1970-01-01.
std::int64_t days_from_civil(int year, unsigned month, unsigned day) {
  year -= month <= 2;
  const int era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(year - era * 400);
  const unsigned doy =
      (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return static_cast<std::int64_t>(era) * 146097 + static_cast<std::int64_t>(doe) - 719468;
}

}  // namespace

std::optional<std::int64_t> parse_iso8601_utc_epoch_seconds(std::string_view value) {
  if (value.size() < 20) {
    return std::nullopt;
  }
  if (value[4] != '-' || value[7] != '-' || value[10] != 'T' ||
      value[13] != ':' || value[16] != ':') {
    return std::nullopt;
  }

  int year = 0;
  int month = 0;
  int day = 0;
  int hour = 0;
  int minute = 0;
  int second = 0;
  if (!read_fixed_int(value, 0, 4, year) ||
      !read_fixed_int(value, 5, 2, month) ||
      !read_fixed_int(value, 8, 2, day) ||
      !read_fixed_int(value, 11, 2, hour) ||
      !read_fixed_int(value, 14, 2, minute) ||
      !read_fixed_int(value, 17, 2, second)) {
    return std::nullopt;
  }

  std::size_t cursor = 19;
  if (cursor < value.size() && value[cursor] == '.') {
    ++cursor;
    const auto fraction_start = cursor;
    while (cursor < value.size() && std::isdigit(static_cast<unsigned char>(value[cursor]))) {
      ++cursor;
    }
    if (cursor == fraction_start) {
      return std::nullopt;
    }
  }

  if (cursor + 1 != value.size() || value[cursor] != 'Z') {
    return std::nullopt;
  }
  if (month < 1 || month > 12) {
    return std::nullopt;
  }
  if (day < 1 || day > days_in_month(year, month)) {
    return std::nullopt;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 60) {
    return std::nullopt;
  }

  return days_from_civil(year, static_cast<unsigned>(month), static_cast<unsigned>(day)) * 86400 +
         static_cast<std::int64_t>(hour) * 3600 +
         static_cast<std::int64_t>(minute) * 60 +
         static_cast<std::int64_t>(second);
}

bool is_iso8601_utc_datetime(std::string_view value) {
  return parse_iso8601_utc_epoch_seconds(value).has_value();
}

}  // namespace excellent_calendar::common
