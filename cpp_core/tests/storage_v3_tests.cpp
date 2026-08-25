#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/domain/reminder_recovery_batch.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/json/calendar_core_v3_storage_bootstrap.hpp"
#include "excellent_calendar/storage/json/calendar_workflow_coordinator.hpp"
#include "excellent_calendar/storage/json/category_json_codec.hpp"
#include "excellent_calendar/storage/json/json_anniversary_transaction.hpp"
#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace {

using excellent_calendar::common::Result;
using excellent_calendar::common::Unit;
using excellent_calendar::repository::RecurringEventState;
using excellent_calendar::storage::json::AtomicJsonFileStore;
using excellent_calendar::storage::json::CalendarWorkflowCoordinator;

constexpr const char* kNow = "2026-08-24T00:00:00Z";
constexpr const char* kEventId = "11111111-1111-4111-8111-111111111111";
constexpr const char* kRecurrenceId = "22222222-2222-4222-8222-222222222222";
constexpr const char* kOccurrenceKey = "33333333-3333-4333-8333-333333333333";
constexpr const char* kReminderId = "44444444-4444-4444-8444-444444444444";
constexpr const char* kNotificationId = "55555555-5555-4555-8555-555555555555";
constexpr const char* kDeliveryId = "66666666-6666-4666-8666-666666666666";
constexpr const char* kAttemptId = "77777777-7777-4777-8777-777777777777";
constexpr const char* kBatchId = "88888888-8888-4888-8888-888888888888";
constexpr const char* kRequestId = "99999999-9999-4999-8999-999999999999";
constexpr const char* kAnniversaryId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
constexpr const char* kAnniversaryRecurrenceId =
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
constexpr const char* kCategoryId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

Result<Unit> success() {
  return Result<Unit>::success(Unit{});
}

std::string error_text(const excellent_calendar::common::Error& error) {
  const auto reason = error.details.find("reason");
  return error.code + ": " + error.message +
         (reason == error.details.end() ? std::string{}
                                        : " (" + reason->second + ")");
}

Result<Unit> injected_failure(std::string phase) {
  return Result<Unit>::failure(excellent_calendar::common::make_error(
      "TEST_INTERRUPTION", "Injected storage interruption",
      {{"phase", std::move(phase)}}));
}

class TemporaryDirectory {
 public:
  TemporaryDirectory()
      : path_(std::filesystem::temp_directory_path() /
              ("excellent_calendar_storage_v3_" +
               excellent_calendar::common::generate_uuid_v4())) {
    std::filesystem::create_directories(path_);
  }

  ~TemporaryDirectory() {
    std::error_code ignored;
    std::filesystem::remove_all(path_, ignored);
  }

  const std::filesystem::path& path() const { return path_; }

 private:
  std::filesystem::path path_;
};

excellent_calendar::domain::Event populated_event() {
  excellent_calendar::domain::Event event;
  event.id = kEventId;
  event.title = "Preserved recurring event";
  event.content = "v2 body";
  event.start_at = "2026-08-24T08:00:00Z";
  event.end_at = "2026-08-24T09:00:00Z";
  event.has_recurrence = true;
  event.status = "active";
  event.recurrence_id = kRecurrenceId;
  event.recurrence_revision = 1;
  event.category_id = kCategoryId;
  event.importance = "important_urgent";
  event.location = "Shanghai";
  event.timezone = "Asia/Shanghai";
  event.source = "manual";
  event.created_at = "2026-01-01T00:00:00Z";
  event.updated_at = kNow;
  return event;
}

excellent_calendar::domain::Event ordinary_event() {
  auto event = populated_event();
  event.id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
  event.title = "Ordinary event";
  event.has_recurrence = false;
  event.recurrence_id = std::nullopt;
  event.recurrence_revision = std::nullopt;
  event.category_id = std::nullopt;
  return event;
}

excellent_calendar::domain::Reminder ordinary_reminder(
    std::string id = kReminderId,
    std::string target_id = kEventId) {
  excellent_calendar::domain::Reminder reminder;
  reminder.id = std::move(id);
  reminder.target_type = "event";
  reminder.target_id = std::move(target_id);
  reminder.remind_at = "2026-08-24T07:30:00Z";
  reminder.methods = {"popup"};
  reminder.message = "preserved reminder";
  reminder.is_enabled = true;
  reminder.status = "sent";
  reminder.scheduled_at = "2026-08-24T00:01:00Z";
  reminder.last_triggered_at = "2026-08-24T07:30:00Z";
  reminder.reactivated_at = "2026-08-23T00:00:00Z";
  reminder.reactivation_count = 2;
  reminder.source = "manual";
  reminder.created_at = "2026-01-01T00:00:00Z";
  reminder.updated_at = kNow;
  return reminder;
}

