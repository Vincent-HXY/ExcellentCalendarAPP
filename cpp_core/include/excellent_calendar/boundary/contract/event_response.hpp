#pragma once

#include <picojson/picojson.h>

#include "excellent_calendar/domain/event.hpp"

namespace excellent_calendar::boundary::contract {

/** 把领域 Event 转成对外返回的 JSON 对象。 */
picojson::value event_response_to_json(const domain::Event& event);

}  // namespace excellent_calendar::boundary::contract
