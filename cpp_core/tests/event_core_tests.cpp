#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"

namespace {

using excellent_calendar::application::CreateEventCommand;
using excellent_calendar::application::EventQuery;
using excellent_calendar::application::EventService;
using excellent_calendar::common::Error;
using excellent_calendar::common::Result;
using excellent_calendar::domain::Event;
using excellent_calendar::repository::EventRepository;

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

picojson::object decode_object(const std::string& json) {
  picojson::value value;
  const auto error = picojson::parse(value, json);
  require(error.empty(), "JSON parse failed: " + error + " json=" + json);
  require(value.is<picojson::object>(), "JSON value is not object");
  return value.get<picojson::object>();
}

std::string string_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  require(found != object.end(), "missing field: " + key);
  require(found->second.is<std::string>(), "field is not string: " + key);
  return found->second.get<std::string>();
}

bool bool_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  require(found != object.end(), "missing field: " + key);
  require(found->second.is<bool>(), "field is not bool: " + key);
  return found->second.get<bool>();
}

int int_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  require(found != object.end(), "missing field: " + key);
  require(found->second.is<double>(), "field is not number: " + key);
  return static_cast<int>(found->second.get<double>());
}

picojson::object object_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  require(found != object.end(), "missing field: " + key);
  require(found->second.is<picojson::object>(), "field is not object: " + key);
  return found->second.get<picojson::object>();
}

picojson::array array_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  require(found != object.end(), "missing field: " + key);
  require(found->second.is<picojson::array>(), "field is not array: " + key);
  return found->second.get<picojson::array>();
}

void expect_ok(const std::string& json) {
  const auto result = decode_object(json);
  require(bool_field(result, "ok"), "NativeResult expected ok=true: " + json);
  const auto error = result.find("error");
  require(error != result.end() && error->second.is<picojson::null>(), "ok result error must be null");
  require(int_field(result, "contract_version") == 1, "contract_version must be 1");
  require(!string_field(result, "request_id").empty(), "request_id must be populated");
}

void expect_error(const std::string& json, const std::string& code) {
  const auto result = decode_object(json);
  require(!bool_field(result, "ok"), "NativeResult expected ok=false: " + json);
  const auto data = result.find("data");
  require(data != result.end() && data->second.is<picojson::null>(), "failed result data must be null");
  const auto error = object_field(result, "error");
  require(string_field(error, "code") == code, "expected error " + code + ", got " + string_field(error, "code"));
  require(int_field(result, "contract_version") == 1, "contract_version must be 1");
  require(!string_field(result, "request_id").empty(), "request_id must be populated");
}

std::filesystem::path make_temp_dir(const std::string& name) {
  auto path = std::filesystem::temp_directory_path() /
              ("excellent_calendar_" + name + "_" + excellent_calendar::common::generate_uuid_v4());
  std::filesystem::create_directories(path);
  return path;
}

std::string encode(const picojson::object& object) {
  return picojson::value(object).serialize();
}

std::string create_request(
    std::string title,
    std::string start_at,
    std::string end_at,
    std::string category_id = "category-work",
    std::string importance = "important_urgent",
    std::string location = "Room 8") {
  picojson::object object;
  object["title"] = picojson::value(std::move(title));
  object["content"] = picojson::value("中文详情 + emoji ✅");
  object["start_at"] = picojson::value(std::move(start_at));
  object["end_at"] = picojson::value(std::move(end_at));
  object["is_all_day"] = picojson::value(false);
  object["category_id"] = picojson::value(std::move(category_id));
  object["importance"] = picojson::value(std::move(importance));
  object["location"] = picojson::value(std::move(location));
  object["timezone"] = picojson::value("Asia/Shanghai");
  object["source"] = picojson::value("manual");
  object["recurrence"] = picojson::value();
  object["reminders"] = picojson::value(picojson::array{});
  return encode(object);
}

std::string search_request(
    std::string keyword = "",
    int page = 1,
    int page_size = 20,
    std::string sort_by = "start_at",
    std::string sort_direction = "asc") {
  picojson::object pagination;
  pagination["page"] = picojson::value(static_cast<double>(page));
  pagination["page_size"] = picojson::value(static_cast<double>(page_size));
  pagination["cursor"] = picojson::value();
  pagination["sort_by"] = picojson::value();
  pagination["sort_direction"] = picojson::value("asc");

  picojson::object object;
  object["keyword"] = keyword.empty() ? picojson::value() : picojson::value(std::move(keyword));
  object["start_at_from"] = picojson::value();
  object["start_at_to"] = picojson::value();
  object["category_ids"] = picojson::value(picojson::array{});
  object["importance"] = picojson::value(picojson::array{});
  object["location"] = picojson::value();
  object["has_recurrence"] = picojson::value();
  object["source"] = picojson::value(picojson::array{});
  object["include_deleted"] = picojson::value(false);
  object["pagination"] = picojson::value(std::move(pagination));
  object["sort_by"] = picojson::value(std::move(sort_by));
  object["sort_direction"] = picojson::value(std::move(sort_direction));
  return encode(object);
}

