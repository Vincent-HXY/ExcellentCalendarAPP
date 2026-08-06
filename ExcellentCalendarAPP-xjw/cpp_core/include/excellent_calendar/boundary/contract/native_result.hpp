#pragma once

#include <string>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::boundary::contract {

/** 构造成功 NativeResult JSON 字符串：ok=true、data 有值、error=null。 */
std::string native_success_json(const picojson::value& data, const std::string& request_id);

/** 构造失败 NativeResult JSON 字符串：ok=false、data=null、error 有值。 */
std::string native_failure_json(const common::Error& error, const std::string& request_id);

}  // namespace excellent_calendar::boundary::contract
