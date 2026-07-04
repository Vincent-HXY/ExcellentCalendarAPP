#include "excellent_calendar/boundary/api/reminder_api.hpp"

#include <cmath>
#include <exception>
#include <limits>
#include <map>
#include <set>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/consume_reminder_after_delivery_request.hpp"
#include "excellent_calendar/boundary/contract/consume_reminder_after_delivery_response.hpp"
#include "excellent_calendar/boundary/contract/get_reminder_request.hpp"
#include "excellent_calendar/boundary/contract/list_schedulable_reminders_request.hpp"
#include "excellent_calendar/boundary/contract/mark_reminder_failed_request.hpp"
#include "excellent_calendar/boundary/contract/mark_reminder_scheduled_request.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/boundary/contract/reminder_list_response.hpp"
#include "excellent_calendar/boundary/contract/reminder_response.hpp"
#include "excellent_calendar/boundary/contract/schedulable_reminder_list_response.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::api {
namespace {

common::Error contract_error(std::string message, std::string field = "") {
  std::map<std::string, std::string> details;
  if (!field.empty()) {
    details["field"] = std::move(field);
  }
  return common::make_error("CONTRACT_VALIDATION_FAILED", std::move(message), std::move(details));
}

common::Error reminder_time_invalid(std::string field) {
  return common::make_error(
      "REMINDER_TIME_INVALID",
      "Reminder time is invalid",
      {{"field", std::move(field)}});
}

common::Error reminder_method_invalid(std::string field = "CreateReminderRequest.methods") {
  return common::make_error(
      "REMINDER_METHOD_INVALID",
      "Reminder method is invalid",
      {{"field", std::move(field)}});
}

common::Error search_query_invalid(std::string field, std::string message) {
  return common::make_error(
      "SEARCH_QUERY_INVALID",
      std::move(message),
      {{"field", std::move(field)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR",
      "Native internal error",
      {{"reason", std::move(reason)}});
}

common::Error feature_not_implemented(std::string feature) {
  return common::make_error(
      "FEATURE_NOT_IMPLEMENTED",
      "Feature is not implemented in native core yet",
      {{"feature", std::move(feature)}});
}

common::Result<picojson::object> parse_json_object(std::string_view request_json) {
  picojson::value value;
  const std::string error = picojson::parse(value, std::string(request_json));
  if (!error.empty()) {
    return common::Result<picojson::object>::failure(contract_error("Request JSON is malformed.", "json"));
  }
  if (!value.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(contract_error("Request JSON must be an object.", "json"));
  }
  return common::Result<picojson::object>::success(value.get<picojson::object>());
}

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return nullptr;
  }
  return &found->second;
}

bool has_unknown_field(const picojson::object& object, const std::set<std::string>& allowed, std::string& unknown) {
  for (const auto& [key, _] : object) {
    if (allowed.find(key) == allowed.end()) {
      unknown = key;
      return true;
    }
  }
  return false;
}

bool is_integer(double value) {
  return std::floor(value) == value;
}

common::Result<std::string> require_string(const picojson::object& object,
                                           const std::string& key,
                                           const std::string& parent,
                                           bool non_empty = false) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<std::string>::failure(contract_error(parent + "." + key + " is required.", parent + "." + key));
  }
  if (!value->is<std::string>() || (non_empty && value->get<std::string>().empty())) {
    return common::Result<std::string>::failure(
        contract_error(parent + "." + key + " must be a string.", parent + "." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> optional_string(const picojson::object& object,
                                                           const std::string& key,
                                                           const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key + " must be a string or null.", parent + "." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<bool> require_bool(const picojson::object& object,
                                  const std::string& key,
                                  const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<bool>::failure(contract_error(parent + "." + key + " is required.", parent + "." + key));
  }
  if (!value->is<bool>()) {
    return common::Result<bool>::failure(contract_error(parent + "." + key + " must be boolean.", parent + "." + key));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<std::optional<bool>> optional_bool(const picojson::object& object,
                                                  const std::string& key,
                                                  const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (!value->is<bool>()) {
    return common::Result<std::optional<bool>>::failure(
        contract_error(parent + "." + key + " must be boolean or null.", parent + "." + key));
  }
  return common::Result<std::optional<bool>>::success(value->get<bool>());
}

common::Result<std::optional<int>> optional_int(const picojson::object& object,
                                                const std::string& key,
                                                const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || !is_integer(value->get<double>())) {
    return common::Result<std::optional<int>>::failure(
        contract_error(parent + "." + key + " must be integer or null.", parent + "." + key));
  }
  const auto number = value->get<double>();
  if (number < static_cast<double>(std::numeric_limits<int>::lowest()) ||
      number > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        contract_error(parent + "." + key + " is out of range.", parent + "." + key));
  }
  return common::Result<std::optional<int>>::success(static_cast<int>(number));
}

common::Result<std::vector<std::string>> required_methods(const picojson::object& object,
                                                          const std::string& parent) {
  const auto* value = field(object, "methods");
  if (value == nullptr) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + ".methods is required.", parent + ".methods"));
  }
  if (!value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + ".methods must be an array.", parent + ".methods"));
  }
  const auto& array = value->get<picojson::array>();
  if (array.empty()) {
    return common::Result<std::vector<std::string>>::failure(reminder_method_invalid(parent + ".methods"));
  }

  std::set<std::string> seen;
  std::vector<std::string> result;
  result.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    if (!array[index].is<std::string>()) {
      return common::Result<std::vector<std::string>>::failure(reminder_method_invalid(parent + ".methods"));
    }
    const auto item = array[index].get<std::string>();
    if (!domain::is_valid_reminder_method(item) || !seen.insert(item).second) {
      return common::Result<std::vector<std::string>>::failure(reminder_method_invalid(parent + ".methods"));
    }
    result.push_back(item);
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

