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
#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/boundary/api/notification_api.hpp"
#include "excellent_calendar/boundary/api/reminder_api.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_notification_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"
#include "support/event_repository_fakes.hpp"

namespace {

using excellent_calendar::application::CancelReminderCommand;
using excellent_calendar::application::CreateReminderCommand;
using excellent_calendar::application::MarkReminderFailedCommand;
using excellent_calendar::application::MarkReminderScheduledCommand;
using excellent_calendar::application::MarkReminderSentCommand;
using excellent_calendar::application::ListSchedulableRemindersCommand;
using excellent_calendar::application::NotificationService;
using excellent_calendar::application::ReminderQuery;
using excellent_calendar::application::ReminderIdCommand;
using excellent_calendar::application::ReminderService;
using excellent_calendar::common::Result;
using excellent_calendar::domain::Event;
using excellent_calendar::domain::Reminder;
using excellent_calendar::repository::EventRepository;
using excellent_calendar::repository::ReminderRepository;
using excellent_calendar::test_support::InMemoryEventRepository;

// 本文件使用轻量自定义断言；失败时抛异常，由 main() 转换为测试进程失败。
void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// 解码并校验边界返回值的顶层 JSON 类型，后续场景只需关注具体字段。
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

// 以下 field 辅助函数会同时检查字段存在性和 JSON 类型。
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

// 验证成功 NativeResult 的公共信封字段。
void expect_ok(const std::string& json) {
  const auto result = decode_object(json);
  require(bool_field(result, "ok"), "NativeResult expected ok=true: " + json);
  const auto error = result.find("error");
  require(error != result.end() && error->second.is<picojson::null>(), "ok result error must be null");
  require(int_field(result, "contract_version") == 1, "contract_version must be 1");
  require(!string_field(result, "request_id").empty(), "request_id must be populated");
}

// 验证失败 NativeResult 的公共结构和指定业务错误码。
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

// 先确认调用成功，再取出 data；避免测试在错误响应上继续做误导性的字段断言。
picojson::object data_object(const std::string& native_result_json) {
  expect_ok(native_result_json);
  return object_field(decode_object(native_result_json), "data");
}

// 为真实 JSON 存储测试创建互不干扰的临时目录。
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

class FailingUpdateReminderRepository final : public ReminderRepository {
 public:
  explicit FailingUpdateReminderRepository(std::shared_ptr<ReminderRepository> delegate)
      : delegate_(std::move(delegate)) {}

  Result<Reminder> create(const Reminder& reminder) override {
    return delegate_->create(reminder);
  }

  Result<std::optional<Reminder>> find_by_id(std::string_view id) override {
    return delegate_->find_by_id(id);
  }

  Result<Reminder> update(const Reminder& /*reminder*/) override {
    return Result<Reminder>::failure(excellent_calendar::common::make_error(
        "STORAGE_IO_ERROR", "Storage input/output operation failed", {}, true));
  }

  Result<std::vector<Reminder>> find_all() override {
    return delegate_->find_all();
  }

