#include "excellent_calendar/boundary/contract/native_result.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value details_to_json(const std::map<std::string, std::string>& details) {
  if (details.empty()) {
    return picojson::value(picojson::object{});
  }
  picojson::object object;
  for (const auto& [key, value] : details) {
    object[key] = picojson::value(value);
  }
  return picojson::value(object);
}

std::string serialize_native_result(picojson::object object) {
  object["contract_version"] = picojson::value(1.0);
  return picojson::value(std::move(object)).serialize();
}

}  // namespace

std::string native_success_json(const picojson::value& data, const std::string& request_id) {
  picojson::object object;
  object["ok"] = picojson::value(true);
  object["data"] = data;
  object["error"] = picojson::value();
  object["request_id"] = picojson::value(request_id);
  return serialize_native_result(std::move(object));
}

std::string native_failure_json(const common::Error& error, const std::string& request_id) {
  picojson::object error_object;
  error_object["code"] = picojson::value(error.code);
  error_object["message"] = picojson::value(error.message);
  error_object["details"] = details_to_json(error.details);
  error_object["retryable"] = picojson::value(error.retryable);

  picojson::object object;
  object["ok"] = picojson::value(false);
  object["data"] = picojson::value();
  object["error"] = picojson::value(std::move(error_object));
  object["request_id"] = picojson::value(request_id);
  return serialize_native_result(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