common::Result<std::vector<std::string>> optional_string_array(const picojson::object& object,
                                                               const std::string& key,
                                                               const std::string& parent,
                                                               bool (*validator)(std::string_view),
                                                               const std::string& invalid_code_field) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<std::vector<std::string>>::success({});
  }
  if (!value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + "." + key + " must be an array.", parent + "." + key));
  }
  std::vector<std::string> result;
  const auto& array = value->get<picojson::array>();
  result.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    if (!array[index].is<std::string>()) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + "." + key + " item must be string.", parent + "." + key));
    }
    const auto item = array[index].get<std::string>();
    if (!validator(item)) {
      if (invalid_code_field == "methods") {
        return common::Result<std::vector<std::string>>::failure(reminder_method_invalid(parent + "." + key));
      }
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + "." + key + " item has an unsupported value.", parent + "." + key));
    }
    result.push_back(item);
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

bool is_valid_sort_by(std::string_view value) {
  return value == "remind_at" ||
         value == "created_at" ||
         value == "updated_at" ||
         value == "status" ||
         value == "target_type";
}

bool is_valid_sort_direction(std::string_view value) {
  return value == "asc" || value == "desc";
}

common::Result<std::vector<std::string>> require_popup_methods(
    const picojson::object& object,
    const std::string& parent) {
  const auto* value = field(object, "supported_methods");
  if (value == nullptr || !value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + ".supported_methods must be an array.", parent + ".supported_methods"));
  }
  const auto& array = value->get<picojson::array>();
  if (array.empty()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + ".supported_methods must not be empty.", parent + ".supported_methods"));
  }
  std::set<std::string> seen;
  std::vector<std::string> methods;
  for (const auto& item : array) {
    if (!item.is<std::string>() || item.get<std::string>() != "popup" ||
        !seen.insert(item.get<std::string>()).second) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + ".supported_methods only accepts unique popup.",
                         parent + ".supported_methods"));
    }
    methods.push_back(item.get<std::string>());
  }
  return common::Result<std::vector<std::string>>::success(std::move(methods));
}

common::Result<contract::GetReminderRequest> parse_get_reminder_request(
    std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) return common::Result<contract::GetReminderRequest>::failure(parsed.error());
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::GetReminderRequest>::failure(
        contract_error("GetReminderRequest contains an unknown field.", "GetReminderRequest." + unknown));
  }
  auto id = require_string(object, "id", "GetReminderRequest", true);
  if (!id.ok()) return common::Result<contract::GetReminderRequest>::failure(id.error());
  return common::Result<contract::GetReminderRequest>::success({id.value()});
}