RecurringEventState populated_state() {
  RecurringEventState state;
  state.events.push_back(populated_event());

  excellent_calendar::domain::Recurrence recurrence;
  recurrence.id = kRecurrenceId;
  recurrence.revision = 1;
  recurrence.frequency = "daily";
  recurrence.start_at = "2026-08-24T08:00:00Z";
  recurrence.timezone = "Asia/Shanghai";
  recurrence.created_at = "2026-01-01T00:00:00Z";
  state.recurrences.push_back(recurrence);

  excellent_calendar::domain::EventOccurrenceState occurrence;
  occurrence.event_id = kEventId;
  occurrence.recurrence_revision = 1;
  occurrence.occurrence_key = kOccurrenceKey;
  occurrence.occurrence_start_at = "2026-08-24T08:00:00Z";
  occurrence.status = "completed";
  occurrence.state_changed_at = kNow;
  occurrence.created_at = "2026-08-24T00:00:00Z";
  occurrence.updated_at = kNow;
  state.occurrence_states.push_back(occurrence);

  state.reminders.push_back(ordinary_reminder());

  excellent_calendar::domain::Notification notification;
  notification.id = kNotificationId;
  notification.delivery_id = kDeliveryId;
  notification.delivery_attempt_id = kAttemptId;
  notification.kind = "reminder";
  notification.reminder_id = kReminderId;
  notification.target_type = "event";
  notification.target_id = kEventId;
  notification.method = "popup";
  notification.title = "Preserved notification";
  notification.body = "audit body";
  notification.planned_at = "2026-08-24T07:30:00Z";
  notification.prepared_at = "2026-08-24T07:29:00Z";
  notification.finalized_at = "2026-08-24T07:30:00Z";
  notification.sent_at = "2026-08-24T07:30:00Z";
  notification.status = "sent";
  notification.created_at = "2026-08-24T07:29:00Z";
  notification.updated_at = "2026-08-24T07:30:00Z";
  state.notifications.push_back(notification);

  excellent_calendar::domain::ReminderRecoveryBatch batch;
  batch.id = kBatchId;
  batch.recovery_request_id = kRequestId;
  batch.trigger_source = "app_start";
  batch.started_at = "2026-08-24T00:00:00Z";
  batch.window_start_at = "2026-08-21T00:00:00Z";
  batch.status = "completed";
  batch.completed_at = "2026-08-24T00:00:01Z";
  state.recovery_batches.push_back(batch);

  excellent_calendar::domain::Anniversary anniversary;
  anniversary.id = kAnniversaryId;
  anniversary.title = u8"迁移纪念日";
  anniversary.date = {2020, 2, 29};
  anniversary.calendar_type = "solar";
  anniversary.recurrence_id = kAnniversaryRecurrenceId;
  anniversary.note = u8"必须保留";
  anniversary.importance = "important_noturgent";
  anniversary.created_at = "2026-01-01T00:00:00Z";
  anniversary.updated_at = "2026-01-02T00:00:00Z";
  anniversary.reminders_enabled = false;
  state.anniversaries.push_back(anniversary);
  state.anniversary_recurrences.push_back(
      {kAnniversaryRecurrenceId, "yearly", 1, "2026-01-01T00:00:00Z",
       std::nullopt});

  auto valid = excellent_calendar::storage::json::validate_recurring_event_state(state);
  require(valid.ok(), "populated golden state must be valid: " +
                          (valid.ok() ? std::string{} : error_text(valid.error())));
  return state;
}

std::vector<excellent_calendar::storage::json::CategoryStorageRecord>
populated_categories() {
  return {{kCategoryId,
           "Work",
           std::optional<std::string>("preserved category"),
           "#3366FF",
           std::optional<std::string>("briefcase"),
           7,
           "2026-01-01T00:00:00Z",
           kNow,
           std::nullopt}};
}

picojson::object encoded_v3_roots(const RecurringEventState& state) {
  picojson::object roots;
  auto categories = excellent_calendar::storage::json::encode_category_store(
      populated_categories(), 3);
  require(categories.ok(), "category fixture encoding must succeed");
  roots["categories"] = std::move(categories.value());
  for (const auto& store :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    if (std::string_view(store.logical_name) == "categories") continue;
    auto encoded = excellent_calendar::storage::json::encode_recurring_event_store(
        store.file_name, state);
    require(encoded.ok(), std::string("fixture encoding failed for ") +
                              store.file_name +
                              (encoded.ok() ? std::string{}
                                            : ": " + error_text(encoded.error())));
    roots[store.logical_name] = std::move(encoded.value());
  }
  return roots;
}

void erase_v3_fields(picojson::object& roots) {
  for (auto& [logical_name, root_value] : roots) {
    auto& root = root_value.get<picojson::object>();
    root["storage_version"] = picojson::value(2.0);
    if (logical_name == "anniversaries") {
      for (auto& item : root.at("anniversaries").get<picojson::array>()) {
        item.get<picojson::object>().erase("reminders_enabled");
      }
    } else if (logical_name == "reminders") {
      for (auto& item : root.at("reminders").get<picojson::array>()) {
        auto& record = item.get<picojson::object>();
        for (const auto* field : {"template_key", "occurrence_date",
                                  "advance_days", "local_time",
                                  "timezone_mode", "fulfillment_delivery_id"}) {
          record.erase(field);
        }
      }
    } else if (logical_name == "notifications") {
      for (auto& item : root.at("notifications").get<picojson::array>()) {
        item.get<picojson::object>().erase("covered_reminder_ids");
      }
    } else if (logical_name == "reminder_recovery_batches") {
      for (auto& item :
           root.at("reminder_recovery_batches").get<picojson::array>()) {
        item.get<picojson::object>().erase("anniversary_catch_up_groups");
      }
    }
  }
}

picojson::object v2_roots(const RecurringEventState& state) {
  auto roots = encoded_v3_roots(state);
  roots.erase("anniversary_reminder_templates");
  erase_v3_fields(roots);
  return roots;
}