 private:
  std::shared_ptr<ReminderRepository> delegate_;
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

std::string schedulable_request(const std::string& from_at,
                                const std::string& to_at,
                                int limit = 128) {
  picojson::object object;
  object["from_at"] = picojson::value(from_at);
  object["to_at"] = picojson::value(to_at);
  object["limit"] = picojson::value(static_cast<double>(limit));
  object["include_failed"] = picojson::value(true);
  object["include_scheduled"] = picojson::value(false);
  object["supported_methods"] =
      picojson::value(picojson::array{picojson::value("popup")});
  return encode(object);
}

std::string create_notification_request(const std::string& reminder_id,
                                        const std::string& event_id,
                                        const std::string& planned_at,
                                        const std::string& sent_at) {
  picojson::object object;
  object["reminder_id"] = picojson::value(reminder_id);
  object["target_type"] = picojson::value("event");
  object["target_id"] = picojson::value(event_id);
  object["method"] = picojson::value("popup");
  object["title"] = picojson::value("Event reminder");
  object["body"] = picojson::value("Reminder body");
  object["planned_at"] = picojson::value(planned_at);
  object["sent_at"] = picojson::value(sent_at);
  object["status"] = picojson::value("sent");
  object["failure_reason"] = picojson::value();
  return encode(object);
}

std::string consume_request(const std::string& reminder_id,
                            const std::string& planned_at,
                            const std::string& sent_at) {
  picojson::object object;
  object["reminder_id"] = picojson::value(reminder_id);
  object["method"] = picojson::value("popup");
  object["title"] = picojson::value("Event reminder");
  object["body"] = picojson::value("Reminder body");
  object["planned_at"] = picojson::value(planned_at);
  object["sent_at"] = picojson::value(sent_at);
  object["delete_after_sent"] = picojson::value(true);
  return encode(object);
}

std::string create_event_and_get_id(const std::filesystem::path& dir) {
  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  const auto event_json = excellent_calendar::boundary::api::create_event(create_event_request());
  const auto event = data_object(event_json);
  return string_field(event, "id");
}

// 目的：验证 ReminderService 的时间、目标、提醒方式和状态迁移规则。
// 方法：注入内存仓库、固定时钟和顺序 ID，构造边界值并检查结果/错误码。
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
  const auto lifecycle_reminder_id = future_time_result.value().id;

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

  auto rescheduled = service.mark_scheduled(scheduled_command);
  require(rescheduled.ok() && rescheduled.value().status == "scheduled",
          "failed reminder should be schedulable again");
  MarkReminderSentCommand sent_command{
      created.value().id,
      "2026-06-08T12:10:00Z",
  };
  auto sent = service.mark_sent(sent_command);
  require(sent.ok() && sent.value().status == "sent", "mark sent should succeed");
  require(sent.value().last_triggered_at == sent_command.last_triggered_at,
          "last_triggered_at should come from the contract command");
  auto failed_after_sent = service.mark_failed(failed_command);
  require(!failed_after_sent.ok() && failed_after_sent.error().code == "REMINDER_ALREADY_CONSUMED",
          "sent reminder should not transition back to failed");

  auto disabled_status = service.disable_reminder(ReminderIdCommand{lifecycle_reminder_id});
  require(disabled_status.ok() && !disabled_status.value().is_enabled,
          "disable should persist is_enabled=false without cancellation");
  auto enabled_status = service.enable_reminder(ReminderIdCommand{lifecycle_reminder_id});
  require(enabled_status.ok() && enabled_status.value().is_enabled && enabled_status.value().status == "pending",
          "enable should restore enabled pending state");

  auto cancelled = service.cancel_reminder({lifecycle_reminder_id, std::nullopt});
  require(cancelled.ok(), "cancel should succeed");
  require(cancelled.value().status == "cancelled", "cancel status should be cancelled");
  require(!cancelled.value().is_enabled, "cancel should disable reminder");
  require(cancelled.value().deleted_at == "2026-06-08T12:00:00Z", "cancel should set deleted_at");

