#pragma once

#include <string>

namespace excellent_calendar::common {

/** 生成 UUID v4 字符串，用于 request_id 和 event id。 */
std::string generate_uuid_v4();

}  // namespace excellent_calendar::common
