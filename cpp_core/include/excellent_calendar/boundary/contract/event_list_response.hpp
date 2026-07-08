#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/application/event_service.hpp"

namespace excellent_calendar::boundary::contract {

/** 把搜索结果转成 JSON：包含 items 数组和 pagination 对象。 */
picojson::value event_list_response_to_json(const application::EventSearchResult& result);

}  // namespace excellent_calendar::boundary::contract
