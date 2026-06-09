#include "excellent_calendar/storage/json/json_event_repository.hpp"

#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <system_error>

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace excellent_calendar::storage::json {
namespace {

common::Error storage_path_invalid(std::string reason) {
  return common::make_error(
      "STORAGE_PATH_INVALID",
      "Storage path is invalid or not writable",
      {{"reason", std::move(reason)}});
}

common::Error storage_io_error(std::string operation, std::string reason) {
  return common::make_error(
      "STORAGE_IO_ERROR",
      "Storage input/output operation failed",
      {{"operation", std::move(operation)}, {"reason", std::move(reason)}},
      true);
}

common::Error storage_corrupted(std::string reason, std::string field = "") {
  std::map<std::string, std::string> details{{"reason", std::move(reason)}};
  if (!field.empty()) {
    details["field"] = std::move(field);
  }
  return common::make_error(
      "STORAGE_DATA_CORRUPTED",
      "Storage data is corrupted",
      std::move(details));
}

bool is_integer_number(double value) {
  return std::floor(value) == value;
}

const picojson::value* object_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return nullptr;
  }
  return &found->second;
}

common::Result<std::string> read_required_string(const picojson::object& object,
                                                 const std::string& key,
                                                 const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || !value->is<std::string>() || value->get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        storage_corrupted(parent + "." + key + " must be a non-empty string", parent + "." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> read_optional_string(const picojson::object& object,
                                                                const std::string& key,
                                                                const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        storage_corrupted(parent + "." + key + " must be a string or null", parent + "." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<bool> read_required_bool(const picojson::object& object,
                                        const std::string& key,
                                        const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || !value->is<bool>()) {
    return common::Result<bool>::failure(
        storage_corrupted(parent + "." + key + " must be boolean", parent + "." + key));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<domain::Event> parse_event_record(const picojson::value& value, std::size_t index) {
  const std::string parent = "events[" + std::to_string(index) + "]";
  if (!value.is<picojson::object>()) {
    return common::Result<domain::Event>::failure(storage_corrupted(parent + " must be object", parent));
  }
  const auto& object = value.get<picojson::object>();

  domain::Event event;

  auto id = read_required_string(object, "id", parent);
  if (!id.ok()) return common::Result<domain::Event>::failure(id.error());
  auto title = read_required_string(object, "title", parent);
  if (!title.ok()) return common::Result<domain::Event>::failure(title.error());
  auto start_at = read_required_string(object, "start_at", parent);
  if (!start_at.ok()) return common::Result<domain::Event>::failure(start_at.error());
  auto end_at = read_required_string(object, "end_at", parent);
  if (!end_at.ok()) return common::Result<domain::Event>::failure(end_at.error());
  auto status = read_required_string(object, "status", parent);
  if (!status.ok()) return common::Result<domain::Event>::failure(status.error());
  auto source = read_required_string(object, "source", parent);
  if (!source.ok()) return common::Result<domain::Event>::failure(source.error());
  auto created_at = read_required_string(object, "created_at", parent);
  if (!created_at.ok()) return common::Result<domain::Event>::failure(created_at.error());
  auto updated_at = read_required_string(object, "updated_at", parent);
  if (!updated_at.ok()) return common::Result<domain::Event>::failure(updated_at.error());

  event.id = id.value();
  event.title = title.value();
  event.start_at = start_at.value();
  event.end_at = end_at.value();
  event.status = status.value();
  event.source = source.value();
  event.created_at = created_at.value();
  event.updated_at = updated_at.value();

  auto content = read_optional_string(object, "content", parent);
  if (!content.ok()) return common::Result<domain::Event>::failure(content.error());
  auto completed_at = read_optional_string(object, "completed_at", parent);
  if (!completed_at.ok()) return common::Result<domain::Event>::failure(completed_at.error());
  auto recurrence_id = read_optional_string(object, "recurrence_id", parent);
  if (!recurrence_id.ok()) return common::Result<domain::Event>::failure(recurrence_id.error());
  auto category_id = read_optional_string(object, "category_id", parent);
  if (!category_id.ok()) return common::Result<domain::Event>::failure(category_id.error());
  auto importance = read_optional_string(object, "importance", parent);
  if (!importance.ok()) return common::Result<domain::Event>::failure(importance.error());
  auto location = read_optional_string(object, "location", parent);
  if (!location.ok()) return common::Result<domain::Event>::failure(location.error());
  auto timezone = read_optional_string(object, "timezone", parent);
  if (!timezone.ok()) return common::Result<domain::Event>::failure(timezone.error());
  auto deleted_at = read_optional_string(object, "deleted_at", parent);
  if (!deleted_at.ok()) return common::Result<domain::Event>::failure(deleted_at.error());
  auto is_all_day = read_required_bool(object, "is_all_day", parent);
  if (!is_all_day.ok()) return common::Result<domain::Event>::failure(is_all_day.error());
  auto has_recurrence = read_required_bool(object, "has_recurrence", parent);
  if (!has_recurrence.ok()) return common::Result<domain::Event>::failure(has_recurrence.error());

  event.content = content.value();
  event.completed_at = completed_at.value();
  event.recurrence_id = recurrence_id.value();
  event.category_id = category_id.value();
  event.importance = importance.value();
  event.location = location.value();
  event.timezone = timezone.value();
  event.deleted_at = deleted_at.value();
  event.is_all_day = is_all_day.value();
  event.has_recurrence = has_recurrence.value();

  if (!common::is_iso8601_utc_datetime(event.start_at)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored start_at is invalid", parent + ".start_at"));
  }
  if (!common::is_iso8601_utc_datetime(event.end_at)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored end_at is invalid", parent + ".end_at"));
  }
  if (!domain::is_valid_event_status(event.status)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored status is invalid", parent + ".status"));
  }
  if (!domain::is_valid_create_event_source(event.source)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored source is invalid", parent + ".source"));
  }
  if (event.importance.has_value() && !domain::is_valid_importance(*event.importance)) {
    return common::Result<domain::Event>::failure(
        storage_corrupted("stored importance is invalid", parent + ".importance"));
  }

  return common::Result<domain::Event>::success(std::move(event));
}

picojson::value optional_string_to_json(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(*value);
}

picojson::value event_to_storage_json(const domain::Event& event) {
  picojson::object object;
  object["id"] = picojson::value(event.id);
  object["title"] = picojson::value(event.title);
  object["content"] = optional_string_to_json(event.content);
  object["start_at"] = picojson::value(event.start_at);
  object["end_at"] = picojson::value(event.end_at);
  object["is_all_day"] = picojson::value(event.is_all_day);
  object["has_recurrence"] = picojson::value(event.has_recurrence);
  object["status"] = picojson::value(event.status);
  object["completed_at"] = optional_string_to_json(event.completed_at);
  object["recurrence_id"] = optional_string_to_json(event.recurrence_id);
  object["category_id"] = optional_string_to_json(event.category_id);
  object["importance"] = optional_string_to_json(event.importance);
  object["location"] = optional_string_to_json(event.location);
  object["timezone"] = optional_string_to_json(event.timezone);
  object["source"] = picojson::value(event.source);
  object["created_at"] = picojson::value(event.created_at);
  object["updated_at"] = picojson::value(event.updated_at);
  object["deleted_at"] = optional_string_to_json(event.deleted_at);
  return picojson::value(object);
}

common::Result<common::Unit> replace_file_atomically(const std::filesystem::path& source,
                                                     const std::filesystem::path& target) {
#if defined(_WIN32)
  const auto source_string = source.string();
  const auto target_string = target.string();
  if (!MoveFileExA(
          source_string.c_str(),
          target_string.c_str(),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return common::Result<common::Unit>::failure(
        storage_io_error("rename", "MoveFileEx failed with code " + std::to_string(GetLastError())));
  }
#else
  std::error_code rename_error;
  std::filesystem::rename(source, target, rename_error);
  if (rename_error) {
    return common::Result<common::Unit>::failure(storage_io_error("rename", rename_error.message()));
  }
#endif
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

JsonEventRepository::JsonEventRepository(std::filesystem::path storage_directory)
    : storage_directory_(std::move(storage_directory)) {}

common::Result<common::Unit> JsonEventRepository::initialize() {
  std::lock_guard<std::mutex> lock(mutex_);

  if (storage_directory_.empty()) {
    return common::Result<common::Unit>::failure(storage_path_invalid("path is empty"));
  }

  std::error_code create_error;
  std::filesystem::create_directories(storage_directory_, create_error);
  if (create_error) {
    return common::Result<common::Unit>::failure(storage_path_invalid(create_error.message()));
  }

  std::error_code status_error;
  if (!std::filesystem::is_directory(storage_directory_, status_error) || status_error) {
    return common::Result<common::Unit>::failure(storage_path_invalid("path is not a directory"));
  }

  const auto probe_path = storage_directory_ / ".write_probe.tmp";
  {
    std::ofstream probe(probe_path, std::ios::binary | std::ios::trunc);
    if (!probe.is_open()) {
      return common::Result<common::Unit>::failure(storage_path_invalid("probe file cannot be opened"));
    }
    probe << "ok";
    probe.flush();
    if (!probe.good()) {
      return common::Result<common::Unit>::failure(storage_path_invalid("probe file cannot be written"));
    }
  }
  std::error_code remove_error;
  std::filesystem::remove(probe_path, remove_error);

  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<domain::Event> JsonEventRepository::create(const domain::Event& event) {
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_events_locked();
  if (!loaded.ok()) {
    return common::Result<domain::Event>::failure(loaded.error());
  }
  auto events = loaded.value();
  events.push_back(event);

  auto saved = save_events_locked(events);
  if (!saved.ok()) {
    return common::Result<domain::Event>::failure(saved.error());
  }
  return common::Result<domain::Event>::success(event);
}

common::Result<std::vector<domain::Event>> JsonEventRepository::find_all() {
  std::lock_guard<std::mutex> lock(mutex_);
  return load_events_locked();
}

common::Result<std::vector<domain::Event>> JsonEventRepository::load_events_locked() {
  const auto path = events_file();
  std::error_code exists_error;
  if (!std::filesystem::exists(path, exists_error)) {
    return common::Result<std::vector<domain::Event>>::success({});
  }
  if (exists_error) {
    return common::Result<std::vector<domain::Event>>::failure(storage_io_error("exists", exists_error.message()));
  }

  std::ifstream input(path, std::ios::binary);
  if (!input.is_open()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_io_error("read", "events.json cannot be opened"));
  }
  std::stringstream buffer;
  buffer << input.rdbuf();
  if (input.bad()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_io_error("read", "events.json read failed"));
  }

  picojson::value root;
  const std::string parse_error = picojson::parse(root, buffer.str());
  if (!parse_error.empty()) {
    std::cerr << "ExcellentCalendar storage parse error: " << parse_error << '\n';
    return common::Result<std::vector<domain::Event>>::failure(storage_corrupted(parse_error));
  }
  if (!root.is<picojson::object>()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_corrupted("root must be object"));
  }
  const auto& object = root.get<picojson::object>();
  const auto* version = object_field(object, "storage_version");
  if (version == nullptr || !version->is<double>() || !is_integer_number(version->get<double>()) ||
      static_cast<int>(version->get<double>()) != 1) {
    return common::Result<std::vector<domain::Event>>::failure(
        storage_corrupted("storage_version must be 1", "storage_version"));
  }
  const auto* events_value = object_field(object, "events");
  if (events_value == nullptr || !events_value->is<picojson::array>()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_corrupted("events must be array", "events"));
  }

  std::vector<domain::Event> events;
  const auto& array = events_value->get<picojson::array>();
  events.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    auto parsed = parse_event_record(array[index], index);
    if (!parsed.ok()) {
      std::cerr << "ExcellentCalendar storage record error: " << parsed.error().message << '\n';
      return common::Result<std::vector<domain::Event>>::failure(parsed.error());
    }
    events.push_back(std::move(parsed.value()));
  }
  return common::Result<std::vector<domain::Event>>::success(std::move(events));
}

common::Result<common::Unit> JsonEventRepository::save_events_locked(const std::vector<domain::Event>& events) {
  std::error_code create_error;
  std::filesystem::create_directories(storage_directory_, create_error);
  if (create_error) {
    return common::Result<common::Unit>::failure(storage_io_error("create_directories", create_error.message()));
  }

  picojson::array event_array;
  event_array.reserve(events.size());
  for (const auto& event : events) {
    event_array.push_back(event_to_storage_json(event));
  }

  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["events"] = picojson::value(event_array);

  const auto tmp_path = events_file().string() + ".tmp";
  {
    std::ofstream output(tmp_path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
      return common::Result<common::Unit>::failure(storage_io_error("write_tmp", "events.json.tmp cannot be opened"));
    }
    output << picojson::value(root).serialize();
    output.flush();
    if (!output.good()) {
      return common::Result<common::Unit>::failure(storage_io_error("write_tmp", "events.json.tmp write failed"));
    }
  }

  auto replaced = replace_file_atomically(tmp_path, events_file());
  if (!replaced.ok()) {
    std::error_code remove_error;
    std::filesystem::remove(tmp_path, remove_error);
    return replaced;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

std::filesystem::path JsonEventRepository::events_file() const {
  return storage_directory_ / "events.json";
}

}  // namespace excellent_calendar::storage::json