  auto repeated_cancel = service.cancel_reminder({lifecycle_reminder_id, std::nullopt});
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

void schedulable_service_tests() {
  auto events = std::make_shared<InMemoryEventRepository>();
  auto reminders = std::make_shared<MemoryReminderRepository>();
  auto add = [&](std::string id,
                 std::string remind_at,
                 std::string status,
                 bool enabled = true,
                 std::optional<std::string> deleted_at = std::nullopt,
                 std::vector<std::string> methods = {"popup"}) {
    auto reminder = reminder_record(std::move(id));
    reminder.remind_at = std::move(remind_at);
    reminder.status = std::move(status);
    reminder.is_enabled = enabled;
    reminder.deleted_at = std::move(deleted_at);
    reminder.methods = std::move(methods);
    reminders->reminders.push_back(std::move(reminder));
  };
  add("pending", "2026-06-08T12:10:00Z", "pending");
  add("failed", "2026-06-08T12:20:00Z", "failed");
  add("scheduled", "2026-06-08T12:30:00Z", "scheduled");
  add("sent", "2026-06-08T12:40:00Z", "sent");
  add("disabled", "2026-06-08T12:15:00Z", "pending", false);
  add("deleted", "2026-06-08T12:15:00Z", "pending", true, "2026-06-08T12:01:00Z");
  add("outside", "2026-06-08T14:00:00Z", "pending");
  add("unsupported", "2026-06-08T12:25:00Z", "pending", true, std::nullopt, {"ring"});

  ReminderService service(
      reminders,
      events,
      [] { return std::string("2026-06-08T12:00:00Z"); },
      [] { return std::string("unused"); });
  auto loaded = service.get_reminder({"pending"});
  require(loaded.ok() && loaded.value().id == "pending", "get_reminder should load by id");
  auto missing = service.get_reminder({"missing"});
  require(!missing.ok() && missing.error().code == "REMINDER_NOT_FOUND",
          "get_reminder should report missing ids");

  ListSchedulableRemindersCommand command;
  command.from_at = "2026-06-08T12:00:00Z";
  command.to_at = "2026-06-08T13:00:00Z";
  command.limit = 10;
  command.supported_methods = {"popup"};
  auto listed = service.list_schedulable_reminders(command);
  require(listed.ok() && listed.value().items.size() == 2,
          "schedulable should include only pending and failed by default");
  require(listed.value().items[0].id == "pending" && listed.value().items[1].id == "failed",
          "schedulable reminders should be ordered by remind_at");
  require(listed.value().unsupported_reminder_ids == std::vector<std::string>{"unsupported"},
          "eligible reminders with unsupported methods should be reported separately");

  command.include_failed = false;
  auto pending_only = service.list_schedulable_reminders(command);
  require(pending_only.ok() && pending_only.value().items.size() == 1 &&
              pending_only.value().items[0].id == "pending",
          "include_failed=false should exclude failed reminders");

  command.include_failed = true;
  command.include_scheduled = true;
  auto with_scheduled = service.list_schedulable_reminders(command);
  require(with_scheduled.ok() && with_scheduled.value().items.size() == 3,
          "include_scheduled=true should include scheduled reminders");

  command.limit = 1;
  auto limited = service.list_schedulable_reminders(command);
  require(limited.ok() && limited.value().items.size() == 1 && limited.value().has_more,
          "schedulable limit should set has_more when results are truncated");
  require(limited.value().next_cursor_remind_at.has_value() && limited.value().next_cursor_id.has_value(),
          "truncated schedulable page should return a keyset cursor");

  command.cursor_remind_at = limited.value().next_cursor_remind_at;
  command.cursor_id = limited.value().next_cursor_id;
  auto second_page = service.list_schedulable_reminders(command);
  require(second_page.ok() && !second_page.value().items.empty() &&
              second_page.value().items.front().id != limited.value().items.front().id,
          "keyset pagination should advance even when the previous item remains failed");

  command.cursor_remind_at = std::nullopt;
  command.cursor_id = std::nullopt;
  command.from_at = std::nullopt;
  command.to_at = std::nullopt;
  command.limit = 500;
  auto unbounded = service.list_schedulable_reminders(command);
  require(unbounded.ok() && unbounded.value().items.size() == 4,
          "unbounded scheduler query should include future reminders outside the old window");

  for (int index = 0; index < 501; ++index) {
    add("bulk-" + std::to_string(index), "2026-06-08T12:50:00Z", "pending");
  }
  command.from_at = "2026-06-08T12:00:00Z";
  command.to_at = "2026-06-08T13:00:00Z";
  command.limit = 500;
  auto bulk_first = service.list_schedulable_reminders(command);
  require(bulk_first.ok() && bulk_first.value().items.size() == 500 && bulk_first.value().has_more,
          "scheduler should expose more than the Android per-UID alarm cap without truncating the queue");
  command.cursor_remind_at = bulk_first.value().next_cursor_remind_at;
  command.cursor_id = bulk_first.value().next_cursor_id;
  auto bulk_second = service.list_schedulable_reminders(command);
  require(bulk_second.ok() && !bulk_second.value().items.empty(),
          "scheduler keyset cursor should drain reminders beyond the first 500");
}

void notification_delivery_tests() {
  const auto dir = make_temp_dir("notification_delivery");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };
  auto reminders = std::make_shared<excellent_calendar::storage::json::JsonReminderRepository>(dir);
  auto notifications = std::make_shared<excellent_calendar::storage::json::JsonNotificationRepository>(dir);
  auto transaction =
      std::make_shared<excellent_calendar::storage::json::JsonReminderNotificationTransaction>(dir);
  require(transaction->initialize().ok(), "delivery transaction should initialize");
  require(reminders->initialize().ok(), "delivery reminder repository should initialize");
  require(notifications->initialize().ok(), "notification repository should initialize");

