#include "excellent_calendar/boundary/api/notification_api.hpp"

#include <exception>
#include <map>
#include <set>

#include <picojson/picojson.h>

#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/create_notification_request.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/boundary/contract/notification_response.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"

namespace excellent_calendar::boundary::api {
namespace {

common::Error contract_error(std::string message, std::string field = "") {
  std::map<std::string, std::string> details;
  if (!field.empty()) details["field"] = std::move(field);
  return common::make_error("CONTRACT_VALIDATION_FAILED", std::move(message), std::move(details));
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  return found == object.end() ? nullptr : &found->second;
}

common::Result<std::string> required_string(const picojson::object& object,
                                            const std::string& key) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<std::string>() || value->get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        contract_error("CreateNotificationRequest." + key + " must be a non-empty string.",
                       "CreateNotificationRequest." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> optional_string(
    const picojson::object& object,
    const std::string& key) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error("CreateNotificationRequest." + key + " must be a string or null.",
                       "CreateNotificationRequest." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<contract::CreateNotificationRequest> parse_request(std::string_view json) {
  picojson::value value;
  const auto error = picojson::parse(value, std::string(json));
  if (!error.empty() || !value.is<picojson::object>()) {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("Request JSON must be a valid object.", "json"));
  }
  const auto& object = value.get<picojson::object>();
  static const std::set<std::string> allowed{
      "reminder_id", "target_type", "target_id", "method", "title", "body",
      "planned_at", "sent_at", "status", "failure_reason"};
  for (const auto& [key, _] : object) {
    if (allowed.find(key) == allowed.end()) {
      return common::Result<contract::CreateNotificationRequest>::failure(
          contract_error("CreateNotificationRequest contains an unknown field.",
                         "CreateNotificationRequest." + key));
    }
  }
  auto reminder_id = required_string(object, "reminder_id");
  auto target_type = required_string(object, "target_type");
  auto target_id = required_string(object, "target_id");
  auto method = required_string(object, "method");
  auto title = required_string(object, "title");
  auto body = optional_string(object, "body");
  auto planned_at = required_string(object, "planned_at");
  auto sent_at = optional_string(object, "sent_at");
  auto status = required_string(object, "status");
  auto failure_reason = optional_string(object, "failure_reason");
  if (!reminder_id.ok()) return common::Result<contract::CreateNotificationRequest>::failure(reminder_id.error());
  if (!target_type.ok()) return common::Result<contract::CreateNotificationRequest>::failure(target_type.error());
  if (!target_id.ok()) return common::Result<contract::CreateNotificationRequest>::failure(target_id.error());
  if (!method.ok()) return common::Result<contract::CreateNotificationRequest>::failure(method.error());
  if (!title.ok()) return common::Result<contract::CreateNotificationRequest>::failure(title.error());
  if (!body.ok()) return common::Result<contract::CreateNotificationRequest>::failure(body.error());
  if (!planned_at.ok()) return common::Result<contract::CreateNotificationRequest>::failure(planned_at.error());
  if (!sent_at.ok()) return common::Result<contract::CreateNotificationRequest>::failure(sent_at.error());
  if (!status.ok()) return common::Result<contract::CreateNotificationRequest>::failure(status.error());
  if (!failure_reason.ok()) return common::Result<contract::CreateNotificationRequest>::failure(failure_reason.error());
  if (target_type.value() != "event" && target_type.value() != "habit" &&
      target_type.value() != "anniversary") {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("CreateNotificationRequest.target_type is invalid.",
                       "CreateNotificationRequest.target_type"));
  }
  if (method.value() != "popup") {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("CreateNotificationRequest.method must be popup.",
                       "CreateNotificationRequest.method"));
  }
  if (status.value() != "sent" && status.value() != "failed") {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("CreateNotificationRequest.status is invalid.",
                       "CreateNotificationRequest.status"));
  }
  if (!common::is_iso8601_utc_datetime(planned_at.value()) ||
      (sent_at.value().has_value() && !common::is_iso8601_utc_datetime(*sent_at.value()))) {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("CreateNotificationRequest contains an invalid UTC date-time.",
                       "CreateNotificationRequest.planned_at"));
  }
  if (status.value() == "sent" && (!sent_at.value().has_value() || failure_reason.value().has_value())) {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("Sent notification fields are inconsistent.",
                       "CreateNotificationRequest.sent_at"));
  }
  if (status.value() == "failed" &&
      (!failure_reason.value().has_value() || failure_reason.value()->empty())) {
    return common::Result<contract::CreateNotificationRequest>::failure(
        contract_error("Failed notification requires failure_reason.",
                       "CreateNotificationRequest.failure_reason"));
  }

  contract::CreateNotificationRequest request;
  request.reminder_id = reminder_id.value();
  request.target_type = target_type.value();
  request.target_id = target_id.value();
  request.method = method.value();
  request.title = title.value();
  request.body = body.value();
  request.planned_at = planned_at.value();
  request.sent_at = sent_at.value();
  request.status = status.value();
  request.failure_reason = failure_reason.value();
  return common::Result<contract::CreateNotificationRequest>::success(std::move(request));
}

}  // namespace

std::string create_notification(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_request(request_json);
    if (!parsed.ok()) return contract::native_failure_json(parsed.error(), request_id);
    const auto service = current_notification_service();
    if (!service) {
      return contract::native_failure_json(
          storage_not_initialized_error("notification.create"), request_id);
    }
    application::CreateNotificationCommand command;
    command.reminder_id = parsed.value().reminder_id;
    command.target_type = parsed.value().target_type;
    command.target_id = parsed.value().target_id;
    command.method = parsed.value().method;
    command.title = parsed.value().title;
    command.body = parsed.value().body;
    command.planned_at = parsed.value().planned_at;
    command.sent_at = parsed.value().sent_at;
    command.status = parsed.value().status;
    command.failure_reason = parsed.value().failure_reason;
    auto created = service->create_notification(command);
    if (!created.ok()) return contract::native_failure_json(created.error(), request_id);
    return contract::native_success_json(
        contract::notification_response_to_json(
            contract::make_notification_response(created.value())),
        request_id);
  } catch (const std::exception& error) {
    return contract::native_failure_json(internal_error(error.what()), request_id);
  } catch (...) {
    return contract::native_failure_json(internal_error("unknown exception"), request_id);
  }
}

}  // namespace excellent_calendar::boundary::api