common::Result<contract::ListSchedulableRemindersRequest>
parse_list_schedulable_reminders_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "from_at", "to_at", "limit", "include_failed", "include_scheduled", "supported_methods"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(
        contract_error("ListSchedulableRemindersRequest contains an unknown field.",
                       "ListSchedulableRemindersRequest." + unknown));
  }
  auto from_at = require_string(object, "from_at", "ListSchedulableRemindersRequest", true);
  auto to_at = require_string(object, "to_at", "ListSchedulableRemindersRequest", true);
  if (!from_at.ok()) return common::Result<contract::ListSchedulableRemindersRequest>::failure(from_at.error());
  if (!to_at.ok()) return common::Result<contract::ListSchedulableRemindersRequest>::failure(to_at.error());
  if (!common::is_iso8601_utc_datetime(from_at.value())) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(
        reminder_time_invalid("ListSchedulableRemindersRequest.from_at"));
  }
  if (!common::is_iso8601_utc_datetime(to_at.value())) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(
        reminder_time_invalid("ListSchedulableRemindersRequest.to_at"));
  }
  auto methods = require_popup_methods(object, "ListSchedulableRemindersRequest");
  if (!methods.ok()) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(methods.error());
  }
  auto limit = optional_int(object, "limit", "ListSchedulableRemindersRequest");
  auto include_failed = optional_bool(object, "include_failed", "ListSchedulableRemindersRequest");
  auto include_scheduled = optional_bool(object, "include_scheduled", "ListSchedulableRemindersRequest");
  if (!limit.ok()) return common::Result<contract::ListSchedulableRemindersRequest>::failure(limit.error());
  if (!include_failed.ok()) return common::Result<contract::ListSchedulableRemindersRequest>::failure(include_failed.error());
  if (!include_scheduled.ok()) return common::Result<contract::ListSchedulableRemindersRequest>::failure(include_scheduled.error());
  if (limit.value().has_value() && (*limit.value() < 1 || *limit.value() > 500)) {
    return common::Result<contract::ListSchedulableRemindersRequest>::failure(
        contract_error("ListSchedulableRemindersRequest.limit is out of range.",
                       "ListSchedulableRemindersRequest.limit"));
  }
  contract::ListSchedulableRemindersRequest request;
  request.from_at = from_at.value();
  request.to_at = to_at.value();
  request.limit = limit.value().value_or(500);
  request.include_failed = include_failed.value().value_or(true);
  request.include_scheduled = include_scheduled.value().value_or(false);
  request.supported_methods = methods.value();
  return common::Result<contract::ListSchedulableRemindersRequest>::success(std::move(request));
}

