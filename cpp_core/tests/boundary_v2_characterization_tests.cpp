#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"
#include "excellent_calendar/common/uuid.hpp"

namespace {

using Endpoint = std::string (*)(std::string_view);

struct EndpointCase {
  const char* name;
  Endpoint endpoint;
};

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

picojson::object parse_envelope(
    const std::string& json,
    const std::string& context) {
  picojson::value value;
  const auto error = picojson::parse(value, json);
  require(error.empty() && value.is<picojson::object>(),
          context + " must return a JSON object");
  auto object = value.get<picojson::object>();
  require(object.at("contract_version").is<double>() &&
              object.at("contract_version").get<double>() == 2.0,
          context + " must preserve contract_version=2");
  require(object.at("request_id").is<std::string>() &&
              excellent_calendar::common::is_uuid(
                  object.at("request_id").get<std::string>()),
          context + " must return a UUID request_id");
  return object;
}

picojson::object require_contract_failure(
    const std::string& json,
    const std::string& context,
    const std::string& expected_field) {
  auto object = parse_envelope(json, context);
  require(object.at("ok").is<bool>() && !object.at("ok").get<bool>() &&
              object.at("data").is<picojson::null>() &&
              object.at("error").is<picojson::object>(),
          context + " must preserve the NativeResult failure envelope");
  const auto& error = object.at("error").get<picojson::object>();
  require(error.at("code").is<std::string>() &&
              error.at("code").get<std::string>() ==
                  "CONTRACT_VALIDATION_FAILED",
          context + " must preserve CONTRACT_VALIDATION_FAILED");
  require(error.at("details").is<picojson::object>(),
          context + " must preserve error details");
  const auto& details = error.at("details").get<picojson::object>();
  require(details.at("field").is<std::string>() &&
              details.at("field").get<std::string>() == expected_field,
          context + " must preserve details.field=" + expected_field);
  return object;
}

const picojson::object& failure_error(
    const picojson::object& object,
    const std::string& context) {
  require(object.at("ok").is<bool>() && !object.at("ok").get<bool>() &&
              object.at("data").is<picojson::null>() &&
              object.at("error").is<picojson::object>(),
          context + " must preserve the NativeResult failure envelope");
  return object.at("error").get<picojson::object>();
}

std::string normalized_failure(
    Endpoint endpoint,
    std::string_view request,
    const std::string& context) {
  auto object = parse_envelope(endpoint(request), context);
  object.erase("request_id");
  return picojson::value(std::move(object)).serialize();
}

void test_every_v2_endpoint_rejects_non_object_json_consistently() {
  using namespace excellent_calendar::boundary::api;
  const std::vector<EndpointCase> endpoints = {
      {"runtime.initialize", initialize_runtime_v2_json},
      {"runtime.resolve_local_datetime", resolve_local_datetime_v2},
      {"runtime.localize_instants", localize_instants_v2},
      {"event.create", create_event_v2},
      {"event.delete", delete_event_v2},
      {"event.search", search_events_v2},
      {"event.get_detail", get_event_detail_v2},
      {"event.complete", complete_event_v2},
      {"event.reopen", reopen_event_v2},
      {"event.list_occurrences", list_event_occurrences_v2},
      {"event_occurrence.complete", complete_event_occurrence_v2},
      {"event_occurrence.reopen", reopen_event_occurrence_v2},
      {"event_occurrence.skip", skip_event_occurrence_v2},
      {"event_occurrence.cancel", cancel_event_occurrence_v2},
      {"event_series.complete", complete_event_series_v2},
      {"event_series.reopen", reopen_event_series_v2},
      {"event_series.cancel", cancel_event_series_v2},
      {"reminder.create", create_reminder_v2},
      {"reminder.update", update_reminder_v2},
      {"reminder.cancel", cancel_reminder_v2},
      {"reminder.list", list_reminders_v2},
      {"reminder.enable", enable_reminder_v2},
      {"reminder.disable", disable_reminder_v2},
      {"reminder.list_schedulable", list_schedulable_recurring_reminders_v2},
      {"reminder.get", get_recurring_reminder_v2},
      {"reminder.mark_scheduled", mark_recurring_reminder_scheduled_v2},
      {"reminder.prepare_delivery", prepare_recurring_reminder_delivery_v2},
      {"reminder.finalize_delivery", finalize_recurring_reminder_delivery_v2},
      {"reminder.plan_recovery", plan_recurring_reminder_recovery_v2},
      {"compat.runtime.initialize", initialize_recurring_runtime_v2_json},
      {"compat.event.create", create_recurring_event_v2},
      {"compat.event.delete", delete_recurring_event_v2},
      {"compat.event.get_detail", get_recurring_event_detail_v2},
      {"compat.reminder.get", get_reminder_v2},
      {"compat.reminder.list_schedulable", list_schedulable_reminders_v2},
      {"compat.reminder.mark_scheduled", mark_reminder_scheduled_v2},
      {"compat.reminder.prepare_delivery", prepare_reminder_delivery_v2},
      {"compat.reminder.finalize_delivery", finalize_reminder_delivery_v2},
      {"compat.reminder.plan_recovery", plan_reminder_recovery_v2},
  };

  for (const auto& test : endpoints) {
    require_contract_failure(
        test.endpoint("[]"), test.name, "json");
  }
}

void test_update_event_preserves_runtime_precondition_order() {
  using namespace excellent_calendar::boundary::api;
  const auto result = parse_envelope(
      update_event_v2("[]"), "event.update runtime precondition");
  const auto& error = failure_error(
      result, "event.update runtime precondition");
  require(error.at("code").is<std::string>() &&
              error.at("code").get<std::string>() ==
                  "STORAGE_NOT_INITIALIZED",
          "event.update must check its existing runtime precondition before parsing");
  const auto& details = error.at("details").get<picojson::object>();
  require(details.at("operation").is<std::string>() &&
              details.at("operation").get<std::string>() == "event.update",
          "event.update runtime failure must preserve details.operation");
}

void test_module_endpoints_preserve_strict_unknown_field_errors() {
  using namespace excellent_calendar::boundary::api;
  require_contract_failure(
      initialize_runtime_v2_json(
          R"({"storage_directory":"storage","tzdb_directory":"tzdb","unknown":true})"),
      "runtime unknown field",
      "InitializeRuntimeRequest.unknown");
  require_contract_failure(
      create_event_v2(R"({"unknown":true})"),
      "event unknown field",
      "CreateEventRequest.unknown");
  require_contract_failure(
      create_reminder_v2(R"({"unknown":true})"),
      "reminder unknown field",
      "CreateReminderRequest.unknown");
}

void test_compatibility_facade_matches_canonical_failures() {
  using namespace excellent_calendar::boundary::api;
  const std::vector<std::pair<Endpoint, Endpoint>> aliases = {
      {initialize_recurring_runtime_v2_json, initialize_runtime_v2_json},
      {create_recurring_event_v2, create_event_v2},
      {update_recurring_event_v2, update_event_v2},
      {delete_recurring_event_v2, delete_event_v2},
      {get_recurring_event_detail_v2, get_event_detail_v2},
      {get_reminder_v2, get_recurring_reminder_v2},
      {list_schedulable_reminders_v2, list_schedulable_recurring_reminders_v2},
      {mark_reminder_scheduled_v2, mark_recurring_reminder_scheduled_v2},
      {prepare_reminder_delivery_v2, prepare_recurring_reminder_delivery_v2},
      {finalize_reminder_delivery_v2, finalize_recurring_reminder_delivery_v2},
      {plan_reminder_recovery_v2, plan_recurring_reminder_recovery_v2},
  };

  for (std::size_t index = 0; index < aliases.size(); ++index) {
    const auto context = "compatibility alias " + std::to_string(index);
    require(
        normalized_failure(aliases[index].first, "[]", context) ==
            normalized_failure(aliases[index].second, "[]", context),
        context + " must match its canonical endpoint except for request_id");
  }
}

}  // namespace

int main() {
  try {
    test_every_v2_endpoint_rejects_non_object_json_consistently();
    test_update_event_preserves_runtime_precondition_order();
    test_module_endpoints_preserve_strict_unknown_field_errors();
    test_compatibility_facade_matches_canonical_failures();
    std::cout << "boundary v2 characterization tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "boundary v2 characterization tests failed: "
              << error.what() << '\n';
    return 1;
  }
}