void write_v2_fixture(
    const std::filesystem::path& directory,
    const RecurringEventState& state,
    const std::set<std::string>& included = {}) {
  AtomicJsonFileStore store(directory);
  require(store.initialize().ok(), "fixture Store must initialize");
  auto roots = v2_roots(state);
  for (const auto& definition :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    const auto found = roots.find(definition.logical_name);
    if (found == roots.end() ||
        (!included.empty() && included.count(definition.logical_name) == 0U)) {
      continue;
    }
    auto written = store.write_json_file(definition.file_name, found->second);
    require(written.ok(), std::string("fixture write failed for ") +
                              definition.file_name);
  }
}

picojson::value read_required(AtomicJsonFileStore& store,
                              const std::string& file_name) {
  auto read = store.read_json_file(file_name);
  require(read.ok() && read.value().has_value(), file_name + " must exist");
  return std::move(*read.value());
}

picojson::value read_contract_golden() {
  std::ifstream input(EXCELLENT_CALENDAR_STORAGE_V3_GOLDEN,
                      std::ios::in | std::ios::binary);
  require(input.is_open(), "frozen Storage v3 golden fixture must be readable");
  picojson::value value;
  const auto error = picojson::parse(value, input);
  require(error.empty() && value.is<picojson::object>(),
          "frozen Storage v3 golden fixture must be valid JSON");
  return value;
}

void require_all_v3_roots(const std::filesystem::path& directory) {
  AtomicJsonFileStore store(directory);
  require(store.initialize().ok(), "v3 directory must initialize");
  for (const auto& definition :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    auto root = read_required(store, definition.file_name);
    const auto& object = root.get<picojson::object>();
    require(object.at("storage_version").get<double>() == 3.0,
            std::string(definition.file_name) + " must declare v3");
  }
  for (const auto& file : {"calendar_workflow_transactions.json",
                           "storage_migrations.json"}) {
    auto root = read_required(store, file);
    require(root.get<picojson::object>().at("storage_version").get<double>() ==
                3.0,
            std::string(file) + " must declare v3");
  }
}

void test_populated_v2_to_v3_golden_and_idempotency() {
  TemporaryDirectory directory;
  write_v2_fixture(directory.path(), populated_state());

  auto migrated = excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
      directory.path());
  require(migrated.ok() && migrated.value().migrated &&
              !migrated.value().resumed,
          "populated v2 fixture must migrate to v3");
  require_all_v3_roots(directory.path());

  excellent_calendar::storage::json::JsonRecurringEventTransaction transaction(
      directory.path());
  require(transaction.initialize().ok(), "migrated v3 transaction must initialize");
  auto loaded = transaction.load();
  require(loaded.ok(), "migrated golden state must load");
  require(loaded.value().events.size() == 1U &&
              loaded.value().events.front().title == "Preserved recurring event" &&
              loaded.value().recurrences.size() == 1U &&
              loaded.value().occurrence_states.size() == 1U &&
              loaded.value().reminders.size() == 1U &&
              loaded.value().reminders.front().status == "sent" &&
              loaded.value().reminders.front().reactivation_count == 2 &&
              loaded.value().notifications.size() == 1U &&
              loaded.value().notifications.front().status == "sent" &&
              loaded.value().recovery_batches.size() == 1U &&
              loaded.value().anniversaries.size() == 1U &&
              !loaded.value().anniversaries.front().reminders_enabled &&
              loaded.value().anniversary_recurrences.size() == 1U &&
              loaded.value().anniversary_reminder_templates.empty(),
          "golden migration must preserve every v2 aggregate and initialize only new fields");

  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "migrated raw Store must initialize");
  const auto golden = read_contract_golden();
  const auto& golden_root = golden.get<picojson::object>();
  require(golden_root.at("source_storage_version").get<double>() == 2.0 &&
              golden_root.at("target_storage_version").get<double>() == 3.0 &&
              golden_root.at("rerun_result").get<std::string>() ==
                  "already_migrated",
          "frozen migration golden must describe the supported v2-to-v3 path");
  const auto& expected = golden_root.at("expected").get<picojson::object>();
  const auto& expected_anniversary =
      expected.at("anniversary").get<picojson::object>();
  const auto anniversary_root = read_required(raw, "anniversaries.json");
  const auto& stored_anniversary =
      anniversary_root.get<picojson::object>()
          .at("anniversaries")
          .get<picojson::array>()
          .front()
          .get<picojson::object>();
  for (const auto& field_value :
       golden_root.at("preserve_exact_fields").get<picojson::array>()) {
    const auto& field = field_value.get<std::string>();
    require(stored_anniversary.at(field).serialize() ==
                expected_anniversary.at(field).serialize(),
            "golden migration must preserve Anniversary." + field);
  }
  require(stored_anniversary.at("reminders_enabled").serialize() ==
              expected_anniversary.at("reminders_enabled").serialize(),
          "golden migration must add reminders_enabled=false");
  const auto template_root =
      read_required(raw, "anniversary_reminder_templates.json");
  require(template_root.get<picojson::object>()
                  .at("anniversary_reminder_templates")
                  .serialize() ==
              expected.at("anniversary_reminder_templates").serialize(),
          "golden migration must create no Anniversary template");
  const auto reminder_root = read_required(raw, "reminders.json");
  const auto& stored_reminder = reminder_root.get<picojson::object>()
                                    .at("reminders")
                                    .get<picojson::array>()
                                    .front()
                                    .get<picojson::object>();
  for (const auto& [field, value] :
       expected.at("reminder_new_fields").get<picojson::object>()) {
    require(stored_reminder.at(field).serialize() == value.serialize(),
            "golden migration must map Reminder." + field);
  }
  const auto notification_root = read_required(raw, "notifications.json");
  require(notification_root.get<picojson::object>()
                  .at("notifications")
                  .get<picojson::array>()
                  .front()
                  .get<picojson::object>()
                  .at("covered_reminder_ids")
                  .serialize() ==
              expected.at("notification_covered_reminder_ids").serialize(),
          "golden migration must add empty covered Reminder membership");
  const auto recovery_root =
      read_required(raw, "reminder_recovery_batches.json");
  require(recovery_root.get<picojson::object>()
                  .at("reminder_recovery_batches")
                  .get<picojson::array>()
                  .front()
                  .get<picojson::object>()
                  .at("anniversary_catch_up_groups")
                  .serialize() ==
              expected.at("recovery_anniversary_catch_up_groups").serialize(),
          "golden migration must add empty Anniversary Recovery groups");
  std::map<std::string, std::string> before;
  for (const auto& definition :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    before[definition.file_name] =
        read_required(raw, definition.file_name).serialize();
  }
  before["calendar_workflow_transactions.json"] =
      read_required(raw, "calendar_workflow_transactions.json").serialize();
  before["storage_migrations.json"] =
      read_required(raw, "storage_migrations.json").serialize();

  auto repeated = excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
      directory.path());
  require(repeated.ok() && repeated.value().already_migrated,
          "repeated v3 bootstrap must be idempotent");
  for (const auto& [file, bytes] : before) {
    require(read_required(raw, file).serialize() == bytes,
            "repeated bootstrap must not rewrite " + file);
  }
  require(!std::filesystem::exists(directory.path() / "workflow_transactions.json") &&
              !std::filesystem::exists(
                  directory.path() / "anniversary_workflow_transactions.json"),
          "committed migration must remove both legacy journal inputs");
}