common::Result<contract::ConsumeReminderAfterDeliveryRequest>
parse_consume_reminder_after_delivery_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "reminder_id", "method", "title", "body", "planned_at", "sent_at", "delete_after_sent"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(
        contract_error("ConsumeReminderAfterDeliveryRequest contains an unknown field.",
                       "ConsumeReminderAfterDeliveryRequest." + unknown));
  }
  auto reminder_id = require_string(object, "reminder_id", "ConsumeReminderAfterDeliveryRequest", true);
  auto method = require_string(object, "method", "ConsumeReminderAfterDeliveryRequest", true);
  auto title = require_string(object, "title", "ConsumeReminderAfterDeliveryRequest", true);
  auto body = optional_string(object, "body", "ConsumeReminderAfterDeliveryRequest");
  auto planned_at = require_string(object, "planned_at", "ConsumeReminderAfterDeliveryRequest", true);
  auto sent_at = require_string(object, "sent_at", "ConsumeReminderAfterDeliveryRequest", true);
  auto delete_after_sent = require_bool(object, "delete_after_sent", "ConsumeReminderAfterDeliveryRequest");
  if (!reminder_id.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(reminder_id.error());
  if (!method.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(method.error());
  if (!title.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(title.error());
  if (!body.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(body.error());
  if (!planned_at.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(planned_at.error());
  if (!sent_at.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(sent_at.error());
  if (!delete_after_sent.ok()) return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(delete_after_sent.error());
  if (method.value() != "popup") {
    return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(
        contract_error("ConsumeReminderAfterDeliveryRequest.method must be popup.",
                       "ConsumeReminderAfterDeliveryRequest.method"));
  }
  if (!common::is_iso8601_utc_datetime(planned_at.value()) ||
      !common::is_iso8601_utc_datetime(sent_at.value())) {
    return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(
        reminder_time_invalid("ConsumeReminderAfterDeliveryRequest.planned_at"));
  }
  if (!delete_after_sent.value()) {
    return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::failure(
        contract_error("ConsumeReminderAfterDeliveryRequest.delete_after_sent must be true.",
                       "ConsumeReminderAfterDeliveryRequest.delete_after_sent"));
  }
  contract::ConsumeReminderAfterDeliveryRequest request;
  request.reminder_id = reminder_id.value();
  request.method = method.value();
  request.title = title.value();
  request.body = body.value();
  request.planned_at = planned_at.value();
  request.sent_at = sent_at.value();
  request.delete_after_sent = delete_after_sent.value();
  return common::Result<contract::ConsumeReminderAfterDeliveryRequest>::success(std::move(request));
}

common::Result<application::CreateReminderCommand> parse_create_reminder_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CreateReminderCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "is_enabled", "source",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::CreateReminderCommand>::failure(
        contract_error("CreateReminderRequest contains an unknown field.", "CreateReminderRequest." + unknown));
  }

  auto target_type = require_string(object, "target_type", "CreateReminderRequest", true);
  if (!target_type.ok()) return common::Result<application::CreateReminderCommand>::failure(target_type.error());
  if (!domain::is_valid_reminder_target_type(target_type.value())) {
    return common::Result<application::CreateReminderCommand>::failure(
        contract_error("CreateReminderRequest.target_type has an unsupported enum value.", "CreateReminderRequest.target_type"));
  }
  auto target_id = require_string(object, "target_id", "CreateReminderRequest", true);
  if (!target_id.ok()) return common::Result<application::CreateReminderCommand>::failure(target_id.error());
  auto methods = required_methods(object, "CreateReminderRequest");
  if (!methods.ok()) return common::Result<application::CreateReminderCommand>::failure(methods.error());
  auto is_enabled = require_bool(object, "is_enabled", "CreateReminderRequest");
  if (!is_enabled.ok()) return common::Result<application::CreateReminderCommand>::failure(is_enabled.error());
  auto source = require_string(object, "source", "CreateReminderRequest", true);
  if (!source.ok()) return common::Result<application::CreateReminderCommand>::failure(source.error());
  if (!domain::is_valid_reminder_source(source.value())) {
    return common::Result<application::CreateReminderCommand>::failure(
        contract_error("CreateReminderRequest.source has an unsupported enum value.", "CreateReminderRequest.source"));
  }

  auto remind_at = optional_string(object, "remind_at", "CreateReminderRequest");
  if (!remind_at.ok()) return common::Result<application::CreateReminderCommand>::failure(remind_at.error());
  if (remind_at.value().has_value() && !common::is_iso8601_utc_datetime(*remind_at.value())) {
    return common::Result<application::CreateReminderCommand>::failure(reminder_time_invalid("CreateReminderRequest.remind_at"));
  }
  auto advance_minutes = optional_int(object, "advance_minutes", "CreateReminderRequest");
  if (!advance_minutes.ok()) return common::Result<application::CreateReminderCommand>::failure(advance_minutes.error());
  if (!remind_at.value().has_value() && !advance_minutes.value().has_value()) {
    return common::Result<application::CreateReminderCommand>::failure(reminder_time_invalid("CreateReminderRequest.remind_at"));
  }
  auto message = optional_string(object, "message", "CreateReminderRequest");
  if (!message.ok()) return common::Result<application::CreateReminderCommand>::failure(message.error());

  application::CreateReminderCommand command;
  command.target_type = target_type.value();
  command.target_id = target_id.value();
  command.remind_at = remind_at.value();
  command.advance_minutes = advance_minutes.value();
  command.methods = methods.value();
  command.message = message.value();
  command.is_enabled = is_enabled.value();
  command.source = source.value();
  return common::Result<application::CreateReminderCommand>::success(std::move(command));
}

common::Result<application::CancelReminderCommand> parse_cancel_reminder_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CancelReminderCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id", "reason"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::CancelReminderCommand>::failure(
        contract_error("CancelReminderRequest contains an unknown field.", "CancelReminderRequest." + unknown));
  }

  auto id = require_string(object, "id", "CancelReminderRequest", true);
  if (!id.ok()) return common::Result<application::CancelReminderCommand>::failure(id.error());
  auto reason = optional_string(object, "reason", "CancelReminderRequest");
  if (!reason.ok()) return common::Result<application::CancelReminderCommand>::failure(reason.error());

  application::CancelReminderCommand command;
  command.id = id.value();
  command.reason = reason.value();
  return common::Result<application::CancelReminderCommand>::success(std::move(command));
}

