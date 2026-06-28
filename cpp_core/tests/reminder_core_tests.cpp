#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/boundary/api/reminder_api.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "support/event_repository_fakes.hpp"

namespace {

using excellent_calendar::application::CancelReminderCommand;
using excellent_calendar::application::CreateReminderCommand;
using excellent_calendar::application::MarkReminderFailedCommand;
using excellent_calendar::application::MarkReminderScheduledCommand;
using excellent_calendar::application::MarkReminderSentCommand;
using excellent_calendar::application::ReminderQuery;
using excellent_calendar::application::ReminderIdCommand;
using excellent_calendar::application::ReminderService;
using excellent_calendar::common::Result;
using excellent_calendar::domain::Event;
using excellent_calendar::domain::Reminder;
using excellent_calendar::repository::EventRepository;
using excellent_calendar::repository::ReminderRepository;
using excellent_calendar::test_support::InMemoryEventRepository;

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

std::string encode(const picojson::object& object) {
  return picojson::value(object).serialize();
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

picojson::object data_object(const std::string& native_result_json) {
  expect_ok(native_result_json);
  return object_field(decode_object(native_result_json), "data");
}

std::filesystem::path make_temp_dir(const std::string& name) {
  auto path = std::filesystem::temp_directory_path() /
              ("excellent_calendar_reminder_" + name + "_" + excellent_calendar::common::generate_uuid_v4());
  std::filesystem::create_directories(path);
  return path;
}

Event event_record(std::string id = "event-1",
                   std::string start_at = "2026-06-08T13:00:00Z",
                   std::optional<std::string> deleted_at = std::nullopt) {
  Event event;
  event.id = std::move(id);
  event.title = "目标事件";
  event.content = std::nullopt;
  event.start_at = std::move(start_at);
  event.end_at = "2026-06-08T14:00:00Z";
  event.is_all_day = false;
  event.has_recurrence = false;
  event.status = "active";
  event.completed_at = std::nullopt;
  event.recurrence_id = std::nullopt;
  event.category_id = std::nullopt;
  event.importance = std::nullopt;
  event.location = std::nullopt;
  event.timezone = "Asia/Shanghai";
  event.source = "manual";
  event.created_at = "2026-06-08T12:00:00Z";
  event.updated_at = "2026-06-08T12:00:00Z";
  event.deleted_at = std::move(deleted_at);
  return event;
}

Reminder reminder_record(std::string id = "reminder-1",
                         std::string target_id = "event-1",
                         std::string message = "中文提醒 ✅") {
  Reminder reminder;
  reminder.id = std::move(id);
  reminder.target_type = "event";
  reminder.target_id = std::move(target_id);
  reminder.remind_at = "2026-06-08T12:30:00Z";
  reminder.methods = {"popup"};
  reminder.advance_minutes = 30;
  reminder.message = std::move(message);
  reminder.is_enabled = true;
  reminder.status = "pending";
  reminder.scheduled_at = std::nullopt;
  reminder.last_triggered_at = std::nullopt;
  reminder.failure_reason = std::nullopt;
  reminder.source = "manual";
  reminder.created_at = "2026-06-08T12:00:00Z";
  reminder.updated_at = "2026-06-08T12:00:00Z";
  reminder.deleted_at = std::nullopt;
  return reminder;
}

class MemoryReminderRepository final : public ReminderRepository {
 public:
  Result<Reminder> create(const Reminder& reminder) override {
    reminders.push_back(reminder);
    return Result<Reminder>::success(reminder);
  }

  Result<std::optional<Reminder>> find_by_id(std::string_view id) override {
    for (const auto& reminder : reminders) {
      if (reminder.id == std::string(id)) {
        return Result<std::optional<Reminder>>::success(reminder);
      }
    }
    return Result<std::optional<Reminder>>::success(std::nullopt);
  }

  Result<Reminder> update(const Reminder& reminder) override {
    for (auto& existing : reminders) {
      if (existing.id == reminder.id) {
        existing = reminder;
        return Result<Reminder>::success(reminder);
      }
    }
    return Result<Reminder>::failure(
        excellent_calendar::common::make_error("REMINDER_NOT_FOUND", "Reminder not found"));
  }

  Result<std::vector<Reminder>> find_all() override {
    return Result<std::vector<Reminder>>::success(reminders);
  }

  std::vector<Reminder> reminders;
};

CreateReminderCommand create_command(std::string target_id = "event-1") {
  CreateReminderCommand command;
  command.target_type = "event";
  command.target_id = std::move(target_id);
  command.remind_at = "2026-06-08T12:30:00Z";
  command.advance_minutes = 30;
  command.methods = {"popup", "ring"};
  command.message = "吃药提醒 ✅";
  command.is_enabled = true;
  command.source = "manual";
  return command;
}

std::string future_utc(int seconds_from_now) {
  const auto now = excellent_calendar::common::parse_iso8601_utc_epoch_seconds(
      excellent_calendar::common::utc_now_iso8601());
  require(now.has_value(), "test clock should produce valid UTC time");
  return excellent_calendar::common::format_epoch_seconds_utc_iso8601(*now + seconds_from_now);
}

std::string create_event_request() {
  picojson::object object;
  object["title"] = picojson::value("Event for reminder");
  object["content"] = picojson::value();
  object["start_at"] = picojson::value(future_utc(7200));
  object["end_at"] = picojson::value(future_utc(10800));
  object["is_all_day"] = picojson::value(false);
  object["category_id"] = picojson::value();
  object["importance"] = picojson::value();
  object["location"] = picojson::value();
  object["timezone"] = picojson::value("Asia/Shanghai");
  object["source"] = picojson::value("manual");
  object["recurrence"] = picojson::value();
  object["reminders"] = picojson::value(picojson::array{});
  return encode(object);
}

std::string create_reminder_request(const std::string& event_id,
                                    std::string remind_at = "",
                                    std::string message = "中文提醒 ✅") {
  picojson::array methods;
  methods.push_back(picojson::value("popup"));

  picojson::object object;
  object["target_type"] = picojson::value("event");
  object["target_id"] = picojson::value(event_id);
  object["remind_at"] = picojson::value(
      remind_at.empty() ? future_utc(3600) : std::move(remind_at));
  object["advance_minutes"] = picojson::value(30.0);
  object["methods"] = picojson::value(std::move(methods));
  object["message"] = picojson::value(std::move(message));
  object["is_enabled"] = picojson::value(true);
  object["source"] = picojson::value("manual");
  return encode(object);
}

std::string cancel_request(const std::string& reminder_id) {
  picojson::object object;
  object["id"] = picojson::value(reminder_id);
  object["reason"] = picojson::value();
  return encode(object);
}

std::string reminder_id_request(const std::string& reminder_id) {
  picojson::object object;
  object["id"] = picojson::value(reminder_id);
  return encode(object);
}

std::string reminder_time_request(const std::string& reminder_id,
                                  const std::string& field,
                                  const std::string& value) {
  picojson::object object;
  object["id"] = picojson::value(reminder_id);
  object[field] = picojson::value(value);
  return encode(object);
}

std::string reminder_failed_request(const std::string& reminder_id,
                                    const std::string& failure_reason) {
  picojson::object object;
  object["id"] = picojson::value(reminder_id);
  object["failure_reason"] = picojson::value(failure_reason);
  return encode(object);
}

std::string list_request(bool include_deleted = false, int page_size = 100) {
  picojson::object pagination;
  pagination["page"] = picojson::value(1.0);
  pagination["page_size"] = picojson::value(static_cast<double>(page_size));
  pagination["cursor"] = picojson::value();
  pagination["sort_by"] = picojson::value();
  pagination["sort_direction"] = picojson::value();

  picojson::object object;
  object["include_deleted"] = picojson::value(include_deleted);
  object["pagination"] = picojson::value(std::move(pagination));
  return encode(object);
}

std::string create_event_and_get_id(const std::filesystem::path& dir) {
  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  const auto event_json = excellent_calendar::boundary::api::create_event(create_event_request());
  const auto event = data_object(event_json);
  return string_field(event, "id");
}

void service_tests() {
  int sequence = 0;
  auto events = std::make_shared<InMemoryEventRepository>();
  events->events.push_back(event_record());
  auto reminders = std::make_shared<MemoryReminderRepository>();
  ReminderService service(
      reminders,
      events,
      [] { return std::string("2026-06-08T12:00:00Z"); },
      [&] { return "reminder-" + std::to_string(++sequence); });

  auto created = service.create_reminder(create_command());
  require(created.ok(), "valid reminder should be created");
  require(created.value().id == "reminder-1", "service should generate reminder id");
  require(created.value().status == "pending", "new reminder status should be pending");
  require(created.value().is_enabled, "new reminder should be enabled");
  require(!created.value().scheduled_at.has_value(), "new reminder scheduled_at should be null");
  require(!created.value().last_triggered_at.has_value(), "new reminder last_triggered_at should be null");
  require(!created.value().failure_reason.has_value(), "new reminder failure_reason should be null");
  require(!created.value().deleted_at.has_value(), "new reminder deleted_at should be null");

  auto second = service.create_reminder(create_command());
  require(second.ok() && second.value().id == "reminder-2", "ids should be unique across creates");

  auto missing_target = service.create_reminder(create_command("missing-event"));
  require(!missing_target.ok() && missing_target.error().code == "REMINDER_TARGET_NOT_FOUND",
          "missing target should be REMINDER_TARGET_NOT_FOUND");

  auto bad_time = create_command();
  bad_time.remind_at = "2026-06-08 12:30:00";
  auto bad_time_result = service.create_reminder(bad_time);
  require(!bad_time_result.ok() && bad_time_result.error().code == "REMINDER_TIME_INVALID",
          "bad remind_at should be REMINDER_TIME_INVALID");

  auto past_time = create_command();
  past_time.remind_at = "2026-06-08T11:59:59Z";
  auto past_time_result = service.create_reminder(past_time);
  require(!past_time_result.ok() && past_time_result.error().code == "REMINDER_TIME_INVALID",
          "past remind_at should be REMINDER_TIME_INVALID");
  require(past_time_result.error().details.at("field") == "remind_at",
          "past remind_at should identify the remind_at field");

  auto current_time = create_command();
  current_time.remind_at = "2026-06-08T12:00:00Z";
  auto current_time_result = service.create_reminder(current_time);
  require(!current_time_result.ok() && current_time_result.error().code == "REMINDER_TIME_INVALID",
          "remind_at equal to now should be REMINDER_TIME_INVALID");

  auto future_time = create_command();
  future_time.remind_at = "2026-06-08T12:00:01Z";
  auto future_time_result = service.create_reminder(future_time);
  require(future_time_result.ok(), "remind_at one second after now should succeed");

  auto empty_methods = create_command();
  empty_methods.methods.clear();
  auto empty_methods_result = service.create_reminder(empty_methods);
  require(!empty_methods_result.ok() && empty_methods_result.error().code == "REMINDER_METHOD_INVALID",
          "empty methods should be REMINDER_METHOD_INVALID");

  auto invalid_method = create_command();
  invalid_method.methods = {"popup", "bad"};
  auto invalid_method_result = service.create_reminder(invalid_method);
  require(!invalid_method_result.ok() && invalid_method_result.error().code == "REMINDER_METHOD_INVALID",
          "invalid method should be REMINDER_METHOD_INVALID");

  auto advance_only = create_command();
  advance_only.remind_at = std::nullopt;
  advance_only.advance_minutes = 30;
  auto advanced = service.create_reminder(advance_only);
  require(advanced.ok() && advanced.value().remind_at == "2026-06-08T12:30:00Z",
          "advance_minutes should derive remind_at from target event start_at");

  auto advance_equal_now = create_command();
  advance_equal_now.remind_at = std::nullopt;
  advance_equal_now.advance_minutes = 60;
  auto advance_equal_result = service.create_reminder(advance_equal_now);
  require(!advance_equal_result.ok() && advance_equal_result.error().code == "REMINDER_TIME_INVALID",
          "advance_minutes deriving now should be REMINDER_TIME_INVALID");

  auto advance_in_past = create_command();
  advance_in_past.remind_at = std::nullopt;
  advance_in_past.advance_minutes = 61;
  auto advance_in_past_result = service.create_reminder(advance_in_past);
  require(!advance_in_past_result.ok() && advance_in_past_result.error().code == "REMINDER_TIME_INVALID",
          "advance_minutes deriving a past time should be REMINDER_TIME_INVALID");

  auto advance_in_future = create_command();
  advance_in_future.remind_at = std::nullopt;
  advance_in_future.advance_minutes = 59;
  auto advance_in_future_result = service.create_reminder(advance_in_future);
  require(advance_in_future_result.ok() &&
              advance_in_future_result.value().remind_at == "2026-06-08T12:01:00Z",
          "advance_minutes deriving a future time should succeed");

  ReminderService invalid_clock_service(
      reminders,
      events,
      [] { return std::string("invalid-clock"); },
      [&] { return "reminder-" + std::to_string(++sequence); });
  auto invalid_clock_result = invalid_clock_service.create_reminder(create_command());
  require(!invalid_clock_result.ok() && invalid_clock_result.error().code == "NATIVE_INTERNAL_ERROR",
          "invalid injected clock should be NATIVE_INTERNAL_ERROR");

  auto unsupported = create_command();
  unsupported.target_type = "habit";
  unsupported.target_id = "habit-1";
  auto unsupported_result = service.create_reminder(unsupported);
  require(!unsupported_result.ok() && unsupported_result.error().code == "FEATURE_NOT_IMPLEMENTED",
          "habit target should not be silently accepted");

  auto disabled = create_command();
  disabled.is_enabled = false;
  auto disabled_result = service.create_reminder(disabled);
  require(!disabled_result.ok() && disabled_result.error().code == "CONTRACT_VALIDATION_FAILED",
          "disabled pending create should be rejected");

  MarkReminderScheduledCommand scheduled_command{
      created.value().id,
      "2026-06-08T12:05:00Z",
  };
  auto scheduled = service.mark_scheduled(scheduled_command);
  require(scheduled.ok(), "mark scheduled should succeed");
  require(scheduled.value().status == "scheduled", "status should be scheduled");
  require(scheduled.value().scheduled_at == scheduled_command.scheduled_at,
          "scheduled_at should come from the contract command");
  require(!scheduled.value().failure_reason.has_value(), "scheduled should clear failure_reason");

  MarkReminderSentCommand sent_command{
      created.value().id,
      "2026-06-08T12:10:00Z",
  };
  auto sent = service.mark_sent(sent_command);
  require(sent.ok() && sent.value().status == "sent", "mark sent should succeed");
  require(sent.value().last_triggered_at == sent_command.last_triggered_at,
          "last_triggered_at should come from the contract command");

  MarkReminderFailedCommand failed_command{
      created.value().id,
      "java.lang.Exception: nope\n\tat /data/user/0/app/Secret.kt:1",
  };
  auto failed = service.mark_failed(failed_command);
  require(failed.ok(), "mark failed should succeed");
  require(failed.value().status == "failed", "status should be failed");
  require(failed.value().failure_reason.has_value(), "failure_reason should be set");
  require(failed.value().failure_reason->find("/data") == std::string::npos, "failure reason should not store paths");
  require(failed.value().failure_reason->find("Secret.kt") == std::string::npos, "failure reason should not store stack frames");

  auto disabled_status = service.disable_reminder(ReminderIdCommand{created.value().id});
  require(disabled_status.ok() && !disabled_status.value().is_enabled,
          "disable should persist is_enabled=false without cancellation");
  auto enabled_status = service.enable_reminder(ReminderIdCommand{created.value().id});
  require(enabled_status.ok() && enabled_status.value().is_enabled && enabled_status.value().status == "pending",
          "enable should restore enabled pending state");

  auto cancelled = service.cancel_reminder({created.value().id, std::nullopt});
  require(cancelled.ok(), "cancel should succeed");
  require(cancelled.value().status == "cancelled", "cancel status should be cancelled");
  require(!cancelled.value().is_enabled, "cancel should disable reminder");
  require(cancelled.value().deleted_at == "2026-06-08T12:00:00Z", "cancel should set deleted_at");

  auto repeated_cancel = service.cancel_reminder({created.value().id, std::nullopt});
  require(repeated_cancel.ok() && repeated_cancel.value().status == "cancelled",
          "repeat cancel should be idempotent");

  auto listed = service.list_reminders(ReminderQuery{});
  require(listed.ok(), "list should succeed");
  for (const auto& reminder : listed.value().items) {
    require(!reminder.deleted_at.has_value(), "ordinary list should exclude soft-deleted reminders");
  }
  ReminderQuery include_deleted;
  include_deleted.include_deleted = true;
  auto all = service.list_reminders(include_deleted);
  require(all.ok() && all.value().items.size() == reminders->reminders.size(),
          "include_deleted should expose retained records");
}

void repository_restart_tests() {
  const auto dir = make_temp_dir("repository");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  {
    excellent_calendar::storage::json::JsonReminderRepository repository(dir);
    require(repository.initialize().ok(), "repository initialize should succeed");
    require(repository.find_all().ok() && repository.find_all().value().empty(),
            "missing reminders.json should read as empty list");
    auto created = repository.create(reminder_record());
    require(created.ok(), "repository create should succeed");
  }

  excellent_calendar::storage::json::JsonReminderRepository reloaded(dir);
  require(reloaded.initialize().ok(), "repository reinitialize should succeed");
  auto loaded = reloaded.find_all();
  require(loaded.ok() && loaded.value().size() == 1, "repository should persist reminder records");
  require(loaded.value()[0].message == "中文提醒 ✅", "repository should preserve UTF-8 message");

  cleanup();
}

void boundary_create_and_status_tests() {
  const auto dir = make_temp_dir("boundary");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  const auto event_id = create_event_and_get_id(dir);

  auto bad_method = decode_object(create_reminder_request(event_id));
  bad_method["methods"] = picojson::value(picojson::array{picojson::value("email")});
  expect_error(excellent_calendar::boundary::api::create_reminder(encode(bad_method)), "REMINDER_METHOD_INVALID");

  expect_error(
      excellent_calendar::boundary::api::create_reminder(create_reminder_request("missing-event")),
      "REMINDER_TARGET_NOT_FOUND");
  expect_error(
      excellent_calendar::boundary::api::create_reminder(create_reminder_request(event_id, "bad-time")),
      "REMINDER_TIME_INVALID");
  expect_error(
      excellent_calendar::boundary::api::create_reminder(
          create_reminder_request(event_id, future_utc(-60))),
      "REMINDER_TIME_INVALID");

  const auto created_json = excellent_calendar::boundary::api::create_reminder(create_reminder_request(event_id));
  const auto reminder = data_object(created_json);
  const auto reminder_id = string_field(reminder, "id");
  require(string_field(reminder, "status") == "pending", "boundary create should return pending");
  require(string_field(reminder, "message") == "中文提醒 ✅", "boundary should preserve Unicode message");

  expect_error(
      excellent_calendar::boundary::api::mark_reminder_scheduled(reminder_id_request(reminder_id)),
      "CONTRACT_VALIDATION_FAILED");
  expect_error(
      excellent_calendar::boundary::api::mark_reminder_scheduled(
          reminder_time_request(reminder_id, "scheduled_at", "bad-time")),
      "REMINDER_TIME_INVALID");
  const auto scheduled_json = excellent_calendar::boundary::api::mark_reminder_scheduled(
      reminder_time_request(reminder_id, "scheduled_at", "2026-06-08T12:05:00Z"));
  const auto scheduled = data_object(scheduled_json);
  require(string_field(scheduled, "status") == "scheduled", "mark scheduled should update status");
  require(string_field(scheduled, "scheduled_at") == "2026-06-08T12:05:00Z",
          "mark scheduled should retain scheduled_at from request JSON");

  const auto sent_json = excellent_calendar::boundary::api::mark_reminder_sent(
      reminder_time_request(reminder_id, "last_triggered_at", "2026-06-08T12:10:00Z"));
  const auto sent = data_object(sent_json);
  require(string_field(sent, "status") == "sent", "mark sent should update status");
  require(string_field(sent, "last_triggered_at") == "2026-06-08T12:10:00Z",
          "mark sent should retain last_triggered_at from request JSON");

  const auto failed_json = excellent_calendar::boundary::api::mark_reminder_failed(
      reminder_failed_request(
          reminder_id,
          "java.lang.IllegalStateException\n at /data/user/0/app/Alarm.kt:7"));
  const auto failed = data_object(failed_json);
  require(string_field(failed, "status") == "failed", "mark failed should update status");
  require(string_field(failed, "failure_reason").find("/data") == std::string::npos,
          "mark failed should sanitize paths");

  const auto disabled_json = excellent_calendar::boundary::api::disable_reminder(
      reminder_id_request(reminder_id));
  require(!bool_field(data_object(disabled_json), "is_enabled"),
          "disable boundary should persist is_enabled=false");
  const auto enabled_json = excellent_calendar::boundary::api::enable_reminder(
      reminder_id_request(reminder_id));
  const auto enabled = data_object(enabled_json);
  require(bool_field(enabled, "is_enabled") && string_field(enabled, "status") == "pending",
          "enable boundary should restore enabled pending state");

  expect_error(
      excellent_calendar::boundary::api::update_reminder(reminder_id_request(reminder_id)),
      "FEATURE_NOT_IMPLEMENTED");
  auto invalid_update = decode_object(reminder_id_request(reminder_id));
  invalid_update["unknown"] = picojson::value(true);
  expect_error(
      excellent_calendar::boundary::api::update_reminder(encode(invalid_update)),
      "CONTRACT_VALIDATION_FAILED");

  const auto cancelled_json = excellent_calendar::boundary::api::cancel_reminder(cancel_request(reminder_id));
  const auto cancelled = data_object(cancelled_json);
  require(string_field(cancelled, "status") == "cancelled", "cancel should update status");
  require(!bool_field(cancelled, "is_enabled"), "cancel should disable reminder");
  require(!string_field(cancelled, "deleted_at").empty(), "cancel should set deleted_at");
  expect_ok(excellent_calendar::boundary::api::cancel_reminder(cancel_request(reminder_id)));

  const auto visible_list = data_object(excellent_calendar::boundary::api::list_reminders(list_request(false)));
  require(array_field(visible_list, "items").empty(), "ordinary list should hide soft-deleted reminder");
  const auto all_list = data_object(excellent_calendar::boundary::api::list_reminders(list_request(true)));
  require(array_field(all_list, "items").size() == 1, "include_deleted list should retain cancelled reminder");

  excellent_calendar::storage::json::JsonReminderRepository repository(dir);
  require(repository.initialize().ok(), "raw repository initialize should succeed");
  auto raw = repository.find_all();
  require(raw.ok() && raw.value().size() == 1, "raw storage should still retain cancelled reminder");
  require(raw.value()[0].deleted_at.has_value(), "raw retained reminder should carry deleted_at");

  cleanup();
}

void boundary_restart_tests() {
  const auto dir = make_temp_dir("restart");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  const auto event_id = create_event_and_get_id(dir);
  expect_ok(excellent_calendar::boundary::api::create_reminder(create_reminder_request(event_id)));
  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  const auto listed = data_object(excellent_calendar::boundary::api::list_reminders(list_request(false)));
  require(array_field(listed, "items").size() == 1, "reinitialize should read persisted reminders");

  cleanup();
}

void concurrency_tests() {
  const auto dir = make_temp_dir("concurrency");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  const auto event_id = create_event_and_get_id(dir);
  std::vector<std::thread> threads;
  for (int index = 0; index < 24; ++index) {
    threads.emplace_back([event_id, index] {
      const auto message = "Concurrent reminder " + std::to_string(index);
      const auto result = excellent_calendar::boundary::api::create_reminder(
          create_reminder_request(event_id, future_utc(3600), message));
      expect_ok(result);
    });
  }
  for (auto& thread : threads) {
    thread.join();
  }

  const auto listed = data_object(excellent_calendar::boundary::api::list_reminders(list_request(false, 100)));
  require(array_field(listed, "items").size() == 24, "concurrent create should not lose reminder records");

  cleanup();
}

void corruption_tests() {
  const auto dir = make_temp_dir("corruption");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  const auto event_id = create_event_and_get_id(dir);
  expect_ok(excellent_calendar::boundary::api::create_reminder(create_reminder_request(event_id)));

  const auto reminders_path = dir / "reminders.json";
  {
    std::ofstream output(reminders_path, std::ios::binary | std::ios::trunc);
    output << "{broken";
  }

  expect_error(excellent_calendar::boundary::api::list_reminders(list_request(false)), "STORAGE_DATA_CORRUPTED");
  {
    std::ifstream input(reminders_path, std::ios::binary);
    std::string content((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    require(content == "{broken", "corrupted reminders.json should not be overwritten");
  }

  cleanup();
}

}  // namespace

int main() {
  try {
    service_tests();
    repository_restart_tests();
    boundary_create_and_status_tests();
    boundary_restart_tests();
    concurrency_tests();
    corruption_tests();
  } catch (const std::exception& error) {
    std::cerr << "reminder_core_tests failed: " << error.what() << '\n';
    return 1;
  }

  std::cout << "reminder_core_tests passed\n";
  return 0;
}