void test_real_device_partial_v2_fixture_migrates_without_data_loss() {
  TemporaryDirectory directory;
  const std::set<std::string> old_workflow_stores = {
      "events", "recurrence_versions", "event_occurrence_states", "reminders",
      "notifications", "reminder_recovery_batches"};
  write_v2_fixture(directory.path(), populated_state(), old_workflow_stores);
  require(!std::filesystem::exists(directory.path() / "anniversaries.json") &&
              !std::filesystem::exists(
                  directory.path() / "calendar_workflow_transactions.json"),
          "true-device fixture must omit newly introduced Stores");

  auto migrated = excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
      directory.path());
  require(migrated.ok(),
          "non-empty partial v2 storage must migrate instead of reporting incomplete");
  excellent_calendar::storage::json::JsonRecurringEventTransaction transaction(
      directory.path());
  require(transaction.initialize().ok(), "partial fixture v3 transaction must initialize");
  auto loaded = transaction.load();
  require(loaded.ok() && loaded.value().events.size() == 1U &&
              loaded.value().reminders.size() == 1U &&
              loaded.value().notifications.size() == 1U &&
              loaded.value().anniversaries.empty(),
          "partial migration must preserve old data without inventing Anniversary data");
  require_all_v3_roots(directory.path());
}

picojson::value prepared_legacy_workflow_journal(
    const picojson::object& roots) {
  const std::set<std::string> affected = {
      "events", "recurrence_versions", "event_occurrence_states", "reminders",
      "notifications", "reminder_recovery_batches"};
  picojson::array affected_json;
  picojson::object after;
  for (const auto& name : affected) {
    affected_json.emplace_back(name);
    after[name] = roots.at(name);
  }
  picojson::object intent;
  intent["after_stores"] = picojson::value(std::move(after));
  picojson::object transaction;
  transaction["transaction_id"] =
      picojson::value("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee");
  transaction["operation"] = picojson::value(
      "event_recurrence_and_first_reminder_create_or_update");
  transaction["intent_version"] = picojson::value(1.0);
  transaction["intent"] = picojson::value(std::move(intent));
  transaction["affected_stores"] = picojson::value(std::move(affected_json));
  transaction["state"] = picojson::value("prepared");
  transaction["prepared_at"] = picojson::value(kNow);
  transaction["committed_at"] = picojson::value();
  picojson::array transactions;
  transactions.emplace_back(std::move(transaction));
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root["transactions"] = picojson::value(std::move(transactions));
  return picojson::value(std::move(root));
}

picojson::value prepared_legacy_anniversary_journal(
    const picojson::object& roots) {
  const std::set<std::string> affected = {"anniversaries",
                                          "anniversary_recurrences"};
  picojson::array affected_json;
  picojson::object after;
  for (const auto& name : affected) {
    affected_json.emplace_back(name);
    after[name] = roots.at(name);
  }
  picojson::object intent;
  intent["after_stores"] = picojson::value(std::move(after));
  picojson::object transaction;
  transaction["transaction_id"] =
      picojson::value("efefefef-efef-4efe-8efe-efefefefefef");
  transaction["operation"] = picojson::value("anniversary_update");
  transaction["intent_version"] = picojson::value(1.0);
  transaction["intent"] = picojson::value(std::move(intent));
  transaction["affected_stores"] = picojson::value(std::move(affected_json));
  transaction["state"] = picojson::value("prepared");
  transaction["prepared_at"] = picojson::value(kNow);
  transaction["committed_at"] = picojson::value();
  picojson::array transactions;
  transactions.emplace_back(std::move(transaction));
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root["transactions"] = picojson::value(std::move(transactions));
  return picojson::value(std::move(root));
}