  auto add = [&](std::string id,
                 std::string status,
                 bool enabled = true,
                 std::optional<std::string> deleted_at = std::nullopt) {
    auto reminder = reminder_record(std::move(id));
    reminder.status = std::move(status);
    reminder.is_enabled = enabled;
    reminder.deleted_at = std::move(deleted_at);
    require(reminders->create(reminder).ok(), "delivery test reminder should persist");
  };
  add("delivery", "scheduled");
  add("failed-log", "pending");
  add("direct", "pending");
  add("stale", "pending");
  add("disabled", "pending", false);
  add("cancelled", "cancelled", false);
  add("deleted", "pending", true, "2026-06-08T12:01:00Z");
  add("rollback", "pending");

  int sequence = 0;
  NotificationService service(
      reminders,
      notifications,
      transaction,
      [] { return std::string("2026-06-08T12:31:00Z"); },
      [&] { return "notification-" + std::to_string(++sequence); });

  excellent_calendar::application::CreateNotificationCommand failed_log;
  failed_log.reminder_id = "failed-log";
  failed_log.target_type = "event";
  failed_log.target_id = "event-1";
  failed_log.method = "popup";
  failed_log.title = "Failed delivery";
  failed_log.planned_at = "2026-06-08T12:30:00Z";
  failed_log.status = "failed";
  failed_log.failure_reason = "java.lang.Exception at /data/user/0/app/Notify.kt";
  auto failed_notification = service.create_notification(failed_log);
  require(failed_notification.ok() && failed_notification.value().status == "failed",
          "notification.create should persist failed delivery logs");
  require(failed_notification.value().reminder_id == std::optional<std::string>("failed-log") &&
              failed_notification.value().target_type == "event" &&
              failed_notification.value().target_id == "event-1",
          "notification log should retain reminder and target association");
  require(failed_notification.value().failure_reason->find("/data") == std::string::npos,
          "notification failure reason should not retain device paths");

  excellent_calendar::application::CreateNotificationCommand sent_log;
  sent_log.reminder_id = "delivery";
  sent_log.target_type = "event";
  sent_log.target_id = "event-1";
  sent_log.method = "popup";
  sent_log.title = "Event reminder";
  sent_log.body = "Body";
  sent_log.planned_at = "2026-06-08T12:30:00Z";
  sent_log.sent_at = "2026-06-08T12:30:01Z";
  sent_log.status = "sent";
  auto prepared = service.create_notification(sent_log);
  require(prepared.ok(), "notification.create should provide a stable sent notification id");

  excellent_calendar::application::ConsumeReminderAfterDeliveryCommand consume;
  consume.reminder_id = "delivery";
  consume.method = "popup";
  consume.title = "Event reminder";
  consume.body = "Body";
  consume.planned_at = "2026-06-08T12:30:00Z";
  consume.sent_at = "2026-06-08T12:30:01Z";
  consume.delete_after_sent = true;
  auto consumed = service.consume_after_delivery(consume);
  require(consumed.ok() && consumed.value().reminder.status == "sent",
          "consume should mark the reminder sent");
  require(consumed.value().reminder.last_triggered_at == consume.sent_at,
          "consume should persist last_triggered_at");
  require(consumed.value().notification.id == prepared.value().id,
          "consume should reuse the notification created before delivery finalization");