common::Result<application::ReminderQuery> parse_list_reminders_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderQuery>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "target_type", "target_id", "remind_at_from", "remind_at_to", "methods", "status", "is_enabled",
      "include_deleted", "pagination", "sort_by", "sort_direction",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::ReminderQuery>::failure(
        contract_error("ListRemindersRequest contains an unknown field.", "ListRemindersRequest." + unknown));
  }

  application::ReminderQuery query;
  auto target_type = optional_string(object, "target_type", "ListRemindersRequest");
  if (!target_type.ok()) return common::Result<application::ReminderQuery>::failure(target_type.error());
  if (target_type.value().has_value()) {
    if (!domain::is_valid_reminder_target_type(*target_type.value())) {
      return common::Result<application::ReminderQuery>::failure(
          contract_error("ListRemindersRequest.target_type has an unsupported enum value.", "ListRemindersRequest.target_type"));
    }
    query.target_type = target_type.value();
  }
  auto target_id = optional_string(object, "target_id", "ListRemindersRequest");
  if (!target_id.ok()) return common::Result<application::ReminderQuery>::failure(target_id.error());
  query.target_id = target_id.value();

  auto remind_at_from = optional_string(object, "remind_at_from", "ListRemindersRequest");
  if (!remind_at_from.ok()) return common::Result<application::ReminderQuery>::failure(remind_at_from.error());
  if (remind_at_from.value().has_value() && !common::is_iso8601_utc_datetime(*remind_at_from.value())) {
    return common::Result<application::ReminderQuery>::failure(reminder_time_invalid("ListRemindersRequest.remind_at_from"));
  }
  auto remind_at_to = optional_string(object, "remind_at_to", "ListRemindersRequest");
  if (!remind_at_to.ok()) return common::Result<application::ReminderQuery>::failure(remind_at_to.error());
  if (remind_at_to.value().has_value() && !common::is_iso8601_utc_datetime(*remind_at_to.value())) {
    return common::Result<application::ReminderQuery>::failure(reminder_time_invalid("ListRemindersRequest.remind_at_to"));
  }
  query.remind_at_from = remind_at_from.value();
  query.remind_at_to = remind_at_to.value();

  auto methods = optional_string_array(
      object, "methods", "ListRemindersRequest", domain::is_valid_reminder_method, "methods");
  if (!methods.ok()) return common::Result<application::ReminderQuery>::failure(methods.error());
  auto status = optional_string_array(
      object, "status", "ListRemindersRequest", domain::is_valid_reminder_status, "status");
  if (!status.ok()) return common::Result<application::ReminderQuery>::failure(status.error());
  query.methods = methods.value();
  query.status = status.value();

  auto is_enabled = optional_bool(object, "is_enabled", "ListRemindersRequest");
  if (!is_enabled.ok()) return common::Result<application::ReminderQuery>::failure(is_enabled.error());
  query.is_enabled = is_enabled.value();
  auto include_deleted = optional_bool(object, "include_deleted", "ListRemindersRequest");
  if (!include_deleted.ok()) return common::Result<application::ReminderQuery>::failure(include_deleted.error());
  query.include_deleted = include_deleted.value().value_or(false);

  auto sort_by = optional_string(object, "sort_by", "ListRemindersRequest");
  if (!sort_by.ok()) return common::Result<application::ReminderQuery>::failure(sort_by.error());
  auto sort_direction = optional_string(object, "sort_direction", "ListRemindersRequest");
  if (!sort_direction.ok()) return common::Result<application::ReminderQuery>::failure(sort_direction.error());
  if (sort_by.value().has_value()) {
    if (!is_valid_sort_by(*sort_by.value())) {
      return common::Result<application::ReminderQuery>::failure(
          contract_error("ListRemindersRequest.sort_by has an unsupported enum value.", "ListRemindersRequest.sort_by"));
    }
    query.sort_by = *sort_by.value();
  }
  if (sort_direction.value().has_value()) {
    if (!is_valid_sort_direction(*sort_direction.value())) {
      return common::Result<application::ReminderQuery>::failure(
          contract_error("ListRemindersRequest.sort_direction has an unsupported enum value.", "ListRemindersRequest.sort_direction"));
    }
    query.sort_direction = *sort_direction.value();
  }

  const auto* pagination_value = field(object, "pagination");
  if (pagination_value != nullptr && !pagination_value->is<picojson::null>()) {
    if (!pagination_value->is<picojson::object>()) {
      return common::Result<application::ReminderQuery>::failure(
          contract_error("ListRemindersRequest.pagination must be an object.", "ListRemindersRequest.pagination"));
    }
    const auto& pagination = pagination_value->get<picojson::object>();
    static const std::set<std::string> pagination_allowed{"page", "page_size", "cursor", "sort_by", "sort_direction"};
    if (has_unknown_field(pagination, pagination_allowed, unknown)) {
      return common::Result<application::ReminderQuery>::failure(
          contract_error("ListRemindersRequest.pagination contains an unknown field.",
                         "ListRemindersRequest.pagination." + unknown));
    }
    auto page = optional_int(pagination, "page", "ListRemindersRequest.pagination");
    if (!page.ok()) return common::Result<application::ReminderQuery>::failure(page.error());
    auto page_size = optional_int(pagination, "page_size", "ListRemindersRequest.pagination");
    if (!page_size.ok()) return common::Result<application::ReminderQuery>::failure(page_size.error());
    auto cursor = optional_string(pagination, "cursor", "ListRemindersRequest.pagination");
    if (!cursor.ok()) return common::Result<application::ReminderQuery>::failure(cursor.error());
    if (cursor.value().has_value()) {
      return common::Result<application::ReminderQuery>::failure(
          search_query_invalid("pagination.cursor", "Cursor pagination is not implemented in this phase"));
    }
    auto pagination_sort_by = optional_string(pagination, "sort_by", "ListRemindersRequest.pagination");
    if (!pagination_sort_by.ok()) return common::Result<application::ReminderQuery>::failure(pagination_sort_by.error());
    auto pagination_sort_direction =
        optional_string(pagination, "sort_direction", "ListRemindersRequest.pagination");
    if (!pagination_sort_direction.ok()) {
      return common::Result<application::ReminderQuery>::failure(pagination_sort_direction.error());
    }
    if (page.value().has_value()) {
      query.pagination.page = *page.value();
    }
    if (page_size.value().has_value()) {
      query.pagination.page_size = *page_size.value();
    }
    if (!sort_by.value().has_value() && pagination_sort_by.value().has_value()) {
      if (!is_valid_sort_by(*pagination_sort_by.value())) {
        return common::Result<application::ReminderQuery>::failure(
            contract_error("ListRemindersRequest.pagination.sort_by has an unsupported enum value.",
                           "ListRemindersRequest.pagination.sort_by"));
      }
      query.sort_by = *pagination_sort_by.value();
    }
    if (!sort_direction.value().has_value() && pagination_sort_direction.value().has_value()) {
      if (!is_valid_sort_direction(*pagination_sort_direction.value())) {
        return common::Result<application::ReminderQuery>::failure(
            contract_error("ListRemindersRequest.pagination.sort_direction has an unsupported enum value.",
                           "ListRemindersRequest.pagination.sort_direction"));
      }
      query.sort_direction = *pagination_sort_direction.value();
    }
  }

  return common::Result<application::ReminderQuery>::success(std::move(query));
}