void test_legacy_prepared_journal_is_recovered_before_migration() {
  TemporaryDirectory directory;
  auto original = populated_state();
  write_v2_fixture(directory.path(), original);
  auto after_state = original;
  after_state.events.front().title = "Recovered before migration";
  after_state.anniversaries.front().title =
      "Recovered Anniversary before migration";
  auto after_roots = v2_roots(after_state);

  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "legacy journal fixture must initialize");
  require(raw.write_json_file("workflow_transactions.json",
                              prepared_legacy_workflow_journal(after_roots))
              .ok(),
          "prepared legacy journal fixture must be written");
  require(raw.write_json_file(
                 "anniversary_workflow_transactions.json",
                 prepared_legacy_anniversary_journal(after_roots))
              .ok(),
          "prepared legacy Anniversary journal fixture must be written");

  auto migrated = excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
      directory.path());
  require(migrated.ok(), "legacy prepared journal must recover then migrate");
  excellent_calendar::storage::json::JsonRecurringEventTransaction transaction(
      directory.path());
  require(transaction.initialize().ok(), "recovered transaction must initialize");
  auto loaded = transaction.load();
  require(loaded.ok() &&
              loaded.value().events.front().title == "Recovered before migration" &&
              loaded.value().anniversaries.front().title ==
                  "Recovered Anniversary before migration",
          "migration must use both recovered v2 after-images as its source");
  require(!std::filesystem::exists(directory.path() / "workflow_transactions.json") &&
              !std::filesystem::exists(
                  directory.path() / "anniversary_workflow_transactions.json"),
          "both legacy journals must be removed only after committed migration");
}

void test_every_migration_store_replacement_resumes() {
  std::vector<std::string> files;
  for (const auto& store :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    files.emplace_back(store.file_name);
  }
  files.emplace_back("calendar_workflow_transactions.json");

  for (const auto& file : files) {
    TemporaryDirectory directory;
    write_v2_fixture(directory.path(), populated_state());
    bool failed = false;
    auto interrupted =
        excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
            directory.path(), [&](std::string_view phase) {
              const auto expected = std::string("migration_after_store:") + file;
              if (!failed && phase == expected) {
                failed = true;
                return injected_failure(expected);
              }
              return success();
            });
    require(!interrupted.ok() && failed,
            "migration failure hook must interrupt after replacing " + file);
    require(std::filesystem::exists(directory.path() / "storage_migrations.json"),
            "interrupted migration must retain its recovery record");

    auto resumed = excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
        directory.path());
    require(resumed.ok() && resumed.value().resumed,
            "migration must resume after interruption at " + file);
    require_all_v3_roots(directory.path());
  }
}

void test_v3_round_trip_and_strict_rejection() {
  TemporaryDirectory directory;
  write_v2_fixture(directory.path(), populated_state());
  require(excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
              directory.path())
              .ok(),
          "strict-reader fixture must migrate");
  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "strict-reader raw Store must initialize");

  RecurringEventState decoded;
  std::map<std::string, picojson::value> roots;
  for (const auto& store :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    roots[store.logical_name] = read_required(raw, store.file_name);
    if (std::string_view(store.logical_name) == "categories") {
      auto categories = excellent_calendar::storage::json::decode_category_store(
          roots.at(store.logical_name), 3);
      require(categories.ok(), "v3 Category reader must accept its writer output");
      auto reencoded = excellent_calendar::storage::json::encode_category_store(
          categories.value(), 3);
      require(reencoded.ok() && reencoded.value().serialize() ==
                                    roots.at(store.logical_name).serialize(),
              "Category v3 reader/writer round-trip must be stable");
    } else {
      auto read = excellent_calendar::storage::json::decode_recurring_event_store(
          store.file_name, roots.at(store.logical_name), decoded);
      require(read.ok(), std::string("v3 reader failed for ") + store.file_name);
    }
  }
  require(excellent_calendar::storage::json::validate_recurring_event_state(decoded)
              .ok(),
          "all decoded v3 roots must form one valid state");
  for (const auto& store :
       excellent_calendar::storage::json::calendar_core_v3_data_stores()) {
    if (std::string_view(store.logical_name) == "categories") continue;
    auto reencoded = excellent_calendar::storage::json::encode_recurring_event_store(
        store.file_name, decoded);
    require(reencoded.ok() &&
                reencoded.value().serialize() ==
                    roots.at(store.logical_name).serialize(),
            std::string(store.file_name) + " v3 round-trip must be stable");
  }

  auto unknown = roots.at("events");
  unknown.get<picojson::object>()["unknown"] = picojson::value(true);
  RecurringEventState rejected;
  auto unknown_result =
      excellent_calendar::storage::json::decode_recurring_event_store(
          "events.json", unknown, rejected);
  require(!unknown_result.ok() &&
              unknown_result.error().code == "STORAGE_DATA_CORRUPTED",
          "v3 roots must reject unknown fields");

  auto missing = roots.at("reminders");
  missing.get<picojson::object>()
      .at("reminders")
      .get<picojson::array>()
      .front()
      .get<picojson::object>()
      .erase("template_key");
  auto missing_result =
      excellent_calendar::storage::json::decode_recurring_event_store(
          "reminders.json", missing, rejected);
  require(!missing_result.ok() &&
              missing_result.error().code == "STORAGE_DATA_CORRUPTED",
          "v3 records must reject missing required nullable fields");

  auto migration = read_required(raw, "storage_migrations.json");
  migration.get<picojson::object>()["unknown"] = picojson::value(true);
  require(raw.write_json_file("storage_migrations.json", migration).ok(),
          "invalid migration fixture must be written");
  auto invalid_migration =
      excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
          directory.path());
  require(!invalid_migration.ok() &&
              invalid_migration.error().code ==
                  "CALENDAR_WORKFLOW_RECOVERY_FAILED",
          "migration records must reject unknown fields");
}

