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

#include "excellent_calendar/application/create_event_workflow_service.hpp"
#include "excellent_calendar/application/event_lifecycle_workflow_service.hpp"
#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/application/notification_service.hpp"
#include "excellent_calendar/application/reminder_service.hpp"
#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"
#include "excellent_calendar/storage/json/json_event_reminder_transaction.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "support/event_repository_fakes.hpp"

namespace {

using excellent_calendar::application::CreateEventCommand;
using excellent_calendar::application::CreateEventWorkflowCommand;
using excellent_calendar::application::CreateEventWorkflowService;
using excellent_calendar::application::CompleteEventCommand;
using excellent_calendar::application::EventQuery;
using excellent_calendar::application::EventLifecycleWorkflowService;
using excellent_calendar::application::EventService;
using excellent_calendar::application::ReopenEventCommand;
using excellent_calendar::application::ReminderDraftCommand;
using excellent_calendar::application::ReminderService;
using excellent_calendar::common::Error;
using excellent_calendar::common::Result;
using excellent_calendar::domain::Event;
using excellent_calendar::domain::Reminder;
using excellent_calendar::test_support::FailingEventRepository;
using excellent_calendar::test_support::InMemoryEventRepository;

class FailingUpdateReminderRepository final : public excellent_calendar::repository::ReminderRepository {
 public:
  explicit FailingUpdateReminderRepository(
      std::shared_ptr<excellent_calendar::repository::ReminderRepository> delegate)
      : delegate_(std::move(delegate)) {}

  Result<Reminder> create(const Reminder& reminder) override {
    return delegate_->create(reminder);
  }

  Result<std::optional<Reminder>> find_by_id(std::string_view id) override {
    return delegate_->find_by_id(id);
  }

  Result<Reminder> update(const Reminder& /*reminder*/) override {
    return Result<Reminder>::failure(
        excellent_calendar::common::make_error("STORAGE_IO_ERROR", "Storage input/output operation failed"));
  }

  Result<std::vector<Reminder>> find_all() override {
    return delegate_->find_all();
  }

