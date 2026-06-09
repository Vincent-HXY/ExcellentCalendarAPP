#pragma once

#include <string_view>

namespace excellent_calendar::domain {

/** 校验创建事件的数据来源是否属于协议允许值。 */
bool is_valid_create_event_source(std::string_view value);

}  // namespace excellent_calendar::domain
