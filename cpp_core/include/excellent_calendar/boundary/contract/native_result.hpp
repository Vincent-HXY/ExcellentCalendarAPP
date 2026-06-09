#pragma once

#include <string>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::boundary::contract {

std::string native_success_json(const picojson::value& data, const std::string& request_id);

std::string native_failure_json(const common::Error& error, const std::string& request_id);

}  // namespace excellent_calendar::boundary::contract
