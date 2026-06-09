#pragma once

#include <string>

namespace excellent_calendar::common {

/** 返回当前 UTC 时间，格式为 ISO 8601：YYYY-MM-DDTHH:MM:SSZ。 */
std::string utc_now_iso8601();

}  // namespace excellent_calendar::common
