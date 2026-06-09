#include "excellent_calendar/boundary/api/event_api.hpp"

#include <cmath>
#include <memory>
#include <mutex>
#include <set>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/boundary/contract/event_list_response.hpp"
#include "excellent_calendar/boundary/contract/event_response.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"

namespace excellent_calendar::boundary::api {
namespace {

struct RuntimeState {
  std::shared_ptr<storage::json::JsonEventRepository> repository;
  std::shared_ptr<application::EventService> service;
  std::string storage_directory;
};

std::mutex g_state_mutex;
RuntimeState g_state;

common::Error contract_error(std::string message, std::string field = "") {
  std::map<std::string, std::string> details;
  if (!field.empty()) {
    details["field"] = std::move(field);
  }
  return common::make_error("CONTRACT_VALIDATION_FAILED", std::move(message), std::move(details));
}

common::Error not_initialized_error() {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED",
      "Native storage has not been initialized",
      {{"operation", "event"}});
}

common::Error feature_not_implemented(std::string feature) {
  return common::make_error(
      "FEATURE_NOT_IMPLEMENTED",
      "Requested feature is not implemented in this phase",
      {{"feature", std::move(feature)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR",
      "Native internal error",
      {{"reason", std::move(reason)}});
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

bool is_integer(double value) {
  return std::floor(value) == value;
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
  return common::Result<std::optional<int>>::success(static_cast<int>(value->get<double>()));
}

common::Result<std::vector<std::string>> optional_string_array(const picojson::object& object,
                                                               const std::string& key,
                                                               const std::string& parent,
                                                               const std::set<std::string>* allowed = nullptr) {
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
    if (allowed != nullptr && allowed->find(item) == allowed->end()) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + "." + key + " item has an unsupported value.", parent + "." + key));
    }
    result.push_back(item);
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

common::Result<application::CreateEventCommand> parse_create_event_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CreateEventCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "title",      "content",     "start_at", "end_at",   "is_all_day", "category_id",
      "importance", "location",    "timezone", "source",   "recurrence", "reminders",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::CreateEventCommand>::failure(
        contract_error("CreateEventRequest contains an unknown field.", "CreateEventRequest." + unknown));
  }

  auto title = require_string(object, "title", "CreateEventRequest", false);
  if (!title.ok()) return common::Result<application::CreateEventCommand>::failure(title.error());
  auto start_at = require_string(object, "start_at", "CreateEventRequest", true);
  if (!start_at.ok()) return common::Result<application::CreateEventCommand>::failure(start_at.error());
  auto end_at = require_string(object, "end_at", "CreateEventRequest", true);
  if (!end_at.ok()) return common::Result<application::CreateEventCommand>::failure(end_at.error());
  auto is_all_day = require_bool(object, "is_all_day", "CreateEventRequest");
  if (!is_all_day.ok()) return common::Result<application::CreateEventCommand>::failure(is_all_day.error());
  auto source = require_string(object, "source", "CreateEventRequest", true);
  if (!source.ok()) return common::Result<application::CreateEventCommand>::failure(source.error());

  if (!common::is_iso8601_utc_datetime(start_at.value())) {
    return common::Result<application::CreateEventCommand>::failure(
        contract_error("CreateEventRequest.start_at must be ISO 8601 UTC date-time.", "CreateEventRequest.start_at"));
  }
  if (!common::is_iso8601_utc_datetime(end_at.value())) {
    return common::Result<application::CreateEventCommand>::failure(
        contract_error("CreateEventRequest.end_at must be ISO 8601 UTC date-time.", "CreateEventRequest.end_at"));
  }
  if (!domain::is_valid_create_event_source(source.value())) {
    return common::Result<application::CreateEventCommand>::failure(
        contract_error("CreateEventRequest.source has an unsupported enum value.", "CreateEventRequest.source"));
  }

  auto content = optional_string(object, "content", "CreateEventRequest");
  if (!content.ok()) return common::Result<application::CreateEventCommand>::failure(content.error());
  auto category_id = optional_string(object, "category_id", "CreateEventRequest");
  if (!category_id.ok()) return common::Result<application::CreateEventCommand>::failure(category_id.error());
  auto importance = optional_string(object, "importance", "CreateEventRequest");
  if (!importance.ok()) return common::Result<application::CreateEventCommand>::failure(importance.error());
  if (importance.value().has_value() && !domain::is_valid_importance(*importance.value())) {
    return common::Result<application::CreateEventCommand>::failure(
        contract_error("CreateEventRequest.importance has an unsupported enum value.", "CreateEventRequest.importance"));
  }
  auto location = optional_string(object, "location", "CreateEventRequest");
  if (!location.ok()) return common::Result<application::CreateEventCommand>::failure(location.error());
  auto timezone = optional_string(object, "timezone", "CreateEventRequest");
  if (!timezone.ok()) return common::Result<application::CreateEventCommand>::failure(timezone.error());

