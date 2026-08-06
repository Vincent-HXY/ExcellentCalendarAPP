#include "excellent_calendar/common/clock.hpp"

#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace excellent_calendar::common {

/** 获取当前系统时间并格式化为 UTC ISO 8601 字符串。 */
std::string utc_now_iso8601() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t time = std::chrono::system_clock::to_time_t(now);

  std::tm utc{};
#if defined(_WIN32)
  // Windows 使用 gmtime_s，POSIX 使用 gmtime_r；两者都是线程安全版本。
  gmtime_s(&utc, &time);
#else
  gmtime_r(&time, &utc);
#endif

  std::ostringstream output;
  output << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
  return output.str();
}

}  // namespace excellent_calendar::common