common::Result<common::Unit> parse_update_reminder_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<common::Unit>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "id", "target_type", "target_id", "remind_at", "advance_minutes", "methods", "message", "source",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<common::Unit>::failure(
        contract_error("UpdateReminderRequest contains an unknown field.", "UpdateReminderRequest." + unknown));
  }

  auto id = require_string(object, "id", "UpdateReminderRequest", true);
  if (!id.ok()) return common::Result<common::Unit>::failure(id.error());
  auto target_type = optional_string(object, "target_type", "UpdateReminderRequest");
  if (!target_type.ok()) return common::Result<common::Unit>::failure(target_type.error());
  if (target_type.value().has_value() && !domain::is_valid_reminder_target_type(*target_type.value())) {
    return common::Result<common::Unit>::failure(
        contract_error("UpdateReminderRequest.target_type has an unsupported enum value.", "UpdateReminderRequest.target_type"));
  }
  auto target_id = optional_string(object, "target_id", "UpdateReminderRequest");
  if (!target_id.ok()) return common::Result<common::Unit>::failure(target_id.error());
  if (target_id.value().has_value() && target_id.value()->empty()) {
    return common::Result<common::Unit>::failure(
        contract_error("UpdateReminderRequest.target_id must be non-empty.", "UpdateReminderRequest.target_id"));
  }
  auto remind_at = optional_string(object, "remind_at", "UpdateReminderRequest");
  if (!remind_at.ok()) return common::Result<common::Unit>::failure(remind_at.error());
  if (remind_at.value().has_value() && !common::is_iso8601_utc_datetime(*remind_at.value())) {
    return common::Result<common::Unit>::failure(reminder_time_invalid("UpdateReminderRequest.remind_at"));
  }
  auto advance_minutes = optional_int(object, "advance_minutes", "UpdateReminderRequest");
  if (!advance_minutes.ok()) return common::Result<common::Unit>::failure(advance_minutes.error());
  if (advance_minutes.value().has_value() && *advance_minutes.value() < 0) {
    return common::Result<common::Unit>::failure(reminder_time_invalid("UpdateReminderRequest.advance_minutes"));
  }
  const auto* methods_value = field(object, "methods");
  if (methods_value != nullptr) {
    auto methods = required_methods(object, "UpdateReminderRequest");
    if (!methods.ok()) return common::Result<common::Unit>::failure(methods.error());
  }
  auto message = optional_string(object, "message", "UpdateReminderRequest");
  if (!message.ok()) return common::Result<common::Unit>::failure(message.error());
  auto source = optional_string(object, "source", "UpdateReminderRequest");
  if (!source.ok()) return common::Result<common::Unit>::failure(source.error());
  if (source.value().has_value() && !domain::is_valid_reminder_source(*source.value())) {
    return common::Result<common::Unit>::failure(
        contract_error("UpdateReminderRequest.source has an unsupported enum value.", "UpdateReminderRequest.source"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<contract::MarkReminderScheduledRequest> parse_mark_reminder_scheduled_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<contract::MarkReminderScheduledRequest>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id", "scheduled_at"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::MarkReminderScheduledRequest>::failure(
        contract_error("MarkReminderScheduledRequest contains an unknown field.",
                       "MarkReminderScheduledRequest." + unknown));
  }
  auto id = require_string(object, "id", "MarkReminderScheduledRequest", true);
  if (!id.ok()) return common::Result<contract::MarkReminderScheduledRequest>::failure(id.error());
  auto scheduled_at = require_string(object, "scheduled_at", "MarkReminderScheduledRequest", true);
  if (!scheduled_at.ok()) return common::Result<contract::MarkReminderScheduledRequest>::failure(scheduled_at.error());
  if (!common::is_iso8601_utc_datetime(scheduled_at.value())) {
    return common::Result<contract::MarkReminderScheduledRequest>::failure(
        reminder_time_invalid("MarkReminderScheduledRequest.scheduled_at"));
  }
  return common::Result<contract::MarkReminderScheduledRequest>::success(
      {id.value(), scheduled_at.value()});
}

