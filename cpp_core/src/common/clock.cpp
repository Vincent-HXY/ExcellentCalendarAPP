#include "excellent_calendar/common/clock.hpp"

#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace excellent_calendar::common {

std::string utc_now_iso8601() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t time = std::chrono::system_clock::to_time_t(now);

  std::tm utc{};
#if defined(_WIN32)
  gmtime_s(&utc, &time);
#else
  gmtime_r(&time, &utc);
#endif

  std::ostringstream output;
  output << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
  return output.str();
}

}  // namespace excellent_calendar::common
