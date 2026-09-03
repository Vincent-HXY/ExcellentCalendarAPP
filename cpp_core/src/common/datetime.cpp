#include "excellent_calendar/common/datetime.hpp"

#include <cctype>
#include <iomanip>
#include <sstream>
#include <string>

namespace excellent_calendar::common {
namespace {

/** 从指定位置读取一个数字字符。 */
bool read_digit(std::string_view value, std::size_t index, int& digit) {
  if (index >= value.size() || !std::isdigit(static_cast<unsigned char>(value[index]))) {
    return false;
  }
  digit = value[index] - '0';
  return true;
}

/** 从固定宽度位置读取整数，例如年 4 位、月 2 位。 */
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

/** 闰年规则：四年一闰，百年不闰，四百年再闰。 */
bool is_leap_year(int year) {
  return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
}

/** 返回指定年月的天数。 */
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

struct CivilDate {
  int year = 0;
  int month = 0;
  int day = 0;
};

CivilDate civil_from_days(std::int64_t days) {
  days += 719468;
  const auto era = (days >= 0 ? days : days - 146096) / 146097;
  const auto doe = static_cast<unsigned>(days - era * 146097);
  const auto yoe =
      (doe - doe / 1460U + doe / 36524U - doe / 146096U) / 365U;
  int year = static_cast<int>(yoe) + static_cast<int>(era) * 400;
  const auto doy = doe - (365U * yoe + yoe / 4U - yoe / 100U);
  const auto mp = (5U * doy + 2U) / 153U;
  const auto day = doy - (153U * mp + 2U) / 5U + 1U;
  const auto month = mp + (mp < 10U ? 3U : static_cast<unsigned>(-9));
  year += month <= 2U;
  return {year, static_cast<int>(month), static_cast<int>(day)};
}

}  // namespace

/** 手写解析项目接受的 UTC ISO 8601 格式，避免依赖平台不一致的时间解析函数。 */
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

  // 支持小数秒，但当前只用秒级 epoch，因此小数部分只校验格式、不参与计算。
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

  // 本项目要求 UTC 时间必须以 Z 结尾，不接受本地时区或 +08:00 这类偏移。
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

/** 是否能成功解析为项目接受的 UTC ISO 8601 时间。 */
bool is_iso8601_utc_datetime(std::string_view value) {
  return parse_iso8601_utc_epoch_seconds(value).has_value();
}

/** 把 epoch 秒格式化为 UTC ISO 8601。 */
std::string format_epoch_seconds_utc_iso8601(std::int64_t epoch_seconds) {
  auto days = epoch_seconds / 86400;
  auto seconds_of_day = epoch_seconds % 86400;
  if (seconds_of_day < 0) {
    seconds_of_day += 86400;
    --days;
  }
  const auto date = civil_from_days(days);
  const auto hour = static_cast<int>(seconds_of_day / 3600);
  const auto minute = static_cast<int>((seconds_of_day % 3600) / 60);
  const auto second = static_cast<int>(seconds_of_day % 60);
  std::ostringstream output;
  output << std::setfill('0') << std::setw(4) << date.year << '-'
         << std::setw(2) << date.month << '-' << std::setw(2) << date.day
         << 'T' << std::setw(2) << hour << ':' << std::setw(2) << minute
         << ':' << std::setw(2) << second << 'Z';
  return output.str();
}

}  // namespace excellent_calendar::common