common::Result<application::MarkReminderSentCommand> parse_mark_reminder_sent_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::MarkReminderSentCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id", "last_triggered_at"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::MarkReminderSentCommand>::failure(
        contract_error("MarkReminderSentRequest contains an unknown field.", "MarkReminderSentRequest." + unknown));
  }
  auto id = require_string(object, "id", "MarkReminderSentRequest", true);
  if (!id.ok()) return common::Result<application::MarkReminderSentCommand>::failure(id.error());
  auto last_triggered_at = require_string(object, "last_triggered_at", "MarkReminderSentRequest", true);
  if (!last_triggered_at.ok()) return common::Result<application::MarkReminderSentCommand>::failure(last_triggered_at.error());
  if (!common::is_iso8601_utc_datetime(last_triggered_at.value())) {
    return common::Result<application::MarkReminderSentCommand>::failure(
        reminder_time_invalid("MarkReminderSentRequest.last_triggered_at"));
  }
  application::MarkReminderSentCommand command;
  command.id = id.value();
  command.last_triggered_at = last_triggered_at.value();
  return common::Result<application::MarkReminderSentCommand>::success(std::move(command));
}

common::Result<contract::MarkReminderFailedRequest> parse_mark_reminder_failed_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<contract::MarkReminderFailedRequest>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id", "failure_reason"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::MarkReminderFailedRequest>::failure(
        contract_error("MarkReminderFailedRequest contains an unknown field.", "MarkReminderFailedRequest." + unknown));
  }
  auto id = require_string(object, "id", "MarkReminderFailedRequest", true);
  if (!id.ok()) return common::Result<contract::MarkReminderFailedRequest>::failure(id.error());
  auto failure_reason = require_string(object, "failure_reason", "MarkReminderFailedRequest", true);
  if (!failure_reason.ok()) return common::Result<contract::MarkReminderFailedRequest>::failure(failure_reason.error());
  return common::Result<contract::MarkReminderFailedRequest>::success(
      {id.value(), failure_reason.value()});
}

common::Result<application::ReminderIdCommand> parse_reminder_id_request(std::string_view request_json,
                                                                         const std::string& parent) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderIdCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{"id"};
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::ReminderIdCommand>::failure(
        contract_error(parent + " contains an unknown field.", parent + "." + unknown));
  }
  auto id = require_string(object, "id", parent, true);
  if (!id.ok()) return common::Result<application::ReminderIdCommand>::failure(id.error());
  application::ReminderIdCommand command;
  command.id = id.value();
  return common::Result<application::ReminderIdCommand>::success(std::move(command));
}