  auto repeated = service.consume_after_delivery(consume);
  require(repeated.ok() && repeated.value().notification.id == prepared.value().id,
          "repeated consume should return the original delivery result");
  auto after_repeat = notifications->find_all();
  require(after_repeat.ok() && after_repeat.value().size() == 2,
          "repeated consume should not create a duplicate notification log");

  auto direct_consume = consume;
  direct_consume.reminder_id = "direct";
  auto direct = service.consume_after_delivery(direct_consume);
  require(direct.ok() && direct.value().notification.id != prepared.value().id,
          "consume should create a notification when Kotlin did not prepare one first");

  auto stale_consume = consume;
  stale_consume.reminder_id = "stale";
  stale_consume.planned_at = "2026-06-08T12:29:00Z";
  auto stale = service.consume_after_delivery(stale_consume);
  require(!stale.ok() && stale.error().code == "REMINDER_NOT_DUE",
          "stale alarm planned_at should not consume an updated reminder");

  for (const auto& id : {"disabled", "cancelled", "deleted"}) {
    auto blocked_command = consume;
    blocked_command.reminder_id = id;
    auto blocked = service.consume_after_delivery(blocked_command);
    require(!blocked.ok() && blocked.error().code == "REMINDER_NOT_DELIVERABLE",
            std::string(id) + " reminder should not be deliverable");
  }

  auto failing_reminders = std::make_shared<FailingUpdateReminderRepository>(reminders);
  NotificationService failing_service(
      failing_reminders,
      notifications,
      transaction,
      [] { return std::string("2026-06-08T12:32:00Z"); },
      [] { return std::string("notification-rollback"); });
  auto rollback_command = consume;
  rollback_command.reminder_id = "rollback";
  auto rollback = failing_service.consume_after_delivery(rollback_command);
  require(!rollback.ok() && rollback.error().code == "STORAGE_IO_ERROR",
          "consume should propagate a Reminder update failure");
  auto after_rollback = notifications->find_all();
  require(after_rollback.ok() && after_rollback.value().size() == 3,
          "failed consume should roll back the newly created notification");
  auto rollback_reminder = reminders->find_by_id("rollback");
  require(rollback_reminder.ok() && rollback_reminder.value()->status == "pending",
          "failed consume should leave the Reminder unchanged");

  excellent_calendar::storage::json::JsonNotificationRepository reloaded(dir);
  require(reloaded.initialize().ok(), "notification repository should restart");
  auto persisted = reloaded.find_all();
  require(persisted.ok() && persisted.value().size() == 3,
          "notification logs should survive repository restart");
  require(!std::filesystem::exists(dir / "reminder_notification_transaction.json"),
          "committed consume should remove its transaction journal");
  cleanup();
}

// 目的：验证 Reminder 写入 JSON 后，重新构造 Repository 仍能读取完整数据。
// 方法：写入临时目录后模拟重启，并比较数量及 UTF-8 字段。
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

// 目的：验证 Reminder 的公开 JSON API 及 pending→scheduled/sent/failed/cancelled 状态变化。
// 方法：创建关联 Event 和 Reminder，逐个调用状态 API，并检查响应及底层软删除记录。
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
  const auto lifecycle_reminder = data_object(
      excellent_calendar::boundary::api::create_reminder(
          create_reminder_request(event_id, future_utc(5400), "Lifecycle reminder")));
  const auto lifecycle_reminder_id = string_field(lifecycle_reminder, "id");

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