Event event_record(
    std::string id,
    std::string title,
    std::string start_at,
    std::string end_at,
    std::optional<std::string> deleted_at = std::nullopt) {
  Event event;
  event.id = std::move(id);
  event.title = std::move(title);
  event.content = "正文";
  event.start_at = std::move(start_at);
  event.end_at = std::move(end_at);
  event.is_all_day = false;
  event.has_recurrence = false;
  event.status = "active";
  event.completed_at = std::nullopt;
  event.recurrence_id = std::nullopt;
  event.category_id = "category-work";
  event.importance = "important_urgent";
  event.location = "上海";
  event.timezone = "Asia/Shanghai";
  event.source = "manual";
  event.created_at = "2026-06-01T00:00:00Z";
  event.updated_at = "2026-06-01T00:00:00Z";
  event.deleted_at = std::move(deleted_at);
  return event;
}

class MemoryRepository final : public EventRepository {
 public:
  Result<Event> create(const Event& event) override {
    events.push_back(event);
    return Result<Event>::success(event);
  }

  Result<std::optional<Event>> find_by_id(std::string_view id) override {
    for (const auto& event : events) {
      if (event.id == std::string(id)) {
        return Result<std::optional<Event>>::success(event);
      }
    }
    return Result<std::optional<Event>>::success(std::nullopt);
  }

  Result<std::vector<Event>> find_all() override {
    return Result<std::vector<Event>>::success(events);
  }

  std::vector<Event> events;
};

class FailingRepository final : public EventRepository {
 public:
  Result<Event> create(const Event& /*event*/) override {
    return Result<Event>::failure(
        excellent_calendar::common::make_error("STORAGE_IO_ERROR", "Storage input/output operation failed"));
  }

  Result<std::optional<Event>> find_by_id(std::string_view /*id*/) override {
    return Result<std::optional<Event>>::failure(
        excellent_calendar::common::make_error("STORAGE_IO_ERROR", "Storage input/output operation failed"));
  }

  Result<std::vector<Event>> find_all() override {
    return Result<std::vector<Event>>::failure(
        excellent_calendar::common::make_error("STORAGE_IO_ERROR", "Storage input/output operation failed"));
  }
};

void service_tests() {
  int sequence = 0;
  auto repository = std::make_shared<MemoryRepository>();
  EventService service(
      repository,
      [] { return std::string("2026-06-08T12:00:00Z"); },
      [&] { return "event-" + std::to_string(++sequence); });

  CreateEventCommand command;
  command.title = "  Design review  ";
  command.start_at = "2026-06-08T13:00:00Z";
  command.end_at = "2026-06-08T14:00:00Z";
  command.is_all_day = false;
  command.source = "manual";

  auto created = service.create_event(command);
  require(created.ok(), "service create should succeed");
  require(created.value().id == "event-1", "service should generate id");
  require(created.value().title == "Design review", "service should trim title");
  require(created.value().status == "active", "service should default active status");
  require(created.value().created_at == created.value().updated_at, "created_at and updated_at should match");

  auto second = service.create_event(command);
  require(second.ok() && second.value().id == "event-2", "service should generate unique ids");

  command.title = " ";
  auto title_error = service.create_event(command);
  require(!title_error.ok() && title_error.error().code == "EVENT_TITLE_EMPTY", "blank title should be EVENT_TITLE_EMPTY");

  command.title = "Bad time";
  command.start_at = "2026-06-08T15:00:00Z";
  command.end_at = "2026-06-08T14:00:00Z";
  auto time_error = service.create_event(command);
  require(!time_error.ok() && time_error.error().code == "EVENT_TIME_INVALID", "start >= end should be EVENT_TIME_INVALID");

  EventService failing_service(
      std::make_shared<FailingRepository>(),
      [] { return std::string("2026-06-08T12:00:00Z"); },
      [] { return std::string("event-fail"); });
  command.start_at = "2026-06-08T13:00:00Z";
  command.end_at = "2026-06-08T14:00:00Z";
  auto repository_error = failing_service.create_event(command);
  require(!repository_error.ok() && repository_error.error().code == "STORAGE_IO_ERROR", "repository errors should propagate");
}