  const auto* recurrence = field(object, "recurrence");
  if (recurrence != nullptr && !recurrence->is<picojson::null>()) {
    // TODO(recurrence): persist Recurrence as an independent entity.
    return common::Result<application::CreateEventCommand>::failure(feature_not_implemented("recurrence"));
  }
  const auto* reminders = field(object, "reminders");
  if (reminders != nullptr) {
    if (!reminders->is<picojson::array>()) {
      return common::Result<application::CreateEventCommand>::failure(
          contract_error("CreateEventRequest.reminders must be an array.", "CreateEventRequest.reminders"));
    }
    if (!reminders->get<picojson::array>().empty()) {
      // TODO(reminder): persist Reminder records through ReminderRepository.
      return common::Result<application::CreateEventCommand>::failure(feature_not_implemented("reminders"));
    }
  }

  application::CreateEventCommand command;
  command.title = title.value();
  command.content = content.value();
  command.start_at = start_at.value();
  command.end_at = end_at.value();
  command.is_all_day = is_all_day.value();
  command.category_id = category_id.value();
  command.importance = importance.value();
  command.location = location.value();
  command.timezone = timezone.value();
  command.source = source.value();
  return common::Result<application::CreateEventCommand>::success(std::move(command));
}

common::Result<application::EventQuery> parse_search_event_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::EventQuery>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "keyword",      "start_at_from", "start_at_to", "category_ids", "importance", "location",
      "has_recurrence", "source",      "include_deleted", "pagination", "sort_by", "sort_direction",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest contains an unknown field.", "SearchEventRequest." + unknown));
  }

  application::EventQuery query;
  auto keyword = optional_string(object, "keyword", "SearchEventRequest");
  if (!keyword.ok()) return common::Result<application::EventQuery>::failure(keyword.error());
  auto start_at_from = optional_string(object, "start_at_from", "SearchEventRequest");
  if (!start_at_from.ok()) return common::Result<application::EventQuery>::failure(start_at_from.error());
  auto start_at_to = optional_string(object, "start_at_to", "SearchEventRequest");
  if (!start_at_to.ok()) return common::Result<application::EventQuery>::failure(start_at_to.error());
  auto location = optional_string(object, "location", "SearchEventRequest");
  if (!location.ok()) return common::Result<application::EventQuery>::failure(location.error());
  auto has_recurrence = optional_bool(object, "has_recurrence", "SearchEventRequest");
  if (!has_recurrence.ok()) return common::Result<application::EventQuery>::failure(has_recurrence.error());
  auto include_deleted = optional_bool(object, "include_deleted", "SearchEventRequest");
  if (!include_deleted.ok()) return common::Result<application::EventQuery>::failure(include_deleted.error());

  static const std::set<std::string> importance_values{
      "unimportant_noturgent", "important_noturgent", "unimportant_urgent", "important_urgent",
  };
  static const std::set<std::string> source_values{"manual", "ai_extraction", "sync", "import", "wechat"};
  auto category_ids = optional_string_array(object, "category_ids", "SearchEventRequest");
  if (!category_ids.ok()) return common::Result<application::EventQuery>::failure(category_ids.error());
  auto importance = optional_string_array(object, "importance", "SearchEventRequest", &importance_values);
  if (!importance.ok()) return common::Result<application::EventQuery>::failure(importance.error());
  auto source = optional_string_array(object, "source", "SearchEventRequest", &source_values);
  if (!source.ok()) return common::Result<application::EventQuery>::failure(source.error());

  query.keyword = keyword.value();
  query.start_at_from = start_at_from.value();
  query.start_at_to = start_at_to.value();
  query.location = location.value();
  query.has_recurrence = has_recurrence.value();
  query.include_deleted = include_deleted.value().value_or(false);
  query.category_ids = category_ids.value();
  query.importance = importance.value();
  query.source = source.value();

  auto sort_by = optional_string(object, "sort_by", "SearchEventRequest");
  if (!sort_by.ok()) return common::Result<application::EventQuery>::failure(sort_by.error());
  auto sort_direction = optional_string(object, "sort_direction", "SearchEventRequest");
  if (!sort_direction.ok()) return common::Result<application::EventQuery>::failure(sort_direction.error());
  if (sort_by.value().has_value()) {
    query.sort_by = *sort_by.value();
  }
  if (sort_direction.value().has_value()) {
    query.sort_direction = *sort_direction.value();
  }

  if (query.sort_by != "start_at" && query.sort_by != "created_at" &&
      query.sort_by != "updated_at" && query.sort_by != "importance" && query.sort_by != "title") {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest.sort_by has an unsupported enum value.", "SearchEventRequest.sort_by"));
  }
  if (query.sort_direction != "asc" && query.sort_direction != "desc") {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest.sort_direction has an unsupported enum value.", "SearchEventRequest.sort_direction"));
  }

  const auto* pagination_value = field(object, "pagination");
  if (pagination_value != nullptr && !pagination_value->is<picojson::null>()) {
    if (!pagination_value->is<picojson::object>()) {
      return common::Result<application::EventQuery>::failure(
          contract_error("SearchEventRequest.pagination must be an object.", "SearchEventRequest.pagination"));
    }
    const auto& pagination = pagination_value->get<picojson::object>();
    static const std::set<std::string> pagination_allowed{"page", "page_size", "cursor", "sort_by", "sort_direction"};
    if (has_unknown_field(pagination, pagination_allowed, unknown)) {
      return common::Result<application::EventQuery>::failure(
          contract_error("SearchEventRequest.pagination contains an unknown field.",
                         "SearchEventRequest.pagination." + unknown));
    }
    auto page = optional_int(pagination, "page", "SearchEventRequest.pagination");
    if (!page.ok()) return common::Result<application::EventQuery>::failure(page.error());
    auto page_size = optional_int(pagination, "page_size", "SearchEventRequest.pagination");
    if (!page_size.ok()) return common::Result<application::EventQuery>::failure(page_size.error());
    auto cursor = optional_string(pagination, "cursor", "SearchEventRequest.pagination");
    if (!cursor.ok()) return common::Result<application::EventQuery>::failure(cursor.error());
    if (cursor.value().has_value()) {
      return common::Result<application::EventQuery>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Cursor pagination is not implemented in this phase",
                             {{"field", "pagination.cursor"}}));
    }
    auto pagination_sort_by = optional_string(pagination, "sort_by", "SearchEventRequest.pagination");
    if (!pagination_sort_by.ok()) return common::Result<application::EventQuery>::failure(pagination_sort_by.error());
    auto pagination_sort_direction =
        optional_string(pagination, "sort_direction", "SearchEventRequest.pagination");
    if (!pagination_sort_direction.ok()) {
      return common::Result<application::EventQuery>::failure(pagination_sort_direction.error());
    }
    if (page.value().has_value()) {
      query.pagination.page = *page.value();
    }
    if (page_size.value().has_value()) {
      query.pagination.page_size = *page_size.value();
    }
    if (!sort_by.value().has_value() && pagination_sort_by.value().has_value()) {
      query.sort_by = *pagination_sort_by.value();
    }
    if (!sort_direction.value().has_value() && pagination_sort_direction.value().has_value()) {
      query.sort_direction = *pagination_sort_direction.value();
    }
  }

  return common::Result<application::EventQuery>::success(std::move(query));
}

