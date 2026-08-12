#pragma once

#include <functional>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::boundary::api::detail {

using V2EndpointCallback = std::function<common::Result<picojson::value>()>;

common::Error contract_error(std::string field, std::string reason);

common::Result<picojson::object> parse_object(std::string_view request_json);

const picojson::value* field(
    const picojson::object& object,
    const std::string& key);

common::Result<common::Unit> reject_unknown(
    const picojson::object& object,
    const std::set<std::string>& allowed,
    const std::string& parent);

common::Result<std::string> require_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool nonempty = true);

common::Result<bool> require_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent);

common::Result<int> require_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent);

common::Result<std::optional<std::string>> nullable_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required);

common::Result<std::optional<int>> nullable_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required);

common::Result<std::optional<bool>> nullable_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required);

common::Result<std::vector<std::string>> string_array(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required = false,
    bool require_unique = false);

std::string respond_v2(const V2EndpointCallback& callback);

}  // namespace excellent_calendar::boundary::api::detail