void test_invalid_generation_is_rejected() {
  TemporaryDirectory directory;
  require(excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
              directory.path())
              .ok(),
          "empty v3 fixture must bootstrap");
  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "generation raw Store must initialize");
  auto journal = read_required(raw, "calendar_workflow_transactions.json");
  journal.get<picojson::object>()
      .at("generations")
      .get<picojson::object>()["reminders"] = picojson::value(-1.0);
  require(raw.write_json_file("calendar_workflow_transactions.json", journal).ok(),
          "invalid generation fixture must be written");
  CalendarWorkflowCoordinator coordinator(directory.path());
  auto initialized = coordinator.initialize();
  require(!initialized.ok() &&
              initialized.error().code == "CALENDAR_WORKFLOW_RECOVERY_FAILED",
          "negative Store generations must fail initialization");
}

excellent_calendar::domain::Reminder anniversary_reminder(
    const excellent_calendar::domain::AnniversaryReminderTemplate& item) {
  auto occurrence_key = excellent_calendar::domain::anniversary_occurrence_key(
      item.anniversary_id, {2026, 8, 24});
  require(occurrence_key.ok(), "Anniversary occurrence key must derive");
  auto id = excellent_calendar::domain::anniversary_reminder_id(
      item.anniversary_id, occurrence_key.value(), item.template_key);
  require(id.ok(), "Anniversary Reminder id must derive");
  excellent_calendar::domain::Reminder reminder;
  reminder.id = id.value();
  reminder.target_type = "anniversary";
  reminder.target_id = item.anniversary_id;
  reminder.occurrence_key = occurrence_key.value();
  reminder.remind_at = "2026-08-23T01:00:00Z";
  reminder.methods = {"popup"};
  reminder.message = "Anniversary reminder";
  reminder.status = "pending";
  reminder.source = "manual";
  reminder.created_at = kNow;
  reminder.updated_at = kNow;
  reminder.template_key = item.template_key;
  reminder.occurrence_date = "2026-08-24";
  reminder.advance_days = item.advance_days;
  reminder.local_time = item.local_time;
  reminder.timezone_mode = "follow_device";
  return reminder;
}