  const auto failed_json = excellent_calendar::boundary::api::mark_reminder_failed(
      reminder_failed_request(
          reminder_id,
          "java.lang.IllegalStateException\n at /data/user/0/app/Alarm.kt:7"));
  const auto failed = data_object(failed_json);
  require(string_field(failed, "status") == "failed", "mark failed should update status");
  require(string_field(failed, "failure_reason").find("/data") == std::string::npos,
          "mark failed should sanitize paths");
  data_object(excellent_calendar::boundary::api::mark_reminder_scheduled(
      reminder_time_request(reminder_id, "scheduled_at", "2026-06-08T12:06:00Z")));
  const auto sent_json = excellent_calendar::boundary::api::mark_reminder_sent(
      reminder_time_request(reminder_id, "last_triggered_at", "2026-06-08T12:10:00Z"));
  const auto sent = data_object(sent_json);
  require(string_field(sent, "status") == "sent", "mark sent should update status");
  require(string_field(sent, "last_triggered_at") == "2026-06-08T12:10:00Z",
          "mark sent should retain last_triggered_at from request JSON");
  expect_error(
      excellent_calendar::boundary::api::mark_reminder_failed(
          reminder_failed_request(reminder_id, "late failure")),
      "REMINDER_ALREADY_CONSUMED");

  const auto disabled_json = excellent_calendar::boundary::api::disable_reminder(
      reminder_id_request(lifecycle_reminder_id));
  require(!bool_field(data_object(disabled_json), "is_enabled"),
          "disable boundary should persist is_enabled=false");
  const auto enabled_json = excellent_calendar::boundary::api::enable_reminder(
      reminder_id_request(lifecycle_reminder_id));
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

  const auto cancelled_json = excellent_calendar::boundary::api::cancel_reminder(
      cancel_request(lifecycle_reminder_id));
  const auto cancelled = data_object(cancelled_json);
  require(string_field(cancelled, "status") == "cancelled", "cancel should update status");
  require(!bool_field(cancelled, "is_enabled"), "cancel should disable reminder");
  require(!string_field(cancelled, "deleted_at").empty(), "cancel should set deleted_at");
  expect_ok(excellent_calendar::boundary::api::cancel_reminder(
      cancel_request(lifecycle_reminder_id)));

  const auto visible_list = data_object(excellent_calendar::boundary::api::list_reminders(list_request(false)));
  require(array_field(visible_list, "items").size() == 1,
          "ordinary list should keep sent reminder and hide soft-deleted reminder");
  const auto all_list = data_object(excellent_calendar::boundary::api::list_reminders(list_request(true)));
  require(array_field(all_list, "items").size() == 2, "include_deleted list should retain cancelled reminder");

  excellent_calendar::storage::json::JsonReminderRepository repository(dir);
  require(repository.initialize().ok(), "raw repository initialize should succeed");
  auto raw = repository.find_all();
  require(raw.ok() && raw.value().size() == 2, "raw storage should retain sent and cancelled reminders");
  require(raw.value()[1].deleted_at.has_value(), "raw retained reminder should carry deleted_at");

  cleanup();
}

// 目的：验证 native runtime 重新初始化后仍能列出先前保存的 Reminder。
// 方法：创建提醒、再次 initialize_storage，再通过边界 API 查询。
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

