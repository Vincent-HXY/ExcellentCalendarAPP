#include "excellent_calendar/boundary/contract/native_result.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

/** Error.details 是 map<string,string>，这里转换成 JSON object。 */
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

/** 给所有 NativeResult 统一补 contract_version 并序列化。 */
std::string serialize_native_result(picojson::object object) {
  object["contract_version"] = picojson::value(1.0);
  return picojson::value(std::move(object)).serialize();
}

}  // namespace

/** 成功响应：ok=true，data 为业务数据，error 为 null。 */
std::string native_success_json(const picojson::value& data, const std::string& request_id) {
  picojson::object object;
  object["ok"] = picojson::value(true);
  object["data"] = data;
  object["error"] = picojson::value();
  object["request_id"] = picojson::value(request_id);
  return serialize_native_result(std::move(object));
}

/** 失败响应：ok=false，data 为 null，error 包含 code/message/details/retryable。 */
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