std::shared_ptr<application::EventService> current_service() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_state.service;
}

std::string failure_response(const common::Error& error, const std::string& request_id) {
  return contract::native_failure_json(error, request_id);
}

}  // namespace

std::string initialize_storage(std::string_view storage_directory) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto repository = std::make_shared<storage::json::JsonEventRepository>(std::filesystem::path(std::string(storage_directory)));
    auto initialized = repository->initialize();
    if (!initialized.ok()) {
      return failure_response(initialized.error(), request_id);
    }

    auto service = std::make_shared<application::EventService>(
        repository,
        common::utc_now_iso8601,
        common::generate_uuid_v4);
    {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      g_state.repository = repository;
      g_state.service = service;
      g_state.storage_directory = std::string(storage_directory);
    }

    picojson::object data;
    data["storage_directory"] = picojson::value(std::string(storage_directory));
    data["storage_version"] = picojson::value(1.0);
    return contract::native_success_json(picojson::value(std::move(data)), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string create_event(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_create_event_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }

    const auto service = current_service();
    if (!service) {
      return failure_response(not_initialized_error(), request_id);
    }

    auto created = service->create_event(parsed.value());
    if (!created.ok()) {
      return failure_response(created.error(), request_id);
    }
    return contract::native_success_json(contract::event_response_to_json(created.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string search_events(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_search_event_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }

    const auto service = current_service();
    if (!service) {
      return failure_response(not_initialized_error(), request_id);
    }

    auto result = service->search_events(parsed.value());
    if (!result.ok()) {
      return failure_response(result.error(), request_id);
    }
    return contract::native_success_json(contract::event_list_response_to_json(result.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

std::string complete_event(std::string_view /*request_json*/) {
  const auto request_id = common::generate_uuid_v4();
  return failure_response(feature_not_implemented("event.complete"), request_id);
}

std::string reopen_event(std::string_view /*request_json*/) {
  const auto request_id = common::generate_uuid_v4();
  return failure_response(feature_not_implemented("event.reopen"), request_id);
}

}  // namespace excellent_calendar::boundary::api