void delivery_boundary_tests() {
  const auto dir = make_temp_dir("delivery_boundary");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };
  const auto event_id = create_event_and_get_id(dir);
  const auto remind_at = future_utc(3600);
  const auto created = data_object(
      excellent_calendar::boundary::api::create_reminder(
          create_reminder_request(event_id, remind_at, "Delivery reminder")));
  const auto reminder_id = string_field(created, "id");

  const auto loaded = data_object(
      excellent_calendar::boundary::api::get_reminder(reminder_id_request(reminder_id)));
  require(string_field(loaded, "id") == reminder_id,
          "reminder.get should return the requested ReminderResponse");
  expect_error(
      excellent_calendar::boundary::api::get_reminder(reminder_id_request("missing")),
      "REMINDER_NOT_FOUND");

  const auto schedulable = data_object(
      excellent_calendar::boundary::api::list_schedulable_reminders(
          schedulable_request(future_utc(-60), future_utc(7200))));
  require(int_field(schedulable, "selected_count") == 1 &&
              array_field(schedulable, "items").size() == 1 &&
              !bool_field(schedulable, "has_more"),
          "list_schedulable should return the pending reminder in the requested window");

  auto unsupported_scan = decode_object(
      schedulable_request(future_utc(-60), future_utc(7200)));
  unsupported_scan["supported_methods"] =
      picojson::value(picojson::array{picojson::value("ring")});
  expect_error(
      excellent_calendar::boundary::api::list_schedulable_reminders(encode(unsupported_scan)),
      "CONTRACT_VALIDATION_FAILED");

  const auto scheduled_at = excellent_calendar::common::utc_now_iso8601();
  const auto scheduled = data_object(
      excellent_calendar::boundary::api::mark_reminder_scheduled(
          reminder_time_request(reminder_id, "scheduled_at", scheduled_at)));
  require(string_field(scheduled, "status") == "scheduled",
          "mark_scheduled should persist scheduled status");

  const auto sent_at = remind_at;
  const auto notification = data_object(
      excellent_calendar::boundary::api::create_notification(
          create_notification_request(reminder_id, event_id, remind_at, sent_at)));
  const auto notification_id = string_field(notification, "id");
  require(string_field(notification, "reminder_id") == reminder_id &&
              string_field(notification, "target_type") == "event" &&
              string_field(notification, "target_id") == event_id,
          "notification.create should preserve reminder and target linkage");

  auto mismatched_notification = decode_object(
      create_notification_request(reminder_id, "wrong-target", remind_at, sent_at));
  expect_error(
      excellent_calendar::boundary::api::create_notification(encode(mismatched_notification)),
      "CONTRACT_VALIDATION_FAILED");

  const auto consumed = data_object(
      excellent_calendar::boundary::api::consume_reminder_after_delivery(
          consume_request(reminder_id, remind_at, sent_at)));
  require(string_field(object_field(consumed, "reminder"), "status") == "sent",
          "consume boundary should return sent ReminderResponse");
  require(string_field(object_field(consumed, "notification"), "id") == notification_id,
          "consume boundary should reuse the notification.create result");

  const auto repeated = data_object(
      excellent_calendar::boundary::api::consume_reminder_after_delivery(
          consume_request(reminder_id, remind_at, sent_at)));
  require(string_field(object_field(repeated, "notification"), "id") == notification_id,
          "repeated consume boundary call should be idempotent");

  const auto after_consumed = data_object(
      excellent_calendar::boundary::api::list_schedulable_reminders(
          schedulable_request(future_utc(-60), future_utc(7200))));
  require(array_field(after_consumed, "items").empty(),
          "sent reminder should no longer be returned by schedulable scan");

  excellent_calendar::storage::json::JsonNotificationRepository notification_repository(dir);
  require(notification_repository.initialize().ok(), "boundary notification repository should initialize");
  auto logs = notification_repository.find_all();
  require(logs.ok() && logs.value().size() == 1,
          "boundary create plus repeated consume should persist one notification log");
  cleanup();
}

// 目的：验证多个线程同时创建 Reminder 时不会覆盖或遗漏 JSON 记录。
// 方法：24 个线程并发调用 API，等待结束后断言列表包含 24 项。
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

// 目的：验证 reminders.json 损坏时返回明确错误，并保留原始坏文件供诊断。
// 方法：主动写入非法 JSON，再查询并确认错误码以及文件未被覆盖。
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

// CTest 以进程退出码判断结果；任一场景异常都会返回 1。
int main() {
  try {
    service_tests();
    schedulable_service_tests();
    notification_delivery_tests();
    repository_restart_tests();
    boundary_create_and_status_tests();
    boundary_restart_tests();
    delivery_boundary_tests();
    concurrency_tests();
    corruption_tests();
  } catch (const std::exception& error) {
    std::cerr << "reminder_core_tests failed: " << error.what() << '\n';
    return 1;
  }

  std::cout << "reminder_core_tests passed\n";
  return 0;
}