void test_shared_coordinator_preserves_cross_workflow_writes_and_rejects_cas() {
  TemporaryDirectory directory;
  require(excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
              directory.path())
              .ok(),
          "cross-workflow fixture must bootstrap");
  excellent_calendar::storage::json::JsonRecurringEventTransaction recurring(
      directory.path());
  excellent_calendar::storage::json::JsonAnniversaryTransaction anniversary(
      directory.path());
  require(recurring.initialize().ok() && anniversary.initialize().ok(),
          "both workflow adapters must share one initialized coordinator");

  const std::string event_reminder_id =
      "12121212-1212-4212-8212-121212121212";
  auto event_commit = recurring.execute(
      "event_recurrence_and_first_reminder_create_or_update",
      "13131313-1313-4313-8313-131313131313", kNow,
      [&](RecurringEventState& state) {
        auto event = ordinary_event();
        auto reminder = ordinary_reminder(event_reminder_id, event.id);
        reminder.status = "pending";
        reminder.scheduled_at = std::nullopt;
        reminder.last_triggered_at = std::nullopt;
        reminder.reactivated_at = std::nullopt;
        reminder.reactivation_count = 0;
        state.events.push_back(event);
        state.reminders.push_back(reminder);
        return success();
      });
  require(event_commit.ok(), "Event workflow must commit its Reminder: " +
                                 (event_commit.ok()
                                      ? std::string{}
                                      : error_text(event_commit.error())));

  auto template_key =
      excellent_calendar::domain::anniversary_reminder_template_key(
          kAnniversaryId, 1, "09:00");
  require(template_key.ok(), "Anniversary template key must derive");
  excellent_calendar::domain::AnniversaryReminderTemplate reminder_template;
  reminder_template.template_key = template_key.value();
  reminder_template.anniversary_id = kAnniversaryId;
  reminder_template.advance_days = 1;
  reminder_template.local_time = "09:00";
  reminder_template.created_at = kNow;
  reminder_template.updated_at = kNow;
  auto anniversary_commit = anniversary.execute(
      "anniversary_create", "14141414-1414-4414-8414-141414141414", kNow,
      [&](excellent_calendar::repository::AnniversaryState& state) {
        excellent_calendar::domain::Anniversary item;
        item.id = kAnniversaryId;
        item.title = "Atomic anniversary";
        item.date = {2020, 8, 24};
        item.calendar_type = "solar";
        item.created_at = kNow;
        item.updated_at = kNow;
        item.reminders_enabled = true;
        state.anniversaries.push_back(item);
        state.reminder_templates.push_back(reminder_template);
        state.reminders.push_back(anniversary_reminder(reminder_template));
        return success();
      });
  require(anniversary_commit.ok(),
          "Anniversary workflow must atomically add its Reminder");
  auto combined = recurring.load();
  require(combined.ok() && combined.value().reminders.size() == 2U &&
              combined.value().events.size() == 1U &&
              combined.value().anniversaries.size() == 1U,
          "sequential workflows must preserve both Reminder projections");

  CalendarWorkflowCoordinator coordinator(directory.path());
  require(coordinator.initialize().ok(), "shared coordinator must initialize");
  auto stale_generations = coordinator.load_generations();
  require(stale_generations.ok(), "shared generations must load");
  const auto stale_reminder_generation =
      stale_generations.value().at("reminders");

  auto later = recurring.update_reminders(
      [&](const RecurringEventState&,
          std::vector<excellent_calendar::domain::Reminder>& reminders) {
        auto found = std::find_if(reminders.begin(), reminders.end(),
                                  [&](const auto& item) {
                                    return item.id == event_reminder_id;
                                  });
        require(found != reminders.end(), "Event Reminder must still exist");
        found->message = "later Recovery/Delivery write";
        found->updated_at = "2026-08-24T00:00:01Z";
        return success();
      });
  require(later.ok(), "later Reminder workflow must commit");

  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "CAS raw Store must initialize");
  const auto current_reminders = read_required(raw, "reminders.json");
  const auto current_bytes = current_reminders.serialize();
  auto current_generations = coordinator.load_generations();
  require(current_generations.ok() &&
              current_generations.value().at("reminders") ==
                  stale_reminder_generation + 1,
          "later write must advance Reminder generation exactly once");

  CalendarWorkflowCoordinator::CommitRequest stale;
  stale.operation = "anniversary_update_with_reminders";
  stale.transaction_id = "15151515-1515-4515-8515-151515151515";
  stale.prepared_at = "2026-08-24T00:00:02Z";
  stale.before_generation["reminders"] = stale_reminder_generation;
  stale.after_stores["reminders"] = current_reminders;
  auto rejected = coordinator.execute(stale);
  require(!rejected.ok() &&
              rejected.error().code == "CALENDAR_WORKFLOW_COMMIT_FAILED",
          "stale Anniversary after-image must fail with stable CAS error");
  require(read_required(raw, "reminders.json").serialize() == current_bytes,
          "rejected stale after-image must not overwrite current Reminder data");
  auto after_rejection = coordinator.load_generations();
  require(after_rejection.ok() &&
              after_rejection.value().at("reminders") ==
                  stale_reminder_generation + 1,
          "rejected CAS must not advance generation");

  auto forged_journal =
      read_required(raw, "calendar_workflow_transactions.json");
  picojson::array affected;
  affected.emplace_back("reminders");
  picojson::object before_generation;
  before_generation["reminders"] =
      picojson::value(static_cast<double>(stale_reminder_generation));
  picojson::object after_stores;
  after_stores["reminders"] = current_reminders;
  picojson::object forged_transaction;
  forged_transaction["transaction_id"] =
      picojson::value("17171717-1717-4717-8717-171717171717");
  forged_transaction["operation"] =
      picojson::value("anniversary_update_with_reminders");
  forged_transaction["intent_version"] = picojson::value(1.0);
  forged_transaction["affected_stores"] = picojson::value(std::move(affected));
  forged_transaction["before_generation"] =
      picojson::value(std::move(before_generation));
  forged_transaction["after_stores"] = picojson::value(std::move(after_stores));
  forged_transaction["state"] = picojson::value("prepared");
  forged_transaction["prepared_at"] = picojson::value("2026-08-24T00:00:03Z");
  forged_transaction["committed_at"] = picojson::value();
  picojson::array forged_transactions;
  forged_transactions.emplace_back(std::move(forged_transaction));
  forged_journal.get<picojson::object>()["transactions"] =
      picojson::value(std::move(forged_transactions));
  require(raw.write_json_file("calendar_workflow_transactions.json",
                              forged_journal)
              .ok(),
          "stale recovery journal fixture must be written");
  CalendarWorkflowCoordinator restarted(directory.path());
  auto stale_recovery = restarted.initialize();
  require(!stale_recovery.ok() &&
              stale_recovery.error().code ==
                  "CALENDAR_WORKFLOW_RECOVERY_FAILED",
          "journal recovery must reject stale before_generation");
  require(read_required(raw, "reminders.json").serialize() == current_bytes,
          "stale journal recovery must preserve the newer Reminder Store");
}