std::string failure_response(const common::Error& error, const std::string& request_id) {
  return contract::native_failure_json(error, request_id);
}

}  // namespace

std::string create_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_create_reminder_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto created = service->create_reminder(parsed.value());
    if (!created.ok()) {
      return failure_response(created.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(created.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string cancel_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_cancel_reminder_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto cancelled = service->cancel_reminder(parsed.value());
    if (!cancelled.ok()) {
      return failure_response(cancelled.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(cancelled.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string update_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_update_reminder_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    return failure_response(feature_not_implemented("reminder.update"), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string list_reminders(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_list_reminders_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto listed = service->list_reminders(parsed.value());
    if (!listed.ok()) {
      return failure_response(listed.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_list_response_to_json(listed.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string get_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_get_reminder_request(request_json);
    if (!parsed.ok()) return failure_response(parsed.error(), request_id);
    const auto service = current_reminder_service();
    if (!service) return failure_response(storage_not_initialized_error("reminder.get"), request_id);
    auto reminder = service->get_reminder({parsed.value().id});
    if (!reminder.ok()) return failure_response(reminder.error(), request_id);
    return contract::native_success_json(
        contract::reminder_response_to_json(reminder.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string list_schedulable_reminders(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_list_schedulable_reminders_request(request_json);
    if (!parsed.ok()) return failure_response(parsed.error(), request_id);
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder.list_schedulable"), request_id);
    }
    application::ListSchedulableRemindersCommand command;
    command.from_at = parsed.value().from_at;
    command.to_at = parsed.value().to_at;
    command.limit = parsed.value().limit;
    command.include_failed = parsed.value().include_failed;
    command.include_scheduled = parsed.value().include_scheduled;
    command.supported_methods = parsed.value().supported_methods;
    auto listed = service->list_schedulable_reminders(command);
    if (!listed.ok()) return failure_response(listed.error(), request_id);
    const auto response = contract::make_schedulable_reminder_list_response(listed.value());
    return contract::native_success_json(
        contract::schedulable_reminder_list_response_to_json(response), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string mark_reminder_scheduled(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_mark_reminder_scheduled_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto updated = service->mark_scheduled(
        {parsed.value().id, parsed.value().scheduled_at});
    if (!updated.ok()) {
      return failure_response(updated.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(updated.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string mark_reminder_sent(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_mark_reminder_sent_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto updated = service->mark_sent(parsed.value());
    if (!updated.ok()) {
      return failure_response(updated.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(updated.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string mark_reminder_failed(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_mark_reminder_failed_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto updated = service->mark_failed(
        {parsed.value().id, parsed.value().failure_reason});
    if (!updated.ok()) {
      return failure_response(updated.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(updated.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string enable_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_reminder_id_request(request_json, "EnableReminderRequest");
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto updated = service->enable_reminder(parsed.value());
    if (!updated.ok()) {
      return failure_response(updated.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(updated.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string disable_reminder(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_reminder_id_request(request_json, "DisableReminderRequest");
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }
    const auto service = current_reminder_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder"), request_id);
    }
    auto updated = service->disable_reminder(parsed.value());
    if (!updated.ok()) {
      return failure_response(updated.error(), request_id);
    }
    return contract::native_success_json(contract::reminder_response_to_json(updated.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string consume_reminder_after_delivery(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_consume_reminder_after_delivery_request(request_json);
    if (!parsed.ok()) return failure_response(parsed.error(), request_id);
    const auto service = current_notification_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("reminder.consume_after_delivery"), request_id);
    }
    application::ConsumeReminderAfterDeliveryCommand command;
    command.reminder_id = parsed.value().reminder_id;
    command.method = parsed.value().method;
    command.title = parsed.value().title;
    command.body = parsed.value().body;
    command.planned_at = parsed.value().planned_at;
    command.sent_at = parsed.value().sent_at;
    command.delete_after_sent = parsed.value().delete_after_sent;
    auto consumed = service->consume_after_delivery(command);
    if (!consumed.ok()) return failure_response(consumed.error(), request_id);
    const auto response = contract::make_consume_reminder_after_delivery_response(consumed.value());
    return contract::native_success_json(
        contract::consume_reminder_after_delivery_response_to_json(response), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

}  // namespace excellent_calendar::boundary::api