 private:
  std::shared_ptr<excellent_calendar::repository::ReminderRepository> delegate_;
};

// 本文件没有引入 GoogleTest，因此用 require 作为最小断言工具。
// 条件失败时抛出异常，main() 会捕获异常并让测试程序以非零状态退出。
void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// 把边界 API 返回的 JSON 解码成对象；格式不合法或顶层不是 object 时立即让测试失败。
picojson::object decode_object(const std::string& json) {
  picojson::value value;
  const auto error = picojson::parse(value, json);
  require(error.empty(), "JSON parse failed: " + error + " json=" + json);
  require(value.is<picojson::object>(), "JSON value is not object");
  return value.get<picojson::object>();
}

// 以下 field 辅助函数同时检查“字段存在”和“字段类型正确”，让场景断言更简洁。
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

// 验证成功的 NativeResult 信封，而不只检查业务 data。
void expect_ok(const std::string& json) {
  const auto result = decode_object(json);
  require(bool_field(result, "ok"), "NativeResult expected ok=true: " + json);
  const auto error = result.find("error");
  require(error != result.end() && error->second.is<picojson::null>(), "ok result error must be null");
  require(int_field(result, "contract_version") == 1, "contract_version must be 1");
  require(!string_field(result, "request_id").empty(), "request_id must be populated");
}

// 验证失败的 NativeResult 结构以及预期错误码。
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

// 每个文件存储场景使用独立临时目录，避免测试之间共享 events.json 而相互污染。
std::filesystem::path make_temp_dir(const std::string& name) {
  auto path = std::filesystem::temp_directory_path() /
              ("excellent_calendar_" + name + "_" + excellent_calendar::common::generate_uuid_v4());
  std::filesystem::create_directories(path);
  return path;
}

std::string encode(const picojson::object& object) {
  return picojson::value(object).serialize();
}

std::string future_utc(int seconds_from_now) {
  const auto now = excellent_calendar::common::parse_iso8601_utc_epoch_seconds(
      excellent_calendar::common::utc_now_iso8601());
  require(now.has_value(), "test clock should produce valid UTC time");
  return excellent_calendar::common::format_epoch_seconds_utc_iso8601(*now + seconds_from_now);
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

picojson::object reminder_draft(int advance_minutes = 15) {
  picojson::object draft;
  draft["target_type"] = picojson::value("event");
  draft["target_id"] = picojson::value();
  draft["remind_at"] = picojson::value();
  draft["advance_minutes"] = picojson::value(static_cast<double>(advance_minutes));
  draft["methods"] = picojson::value(picojson::array{picojson::value("popup")});
  draft["message"] = picojson::value("Event reminder");
  draft["is_enabled"] = picojson::value(true);
  draft["source"] = picojson::value("manual");
  return draft;
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
  object["status"] = picojson::value(picojson::array{});
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

Reminder reminder_record(
    std::string id,
    std::string target_id,
    std::string status = "scheduled") {
  Reminder reminder;
  reminder.id = std::move(id);
  reminder.target_type = "event";
  reminder.target_id = std::move(target_id);
  reminder.remind_at = "2026-06-08T12:30:00Z";
  reminder.methods = {"popup"};
  reminder.advance_minutes = 30;
  reminder.message = "Lifecycle reminder";
  reminder.is_enabled = true;
  reminder.status = std::move(status);
  reminder.scheduled_at = "2026-06-08T12:00:00Z";
  reminder.last_triggered_at = std::nullopt;
  reminder.failure_reason = std::nullopt;
  reminder.cancellation_reason = std::nullopt;
  reminder.source = "manual";
  reminder.created_at = "2026-06-08T11:00:00Z";
  reminder.updated_at = "2026-06-08T11:00:00Z";
  reminder.deleted_at = std::nullopt;
  return reminder;
}

// 目的：验证 EventService 的业务规则，与 JSON 文件实现解耦。
// 方法：注入内存/失败 Repository 及固定时钟、ID 生成器，再检查结果和错误码。
void service_tests() {
  int sequence = 0;
  std::string clock_value = "2026-06-08T12:00:00Z";
  auto repository = std::make_shared<InMemoryEventRepository>();
  EventService service(
      repository,
      [&] { return clock_value; },
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
      std::make_shared<FailingEventRepository>(),
      [] { return std::string("2026-06-08T12:00:00Z"); },
      [] { return std::string("event-fail"); });
  command.start_at = "2026-06-08T13:00:00Z";
  command.end_at = "2026-06-08T14:00:00Z";
  auto repository_error = failing_service.create_event(command);
  require(!repository_error.ok() && repository_error.error().code == "STORAGE_IO_ERROR", "repository errors should propagate");

  CompleteEventCommand complete_command;
  complete_command.event_id = created.value().id;
  complete_command.completed_at = "2026-06-08T12:30:00Z";
  complete_command.source = "manual";
  clock_value = "2026-06-08T12:31:00Z";
  auto completed = service.complete_event(complete_command);
  require(completed.ok() && completed.value().status == "completed",
          "complete should persist completed status through repository update");
  require(completed.value().completed_at == complete_command.completed_at,
          "complete should persist the contract completed_at value");
  require(completed.value().updated_at == clock_value,
          "complete should update updated_at from the C++ clock");

  auto repeated_command = complete_command;
  repeated_command.completed_at = "2026-06-08T12:40:00Z";
  repeated_command.source = "sync";
  clock_value = "2026-06-08T12:45:00Z";
  auto repeated = service.complete_event(repeated_command);
  require(repeated.ok() && repeated.value().status == "completed",
          "completing an already completed event should be idempotent");
  require(repeated.value().completed_at == complete_command.completed_at,
          "idempotent complete should preserve the original completed_at");
  require(repeated.value().updated_at == completed.value().updated_at,
          "idempotent complete should preserve the original updated_at");

  EventQuery default_status_query;
  auto active_results = service.search_events(default_status_query);
  require(active_results.ok() && active_results.value().items.size() == 1 &&
              active_results.value().items[0].status == "active",
          "search without status should default to active events");

  EventQuery completed_query;
  completed_query.status = {"completed"};
  completed_query.sort_by = "updated_at";
  completed_query.sort_direction = "desc";
  auto completed_results = service.search_events(completed_query);
  require(completed_results.ok() && completed_results.value().items.size() == 1 &&
              completed_results.value().items[0].id == created.value().id,
          "search status=completed should return the completed event only");

  EventQuery invalid_status_query;
  invalid_status_query.status = {"done"};
  auto invalid_status = service.search_events(invalid_status_query);
  require(!invalid_status.ok() && invalid_status.error().code == "SEARCH_QUERY_INVALID",
          "direct service queries should reject invalid event statuses");

  auto missing_command = complete_command;
  missing_command.event_id = "event-missing";
  auto missing = service.complete_event(missing_command);
  require(!missing.ok() && missing.error().code == "EVENT_NOT_FOUND",
          "completing a missing event should return EVENT_NOT_FOUND");

  auto deleted_event = event_record(
      "event-deleted", "Deleted", "2026-06-08T13:00:00Z", "2026-06-08T14:00:00Z",
      "2026-06-08T12:10:00Z");
  deleted_event.status = "completed";
  deleted_event.completed_at = "2026-06-08T12:05:00Z";
  repository->events.push_back(deleted_event);
  auto deleted_command = complete_command;
  deleted_command.event_id = deleted_event.id;
  auto deleted = service.complete_event(deleted_command);
  require(!deleted.ok() && deleted.error().code == "EVENT_NOT_FOUND",
          "soft-deleted events should not be completable");
  auto completed_without_deleted = service.search_events(completed_query);
  require(completed_without_deleted.ok() && completed_without_deleted.value().items.size() == 1,
          "completed search should exclude soft-deleted events by default");

  auto recurring_event = event_record(
      "event-recurring", "Recurring", "2026-06-08T13:00:00Z", "2026-06-08T14:00:00Z");
  recurring_event.has_recurrence = true;
  recurring_event.recurrence_id = "recurrence-1";
  repository->events.push_back(recurring_event);
  auto recurring_command = complete_command;
  recurring_command.event_id = recurring_event.id;
  auto recurring = service.complete_event(recurring_command);
  require(!recurring.ok() && recurring.error().code == "FEATURE_NOT_IMPLEMENTED",
          "recurring events should remain outside single-event completion");

  ReopenEventCommand reopen_command{created.value().id};
  auto reopened = service.reopen_event(reopen_command);
  require(reopened.ok() && reopened.value().status == "active",
          "reopen should persist active status through repository update");
  require(!reopened.value().completed_at.has_value(), "reopen should clear completed_at");

  auto complete_repository_error = failing_service.complete_event(complete_command);
  require(!complete_repository_error.ok() && complete_repository_error.error().code == "STORAGE_IO_ERROR",
          "complete should propagate repository lookup errors");
}

// 目的：验证 JsonEventRepository 能真实持久化 Event，并在重新初始化后恢复数据。
// 方法：在临时目录写入记录，构造新的 Repository 读取同一目录并比较字段。
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

  auto completion_repository =
      std::make_shared<excellent_calendar::storage::json::JsonEventRepository>(dir);
  require(completion_repository->initialize().ok(), "completion repository should initialize");
  EventService completion_service(
      completion_repository,
      [] { return std::string("2026-06-08T03:01:00Z"); },
      [] { return std::string("unused-id"); });
  CompleteEventCommand complete_command;
  complete_command.event_id = "event-1";
  complete_command.completed_at = "2026-06-08T03:00:00Z";
  complete_command.source = "manual";
  auto completed = completion_service.complete_event(complete_command);
  require(completed.ok() && completed.value().status == "completed",
          "JSON repository should persist completed status");

  excellent_calendar::storage::json::JsonEventRepository completed_reloaded(dir);
  require(completed_reloaded.initialize().ok(), "completed repository should reinitialize");
  auto completed_after_restart = completed_reloaded.find_by_id("event-1");
  require(completed_after_restart.ok() && completed_after_restart.value().has_value(),
          "completed event should remain readable after restart");
  require(completed_after_restart.value()->status == "completed" &&
              completed_after_restart.value()->completed_at == complete_command.completed_at &&
              completed_after_restart.value()->updated_at == "2026-06-08T03:01:00Z",
          "completed fields should survive repository restart");

  cleanup();
}

// 目的：验证创建带提醒的 Event 时，Event 与 Reminder 会作为一个工作流共同落盘。
// 方法：从边界 API 发起请求，再直接读取两个 Repository 检查关联 ID 和初始状态。
void embedded_reminder_boundary_tests() {
  const auto dir = make_temp_dir("embedded_reminder");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  auto request = decode_object(
      create_request("Reminder Event", future_utc(7200), future_utc(10800)));
  auto draft = reminder_draft();
  draft["target_id"] = picojson::value("client-supplied-id");
  request["reminders"] = picojson::value(
      picojson::array{picojson::value(std::move(draft))});
  const auto response = decode_object(excellent_calendar::boundary::api::create_event(encode(request)));
  require(bool_field(response, "ok"), "event with reminder should be created");
  const auto event_id = string_field(object_field(response, "data"), "id");

  excellent_calendar::storage::json::JsonEventRepository event_repository(dir);
  excellent_calendar::storage::json::JsonReminderRepository reminder_repository(dir);
  require(event_repository.initialize().ok(), "event repository should initialize");
  require(reminder_repository.initialize().ok(), "reminder repository should initialize");
  const auto events = event_repository.find_all();
  const auto reminders = reminder_repository.find_all();
  require(events.ok() && events.value().size() == 1, "workflow should persist one Event");
  require(reminders.ok() && reminders.value().size() == 1, "workflow should persist one Reminder");
  require(reminders.value()[0].target_id == event_id, "Reminder should target the generated Event id");
  require(reminders.value()[0].status == "pending", "embedded Reminder should start pending");
  require(!std::filesystem::exists(dir / "event_reminder_transaction.json"),
          "committed workflow should remove its transaction journal");

  cleanup();
}

// 目的：验证 Reminder 校验失败时不会只留下 Event，避免跨仓库的半完成数据。
// 方法：制造非法提醒时间，随后确认两个仓库和事务日志都已回滚/清理。
void workflow_rollback_tests() {
  const auto dir = make_temp_dir("workflow_rollback");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  auto event_repository =
      std::make_shared<excellent_calendar::storage::json::JsonEventRepository>(dir);
  auto reminder_repository =
      std::make_shared<excellent_calendar::storage::json::JsonReminderRepository>(dir);
  auto transaction =
      std::make_shared<excellent_calendar::storage::json::JsonEventReminderTransaction>(dir);
  require(transaction->initialize().ok(), "transaction should initialize");
  require(event_repository->initialize().ok(), "event repository should initialize");
  require(reminder_repository->initialize().ok(), "reminder repository should initialize");

  auto ids = std::make_shared<std::vector<std::string>>(
      std::initializer_list<std::string>{"event-id", "reminder-1", "reminder-2"});
  auto id_index = std::make_shared<std::size_t>(0);
  auto id_generator = [ids, id_index] {
    const auto index = (*id_index)++;
    return ids->at(index);
  };
  auto event_service = std::make_shared<EventService>(
      event_repository,
      [] { return std::string("2026-06-08T00:00:00Z"); },
      id_generator);
  auto reminder_service = std::make_shared<ReminderService>(
      reminder_repository,
      event_repository,
      [] { return std::string("2026-06-08T00:00:00Z"); },
      id_generator);
  CreateEventWorkflowService workflow(event_service, reminder_service, transaction);

  CreateEventWorkflowCommand command;
  command.event.title = "Atomic workflow";
  command.event.start_at = "2026-06-08T01:00:00Z";
  command.event.end_at = "2026-06-08T02:00:00Z";
  command.event.is_all_day = false;
  command.event.source = "manual";
  ReminderDraftCommand draft;
  draft.target_type = "event";
  draft.advance_minutes = 30;
  draft.methods = {"popup"};
  draft.is_enabled = true;
  draft.source = "manual";
  auto past_draft = draft;
  past_draft.advance_minutes = std::nullopt;
  past_draft.remind_at = "2026-06-07T23:59:59Z";
  command.reminders = {draft, past_draft};

  const auto result = workflow.create_event(command);
  require(!result.ok() && result.error().code == "REMINDER_TIME_INVALID",
          "second past Reminder should fail the workflow");
  require(event_repository->find_all().ok() && event_repository->find_all().value().empty(),
          "failed workflow should roll back Event");
  require(reminder_repository->find_all().ok() && reminder_repository->find_all().value().empty(),
          "failed workflow should roll back every Reminder");
  require(!std::filesystem::exists(dir / "event_reminder_transaction.json"),
          "completed rollback should remove its transaction journal");

  cleanup();
}

// 目的：验证完成 Event 后取消 Reminder 的生命周期 workflow 仍是原子操作。
// 方法：让 Reminder update 失败，随后确认 Event 完成状态也被事务回滚。
void lifecycle_workflow_rollback_tests() {
  const auto dir = make_temp_dir("lifecycle_workflow_rollback");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  auto event_repository =
      std::make_shared<excellent_calendar::storage::json::JsonEventRepository>(dir);
  auto reminder_repository =
      std::make_shared<excellent_calendar::storage::json::JsonReminderRepository>(dir);
  auto transaction =
      std::make_shared<excellent_calendar::storage::json::JsonEventReminderTransaction>(dir);
  require(transaction->initialize().ok(), "lifecycle transaction should initialize");
  require(event_repository->initialize().ok(), "lifecycle event repository should initialize");
  require(reminder_repository->initialize().ok(), "lifecycle reminder repository should initialize");
  require(event_repository->create(
              event_record("event-lifecycle", "Lifecycle rollback", "2026-06-08T12:00:00Z", "2026-06-08T13:00:00Z"))
              .ok(),
          "lifecycle event should be created");
  require(reminder_repository->create(reminder_record("reminder-lifecycle", "event-lifecycle")).ok(),
          "lifecycle reminder should be created");

  auto event_service = std::make_shared<EventService>(
      event_repository,
      [] { return std::string("2026-06-08T12:05:00Z"); },
      [] { return std::string("unused-id"); });
  auto failing_reminder_repository =
      std::make_shared<FailingUpdateReminderRepository>(reminder_repository);
  EventLifecycleWorkflowService workflow(
      event_service,
      failing_reminder_repository,
      transaction,
      [] { return std::string("2026-06-08T12:05:00Z"); });

  CompleteEventCommand command;
  command.event_id = "event-lifecycle";
  command.completed_at = "2026-06-08T12:05:00Z";
  command.source = "manual";
  command.note = std::nullopt;
  auto completed = workflow.complete_event(command);
  require(!completed.ok() && completed.error().code == "STORAGE_IO_ERROR",
          "lifecycle workflow should surface Reminder update failure");

  auto event_after_failure = event_repository->find_by_id("event-lifecycle");
  require(event_after_failure.ok() && event_after_failure.value().has_value() &&
              event_after_failure.value()->status == "active" &&
              !event_after_failure.value()->completed_at.has_value(),
          "failed lifecycle workflow should roll back Event completion");
  auto reminder_after_failure = reminder_repository->find_by_id("reminder-lifecycle");
  require(reminder_after_failure.ok() && reminder_after_failure.value().has_value() &&
              reminder_after_failure.value()->status == "scheduled" &&
              reminder_after_failure.value()->is_enabled &&
              !reminder_after_failure.value()->deleted_at.has_value() &&
              !reminder_after_failure.value()->cancellation_reason.has_value(),
          "failed lifecycle workflow should leave Reminder unchanged");
  require(!std::filesystem::exists(dir / "event_reminder_transaction.json"),
          "failed lifecycle workflow should remove its transaction journal");

  cleanup();
}

// 目的：验证进程中断后，初始化过程能根据事务日志恢复未完成操作。
// 方法：手工写入未提交日志和 Event，再重新初始化事务并检查残留文件被清理。
void transaction_recovery_tests() {
  const auto dir = make_temp_dir("transaction_recovery");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  excellent_calendar::storage::json::AtomicJsonFileStore store(dir);
  require(store.initialize().ok(), "file store should initialize");
  picojson::object journal;
  journal["storage_version"] = picojson::value(1.0);
  journal["events_exists"] = picojson::value(false);
  journal["events"] = picojson::value();
  journal["reminders_exists"] = picojson::value(false);
  journal["reminders"] = picojson::value();
  require(store.write_json_file("event_reminder_transaction.json", picojson::value(journal)).ok(),
          "transaction preimage should be journaled");

  excellent_calendar::storage::json::JsonEventRepository event_repository(dir);
  require(event_repository.initialize().ok(), "event repository should initialize");
  require(event_repository.create(
              event_record("uncommitted-event", "Interrupted", "2026-06-08T01:00:00Z", "2026-06-08T02:00:00Z"))
              .ok(),
          "uncommitted Event should be written for recovery test");

  excellent_calendar::storage::json::JsonEventReminderTransaction recovered(dir);
  require(recovered.initialize().ok(), "transaction initialization should recover unfinished work");
  require(!std::filesystem::exists(dir / "events.json"), "recovery should remove uncommitted Event data");
  require(!std::filesystem::exists(dir / "reminders.json"), "recovery should preserve absent Reminder data");
  require(!std::filesystem::exists(dir / "event_reminder_transaction.json"),
          "recovery should remove the completed journal");

  cleanup();
}

// 目的：验证 C++ 公开 JSON 边界的 Contract 校验、搜索筛选、分页和生命周期操作。
// 方法：发送合法与非法 JSON，请求完成/重开 Event，并检查 NativeResult 和持久化结果。
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
  expect_error(excellent_calendar::boundary::api::create_event(encode(reminder_request)), "CONTRACT_VALIDATION_FAILED");

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

  auto lifecycle_request = decode_object(create_request("Lifecycle", future_utc(7200), future_utc(10800)));
  lifecycle_request["reminders"] = picojson::value(picojson::array{
      picojson::value(reminder_draft(15)),
      picojson::value(reminder_draft(30)),
      picojson::value(reminder_draft(45)),
  });
  const auto lifecycle_create = decode_object(
      excellent_calendar::boundary::api::create_event(encode(lifecycle_request)));
  require(bool_field(lifecycle_create, "ok"), "lifecycle event should be created");
  const auto lifecycle_id = string_field(object_field(lifecycle_create, "data"), "id");

  excellent_calendar::storage::json::JsonReminderRepository lifecycle_reminder_repository(dir);
  require(lifecycle_reminder_repository.initialize().ok(), "lifecycle reminder repository should initialize");
  auto lifecycle_reminders = lifecycle_reminder_repository.find_all();
  require(lifecycle_reminders.ok(), "lifecycle reminders should load");
  std::vector<excellent_calendar::domain::Reminder> target_reminders;
  for (auto reminder : lifecycle_reminders.value()) {
    if (reminder.target_id == lifecycle_id) {
      target_reminders.push_back(reminder);
    }
  }
  require(target_reminders.size() == 3, "lifecycle event should have three reminders");
  target_reminders[0].status = "scheduled";
  target_reminders[0].scheduled_at = excellent_calendar::common::utc_now_iso8601();
  target_reminders[1].status = "sent";
  target_reminders[1].last_triggered_at = excellent_calendar::common::utc_now_iso8601();
  target_reminders[2].status = "cancelled";
  target_reminders[2].is_enabled = false;
  target_reminders[2].deleted_at = excellent_calendar::common::utc_now_iso8601();
  target_reminders[2].cancellation_reason = "user_cancelled";
  for (const auto& reminder : target_reminders) {
    require(lifecycle_reminder_repository.update(reminder).ok(), "prepared reminder state should persist");
  }

  picojson::object complete_request;
  complete_request["event_id"] = picojson::value(lifecycle_id);
  complete_request["completed_at"] = picojson::value("2026-06-10T02:00:00Z");
  complete_request["source"] = picojson::value("manual");
  complete_request["note"] = picojson::value();
  const auto completed_json = excellent_calendar::boundary::api::complete_event(encode(complete_request));
  expect_ok(completed_json);
  const auto completed = object_field(decode_object(completed_json), "data");
  require(string_field(completed, "status") == "completed",
          "complete boundary should return EventResponse with completed status");
  require(string_field(completed, "completed_at") == "2026-06-10T02:00:00Z",
          "complete boundary should return the contract completed_at");
  require(!string_field(completed, "updated_at").empty(),
          "complete boundary should return updated_at");
  const auto deleted_at = completed.find("deleted_at");
  require(deleted_at != completed.end() && deleted_at->second.is<picojson::null>(),
          "completed event should remain non-deleted");

  auto after_complete = lifecycle_reminder_repository.find_all();
  require(after_complete.ok(), "reminders should load after complete");
  std::optional<excellent_calendar::domain::Reminder> completed_cancelled;
  std::optional<excellent_calendar::domain::Reminder> completed_sent;
  std::optional<excellent_calendar::domain::Reminder> completed_user_cancelled;
  for (const auto& reminder : after_complete.value()) {
    if (reminder.id == target_reminders[0].id) completed_cancelled = reminder;
    if (reminder.id == target_reminders[1].id) completed_sent = reminder;
    if (reminder.id == target_reminders[2].id) completed_user_cancelled = reminder;
  }
  require(completed_cancelled.has_value() &&
              completed_cancelled->status == "cancelled" &&
              !completed_cancelled->is_enabled &&
              completed_cancelled->deleted_at.has_value() &&
              !completed_cancelled->scheduled_at.has_value() &&
              completed_cancelled->cancellation_reason == std::optional<std::string>("event_completed"),
          "complete should cancel scheduled event reminders with event_completed reason");
  require(completed_sent.has_value() && completed_sent->status == "sent",
          "complete should not alter already sent reminders");
  require(completed_user_cancelled.has_value() &&
              completed_user_cancelled->status == "cancelled" &&
              completed_user_cancelled->cancellation_reason == std::optional<std::string>("user_cancelled"),
          "complete should not overwrite user-cancelled reminders");

  const auto original_updated_at = string_field(completed, "updated_at");
  auto legacy_scheduled = *completed_sent;
  legacy_scheduled.status = "scheduled";
  legacy_scheduled.is_enabled = true;
  legacy_scheduled.deleted_at = std::nullopt;
  legacy_scheduled.scheduled_at = excellent_calendar::common::utc_now_iso8601();
  legacy_scheduled.last_triggered_at = std::nullopt;
  legacy_scheduled.cancellation_reason = std::nullopt;
  require(lifecycle_reminder_repository.update(legacy_scheduled).ok(),
          "legacy scheduled reminder should be prepared");
  complete_request["completed_at"] = picojson::value("2026-06-10T02:30:00Z");
  complete_request["source"] = picojson::value("auto");
  const auto repeated_json = excellent_calendar::boundary::api::complete_event(encode(complete_request));
  expect_ok(repeated_json);
  const auto repeated = object_field(decode_object(repeated_json), "data");
  require(string_field(repeated, "completed_at") == "2026-06-10T02:00:00Z" &&
              string_field(repeated, "updated_at") == original_updated_at,
          "repeated complete should return the existing completed EventResponse unchanged");
  auto after_repeated_complete = lifecycle_reminder_repository.find_by_id(legacy_scheduled.id);
  require(after_repeated_complete.ok() &&
              after_repeated_complete.value().has_value() &&
              after_repeated_complete.value()->status == "cancelled" &&
              after_repeated_complete.value()->cancellation_reason == std::optional<std::string>("event_completed"),
          "repeated complete should clean legacy open reminders for completed events");

  auto missing_complete_request = complete_request;
  missing_complete_request["event_id"] = picojson::value("event-missing");
  expect_error(excellent_calendar::boundary::api::complete_event(encode(missing_complete_request)),
               "EVENT_NOT_FOUND");

  expect_ok(excellent_calendar::boundary::api::initialize_storage(dir.string()));
  const auto default_lifecycle_search_json =
      excellent_calendar::boundary::api::search_events(search_request("Lifecycle"));
  expect_ok(default_lifecycle_search_json);
  require(array_field(object_field(decode_object(default_lifecycle_search_json), "data"), "items").empty(),
          "search without status should not mix completed events into active results");

  auto completed_search_request = decode_object(search_request("Lifecycle", 1, 20, "updated_at", "desc"));
  completed_search_request["status"] =
      picojson::value(picojson::array{picojson::value("completed")});
  const auto completed_search_json = excellent_calendar::boundary::api::search_events(
      encode(completed_search_request));
  expect_ok(completed_search_json);
  const auto completed_items =
      array_field(object_field(decode_object(completed_search_json), "data"), "items");
  require(completed_items.size() == 1 &&
              string_field(completed_items[0].get<picojson::object>(), "status") == "completed",
          "event.search status=completed should return the persisted completed event");
  const auto completed_deleted_at = completed_items[0].get<picojson::object>().find("deleted_at");
  require(completed_deleted_at != completed_items[0].get<picojson::object>().end() &&
              completed_deleted_at->second.is<picojson::null>(),
          "completed search should return only non-deleted events by default");

  auto invalid_status_search = decode_object(search_request());
  invalid_status_search["status"] =
      picojson::value(picojson::array{picojson::value("done")});
  expect_error(excellent_calendar::boundary::api::search_events(encode(invalid_status_search)),
               "CONTRACT_VALIDATION_FAILED");

  picojson::object reopen_request;
  reopen_request["event_id"] = picojson::value(lifecycle_id);
  const auto reopened = object_field(
      decode_object(excellent_calendar::boundary::api::reopen_event(encode(reopen_request))),
      "data");
  require(string_field(reopened, "status") == "active",
          "reopen boundary should return EventResponse with active status");
  auto after_reopen_a = lifecycle_reminder_repository.find_by_id(target_reminders[0].id);
  auto after_reopen_b = lifecycle_reminder_repository.find_by_id(legacy_scheduled.id);
  auto after_reopen_user = lifecycle_reminder_repository.find_by_id(target_reminders[2].id);
  require(after_reopen_a.ok() && after_reopen_a.value().has_value() &&
              after_reopen_a.value()->status == "pending" &&
              after_reopen_a.value()->is_enabled &&
              !after_reopen_a.value()->deleted_at.has_value() &&
              !after_reopen_a.value()->cancellation_reason.has_value(),
          "reopen should restore future reminders cancelled by event completion");
  require(after_reopen_b.ok() && after_reopen_b.value().has_value() &&
              after_reopen_b.value()->status == "pending" &&
              after_reopen_b.value()->is_enabled,
          "reopen should restore legacy reminders cancelled by repeated completion cleanup");
  require(after_reopen_user.ok() && after_reopen_user.value().has_value() &&
              after_reopen_user.value()->status == "cancelled" &&
              after_reopen_user.value()->cancellation_reason == std::optional<std::string>("user_cancelled"),
          "reopen should not restore user-cancelled reminders");

  picojson::object update_request;
  update_request["id"] = picojson::value(lifecycle_id);
  expect_error(excellent_calendar::boundary::api::update_event(encode(update_request)),
               "FEATURE_NOT_IMPLEMENTED");
  update_request["title"] = picojson::value("   ");
  expect_error(excellent_calendar::boundary::api::update_event(encode(update_request)),
               "CONTRACT_VALIDATION_FAILED");

  picojson::object delete_request;
  delete_request["id"] = picojson::value(lifecycle_id);
  delete_request["delete_mode"] = picojson::value("soft");
  expect_error(excellent_calendar::boundary::api::delete_event(encode(delete_request)),
               "FEATURE_NOT_IMPLEMENTED");
  delete_request["delete_mode"] = picojson::value("invalid");
  expect_error(excellent_calendar::boundary::api::delete_event(encode(delete_request)),
               "CONTRACT_VALIDATION_FAILED");

  cleanup();
}

// 目的：验证软删除过滤，以及损坏的 JSON 不会被静默覆盖。
// 方法：准备正常/已删除记录并主动写坏文件，再检查查询结果和错误码。
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

// 目的：验证并发创建时文件锁和仓库锁不会丢失记录。
// 方法：启动 24 个线程同时调用公开 API，join 后查询并断言恰有 24 条数据。
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

// 目的：验证非法存储路径会返回稳定的 STORAGE_PATH_INVALID，而不是崩溃。
// 方法：分别传入空路径和普通文件路径，检查统一错误信封。
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

// A failed replacement must revoke every previously borrowed v1 writer. This
// exercises both direct repository-backed services and the two transaction
// workflows; the valid commands ensure STORAGE_NOT_INITIALIZED comes from the
// storage generation guard rather than unrelated command validation.
void stale_v1_runtime_borrower_tests() {
  const auto dir = make_temp_dir("stale_v1_runtime");
  auto cleanup = [&] { std::filesystem::remove_all(dir); };

  auto initialized = excellent_calendar::boundary::api::initialize_runtime(dir.string());
  require(initialized.ok(), "initial v1 runtime should initialize");
  auto stale_event_service = excellent_calendar::boundary::api::current_event_service();
  auto stale_reminder_service = excellent_calendar::boundary::api::current_reminder_service();
  auto stale_create_workflow =
      excellent_calendar::boundary::api::current_create_event_workflow_service();
  auto stale_notification_service =
      excellent_calendar::boundary::api::current_notification_service();
  require(stale_event_service && stale_reminder_service && stale_create_workflow &&
              stale_notification_service,
          "v1 runtime should publish all legacy borrowers");

  const auto invalid_path = dir / "not_a_directory";
  {
    std::ofstream output(invalid_path, std::ios::binary | std::ios::trunc);
    output << "file";
  }
  auto replacement = excellent_calendar::boundary::api::initialize_runtime(
      invalid_path.string());
  require(!replacement.ok() && replacement.error().code == "STORAGE_PATH_INVALID",
          "invalid v1 replacement should fail deterministically");
  require(!excellent_calendar::boundary::api::current_event_service() &&
              !excellent_calendar::boundary::api::current_reminder_service() &&
              !excellent_calendar::boundary::api::current_create_event_workflow_service() &&
              !excellent_calendar::boundary::api::current_notification_service(),
          "failed replacement must leave no newly published runtime services");

  CreateEventCommand event_command;
  event_command.title = "stale writer";
  event_command.start_at = future_utc(3600);
  event_command.end_at = future_utc(7200);
  event_command.is_all_day = false;
  event_command.timezone = "Asia/Shanghai";
  event_command.source = "manual";

  auto stale_event_write = stale_event_service->create_event(event_command);
  require(!stale_event_write.ok() &&
              stale_event_write.error().code == "STORAGE_NOT_INITIALIZED",
          "stale EventService must not write its old v1 directory");

  excellent_calendar::application::ReminderQuery reminder_query;
  auto stale_reminder_read = stale_reminder_service->list_reminders(reminder_query);
  require(!stale_reminder_read.ok() &&
              stale_reminder_read.error().code == "STORAGE_NOT_INITIALIZED",
          "stale ReminderService must not read its old v1 directory");

  CreateEventWorkflowCommand workflow_command;
  workflow_command.event = event_command;
  auto stale_event_transaction = stale_create_workflow->create_event(workflow_command);
  require(!stale_event_transaction.ok() &&
              stale_event_transaction.error().code == "STORAGE_NOT_INITIALIZED",
          "stale EventReminder transaction must reject before invoking its callback");

  excellent_calendar::application::ConsumeReminderAfterDeliveryCommand delivery_command;
  delivery_command.reminder_id = "00000000-0000-4000-8000-000000000001";
  delivery_command.method = "popup";
  delivery_command.title = "stale delivery";
  delivery_command.planned_at = "2026-06-08T12:00:00Z";
  delivery_command.sent_at = "2026-06-08T12:00:01Z";
  delivery_command.delete_after_sent = true;
  auto stale_delivery_transaction =
      stale_notification_service->consume_after_delivery(delivery_command);
  require(!stale_delivery_transaction.ok() &&
              stale_delivery_transaction.error().code == "STORAGE_NOT_INITIALIZED",
          "stale ReminderNotification transaction must reject before invoking its callback");

  for (const auto* file : {"events.json", "reminders.json", "notifications.json",
                           "event_reminder_transaction.json",
                           "reminder_notification_transaction.json"}) {
    require(!std::filesystem::exists(dir / file),
            std::string("stale borrower must not create old v1 file: ") + file);
  }
  cleanup();
}

}  // namespace

// CTest 运行的是这个可执行程序；任一场景抛异常即整体失败。
int main() {
  try {
    service_tests();
    repository_tests();
    embedded_reminder_boundary_tests();
    workflow_rollback_tests();
    lifecycle_workflow_rollback_tests();
    transaction_recovery_tests();
    boundary_and_search_tests();
    soft_delete_and_corruption_tests();
    concurrency_tests();
    stale_v1_runtime_borrower_tests();
    initialize_failure_tests();
  } catch (const std::exception& error) {
    std::cerr << "event_core_tests failed: " << error.what() << '\n';
    return 1;
  }

  std::cout << "event_core_tests passed\n";
  return 0;
}