void test_post_commit_cleanup_failures_preserve_committed_success() {
  const auto exercise = [](std::string failure_phase,
                           std::string transaction_id,
                           bool retry_before_restart) {
    TemporaryDirectory directory;
    require(excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
                directory.path())
                .ok(),
            failure_phase + " fixture must bootstrap");

    bool interrupted = false;
    CalendarWorkflowCoordinator coordinator(
        directory.path(), [&](std::string_view phase) {
          if (!interrupted && phase == failure_phase) {
            interrupted = true;
            return injected_failure(std::string(phase));
          }
          return success();
        });
    require(coordinator.initialize().ok(),
            failure_phase + " coordinator must initialize");
    auto generations = coordinator.load_generations();
    require(generations.ok(), failure_phase + " generations must load");

    RecurringEventState after_state;
    after_state.events.push_back(ordinary_event());
    auto events = excellent_calendar::storage::json::encode_recurring_event_store(
        "events.json", after_state);
    require(events.ok(), failure_phase + " Event after-image must encode");

    CalendarWorkflowCoordinator::CommitRequest request;
    request.operation =
        "event_recurrence_and_first_reminder_create_or_update";
    request.transaction_id = std::move(transaction_id);
    request.prepared_at = kNow;
    request.before_generation["events"] =
        generations.value().at("events");
    request.after_stores["events"] = std::move(events.value());

    auto committed = coordinator.execute(request);
    require(committed.ok() && interrupted,
            failure_phase +
                " occurs after the authoritative marker and must still return committed success");

    AtomicJsonFileStore raw(directory.path());
    require(raw.initialize().ok(), failure_phase + " raw Store must initialize");
    auto journal = read_required(raw, "calendar_workflow_transactions.json");
    const auto& pending =
        journal.get<picojson::object>().at("transactions").get<picojson::array>();
    require(pending.size() == 1U &&
                pending.front()
                        .get<picojson::object>()
                        .at("state")
                        .get<std::string>() == "committed",
            failure_phase +
                " must retain a committed journal until cleanup can be retried");

    if (retry_before_restart) {
      auto retried = coordinator.execute(request);
      require(retried.ok(),
              failure_phase +
                  " retry with the same transaction id must replay committed success");
      auto after_retry = coordinator.load_generations();
      require(after_retry.ok() &&
                  after_retry.value().at("events") ==
                      generations.value().at("events") + 1,
              failure_phase +
                  " retry must not apply the committed after-image or generation twice");
    }

    excellent_calendar::storage::json::JsonRecurringEventTransaction restarted(
        directory.path());
    require(restarted.initialize().ok(),
            failure_phase + " restart must compact committed cleanup state");
    auto loaded = restarted.load();
    require(loaded.ok() && loaded.value().events.size() == 1U &&
                loaded.value().events.front().id == ordinary_event().id,
            failure_phase +
                " restart must preserve the already-authoritative Event exactly once");
    CalendarWorkflowCoordinator after_restart(directory.path());
    auto after_restart_generations = after_restart.load_generations();
    require(after_restart_generations.ok() &&
                after_restart_generations.value().at("events") ==
                    generations.value().at("events") + 1,
            failure_phase +
                " restart recovery must not advance the committed generation twice");
    journal = read_required(raw, "calendar_workflow_transactions.json");
    require(journal.get<picojson::object>()
                .at("transactions")
                .get<picojson::array>()
                .empty(),
            failure_phase + " restart must finish idempotent journal cleanup");
  };

  exercise("after_commit", "18181818-1818-4818-8818-181818181818",
           false);
  exercise("before_compact", "19191919-1919-4919-8919-191919191919",
           true);
}

void test_unified_prepared_journal_replays_frozen_after_image() {
  TemporaryDirectory directory;
  require(excellent_calendar::storage::json::prepare_calendar_core_v3_storage(
              directory.path())
              .ok(),
          "shared recovery fixture must bootstrap");
  bool interrupted = false;
  excellent_calendar::storage::json::JsonRecurringEventTransaction writer(
      directory.path(), [&](std::string_view phase) {
        if (!interrupted && phase == "after_store:events.json") {
          interrupted = true;
          return injected_failure(std::string(phase));
        }
        return success();
      });
  require(writer.initialize().ok(), "interrupted writer must initialize");
  auto commit = writer.execute(
      "event_recurrence_and_first_reminder_create_or_update",
      "16161616-1616-4616-8616-161616161616", kNow,
      [&](RecurringEventState& state) {
        state.events.push_back(ordinary_event());
        return success();
      });
  require(!commit.ok() && interrupted,
          "workflow fixture must stop after applying the first frozen after-image: " +
              (commit.ok() ? std::string{} : error_text(commit.error())));

  excellent_calendar::storage::json::JsonRecurringEventTransaction restarted(
      directory.path());
  require(restarted.initialize().ok(),
          "runtime restart must replay and compact the shared prepared journal");
  auto loaded = restarted.load();
  require(loaded.ok() && loaded.value().events.size() == 1U,
          "shared recovery must preserve the frozen Event after-image");
  AtomicJsonFileStore raw(directory.path());
  require(raw.initialize().ok(), "shared recovery raw Store must initialize");
  auto journal = read_required(raw, "calendar_workflow_transactions.json");
  require(journal.get<picojson::object>()
              .at("transactions")
              .get<picojson::array>()
              .empty(),
          "successful shared recovery must compact its journal");
}

}  // namespace

int main() {
  const std::vector<std::pair<std::string, void (*)()>> tests = {
      {"populated v2 to v3 golden and idempotency",
       test_populated_v2_to_v3_golden_and_idempotency},
      {"real-device partial v2 migration",
       test_real_device_partial_v2_fixture_migrates_without_data_loss},
      {"legacy prepared journal recovery",
       test_legacy_prepared_journal_is_recovered_before_migration},
      {"migration replacement interruption recovery",
       test_every_migration_store_replacement_resumes},
      {"v3 round-trip and strict rejection",
       test_v3_round_trip_and_strict_rejection},
      {"invalid generation rejection", test_invalid_generation_is_rejected},
      {"shared coordinator sequencing and CAS",
       test_shared_coordinator_preserves_cross_workflow_writes_and_rejects_cas},
      {"post-commit cleanup failures preserve committed success",
       test_post_commit_cleanup_failures_preserve_committed_success},
      {"unified prepared journal recovery",
       test_unified_prepared_journal_replays_frozen_after_image},
  };
  int failures = 0;
  for (const auto& [name, test] : tests) {
    try {
      test();
      std::cout << "[PASS] " << name << '\n';
    } catch (const std::exception& error) {
      ++failures;
      std::cerr << "[FAIL] " << name << ": " << error.what() << '\n';
    }
  }
  if (failures != 0) {
    std::cerr << failures << " Storage v3 test(s) failed\n";
    return 1;
  }
  return 0;
}
