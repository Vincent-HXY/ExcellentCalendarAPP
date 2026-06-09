#pragma once

#include "excellent_calendar/application/event_service.hpp"

namespace excellent_calendar::boundary::contract {

/**
 * 搜索请求目前直接复用 application::EventQuery。
 *
 * `using` 是类型别名，不会创建新类型；这样 boundary 和 application 暂时共享同一份查询结构。
 */
using SearchEventRequest = application::EventQuery;

}  // namespace excellent_calendar::boundary::contract
