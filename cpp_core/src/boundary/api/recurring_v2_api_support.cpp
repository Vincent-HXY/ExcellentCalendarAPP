#include "recurring_v2_api_internal.hpp"

#include <cmath>
#include <exception>
#include <limits>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/id_generator.hpp"

namespace excellent_calendar::boundary::api::detail {

common::Error contract_error(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

common::Result<picojson::object> parse_object(std::string_view request_json) {
  picojson::value value;
  const auto error = picojson::parse(value, std::string(request_json));
  if (!error.empty() || !value.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        contract_error("json", "request must be a valid JSON object"));
  }
  return common::Result<picojson::object>::success(value.get<picojson::object>());
}

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  return found == object.end() ? nullptr : &found->second;
}

common::Result<common::Unit> reject_unknown(
    const picojson::object& object,
    const std::set<std::string>& allowed,
    const std::string& parent) {
  for (const auto& [key, _] : object) {
    if (allowed.count(key) == 0U) {
      return common::Result<common::Unit>::failure(
          contract_error(parent + "." + key, "unknown field"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::string> require_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool nonempty) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<std::string>() ||
      (nonempty && value->get<std::string>().empty())) {
    return common::Result<std::string>::failure(
        contract_error(parent + "." + key, "string field is missing or invalid"));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<bool> require_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<bool>()) {
    return common::Result<bool>::failure(
        contract_error(parent + "." + key, "boolean field is missing or invalid"));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<int> require_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<double>() ||
      std::floor(value->get<double>()) != value->get<double>() ||
      value->get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<int>::failure(
        contract_error(parent + "." + key, "integer field is missing or invalid"));
  }
  return common::Result<int>::success(static_cast<int>(value->get<double>()));
}

common::Result<std::optional<std::string>> nullable_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    if (required) {
      return common::Result<std::optional<std::string>>::failure(
          contract_error(parent + "." + key, "required nullable field is missing"));
    }
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key, "field must be string or null"));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<std::optional<int>> nullable_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    if (required) {
      return common::Result<std::optional<int>>::failure(
          contract_error(parent + "." + key, "required nullable field is missing"));
    }
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || std::floor(value->get<double>()) != value->get<double>() ||
      value->get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        contract_error(parent + "." + key, "field must be integer or null"));
  }
  return common::Result<std::optional<int>>::success(
      static_cast<int>(value->get<double>()));
}

common::Result<std::optional<bool>> nullable_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return required
               ? common::Result<std::optional<bool>>::failure(
                     contract_error(parent + "." + key, "required nullable field is missing"))
               : common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (!value->is<bool>()) {
    return common::Result<std::optional<bool>>::failure(
        contract_error(parent + "." + key, "field must be boolean or null"));
  }
  return common::Result<std::optional<bool>>::success(value->get<bool>());
}

common::Result<std::vector<std::string>> string_array(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required,
    bool require_unique) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return required
               ? common::Result<std::vector<std::string>>::failure(
                     contract_error(parent + "." + key, "required array is missing"))
               : common::Result<std::vector<std::string>>::success({});
  }
  if (!value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + "." + key, "field must be an array"));
  }
  std::vector<std::string> result;
  std::set<std::string> unique;
  for (const auto& item : value->get<picojson::array>()) {
    if (!item.is<std::string>() ||
        (require_unique && !unique.insert(item.get<std::string>()).second)) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(
              parent + "." + key,
              require_unique ? "array must contain unique strings"
                             : "array must contain strings"));
    }
    result.push_back(item.get<std::string>());
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

std::string respond_v2(const V2EndpointCallback& callback) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto result = callback();
    return result.ok()
               ? contract::native_success_json_v2(result.value(), request_id)
               : contract::native_failure_json_v2(result.error(), request_id);
  } catch (const std::exception& error) {
    return contract::native_failure_json_v2(internal_error(error.what()), request_id);
  } catch (...) {
    return contract::native_failure_json_v2(
        internal_error("unknown exception"), request_id);
  }
}

}  // namespace excellent_calendar::boundary::api::detail