void repository_tests() {
  const auto dir = make_temp_dir("repository");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  excellent_calendar::storage::json::JsonEventRepository repository(dir);
  auto initialized = repository.initialize();
  require(initialized.ok(), "repository initialize should succeed");
  auto empty = repository.find_all();
  require(empty.ok() && empty.value().empty(), "missing events.json should read as empty list");

  auto created = repository.create(event_record("event-1", "中文标题 ✅", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z"));
  require(created.ok(), "repository create should succeed");
  auto second = repository.create(event_record("event-2", "Second", "2026-06-09T01:00:00Z", "2026-06-09T02:00:00Z"));
  require(second.ok(), "second repository create should succeed");

  excellent_calendar::storage::json::JsonEventRepository reloaded(dir);
  require(reloaded.initialize().ok(), "repository reinitialize should succeed");
  auto loaded = reloaded.find_all();
  require(loaded.ok() && loaded.value().size() == 2, "repository should persist records");
  require(loaded.value()[0].title == "中文标题 ✅", "repository should preserve UTF-8");

  cleanup();
}

void boundary_and_search_tests() {
  const auto dir = make_temp_dir("boundary");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));

  expect_error(excellent_calendar::boundary::api::create_event("{not-json"), "CONTRACT_VALIDATION_FAILED");
  expect_error(
      excellent_calendar::boundary::api::create_event(
          create_request("", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z")),
      "EVENT_TITLE_EMPTY");
  expect_error(
      excellent_calendar::boundary::api::create_event(
          create_request("Bad enum", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z", "category-work", "bad")),
      "CONTRACT_VALIDATION_FAILED");
  expect_error(
      excellent_calendar::boundary::api::create_event(
          create_request("Bad datetime", "2026-06-08 01:00:00", "2026-06-08T02:00:00Z")),
      "CONTRACT_VALIDATION_FAILED");
  expect_error(
      excellent_calendar::boundary::api::create_event(
          create_request("Bad range", "2026-06-08T02:00:00Z", "2026-06-08T02:00:00Z")),
      "EVENT_TIME_INVALID");

  auto recurrence_request = decode_object(create_request("Repeat", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z"));
  picojson::object recurrence;
  recurrence["frequency"] = picojson::value("weekly");
  recurrence["interval"] = picojson::value(1.0);
  recurrence["start_at"] = picojson::value("2026-06-08T01:00:00Z");
  recurrence["timezone"] = picojson::value("Asia/Shanghai");
  recurrence_request["recurrence"] = picojson::value(recurrence);
  expect_error(excellent_calendar::boundary::api::create_event(encode(recurrence_request)), "FEATURE_NOT_IMPLEMENTED");

  auto reminder_request = decode_object(create_request("Reminder", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z"));
  reminder_request["reminders"] = picojson::value(picojson::array{picojson::value(picojson::object{})});
  expect_error(excellent_calendar::boundary::api::create_event(encode(reminder_request)), "FEATURE_NOT_IMPLEMENTED");

  expect_ok(
      excellent_calendar::boundary::api::create_event(
          create_request("上海会议 ✅", "2026-06-08T01:00:00.000Z", "2026-06-08T02:00:00.000Z")));
  expect_ok(
      excellent_calendar::boundary::api::create_event(
          create_request("Coffee", "2026-06-09T01:00:00Z", "2026-06-09T02:00:00Z", "category-life", "important_noturgent", "Cafe")));
  expect_ok(
      excellent_calendar::boundary::api::create_event(
          create_request("Alpha", "2026-06-07T01:00:00Z", "2026-06-07T02:00:00Z", "category-work", "unimportant_noturgent", "Room 9")));

  const auto search_json = excellent_calendar::boundary::api::search_events(search_request("", 1, 2, "start_at", "asc"));
  expect_ok(search_json);
  const auto search = decode_object(search_json);
  const auto data = object_field(search, "data");
  const auto items = array_field(data, "items");
  require(items.size() == 2, "pagination should return first two events");
  const auto first = items[0].get<picojson::object>();
  require(string_field(first, "title") == "Alpha", "start_at asc should be stable and ordered");
  const auto pagination = object_field(data, "pagination");
  require(int_field(pagination, "total") == 3, "pagination total should be 3");
  require(bool_field(pagination, "has_more"), "pagination has_more should be true");

  auto keyword_query = decode_object(search_request("会议", 1, 20, "start_at", "asc"));
  auto keyword_result_json = excellent_calendar::boundary::api::search_events(encode(keyword_query));
  expect_ok(keyword_result_json);
  auto keyword_items = array_field(object_field(decode_object(keyword_result_json), "data"), "items");
  require(keyword_items.size() == 1, "keyword should match Chinese title");

  auto filter_query = decode_object(search_request("", 1, 20, "title", "asc"));
  filter_query["category_ids"] = picojson::value(picojson::array{picojson::value("category-life")});
  filter_query["importance"] = picojson::value(picojson::array{picojson::value("important_noturgent")});
  auto filtered_json = excellent_calendar::boundary::api::search_events(encode(filter_query));
  expect_ok(filtered_json);
  auto filtered_items = array_field(object_field(decode_object(filtered_json), "data"), "items");
  require(filtered_items.size() == 1, "category and importance filters should match one event");
  require(string_field(filtered_items[0].get<picojson::object>(), "title") == "Coffee", "filtered item should be Coffee");

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  auto reloaded_json = excellent_calendar::boundary::api::search_events(search_request());
  expect_ok(reloaded_json);
  require(array_field(object_field(decode_object(reloaded_json), "data"), "items").size() == 3,
          "reinitialize should keep persisted events");

  cleanup();
}

void soft_delete_and_corruption_tests() {
  const auto dir = make_temp_dir("corruption");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  {
    excellent_calendar::storage::json::JsonEventRepository repository(dir);
    require(repository.initialize().ok(), "repository initialize should succeed");
    require(repository.create(event_record("event-live", "Live", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z")).ok(),
            "live create should succeed");
    require(repository.create(event_record(
                "event-deleted",
                "Deleted",
                "2026-06-09T01:00:00Z",
                "2026-06-09T02:00:00Z",
                "2026-06-10T01:00:00Z"))
                .ok(),
            "deleted create should succeed");
  }

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  auto default_search = excellent_calendar::boundary::api::search_events(search_request());
  expect_ok(default_search);
  require(array_field(object_field(decode_object(default_search), "data"), "items").size() == 1,
          "default search should exclude deleted_at");

  auto include_deleted = decode_object(search_request());
  include_deleted["include_deleted"] = picojson::value(true);
  auto include_deleted_json = excellent_calendar::boundary::api::search_events(encode(include_deleted));
  expect_ok(include_deleted_json);
  require(array_field(object_field(decode_object(include_deleted_json), "data"), "items").size() == 2,
          "include_deleted should include soft-deleted records");

  const auto events_path = dir / "events.json";
  {
    std::ofstream output(events_path, std::ios::binary | std::ios::trunc);
    output << "{broken";
  }
  auto corrupted = excellent_calendar::boundary::api::search_events(search_request());
  expect_error(corrupted, "STORAGE_DATA_CORRUPTED");
  {
    std::ifstream input(events_path, std::ios::binary);
    std::string content((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    require(content == "{broken", "corrupted file should not be overwritten");
  }

  cleanup();
}

void concurrency_tests() {
  const auto dir = make_temp_dir("concurrency");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));

  std::vector<std::thread> threads;
  for (int index = 0; index < 24; ++index) {
    threads.emplace_back([index] {
      const auto title = "Concurrent " + std::to_string(index);
      const auto result = excellent_calendar::boundary::api::create_event(
          create_request(title, "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z"));
      expect_ok(result);
    });
  }
  for (auto& thread : threads) {
    thread.join();
  }

  auto search = excellent_calendar::boundary::api::search_events(search_request("", 1, 100));
  expect_ok(search);
  require(array_field(object_field(decode_object(search), "data"), "items").size() == 24,
          "concurrent create should not lose records");

  cleanup();
}

void initialize_failure_tests() {
  expect_error(excellent_calendar::boundary::api::initialize_storage(""), "STORAGE_PATH_INVALID");

  const auto dir = make_temp_dir("path_file");
  const auto file_path = dir / "not_a_directory";
  {
    std::ofstream output(file_path, std::ios::binary | std::ios::trunc);
    output << "file";
  }
  expect_error(excellent_calendar::boundary::api::initialize_storage(file_path.string()), "STORAGE_PATH_INVALID");
  std::filesystem::remove_all(dir);
}

}  // namespace

int main() {
  try {
    service_tests();
    repository_tests();
    boundary_and_search_tests();
    soft_delete_and_corruption_tests();
    concurrency_tests();
    initialize_failure_tests();
  } catch (const std::exception& error) {
    std::cerr << "event_core_tests failed: " << error.what() << '\n';
    return 1;
  }

  std::cout << "event_core_tests passed\n";
  return 0;
}
