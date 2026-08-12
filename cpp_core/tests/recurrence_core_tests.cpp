#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/reminder_service_v2.hpp"
#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_event_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/rolling_reminder_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"
#include "excellent_calendar/storage/json/json_category_repository.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"

namespace {

using excellent_calendar::domain::LocalDateTime;
using excellent_calendar::domain::LocalDateTimeResolution;
using excellent_calendar::infrastructure::time::TzdbLocalTimeResolver;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

std::shared_ptr<TzdbLocalTimeResolver> create_resolver() {
  auto result = TzdbLocalTimeResolver::create(
      std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR));
  require(result.ok(), result.ok() ? "" : result.error().message + ": " +
                                             result.error().details.at("reason"));
  return result.value();
}

void test_contract_uuid_v5_vectors() {
  constexpr const char* occurrence_namespace = "2fa8ebd0-958e-5eae-83d1-1aa5da893415";
  auto occurrence = excellent_calendar::common::generate_uuid_v5(
      occurrence_namespace,
      "[\"11111111-1111-4111-8111-111111111111\",1,\"2026-03-29T01:30:00\"]");
  require(occurrence.ok(), "timed occurrence UUID generation should succeed");
  require(occurrence.value() == "24c7eda2-669c-5400-bf21-b8291b40395e",
          "timed occurrence UUID must match Contract v2 vector");

  constexpr const char* reminder_namespace = "57b84799-6049-567e-8f29-ae597c333140";
  auto reminder = excellent_calendar::common::generate_uuid_v5(
      reminder_namespace,
      "[\"11111111-1111-4111-8111-111111111111\",1,\"24c7eda2-669c-5400-bf21-b8291b40395e\",15,[\"popup\"]]");
  require(reminder.ok(), "recurring reminder UUID generation should succeed");
  require(reminder.value() == "a5c24834-aa63-5130-a5f7-3fbcec2468c0",
          "recurring reminder UUID must match Contract v2 vector");

  constexpr const char* delivery_namespace = "74f9acf9-a4ce-59d1-9934-5cd7ce796976";
  auto delivery = excellent_calendar::common::generate_uuid_v5(
      delivery_namespace,
      "[\"a5c24834-aa63-5130-a5f7-3fbcec2468c0\",\"popup\"]");
  require(delivery.ok() && delivery.value() == "b35d3bf5-f666-54e6-8340-423379f37a77",
          "Reminder delivery UUID must match Contract v2 vector");
  auto summary = excellent_calendar::common::generate_uuid_v5(
      delivery_namespace,
      "[\"recovery_summary\",\"22222222-2222-4222-8222-222222222222\",\"popup\"]");
  require(summary.ok() && summary.value() == "0cb2958b-7c4a-5e0e-b4a7-8fd7eb048c87",
          "recovery summary UUID must match Contract v2 vector");
}

void test_london_dst_gap_moves_to_first_legal_instant() {
  auto resolver = create_resolver();
  auto resolved = resolver->resolve_local_datetime(
      LocalDateTime{2026, 3, 29, 1, 30, 0}, "Europe/London");
  require(resolved.ok(), "London DST gap should resolve");
  require(resolved.value().utc_instant == "2026-03-29T01:00:00Z",
           "nonexistent local time must move to the first legal instant");
  require(resolved.value().resolution == LocalDateTimeResolution::gap_shifted &&
              resolved.value().resolved_local_datetime ==
                  LocalDateTime{2026, 3, 29, 2, 0, 0},
          "gap resolution must report the first legal local wall time");
}

void test_london_dst_fold_chooses_earlier_instant() {
  auto resolver = create_resolver();
  auto resolved = resolver->resolve_local_datetime(
      LocalDateTime{2026, 10, 25, 1, 30, 0}, "Europe/London");
  require(resolved.ok(), "London DST fold should resolve");
  require(resolved.value().utc_instant == "2026-10-25T00:30:00Z",
           "ambiguous local time must choose the earlier instant");
  require(resolved.value().resolution == LocalDateTimeResolution::fold_earlier &&
              resolved.value().resolved_local_datetime ==
                  LocalDateTime{2026, 10, 25, 1, 30, 0},
          "fold resolution must retain the requested wall time and report its branch");
}

void test_timezone_round_trip_and_validation() {
  auto resolver = create_resolver();
  require(resolver->tzdb_version() == "2026c", "resolver must expose pinned TZDB version");
  auto local = resolver->to_local("2026-08-03T01:00:00Z", "Asia/Shanghai");
  require(local.ok(), "Shanghai conversion should succeed");
  require(local.value() == LocalDateTime{2026, 8, 3, 9, 0, 0},
           "UTC instant must convert using the Event timezone");
  auto exact = resolver->resolve_local_datetime(
      LocalDateTime{2026, 8, 3, 9, 0, 0}, "Asia/Shanghai");
  require(exact.ok() && exact.value().utc_instant == "2026-08-03T01:00:00Z" &&
              exact.value().resolution == LocalDateTimeResolution::exact,
          "ordinary local time must report an exact resolution");
  auto invalid = resolver->validate_timezone("Europe/Not-A-Zone");
  require(!invalid.ok() && invalid.error().code == "TIMEZONE_ID_INVALID",
          "unknown IANA zone must fail explicitly");
}

excellent_calendar::domain::RecurringEventSchedule timed_schedule(
    std::string start_at,
    std::string end_at,
    std::string timezone = "Europe/London") {
  return excellent_calendar::domain::RecurringEventSchedule{
      "11111111-1111-4111-8111-111111111111",
      std::move(start_at),
      std::move(end_at),
      std::nullopt,
      std::nullopt,
      false,
      std::move(timezone)};
}

excellent_calendar::domain::Recurrence derive(
    excellent_calendar::application::RecurrenceService& service,
    const excellent_calendar::domain::RecurringEventSchedule& event,
    std::string frequency) {
  auto result = service.derive_recurrence(
      event,
      excellent_calendar::domain::EventRecurrenceRuleInput{
          std::move(frequency), 1, std::nullopt, std::nullopt},
      "33333333-3333-4333-8333-333333333333",
      1,
      "2026-01-01T00:00:00Z");
  require(result.ok(), result.ok() ? "" : result.error().message);
  return result.value();
}

void test_daily_uses_local_calendar_across_london_gap() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  auto event = timed_schedule("2026-03-28T01:30:00Z", "2026-03-28T02:30:00Z");
  const auto recurrence = derive(service, event, "daily");
  auto first = service.occurrence_at(event, recurrence, 0);
  auto gap = service.occurrence_at(event, recurrence, 1);
  auto after = service.occurrence_at(event, recurrence, 2);
  require(first.ok() && gap.ok() && after.ok(), "daily occurrences should expand");
  require(*first.value().occurrence_start_at == "2026-03-28T01:30:00Z",
          "first occurrence should preserve start");
  require(*gap.value().occurrence_start_at == "2026-03-29T01:00:00Z",
          "gap occurrence should move to first legal instant");
  require(*after.value().occurrence_start_at == "2026-03-30T00:30:00Z",
          "daily recurrence should return to the same local wall time");
}

void test_weekly_derives_single_weekday_and_uses_calendar_week() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  auto event = timed_schedule("2026-03-22T01:30:00Z", "2026-03-22T02:30:00Z");
  const auto recurrence = derive(service, event, "weekly");
  require(recurrence.days_of_week.size() == 1U && recurrence.days_of_week.front() == 7,
          "weekly recurrence must derive exactly the initial ISO weekday");
  auto next = service.occurrence_at(event, recurrence, 1);
  require(next.ok() && *next.value().occurrence_start_at == "2026-03-29T01:00:00Z",
          "weekly recurrence must advance seven local calendar days");
}

void test_monthly_preserves_permanent_anchor() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  auto event = timed_schedule("2026-01-31T09:00:00Z", "2026-01-31T10:00:00Z");
  const auto recurrence = derive(service, event, "monthly");
  require(recurrence.day_of_month == std::optional<int>(31),
          "monthly recurrence must derive the original local day anchor");
  auto february = service.occurrence_at(event, recurrence, 1);
  auto march = service.occurrence_at(event, recurrence, 2);
  auto april = service.occurrence_at(event, recurrence, 3);
  require(february.ok() && march.ok() && april.ok(), "monthly occurrences should expand");
  require(february.value().original_local_start == "2026-02-28T09:00:00",
          "missing anchor day should clamp to February end");
  require(march.value().original_local_start == "2026-03-31T09:00:00",
          "February clamp must not replace the permanent anchor");
  require(april.value().original_local_start == "2026-04-30T09:00:00",
          "April should clamp independently from the permanent anchor");
}

void test_all_day_recurrence_expands_without_reminder_time() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  excellent_calendar::domain::RecurringEventSchedule event{
      "11111111-1111-4111-8111-111111111111",
      std::nullopt,
      std::nullopt,
      "2026-01-31",
      "2026-02-01",
      true,
      "Asia/Shanghai"};
  const auto recurrence = derive(service, event, "monthly");
  auto listed = service.list_all_day_occurrences(
      event, recurrence, "2026-02-01", "2026-05-01", 20);
  require(listed.ok() && listed.value().size() == 3U,
          "bounded all-day recurrence query should return three occurrences");
  require(*listed.value()[0].occurrence_start_date == "2026-02-28" &&
              *listed.value()[1].occurrence_start_date == "2026-03-31" &&
              *listed.value()[2].occurrence_start_date == "2026-04-30",
          "all-day monthly expansion must preserve the anchor");
}

void test_unsupported_and_bounded_rules_fail_in_core() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  auto event = timed_schedule("2026-08-03T08:00:00Z", "2026-08-03T09:00:00Z");
  for (const auto& frequency : {std::string("yearly"), std::string("custom")}) {
    auto result = service.derive_recurrence(
        event,
        excellent_calendar::domain::EventRecurrenceRuleInput{
            frequency, 1, std::nullopt, std::nullopt},
        "33333333-3333-4333-8333-333333333333",
        1,
        "2026-08-01T00:00:00Z");
    require(!result.ok() && result.error().code == "FEATURE_NOT_IMPLEMENTED",
            "yearly/custom must be rejected defensively by C++ Core");
  }
  auto interval = service.derive_recurrence(
      event,
      excellent_calendar::domain::EventRecurrenceRuleInput{
          "daily", 2, std::nullopt, std::nullopt},
      "33333333-3333-4333-8333-333333333333",
      1,
      "2026-08-01T00:00:00Z");
  require(!interval.ok() && interval.error().code == "RECURRENCE_RULE_INVALID",
          "custom interval must be rejected by C++ Core");
  auto ending = service.derive_recurrence(
      event,
      excellent_calendar::domain::EventRecurrenceRuleInput{
          "daily", 1, "2026-09-01T00:00:00Z", std::nullopt},
      "33333333-3333-4333-8333-333333333333",
      1,
      "2026-08-01T00:00:00Z");
  require(!ending.ok() && ending.error().code == "RECURRENCE_RULE_INVALID",
          "end_at must be rejected by C++ Core");

  auto weekly = derive(service, event, "weekly");
  weekly.days_of_week = {1, 3};
  auto multiple_weekdays = service.occurrence_at(event, weekly, 0);
  require(!multiple_weekdays.ok() &&
              multiple_weekdays.error().code == "RECURRENCE_RULE_INVALID",
          "stored weekly rules with multiple weekdays must be rejected defensively");
  auto monthly = derive(service, event, "monthly");
  monthly.start_at = "2026-08-04T08:00:00Z";
  auto conflicting_start = service.occurrence_at(event, monthly, 0);
  require(!conflicting_start.ok() &&
              conflicting_start.error().code == "RECURRENCE_RULE_INVALID",
          "Recurrence.start_at conflicting with Event.start_at must be unrepresentable");
}

void test_timed_recurrence_rejects_nonpositive_local_interval_across_fold() {
  auto resolver = create_resolver();
  excellent_calendar::application::RecurrenceService service(resolver);
  auto event = timed_schedule(
      "2026-10-25T00:30:00Z", "2026-10-25T01:15:00Z");
  auto result = service.derive_recurrence(
      event,
      excellent_calendar::domain::EventRecurrenceRuleInput{
          "daily", 1, std::nullopt, std::nullopt},
      "33333333-3333-4333-8333-333333333333",
      1,
      "2026-08-01T00:00:00Z");
  require(!result.ok() && result.error().code == "RECURRENCE_RULE_INVALID",
          "a UTC-positive but locally reversed interval at a DST fold must be rejected");
}

class TemporaryDirectory {
 public:
  TemporaryDirectory()
      : path_(std::filesystem::temp_directory_path() /
              ("excellent_calendar_recurring_test_" +
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

class CountingRecurringEventTransaction final
    : public excellent_calendar::repository::RecurringEventTransaction {
 public:
  explicit CountingRecurringEventTransaction(
      std::shared_ptr<excellent_calendar::repository::RecurringEventTransaction> delegate)
      : delegate_(std::move(delegate)) {}

  excellent_calendar::common::Result<excellent_calendar::common::Unit> initialize() override {
    return delegate_->initialize();
  }

  excellent_calendar::common::Result<excellent_calendar::repository::RecurringEventState>
  load() override {
    ++load_count_;
    return delegate_->load();
  }

  excellent_calendar::common::Result<excellent_calendar::common::Unit>
  prepare_notification(const NotificationPrepareOperation& action) override {
    return delegate_->prepare_notification(action);
  }

  excellent_calendar::common::Result<excellent_calendar::common::Unit> update_reminders(
      const ReminderUpdateOperation& action) override {
    return delegate_->update_reminders(action);
  }

  excellent_calendar::common::Result<excellent_calendar::common::Unit> execute(
      std::string_view operation,
      std::string transaction_id,
      std::string prepared_at,
      const Operation& action) override {
    return delegate_->execute(
        operation, std::move(transaction_id), std::move(prepared_at), action);
  }

  int load_count() const { return load_count_; }

 private:
  std::shared_ptr<excellent_calendar::repository::RecurringEventTransaction> delegate_;
  int load_count_ = 0;
};

class WorkflowFixture {
 public:
  WorkflowFixture()
      : resolver(create_resolver()),
        recurrence(std::make_shared<excellent_calendar::application::RecurrenceService>(resolver)),
        rolling(std::make_shared<excellent_calendar::application::RollingReminderService>(recurrence)),
        store(std::make_shared<excellent_calendar::storage::json::JsonRecurringEventTransaction>(
            directory.path())),
        category_repository(std::make_shared<
                            excellent_calendar::storage::json::JsonCategoryRepository>(
            directory.path())),
        workflow(std::make_shared<excellent_calendar::application::RecurringEventWorkflowService>(
            store,
            recurrence,
            rolling,
            [this]() { return now; },
            excellent_calendar::common::generate_uuid_v4)),
        delivery(std::make_shared<
                 excellent_calendar::application::RecurringReminderDeliveryWorkflowService>(
            store,
            rolling,
            [this]() { return now; },
            excellent_calendar::common::generate_uuid_v4)),
        recovery(std::make_shared<excellent_calendar::application::ReminderRecoveryWorkflowService>(
            store,
            recurrence,
            rolling,
            [this]() { return now; },
            excellent_calendar::common::generate_uuid_v4)),
        event_query(std::make_shared<excellent_calendar::application::RecurringEventQueryService>(
            store,
            recurrence,
            category_repository)),
        reminder_query(std::make_shared<
                       excellent_calendar::application::RecurringReminderQueryService>(
            store,
            [this]() { return now; })) {
    require(store->initialize().ok(), "workflow store should initialize");
    require(category_repository->initialize().ok(),
            "Category store should initialize for Event aggregate queries");
  }

  excellent_calendar::application::CreateRecurringEventCommand daily_command() const {
    excellent_calendar::domain::Event event;
    event.title = "Daily stand-up";
    event.start_at = "2026-08-03T08:00:00Z";
    event.end_at = "2026-08-03T09:00:00Z";
    event.is_all_day = false;
    event.timezone = "Europe/London";
    event.source = "manual";
    return excellent_calendar::application::CreateRecurringEventCommand{
        event,
        excellent_calendar::domain::EventRecurrenceRuleInput{
            "daily", 1, std::nullopt, std::nullopt},
        {excellent_calendar::domain::RecurringReminderDraft{
            30, {"popup"}, "Stand-up starts soon", true, "manual"}}};
  }

  TemporaryDirectory directory;
  std::string now = "2026-08-03T07:00:00Z";
  std::shared_ptr<TzdbLocalTimeResolver> resolver;
  std::shared_ptr<excellent_calendar::application::RecurrenceService> recurrence;
  std::shared_ptr<excellent_calendar::application::RollingReminderService> rolling;
  std::shared_ptr<excellent_calendar::storage::json::JsonRecurringEventTransaction> store;
  std::shared_ptr<excellent_calendar::storage::json::JsonCategoryRepository>
      category_repository;
  std::shared_ptr<excellent_calendar::application::RecurringEventWorkflowService> workflow;
  std::shared_ptr<
      excellent_calendar::application::RecurringReminderDeliveryWorkflowService> delivery;
  std::shared_ptr<excellent_calendar::application::ReminderRecoveryWorkflowService> recovery;
  std::shared_ptr<excellent_calendar::application::RecurringEventQueryService> event_query;
  std::shared_ptr<excellent_calendar::application::RecurringReminderQueryService> reminder_query;
};

excellent_calendar::domain::Event stored_recurring_event() {
  excellent_calendar::domain::Event event;
  event.id = "11111111-1111-4111-8111-111111111111";
  event.title = "London daily stand-up";
  event.start_at = "2026-03-28T01:30:00Z";
  event.end_at = "2026-03-28T02:30:00Z";
  event.is_all_day = false;
  event.has_recurrence = true;
  event.status = std::string(excellent_calendar::domain::kEventStatusActive);
  event.recurrence_id = "33333333-3333-4333-8333-333333333333";
  event.recurrence_revision = 1;
  event.timezone = "Europe/London";
  event.source = "manual";
  event.created_at = "2026-03-01T00:00:00Z";
  event.updated_at = event.created_at;
  return event;
}

excellent_calendar::domain::Recurrence stored_daily_recurrence() {
  excellent_calendar::domain::Recurrence recurrence;
  recurrence.id = "33333333-3333-4333-8333-333333333333";
  recurrence.revision = 1;
  recurrence.frequency = "daily";
  recurrence.interval = 1;
  recurrence.start_at = "2026-03-28T01:30:00Z";
  recurrence.timezone = "Europe/London";
  recurrence.created_at = "2026-03-01T00:00:00Z";
  return recurrence;
}

void test_storage_v2_reload_and_prepared_journal_replay() {
  TemporaryDirectory directory;
  excellent_calendar::storage::json::JsonRecurringEventTransaction store(directory.path());
  auto initialized = store.initialize();
  require(initialized.ok(), "v2 recurring store should initialize empty roots");
  auto committed = store.execute(
      "event_recurrence_and_first_reminder_create_or_update",
      "44444444-4444-4444-8444-444444444444",
      "2026-03-01T00:00:00Z",
      [](excellent_calendar::repository::RecurringEventState& state) {
        state.events.push_back(stored_recurring_event());
        state.recurrences.push_back(stored_daily_recurrence());
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(committed.ok(), "v2 transaction should commit");

  excellent_calendar::storage::json::JsonRecurringEventTransaction reloaded(directory.path());
  require(reloaded.initialize().ok(), "v2 store should reload after process restart");
  auto state = reloaded.load();
  require(state.ok() && state.value().events.size() == 1U &&
              state.value().recurrences.size() == 1U,
          "v2 store reload must preserve Event and Recurrence together");

  bool fail_once = true;
  excellent_calendar::storage::json::JsonRecurringEventTransaction interrupted(
      directory.path(),
      [&fail_once](std::string_view phase) {
        if (fail_once && phase == "after_prepare") {
          fail_once = false;
          return excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
              excellent_calendar::common::make_error(
                  "STORAGE_IO_ERROR", "simulated process interruption", {}, true));
        }
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  auto interrupted_result = interrupted.execute(
      "occurrence_state_and_reminder_transition",
      "55555555-5555-4555-8555-555555555555",
      "2026-03-02T00:00:00Z",
      [](excellent_calendar::repository::RecurringEventState& state) {
        state.events.front().title = "changed through replay";
        state.events.front().updated_at = "2026-03-02T00:00:00Z";
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(!interrupted_result.ok(), "simulated interruption should fail the active call");

  excellent_calendar::storage::json::AtomicJsonFileStore journal_store(directory.path());
  auto journal = journal_store.read_json_file("workflow_transactions.json");
  require(journal.ok() && journal.value().has_value(),
          "interrupted workflow must retain one prepared journal record");
  const auto& transaction = journal.value()
                                ->get<picojson::object>()
                                .at("transactions")
                                .get<picojson::array>()
                                .front()
                                .get<picojson::object>();
  std::set<std::string> affected;
  for (const auto& item : transaction.at("affected_stores").get<picojson::array>()) {
    affected.insert(item.get<std::string>());
  }
  const std::set<std::string> logical_stores = {
      "events", "recurrence_versions", "event_occurrence_states",
      "reminders", "notifications", "reminder_recovery_batches"};
  const auto& after_stores = transaction.at("intent")
                                 .get<picojson::object>()
                                 .at("after_stores")
                                 .get<picojson::object>();
  std::set<std::string> after_store_keys;
  for (const auto& [name, _] : after_stores) after_store_keys.insert(name);
  require(affected == logical_stores && after_store_keys == logical_stores,
          "journal must use logical store names rather than storage file names");

  excellent_calendar::storage::json::JsonRecurringEventTransaction recovered(directory.path());
  require(recovered.initialize().ok(), "prepared journal should replay on restart");
  auto recovered_state = recovered.load();
  require(recovered_state.ok() && recovered_state.value().events.front().title ==
                                      "changed through replay",
          "prepared after-state must be applied idempotently during recovery");
}

void test_v2_transaction_rejects_unprepared_v1_directory_without_partial_writes() {
  TemporaryDirectory directory;
  excellent_calendar::storage::json::JsonEventRepository legacy(directory.path());
  require(legacy.initialize().ok(), "legacy v1 Event root should initialize for safety test");
  require(legacy.create(stored_recurring_event()).ok(),
          "legacy v1 Event root should be materialized for safety test");
  excellent_calendar::storage::json::JsonRecurringEventTransaction v2(directory.path());
  auto initialized = v2.initialize();
  require(!initialized.ok() && initialized.error().code == "STORAGE_DATA_CORRUPTED",
          "the v2 transaction must reject v1 when runtime bootstrap was bypassed");
  require(!std::filesystem::exists(directory.path() / "recurrence_versions.json") &&
              !std::filesystem::exists(directory.path() / "workflow_transactions.json"),
          "failed v1 preflight must not create any partial v2 stores");
}

void test_v2_runtime_discards_confirmed_v1_before_initialization() {
  TemporaryDirectory parent;
  const auto active = parent.path() / "calendar_core_storage_json";
  std::filesystem::create_directories(active);
  excellent_calendar::storage::json::JsonEventRepository legacy(active);
  require(legacy.initialize().ok(), "legacy v1 Event root should initialize");
  require(legacy.create(stored_recurring_event()).ok(),
          "legacy v1 Event root should contain recognizable user data");

  auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
      active.string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok() && initialized.value().storage_format_version == 2,
          "runtime should discard confirmed v1 and initialize an empty v2 store");
  require(std::filesystem::is_directory(active) &&
              std::filesystem::exists(active / "recurrence_versions.json") &&
              std::filesystem::exists(active / "workflow_transactions.json"),
          "runtime should publish a complete v2 directory at the active path");

  const auto prefix = active.filename().generic_string() + ".v1.archived.";
  for (const auto& entry : std::filesystem::directory_iterator(parent.path())) {
    require(!(entry.is_directory() &&
              entry.path().filename().generic_string().rfind(prefix, 0) == 0U),
            "v1 must not be preserved as a sibling archive");
  }

  excellent_calendar::storage::json::JsonRecurringEventTransaction v2(active);
  require(v2.initialize().ok(), "new active v2 directory should reopen cleanly");
  auto state = v2.load();
  require(state.ok() && state.value().events.empty() && state.value().reminders.empty(),
          "v1 data must not be reinterpreted or migrated into the empty v2 store");
}

void test_v2_runtime_refuses_corrupt_v1_without_discarding_or_partial_v2() {
  TemporaryDirectory parent;
  const auto active = parent.path() / "calendar_core_storage_json";
  excellent_calendar::storage::json::AtomicJsonFileStore raw(active);
  require(raw.initialize().ok(), "corrupt-v1 test directory should initialize");
  picojson::object forged;
  forged["storage_version"] = picojson::value(1.0);
  forged["events"] = picojson::value("corrupt");
  require(raw.write_json_file("events.json", picojson::value(forged)).ok(),
          "forged v1 Event root should be written for preflight test");

  auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
      active.string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(!initialized.ok() && initialized.error().code == "STORAGE_DATA_CORRUPTED",
          "a version marker alone must not qualify a directory as confirmed v1");
  require(std::filesystem::exists(active / "events.json") &&
              !std::filesystem::exists(active / "recurrence_versions.json") &&
              !std::filesystem::exists(active / "workflow_transactions.json"),
          "failed v1 preflight must preserve the source and create no v2 files");
  const auto prefix = active.filename().generic_string() + ".v1.archived.";
  const bool discarded = std::any_of(
      std::filesystem::directory_iterator(parent.path()),
      std::filesystem::directory_iterator(), [&](const auto& entry) {
        return entry.path().filename().generic_string().rfind(prefix, 0) == 0U;
      });
  require(!discarded, "corrupt v1 must never be removed or treated as valid");
}

void test_v1_discard_classifier_rejects_v2_reminder_enums() {
  for (const auto& variant : {std::string("expired"),
                              std::string("occurrence_reopened")}) {
    TemporaryDirectory parent;
    const auto active = parent.path() / "calendar_core_storage_json";
    excellent_calendar::storage::json::JsonReminderRepository legacy(active);
    require(legacy.initialize().ok(), "legacy Reminder store should initialize");
    excellent_calendar::domain::Reminder reminder;
    reminder.id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    reminder.target_type = "event";
    reminder.target_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    reminder.remind_at = "2026-08-03T08:00:00Z";
    reminder.methods = {"popup"};
    reminder.is_enabled = false;
    reminder.status = variant == "expired" ? "expired" : "cancelled";
    reminder.cancellation_reason =
        variant == "occurrence_reopened"
            ? std::optional<std::string>("occurrence_reopened")
            : std::nullopt;
    reminder.source = "manual";
    reminder.created_at = "2026-08-03T07:00:00Z";
    reminder.updated_at = "2026-08-03T07:00:00Z";
    require(legacy.create(reminder).ok(),
            "legacy writer should materialize the preflight fixture");

    auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
        active.string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
    require(!initialized.ok() && initialized.error().code == "STORAGE_DATA_CORRUPTED",
            "v1 discard classifier must reject v2-only Reminder enum values");
    const auto prefix = active.filename().generic_string() + ".v1.archived.";
    const bool discarded = std::any_of(
        std::filesystem::directory_iterator(parent.path()),
        std::filesystem::directory_iterator(), [&](const auto& entry) {
          return entry.path().filename().generic_string().rfind(prefix, 0) == 0U;
        });
    require(!discarded &&
                std::filesystem::exists(active / "reminders.json") &&
                !std::filesystem::exists(active / "recurrence_versions.json"),
            "rejected v2-only values must preserve v1 data without partial v2 output");
  }
}

void test_recurring_runtime_initializes_pinned_tzdb_and_v2_services() {
  TemporaryDirectory directory;
  auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
      directory.path().string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok() && initialized.value().initialized &&
              initialized.value().storage_format_version == 2 &&
              initialized.value().tzdb_version == "2026c",
          "recurring runtime must initialize storage v2 after validating pinned TZDB");
  require(excellent_calendar::boundary::api::current_recurring_event_workflow_service() !=
                  nullptr &&
              excellent_calendar::boundary::api::
                      current_recurring_reminder_delivery_workflow_service() != nullptr &&
              excellent_calendar::boundary::api::current_reminder_recovery_workflow_service() !=
                  nullptr &&
              excellent_calendar::boundary::api::current_reminder_service_v2() != nullptr,
          "recurring runtime must expose unified Event, Reminder, delivery, and recovery services");
}

void test_failed_v2_reinitialization_clears_previously_published_writers() {
  TemporaryDirectory valid;
  auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
      valid.path().string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok() &&
              excellent_calendar::boundary::api::current_reminder_service_v2() != nullptr,
          "precondition runtime should publish a v2 writer");
  auto stale_writer = excellent_calendar::boundary::api::current_reminder_service_v2();

  TemporaryDirectory rejected;
  auto failed = excellent_calendar::boundary::api::initialize_recurring_runtime(
      rejected.path().string(),
      (rejected.path() / "missing_tzdb").string());
  require(!failed.ok() &&
              excellent_calendar::boundary::api::current_recurring_event_workflow_service() ==
                  nullptr &&
              excellent_calendar::boundary::api::current_reminder_service_v2() == nullptr &&
              excellent_calendar::boundary::api::current_storage_directory().empty(),
          "failed reinitialization must leave no previous v1 or v2 writer reachable");
  auto stale_access = stale_writer->list({});
  require(!stale_access.ok() && stale_access.error().code == "STORAGE_NOT_INITIALIZED",
          "an already-borrowed v2 service must be revoked after runtime replacement fails");
}

void test_create_and_complete_occurrence_rolls_next_reminder_atomically() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "recurring Event create should succeed");
  auto initial = fixture.store->load();
  require(initial.ok() && initial.value().events.size() == 1U &&
              initial.value().recurrences.size() == 1U &&
              initial.value().reminders.size() == 1U,
          "create transaction must persist Event, Recurrence, and one rolling Reminder");
  require(initial.value().reminders.front().remind_at == "2026-08-03T07:30:00Z",
          "first rolling Reminder should derive remind_at from occurrence start");

  const auto occurrence = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(initial.value().events.front()),
      initial.value().recurrences.front(),
      0);
  require(occurrence.ok(), "first occurrence should expand");
  fixture.now = "2026-08-03T07:10:00Z";
  auto completed = fixture.workflow->complete_occurrence(
      excellent_calendar::application::OccurrenceOperationCommand{
          created.value().id,
          1,
          occurrence.value().occurrence_key,
          occurrence.value().occurrence_start_at,
          std::nullopt});
  require(completed.ok() && completed.value().status == "completed",
          "occurrence complete should persist sparse completed state");
  auto state = fixture.store->load();
  require(state.ok() && state.value().events.front().status == "active",
          "occurrence operation must not complete the whole series");
  require(state.value().reminders.size() == 2U,
          "occurrence transition must retain history and create a successor");
  const auto cancelled = std::count_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.status == "cancelled" &&
               reminder.cancellation_reason == std::optional<std::string>("occurrence_completed");
      });
  const auto open = std::count_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.status == "pending" && reminder.is_enabled;
      });
  require(cancelled == 1 && open == 1,
          "current cancellation and successor creation must commit as one state");
  const auto successor = std::find_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.status == "pending";
      });
  require(successor != state.value().reminders.end() &&
              successor->remind_at == "2026-08-04T07:30:00Z",
          "successor should target the next local calendar day");
}

void test_series_reopen_starts_after_reopened_at_without_catchup() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "recurring Event create should succeed");
  fixture.now = "2026-08-03T07:05:00Z";
  auto completed = fixture.workflow->complete_series(
      excellent_calendar::application::SeriesOperationCommand{created.value().id, 1});
  require(completed.ok() && completed.value().status == "completed",
          "series complete should succeed");

  fixture.now = "2026-08-06T10:00:00Z";
  auto reopened = fixture.workflow->reopen_series(
      excellent_calendar::application::SeriesOperationCommand{created.value().id, 1});
  require(reopened.ok() && reopened.value().status == "active",
          "completed series should reopen");
  auto state = fixture.store->load();
  require(state.ok(), "reopened state should load");
  const auto open = std::count_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.status == "pending" && reminder.is_enabled;
      });
  require(open == 1, "reopened series should have exactly one open next Reminder");
  const auto next = std::find_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.status == "pending";
      });
  require(next != state.value().reminders.end() && next->remind_at == "2026-08-07T07:30:00Z",
          "series reopen must start after reopened_at and must not backfill prior occurrences");
}

void test_terminal_series_rejects_occurrence_mutation_without_reopening_chain() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "series should be created before terminal-state guard test");
  auto initial = fixture.store->load();
  auto first = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(initial.value().events.front()),
      initial.value().recurrences.front(), 0);
  auto second = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(initial.value().events.front()),
      initial.value().recurrences.front(), 1);
  require(first.ok() && second.ok(), "guard test occurrences should expand");
  auto first_completed = fixture.workflow->complete_occurrence(
      {created.value().id, 1, first.value().occurrence_key,
       first.value().occurrence_start_at, std::nullopt});
  require(first_completed.ok(), "first occurrence should complete while series is active");
  auto series_completed = fixture.workflow->complete_series({created.value().id, 1});
  require(series_completed.ok(), "series should enter completed state");
  auto before_rejected = fixture.store->load();

  auto reopen_occurrence = fixture.workflow->reopen_occurrence(
      {created.value().id, 1, first.value().occurrence_key,
       first.value().occurrence_start_at, std::nullopt});
  auto skip_occurrence = fixture.workflow->skip_occurrence(
      {created.value().id, 1, second.value().occurrence_key,
       second.value().occurrence_start_at, std::nullopt});
  require(!reopen_occurrence.ok() &&
              reopen_occurrence.error().code == "OCCURRENCE_OPERATION_INVALID" &&
              !skip_occurrence.ok() &&
              skip_occurrence.error().code == "OCCURRENCE_OPERATION_INVALID",
          "completed series must reject every direct occurrence mutation");

  auto after_rejected = fixture.store->load();
  require(before_rejected.ok() && after_rejected.ok(),
          "terminal-state guard snapshots should reload");
  const auto open = std::count_if(
      after_rejected.value().reminders.begin(), after_rejected.value().reminders.end(),
      [](const auto& reminder) {
        return reminder.is_enabled &&
               (reminder.status == "pending" || reminder.status == "scheduled");
      });
  require(open == 0 &&
              before_rejected.value().events.front().status ==
                  after_rejected.value().events.front().status &&
              before_rejected.value().events.front().updated_at ==
                  after_rejected.value().events.front().updated_at &&
              before_rejected.value().occurrence_states.size() ==
                  after_rejected.value().occurrence_states.size() &&
              before_rejected.value().reminders.size() ==
                  after_rejected.value().reminders.size(),
          "rejected occurrence mutation must not reopen or append Reminder tasks");
}

void test_series_update_creates_revision_and_cancels_old_open_reminder() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "recurring Event create should succeed");
  auto replacement = fixture.daily_command().event;
  replacement.title = "Monthly stand-up";
  replacement.start_at = "2026-08-31T08:00:00Z";
  replacement.end_at = "2026-08-31T09:00:00Z";
  fixture.now = "2026-08-03T07:10:00Z";
  excellent_calendar::application::UpdateRecurringEventSeriesCommand update;
  update.event_id = created.value().id;
  update.expected_recurrence_revision = {true, 1};
  update.title = {true, replacement.title};
  update.time = {
      true,
      excellent_calendar::application::EventTimeReplacement{
          replacement.start_at, replacement.end_at, std::nullopt, std::nullopt,
          false, replacement.timezone.value_or("Asia/Shanghai")}};
  update.recurrence = {
      true,
      excellent_calendar::domain::EventRecurrenceRuleInput{
          "monthly", 1, std::nullopt, std::nullopt}};
  update.reminders = {
      true,
       {excellent_calendar::application::EventReminderDraftInput{
           "event", std::nullopt, std::nullopt, 30, {"popup"}, "Monthly soon",
           true, "manual", false, true, true}}};
  auto updated = fixture.workflow->update_series(update);
  require(updated.ok() && updated.value().recurrence_revision == std::optional<int>(2),
          "whole-series update should advance immutable recurrence revision");
  auto state = fixture.store->load();
  require(state.ok() && state.value().recurrences.size() == 2U,
          "old recurrence revision should remain historical");
  const auto old_cancelled = std::count_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.recurrence_revision == 1 && reminder.status == "cancelled" &&
               reminder.cancellation_reason == std::optional<std::string>("series_updated");
      });
  const auto new_open = std::count_if(
      state.value().reminders.begin(), state.value().reminders.end(), [](const auto& reminder) {
        return reminder.recurrence_revision == 2 && reminder.status == "pending";
      });
  require(old_cancelled == 1 && new_open == 1,
          "revision replacement must cancel old and create new rolling Reminder atomically");
}

void test_series_partial_update_requires_current_revision_without_writes() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "series should be created before revision conflict tests");
  auto initial = fixture.store->load();
  require(initial.ok() && initial.value().reminders.size() == 1U,
          "revision conflict precondition should contain one rolling Reminder");
  const auto original_reminder_id = initial.value().reminders.front().id;

  const auto assert_conflict = [&](
                                   excellent_calendar::application::FieldPatch<
                                       std::optional<int>> revision,
                                   const std::string& attempted_title) {
    excellent_calendar::application::UpdateRecurringEventSeriesCommand update;
    update.event_id = created.value().id;
    update.expected_recurrence_revision = revision;
    update.title = {true, attempted_title};
    auto rejected = fixture.workflow->update_series(update);
    require(!rejected.ok() && rejected.error().code == "RECURRENCE_REVISION_CONFLICT",
            "missing, null, or stale revision must reject a recurring partial update");
    auto state = fixture.store->load();
    require(state.ok() && state.value().events.front().title == "Daily stand-up" &&
                state.value().recurrences.size() == 1U &&
                state.value().reminders.size() == 1U &&
                state.value().reminders.front().id == original_reminder_id,
            "revision conflict must roll back Event, Recurrence, and Reminder writes");
  };

  assert_conflict({}, "Missing revision");
  assert_conflict({true, std::nullopt}, "Null revision");
  assert_conflict({true, 2}, "Stale revision");
}

void test_same_template_keeps_revision_but_message_change_creates_revision() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "series should be created before template comparison test");
  auto initial = fixture.store->load();
  require(initial.ok() && initial.value().reminders.size() == 1U,
          "template comparison precondition should contain one Reminder");
  const auto original_reminder_id = initial.value().reminders.front().id;

  excellent_calendar::application::UpdateRecurringEventSeriesCommand same;
  same.event_id = created.value().id;
  same.expected_recurrence_revision = {true, 1};
  same.reminders = {
      true,
       {excellent_calendar::application::EventReminderDraftInput{
           "event", std::nullopt, std::nullopt, 30, {"popup"},
           "Stand-up starts soon", true, "manual", false, true, true}}};
  auto unchanged = fixture.workflow->update_series(same);
  require(unchanged.ok() &&
              unchanged.value().recurrence_revision == std::optional<int>(1),
          "semantically equal Reminder replacement must keep recurrence revision");
  auto after_same = fixture.store->load();
  require(after_same.ok() && after_same.value().recurrences.size() == 1U &&
              after_same.value().reminders.size() == 1U &&
              after_same.value().reminders.front().id == original_reminder_id,
          "equal templates must not cancel or recreate the rolling Reminder");

  auto changed = same;
  changed.reminders.value.front().message = "Changed reminder body";
  auto revised = fixture.workflow->update_series(changed);
  require(revised.ok() && revised.value().recurrence_revision == std::optional<int>(2),
          "Reminder message change alone must create an immutable revision");
  auto after_change = fixture.store->load();
  require(after_change.ok(), "message revision state should reload");
  const auto old_cancelled = std::count_if(
      after_change.value().reminders.begin(), after_change.value().reminders.end(),
      [&](const auto& reminder) {
        return reminder.id == original_reminder_id && reminder.status == "cancelled" &&
               reminder.cancellation_reason == std::optional<std::string>("series_updated");
      });
  const auto new_open = std::count_if(
      after_change.value().reminders.begin(), after_change.value().reminders.end(),
      [](const auto& reminder) {
        return reminder.recurrence_revision == std::optional<int>(2) &&
               reminder.status == "pending" &&
               reminder.message == std::optional<std::string>("Changed reminder body");
      });
  require(after_change.value().recurrences.size() == 2U &&
              old_cancelled == 1 && new_open == 1,
          "message revision should retain old history and create one new open Reminder");
}

void test_updating_completed_series_metadata_keeps_revision_until_reopen() {
  WorkflowFixture fixture;
  auto command = fixture.daily_command();
  auto created = fixture.workflow->create_series(command);
  require(created.ok(), "series should be created before completion/update test");
  auto completed = fixture.workflow->complete_series({created.value().id, 1});
  require(completed.ok(), "series should complete");
  auto before = fixture.store->load();
  require(before.ok() && before.value().reminders.size() == 1U,
          "completed series should retain its cancelled Reminder history");
  const auto original_reminder_id = before.value().reminders.front().id;
  excellent_calendar::application::UpdateRecurringEventSeriesCommand update;
  update.event_id = created.value().id;
  update.expected_recurrence_revision = {true, 1};
  update.title = {true, "Edited completed series"};
  auto updated = fixture.workflow->update_series(update);
  require(updated.ok() && updated.value().status == "completed" &&
              updated.value().recurrence_revision == std::optional<int>(1),
          "metadata-only update should preserve completed status and recurrence revision");
  auto state = fixture.store->load();
  require(state.ok() && state.value().recurrences.size() == 1U,
          "metadata-only update must not append a recurrence revision");
  const auto retained = std::find_if(
      state.value().reminders.begin(), state.value().reminders.end(),
      [&](const auto& reminder) {
        return reminder.id == original_reminder_id &&
               reminder.recurrence_revision == std::optional<int>(1);
      });
  require(retained != state.value().reminders.end() &&
              retained->status == "cancelled" && !retained->is_enabled &&
              retained->cancellation_reason ==
                  std::optional<std::string>("series_completed"),
          "metadata-only update must retain the existing cancelled Reminder unchanged");
  fixture.now = "2026-08-03T07:10:00Z";
  auto reopened = fixture.workflow->reopen_series({created.value().id, 1});
  require(reopened.ok() && reopened.value().status == "active",
          "completed revision should still be reopenable");
  auto after = fixture.store->load();
  require(after.ok() && std::any_of(
                            after.value().reminders.begin(),
                            after.value().reminders.end(),
                            [&](const auto& reminder) {
                              return reminder.target_id == created.value().id &&
                                     reminder.recurrence_revision == std::optional<int>(1) &&
                                     reminder.status == "pending" && reminder.is_enabled &&
                                     reminder.remind_at > fixture.now;
                            }),
          "series reopen must reactivate the first valid reminder after reopened_at");
}

void test_occurrence_reopen_defers_and_reuses_the_same_successor() {
  for (const auto& operation : {std::string("skip"), std::string("cancel")}) {
    WorkflowFixture fixture;
    auto created = fixture.workflow->create_series(fixture.daily_command());
    auto state = fixture.store->load();
    auto occurrence = fixture.recurrence->occurrence_at(
        excellent_calendar::domain::recurring_schedule_from_event(state.value().events.front()),
        state.value().recurrences.front(), 0);
    excellent_calendar::application::OccurrenceOperationCommand command{
        created.value().id,
        1,
        occurrence.value().occurrence_key,
        occurrence.value().occurrence_start_at,
        std::nullopt};
    fixture.now = "2026-08-03T07:05:00Z";
    auto changed = operation == "skip" ? fixture.workflow->skip_occurrence(command)
                                        : fixture.workflow->cancel_occurrence(command);
    require(changed.ok() && changed.value().status ==
                                (operation == "skip" ? "skipped" : "cancelled"),
            "skip/cancel should persist a sparse terminal occurrence state");
    auto terminal = fixture.store->load();
    const auto original_id = terminal.value().reminders.front().id;
    const auto successor = std::find_if(
        terminal.value().reminders.begin(), terminal.value().reminders.end(),
        [&](const auto& reminder) {
          return reminder.id != original_id && reminder.is_enabled &&
                 (reminder.status == "pending" || reminder.status == "scheduled");
        });
    require(successor != terminal.value().reminders.end(),
            "terminal occurrence must create one open rolling successor");
    const auto successor_id = successor->id;
    fixture.now = "2026-08-03T07:06:00Z";
    auto successor_scheduled = fixture.reminder_query->mark_scheduled(
        {successor_id, successor->remind_at, fixture.now});
    require(successor_scheduled.ok() && successor_scheduled.value().status == "scheduled",
            "successor should be scheduled before reopen freezes it");
    require(terminal.value().reminders.front().cancellation_reason ==
                std::optional<std::string>(operation == "skip" ? "occurrence_skipped"
                                                               : "occurrence_cancelled"),
            "occurrence transition must retain the precise cancellation reason");

    fixture.now = "2026-08-03T07:10:00Z";
    auto reopened = fixture.workflow->reopen_occurrence(command);
    require(reopened.ok() && reopened.value().status == "scheduled",
            "occurrence reopen should atomically defer the rolling successor");
    auto restored = fixture.store->load();
    const auto original = std::find_if(
        restored.value().reminders.begin(), restored.value().reminders.end(),
        [&](const auto& reminder) { return reminder.id == original_id; });
    const auto open_count = std::count_if(
        restored.value().reminders.begin(), restored.value().reminders.end(),
        [](const auto& reminder) {
          return reminder.is_enabled &&
                 (reminder.status == "pending" || reminder.status == "scheduled");
        });
    const auto deferred = std::find_if(
        restored.value().reminders.begin(), restored.value().reminders.end(),
        [&](const auto& reminder) { return reminder.id == successor_id; });
    require(original != restored.value().reminders.end() &&
                original->status == "pending" && original->is_enabled &&
                original->reactivation_count == 1 &&
                deferred != restored.value().reminders.end() &&
                deferred->status == "cancelled" && !deferred->is_enabled &&
                deferred->cancellation_reason ==
                    std::optional<std::string>("occurrence_reopened") &&
                open_count == 1,
            "reopen must restore the original and park exactly the existing successor");

    fixture.now = "2026-08-03T07:15:00Z";
    auto terminal_again = operation == "skip" ? fixture.workflow->skip_occurrence(command)
                                                : fixture.workflow->cancel_occurrence(command);
    require(terminal_again.ok(), "reopened occurrence should be terminal again");
    auto rolled = fixture.store->load();
    const auto reused = std::find_if(
        rolled.value().reminders.begin(), rolled.value().reminders.end(),
        [&](const auto& reminder) { return reminder.id == successor_id; });
    const auto rolled_open_count = std::count_if(
        rolled.value().reminders.begin(), rolled.value().reminders.end(),
        [](const auto& reminder) {
          return reminder.is_enabled &&
                 (reminder.status == "pending" || reminder.status == "scheduled");
        });
    require(reused != rolled.value().reminders.end() && reused->status == "pending" &&
                reused->is_enabled && reused->reactivation_count == 1 &&
                reused->cancellation_reason ==
                    std::optional<std::string>("occurrence_reopened") &&
                rolled_open_count == 1,
            "rolling must reactivate the same deterministic successor without duplication");
  }
}

void test_series_reopen_restores_only_one_reminder_per_deferred_template() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "series should be created before deferred series reopen test");
  auto state = fixture.store->load();
  auto occurrence = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(state.value().events.front()),
      state.value().recurrences.front(), 0);
  excellent_calendar::application::OccurrenceOperationCommand occurrence_command{
      created.value().id, 1, occurrence.value().occurrence_key,
      occurrence.value().occurrence_start_at, std::nullopt};
  fixture.now = "2026-08-03T07:05:00Z";
  require(fixture.workflow->skip_occurrence(occurrence_command).ok(),
          "first occurrence should create a successor");
  fixture.now = "2026-08-03T07:10:00Z";
  require(fixture.workflow->reopen_occurrence(occurrence_command).ok(),
          "occurrence reopen should park that successor");

  auto deferred = fixture.store->load();
  require(deferred.ok() && deferred.value().reminders.size() == 2U,
          "deferred chain should retain original and successor records");
  fixture.now = "2026-08-03T07:12:00Z";
  require(fixture.workflow->complete_series({created.value().id, 1}).ok(),
          "series completion should override all deferred reasons");
  auto completed = fixture.store->load();
  require(std::all_of(
              completed.value().reminders.begin(), completed.value().reminders.end(),
              [](const auto& reminder) {
                return reminder.status == "cancelled" && !reminder.is_enabled &&
                       reminder.cancellation_reason ==
                           std::optional<std::string>("series_completed");
              }),
          "series reason must override the parked rolling reason");

  fixture.now = "2026-08-03T07:15:00Z";
  auto reopened = fixture.workflow->reopen_series({created.value().id, 1});
  auto replay = fixture.workflow->reopen_series({created.value().id, 1});
  require(reopened.ok() && replay.ok(), "series reopen should be idempotent");
  auto restored = fixture.store->load();
  const auto open_count = std::count_if(
      restored.value().reminders.begin(), restored.value().reminders.end(),
      [](const auto& reminder) {
        return reminder.is_enabled &&
               (reminder.status == "pending" || reminder.status == "scheduled");
      });
  const auto parked_count = std::count_if(
      restored.value().reminders.begin(), restored.value().reminders.end(),
      [](const auto& reminder) {
        return reminder.status == "cancelled" && !reminder.is_enabled &&
               reminder.cancellation_reason ==
                   std::optional<std::string>("occurrence_reopened");
      });
  require(open_count == 1 && parked_count == 1,
          "series reopen must restore only the earliest future Reminder per template");
}

void test_reminderless_occurrence_reopen_remains_supported_and_idempotent() {
  WorkflowFixture fixture;
  auto command_template = fixture.daily_command();
  command_template.reminders.clear();
  auto created = fixture.workflow->create_series(command_template);
  auto state = fixture.store->load();
  auto occurrence = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(state.value().events.front()),
      state.value().recurrences.front(), 0);
  excellent_calendar::application::OccurrenceOperationCommand command{
      created.value().id, 1, occurrence.value().occurrence_key,
      occurrence.value().occurrence_start_at, std::nullopt};
  fixture.now = "2026-08-03T07:05:00Z";
  require(fixture.workflow->skip_occurrence(command).ok(),
          "reminderless occurrence should enter a terminal sparse state");
  fixture.now = "2026-08-03T07:10:00Z";
  auto reopened = fixture.workflow->reopen_occurrence(command);
  auto replay = fixture.workflow->reopen_occurrence(command);
  require(reopened.ok() && replay.ok() && reopened.value().status == "scheduled" &&
              replay.value().reopened_at == reopened.value().reopened_at,
          "occurrence reopen remains supported when no rolling successor must be deferred");
}

void test_series_cancel_and_delete_cancel_open_chain_with_precise_reason() {
  {
    WorkflowFixture fixture;
    auto created = fixture.workflow->create_series(fixture.daily_command());
    fixture.now = "2026-08-03T07:05:00Z";
    auto cancelled = fixture.workflow->cancel_series(
        excellent_calendar::application::SeriesOperationCommand{created.value().id, 1});
    require(cancelled.ok() && cancelled.value().status == "cancelled",
            "whole series cancellation should transition the Event");
    auto state = fixture.store->load();
    require(state.value().reminders.front().status == "cancelled" &&
                state.value().reminders.front().cancellation_reason ==
                    std::optional<std::string>("series_cancelled"),
            "series cancellation must terminate the open rolling Reminder");
  }
  {
    WorkflowFixture fixture;
    auto created = fixture.workflow->create_series(fixture.daily_command());
    fixture.now = "2026-08-03T07:05:00Z";
    auto deleted = fixture.workflow->delete_series(
        excellent_calendar::application::DeleteRecurringSeriesCommand{
            created.value().id, 1, "soft", "all_occurrences"});
    require(deleted.ok() && deleted.value().deleted_at == fixture.now,
            "whole series delete should soft-delete the Event");
    auto state = fixture.store->load();
    require(state.value().reminders.front().status == "cancelled" &&
                state.value().reminders.front().cancellation_reason ==
                    std::optional<std::string>("series_deleted"),
            "series delete must terminate the open chain without physical history deletion");
  }
}

void test_all_day_recurring_event_rejects_nonempty_reminders_without_writing() {
  WorkflowFixture fixture;
  auto command = fixture.daily_command();
  command.event.start_at.clear();
  command.event.end_at.clear();
  command.event.start_date = "2026-08-03";
  command.event.end_date = "2026-08-04";
  command.event.is_all_day = true;
  auto result = fixture.workflow->create_series(command);
  require(!result.ok() && result.error().code ==
                              "ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED",
          "all-day recurring Event plus Reminder must fail explicitly");
  auto state = fixture.store->load();
  require(state.ok() && state.value().events.empty() && state.value().reminders.empty(),
          "rejected all-day Reminder combination must not write partial state");
}

void test_delivery_prepare_finalize_is_idempotent_and_rolls_successor() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "recurring Event create should succeed before delivery");
  auto initial = fixture.store->load();
  require(initial.ok() && initial.value().reminders.size() == 1U,
          "delivery fixture should have one rolling Reminder");
  const auto current = initial.value().reminders.front();
  fixture.now = current.remind_at;
  const excellent_calendar::application::PrepareDeliveryCommand command{
      "reminder", current.id, std::nullopt, "popup", current.remind_at};
  auto prepared = fixture.delivery->prepare_delivery(command);
  require(prepared.ok() && prepared.value().notification.status == "prepared" &&
              !prepared.value().idempotent_replay,
          "first delivery prepare should persist a prepared attempt");
  auto replay = fixture.delivery->prepare_delivery(command);
  require(replay.ok() && replay.value().idempotent_replay &&
              replay.value().notification.delivery_attempt_id ==
                  prepared.value().notification.delivery_attempt_id,
          "repeated prepare must reuse the exact prepared attempt");

  fixture.now = "2026-08-03T07:31:00Z";
  auto finalized = fixture.delivery->finalize_delivery(
      excellent_calendar::application::FinalizeDeliveryCommand{
          *prepared.value().notification.delivery_attempt_id,
          "sent",
          std::nullopt,
          std::nullopt});
  require(finalized.ok() && finalized.value().reminder.has_value() &&
              finalized.value().reminder->status == "sent" &&
              finalized.value().reminder->last_triggered_at == fixture.now &&
              finalized.value().successor.has_value(),
          "sent finalization must retain history and create the successor atomically");
  require(finalized.value().successor->remind_at == "2026-08-04T07:30:00Z",
          "delivery successor should use the next local calendar occurrence");
  auto finalized_replay = fixture.delivery->finalize_delivery(
      excellent_calendar::application::FinalizeDeliveryCommand{
          *prepared.value().notification.delivery_attempt_id,
          "sent",
          std::nullopt,
          std::nullopt});
  require(finalized_replay.ok() && finalized_replay.value().idempotent_replay,
          "same finalization outcome must be idempotent");

  auto state = fixture.store->load();
  require(state.ok() && state.value().notifications.size() == 1U &&
              state.value().reminders.size() == 2U &&
              state.value().notifications.front().status == "sent",
          "Notification, consumed Reminder, and successor must persist together");
}

void test_retryable_delivery_failure_keeps_current_reminder_pending() {
  WorkflowFixture fixture;
  require(fixture.workflow->create_series(fixture.daily_command()).ok(),
          "recurring Event create should succeed before retryable delivery");
  auto state = fixture.store->load();
  const auto current = state.value().reminders.front();
  fixture.now = current.remind_at;
  auto prepared = fixture.delivery->prepare_delivery(
      excellent_calendar::application::PrepareDeliveryCommand{
          "reminder", current.id, std::nullopt, "popup", current.remind_at});
  require(prepared.ok(), "retryable delivery should prepare");
  fixture.now = "2026-08-03T07:31:00Z";
  auto failed = fixture.delivery->finalize_delivery(
      excellent_calendar::application::FinalizeDeliveryCommand{
           *prepared.value().notification.delivery_attempt_id,
           "failed",
           "retryable",
           "NOTIFICATION_DELIVERY_FAILED"});
  require(failed.ok() && failed.value().reminder.has_value() &&
              failed.value().reminder->status == "pending" &&
              !failed.value().successor.has_value(),
          "retryable failure must keep the current Reminder pending without a successor");
  auto retried = fixture.delivery->prepare_delivery(
      excellent_calendar::application::PrepareDeliveryCommand{
          "reminder", current.id, std::nullopt, "popup", current.remind_at});
  require(retried.ok() && !retried.value().idempotent_replay &&
              retried.value().notification.delivery_id == prepared.value().notification.delivery_id &&
              retried.value().notification.delivery_attempt_id !=
                  prepared.value().notification.delivery_attempt_id,
          "retryable failure should create a new attempt under the stable delivery ID");
}

void test_delivery_finalize_validates_contract_error_retryability() {
  WorkflowFixture fixture;
  require(fixture.workflow->create_series(fixture.daily_command()).ok(),
          "recurring Event create should succeed before failure metadata validation");
  auto state = fixture.store->load();
  const auto current = state.value().reminders.front();
  fixture.now = current.remind_at;
  auto prepared = fixture.delivery->prepare_delivery(
      {"reminder", current.id, std::nullopt, "popup", current.remind_at});
  require(prepared.ok(), "failure metadata validation requires a prepared attempt");
  const auto attempt_id = *prepared.value().notification.delivery_attempt_id;

  auto unknown = fixture.delivery->finalize_delivery(
      {attempt_id, "failed", "retryable", "ANDROID_NOTIFICATION_TEMPORARY"});
  require(!unknown.ok() && unknown.error().code == "CONTRACT_VALIDATION_FAILED" &&
              unknown.error().details.at("field") == "error_code",
          "finalize must reject error codes absent from error_codes.yaml");

  auto retryable_as_permanent = fixture.delivery->finalize_delivery(
      {attempt_id, "failed", "permanent", "STORAGE_IO_ERROR"});
  require(!retryable_as_permanent.ok() &&
              retryable_as_permanent.error().code == "CONTRACT_VALIDATION_FAILED" &&
              retryable_as_permanent.error().details.at("field") == "failure_class",
          "finalize must not permanently consume a retryable Contract error");

  auto permanent_as_retryable = fixture.delivery->finalize_delivery(
      {attempt_id, "failed", "retryable", "EVENT_NOT_FOUND"});
  require(!permanent_as_retryable.ok() &&
              permanent_as_retryable.error().code == "CONTRACT_VALIDATION_FAILED" &&
              permanent_as_retryable.error().details.at("field") == "failure_class",
          "finalize must not retry a permanent Contract error indefinitely");

  auto unchanged = fixture.store->load();
  require(unchanged.ok() && unchanged.value().notifications.size() == 1U &&
              unchanged.value().notifications.front().status == "prepared" &&
              unchanged.value().reminders.front().status == "pending",
          "rejected failure metadata must not mutate Notification or Reminder state");

  auto valid = fixture.delivery->finalize_delivery(
      {attempt_id, "failed", "retryable", "NOTIFICATION_DELIVERY_FAILED"});
  require(valid.ok() && valid.value().notification.status == "failed" &&
              valid.value().reminder.has_value() &&
              valid.value().reminder->status == "pending",
          "a retryable error declared by the Contract should still finalize normally");
}

void test_delivery_finalize_recovers_prepared_workflow_after_restart() {
  WorkflowFixture fixture;
  require(fixture.workflow->create_series(fixture.daily_command()).ok(),
          "recurring Event create should succeed before interrupted delivery");
  auto state = fixture.store->load();
  const auto current = state.value().reminders.front();
  fixture.now = current.remind_at;
  auto prepared = fixture.delivery->prepare_delivery(
      excellent_calendar::application::PrepareDeliveryCommand{
          "reminder", current.id, std::nullopt, "popup", current.remind_at});
  require(prepared.ok(), "interrupted delivery should prepare first");

  bool fail_once = true;
  auto interrupted_store = std::make_shared<
      excellent_calendar::storage::json::JsonRecurringEventTransaction>(
      fixture.directory.path(),
      [&fail_once](std::string_view phase) {
        if (fail_once && phase == "after_prepare") {
          fail_once = false;
          return excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
              excellent_calendar::common::make_error(
                  "STORAGE_IO_ERROR", "simulated delivery process interruption", {}, true));
        }
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  fixture.now = "2026-08-03T07:31:00Z";
  excellent_calendar::application::RecurringReminderDeliveryWorkflowService interrupted_delivery(
      interrupted_store,
      fixture.rolling,
      [&fixture]() { return fixture.now; },
      excellent_calendar::common::generate_uuid_v4);
  auto interrupted = interrupted_delivery.finalize_delivery(
      excellent_calendar::application::FinalizeDeliveryCommand{
          *prepared.value().notification.delivery_attempt_id,
          "sent",
          std::nullopt,
          std::nullopt});
  require(!interrupted.ok() && interrupted.error().code == "STORAGE_IO_ERROR",
          "simulated process interruption should stop the active finalize call");

  excellent_calendar::storage::json::JsonRecurringEventTransaction recovered(
      fixture.directory.path());
  require(recovered.initialize().ok(),
          "restart must replay the prepared delivery workflow transaction");
  auto recovered_state = recovered.load();
  const auto sent = std::count_if(
      recovered_state.value().reminders.begin(), recovered_state.value().reminders.end(),
      [](const auto& reminder) { return reminder.status == "sent"; });
  const auto pending = std::count_if(
      recovered_state.value().reminders.begin(), recovered_state.value().reminders.end(),
      [](const auto& reminder) { return reminder.status == "pending"; });
  require(recovered_state.ok() && sent == 1 && pending == 1 &&
              recovered_state.value().notifications.size() == 1U &&
              recovered_state.value().notifications.front().status == "sent",
          "replay must restore Notification, consumed Reminder, and exactly one successor");
}

void test_recovery_window_is_inclusive_and_selects_global_newest_twenty() {
  WorkflowFixture fixture;
  const auto now = excellent_calendar::common::parse_iso8601_utc_epoch_seconds(
      "2026-08-03T12:00:00Z");
  require(now.has_value(), "test recovery time should parse");
  std::vector<std::string> ids;
  auto seeded = fixture.store->execute(
      "event_recurrence_and_first_reminder_create_or_update",
      excellent_calendar::common::generate_uuid_v4(),
      fixture.now,
      [&](excellent_calendar::repository::RecurringEventState& state) {
        state.events.push_back(stored_recurring_event());
        state.recurrences.push_back(stored_daily_recurrence());
        for (int hour = 0; hour < 22; ++hour) {
          excellent_calendar::domain::Reminder reminder;
          reminder.id = excellent_calendar::common::generate_uuid_v4();
          ids.push_back(reminder.id);
          reminder.target_type = "event";
          reminder.target_id = "11111111-1111-4111-8111-111111111111";
          reminder.remind_at = excellent_calendar::common::format_epoch_seconds_utc_iso8601(
              *now - 72 * 60 * 60 + hour * 60 * 60);
          reminder.methods = {"popup"};
          reminder.is_enabled = true;
          reminder.status = "pending";
          reminder.source = "manual";
          reminder.created_at = fixture.now;
          reminder.updated_at = fixture.now;
          state.reminders.push_back(reminder);
        }
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(seeded.ok(), "ordinary due Reminders should seed recovery storage");
  const auto oldest_remind_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now - 72 * 60 * 60);
  auto prepared_overflow = fixture.delivery->prepare_delivery(
      {"reminder", ids.front(), std::nullopt, "popup", oldest_remind_at});
  require(prepared_overflow.ok(),
          "oldest in-window Reminder should have a frozen attempt before recovery");
  fixture.now = "2026-08-03T12:00:00Z";
  const std::string request_id = excellent_calendar::common::generate_uuid_v4();
  auto planned = fixture.recovery->plan_recovery(
      excellent_calendar::application::PlanReminderRecoveryCommand{
          request_id, "device_boot"});
  require(planned.ok() && planned.value().detail_reminders.size() == 20U &&
              planned.value().batch.window_overflow_count == 2 &&
              planned.value().batch.summary_reminder_ids.size() == 2U,
          "recovery must globally select 20 details and summarize the overflow");
  require(planned.value().prepared_attempt_resolutions.size() == 1U &&
              planned.value().prepared_attempt_resolutions.front().delivery_attempt_id ==
                  *prepared_overflow.value().notification.delivery_attempt_id &&
              planned.value().prepared_attempt_resolutions.front().resolution ==
                  "abandoned_to_summary" &&
              planned.value().prepared_attempt_resolutions.front().replacement_delivery_id ==
                  planned.value().batch.summary_delivery_id,
          "prepared overflow must be atomically abandoned in favor of the summary");
  require(planned.value().batch.summary_reminder_ids[0] == ids[0] &&
              planned.value().batch.summary_reminder_ids[1] == ids[1] &&
              planned.value().detail_reminders.front().id == ids[2] &&
              planned.value().detail_reminders.back().id == ids[21],
          "exactly-72-hour Reminder must be included and newest 20 must be detail items");
  require(std::is_sorted(
              planned.value().detail_reminders.begin(), planned.value().detail_reminders.end(),
              [](const auto& left, const auto& right) {
                return left.remind_at < right.remind_at ||
                       (left.remind_at == right.remind_at && left.id < right.id);
              }),
          "selected detail Reminders must be returned in ascending delivery order");

  auto replay = fixture.recovery->plan_recovery(
      excellent_calendar::application::PlanReminderRecoveryCommand{
          request_id, "device_boot"});
  require(replay.ok() && replay.value().idempotent_replay &&
              replay.value().batch.id == planned.value().batch.id &&
              replay.value().prepared_attempt_resolutions.size() == 1U &&
              replay.value().prepared_attempt_resolutions.front().resolution ==
                  "abandoned_to_summary",
          "same recovery request ID must replay the persisted batch");
  auto conflict = fixture.recovery->plan_recovery(
      excellent_calendar::application::PlanReminderRecoveryCommand{
          excellent_calendar::common::generate_uuid_v4(), "app_start"});
  require(!conflict.ok() && conflict.error().code == "RECOVERY_BATCH_CONFLICT",
          "a second request must not overlap an incomplete recovery batch");

  auto stale_finalize = fixture.delivery->finalize_delivery(
      {*prepared_overflow.value().notification.delivery_attempt_id,
       "sent", std::nullopt, std::nullopt});
  require(!stale_finalize.ok() &&
              stale_finalize.error().code == "DELIVERY_ATTEMPT_INVALID",
          "an attempt abandoned to recovery summary must reject stale finalize");

  auto prepared_summary = fixture.delivery->prepare_delivery(
      excellent_calendar::application::PrepareDeliveryCommand{
          "recovery_summary",
          std::nullopt,
          planned.value().batch.id,
          "popup",
          std::nullopt});
  require(prepared_summary.ok() &&
              prepared_summary.value().notification.delivery_id ==
                  planned.value().batch.summary_delivery_id &&
              prepared_summary.value().notification.planned_at ==
                  planned.value().batch.started_at,
          "recovery summary must use its stable delivery ID and batch start as planned_at");
  fixture.now = "2026-08-03T12:01:00Z";
  auto summary_sent = fixture.delivery->finalize_delivery(
      excellent_calendar::application::FinalizeDeliveryCommand{
          *prepared_summary.value().notification.delivery_attempt_id,
          "sent",
          std::nullopt,
          std::nullopt});
  require(summary_sent.ok() && summary_sent.value().recovery_batch.has_value() &&
              summary_sent.value().recovery_batch->status == "in_progress",
          "summary delivery should consume overflow but wait for outstanding detail deliveries");
  for (const auto& reminder : planned.value().detail_reminders) {
    auto prepared_detail = fixture.delivery->prepare_delivery(
        excellent_calendar::application::PrepareDeliveryCommand{
            "reminder",
            reminder.id,
            planned.value().batch.id,
            "popup",
            reminder.remind_at});
    require(prepared_detail.ok(), "each selected recovery detail should prepare");
    auto detail_sent = fixture.delivery->finalize_delivery(
        excellent_calendar::application::FinalizeDeliveryCommand{
            *prepared_detail.value().notification.delivery_attempt_id,
            "sent",
            std::nullopt,
            std::nullopt});
    require(detail_sent.ok(), "each selected recovery detail should finalize");
  }
  auto completed = fixture.store->load();
  const auto completed_batch = std::find_if(
      completed.value().recovery_batches.begin(), completed.value().recovery_batches.end(),
      [&](const auto& batch) { return batch.id == planned.value().batch.id; });
  require(completed_batch != completed.value().recovery_batches.end() &&
              completed_batch->status == "completed" &&
              completed_batch->completed_at == fixture.now,
          "batch should complete only after summary and every detail are logically delivered");
}

void test_recovery_counts_old_unexpanded_occurrences_without_bulk_creation() {
  WorkflowFixture fixture;
  require(fixture.workflow->create_series(fixture.daily_command()).ok(),
          "daily series should seed one rolling Reminder");
  auto before = fixture.store->load();
  require(before.ok() && before.value().reminders.size() == 1U,
          "daily series should start with one Reminder");
  const auto old_id = before.value().reminders.front().id;
  fixture.now = "2026-08-08T10:00:00Z";
  auto planned = fixture.recovery->plan_recovery(
      excellent_calendar::application::PlanReminderRecoveryCommand{
          excellent_calendar::common::generate_uuid_v4(), "alarm_reconcile"});
  require(planned.ok() && planned.value().batch.older_skipped_occurrence_count == 2 &&
              planned.value().batch.older_skipped_reminder_count == 3 &&
              planned.value().detail_reminders.size() == 3U,
          "unmaterialized and materialized pre-window Reminders should be summarized");
  auto after = fixture.store->load();
  require(after.ok() && after.value().reminders.size() == 5U,
          "recovery should create three window Reminders plus one future successor only");
  const auto old = std::find_if(after.value().reminders.begin(), after.value().reminders.end(),
                                [&](const auto& reminder) { return reminder.id == old_id; });
  const auto future_open = std::count_if(
      after.value().reminders.begin(), after.value().reminders.end(),
      [&](const auto& reminder) {
        return reminder.recurrence_revision.has_value() && reminder.is_enabled &&
               (reminder.status == "pending" || reminder.status == "scheduled") &&
               reminder.remind_at > fixture.now;
      });
  require(old != after.value().reminders.end() && old->status == "expired" &&
              !old->is_enabled && !old->scheduled_at.has_value() &&
              old->expiration_reason ==
                  std::optional<std::string>("recovery_window_elapsed") &&
              old->expired_at == fixture.now && !old->recovery_batch_id.has_value() &&
              future_open == 1,
          "pre-window rolling Reminder must expire while preserving one future successor");
}

void test_recovery_expires_old_ordinary_reminder_and_abandons_its_attempt() {
  WorkflowFixture fixture;
  const std::string event_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const std::string reminder_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  auto seeded = fixture.store->execute(
      "event_recurrence_and_first_reminder_create_or_update",
      excellent_calendar::common::generate_uuid_v4(), fixture.now,
      [&](excellent_calendar::repository::RecurringEventState& state) {
        auto event = stored_recurring_event();
        event.id = event_id;
        event.has_recurrence = false;
        event.recurrence_id = std::nullopt;
        event.recurrence_revision = std::nullopt;
        state.events.push_back(event);
        excellent_calendar::domain::Reminder reminder;
        reminder.id = reminder_id;
        reminder.target_type = "event";
        reminder.target_id = event_id;
        reminder.remind_at = "2026-08-01T00:00:00Z";
        reminder.methods = {"popup"};
        reminder.is_enabled = true;
        reminder.status = "pending";
        reminder.source = "manual";
        reminder.created_at = fixture.now;
        reminder.updated_at = fixture.now;
        state.reminders.push_back(reminder);
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(seeded.ok(), "ordinary pre-window Reminder should seed recovery state");
  fixture.now = "2026-08-03T07:00:00Z";
  auto prepared = fixture.delivery->prepare_delivery(
      {"reminder", reminder_id, std::nullopt, "popup", "2026-08-01T00:00:00Z"});
  require(prepared.ok(), "ordinary Reminder should be prepared before it leaves the window");
  fixture.now = "2026-08-05T01:00:00Z";
  auto planned = fixture.recovery->plan_recovery(
      {excellent_calendar::common::generate_uuid_v4(), "app_start"});
  require(planned.ok() && planned.value().detail_reminders.empty() &&
              planned.value().batch.older_skipped_occurrence_count == 0 &&
              planned.value().batch.older_skipped_reminder_count == 1 &&
              planned.value().batch.summary_delivery_id.has_value() &&
              planned.value().batch.status == "in_progress" &&
              planned.value().prepared_attempt_resolutions.size() == 1U &&
              planned.value().prepared_attempt_resolutions.front().resolution ==
                  "abandoned_outside_window" &&
              planned.value().prepared_attempt_resolutions.front().replacement_delivery_id ==
                  planned.value().batch.summary_delivery_id,
          "materialized pre-window Reminder and prepared attempt must move to summary audit");
  auto after = fixture.store->load();
  require(after.ok(), "ordinary Reminder state should reload");
  const auto reminder = std::find_if(
      after.value().reminders.begin(), after.value().reminders.end(),
      [&](const auto& item) { return item.id == reminder_id; });
  const auto attempt = std::find_if(
      after.value().notifications.begin(), after.value().notifications.end(),
      [&](const auto& item) {
        return item.delivery_attempt_id == prepared.value().notification.delivery_attempt_id;
      });
  require(reminder != after.value().reminders.end() && !reminder->is_enabled &&
              reminder->status == "expired" && !reminder->scheduled_at.has_value() &&
              reminder->expiration_reason ==
                  std::optional<std::string>("recovery_window_elapsed") &&
              reminder->expired_at == fixture.now &&
              !reminder->recovery_batch_id.has_value() &&
              attempt != after.value().notifications.end() &&
              attempt->status == "abandoned" &&
              attempt->abandon_reason ==
                  std::optional<std::string>("recovery_window_elapsed") &&
              attempt->resolved_by_recovery_batch_id ==
                  std::optional<std::string>(planned.value().batch.id) &&
              !attempt->recovery_batch_id.has_value(),
          "old ordinary Reminder must expire and retain an immutable abandoned attempt");
  const auto expired_json =
      excellent_calendar::boundary::contract::reminder_response_v2_to_json(*reminder)
          .get<picojson::object>();
  const auto abandoned_json =
      excellent_calendar::boundary::contract::notification_response_v2_to_json(*attempt)
          .get<picojson::object>();
  require(expired_json.at("expiration_reason").get<std::string>() ==
                  "recovery_window_elapsed" &&
              expired_json.at("expired_at").get<std::string>() == fixture.now &&
              abandoned_json.at("resolved_by_recovery_batch_id").get<std::string>() ==
                  planned.value().batch.id &&
              abandoned_json.at("abandon_reason").get<std::string>() ==
                  "recovery_window_elapsed",
          "v2 boundary JSON must expose expiration and abandonment audit fields");
  auto stale_finalize = fixture.delivery->finalize_delivery(
      {*prepared.value().notification.delivery_attempt_id,
       "sent", std::nullopt, std::nullopt});
  require(!stale_finalize.ok() &&
              stale_finalize.error().code == "DELIVERY_ATTEMPT_INVALID",
          "outside-window abandoned attempt must reject stale finalize");
}

void test_recovery_adopts_prepared_attempt_and_blocks_conflicting_mutations() {
  WorkflowFixture fixture;
  const std::string event_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const std::string reminder_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const std::string remind_at = "2026-08-03T06:30:00Z";
  auto seeded = fixture.store->execute(
      "event_recurrence_and_first_reminder_create_or_update",
      excellent_calendar::common::generate_uuid_v4(), fixture.now,
      [&](excellent_calendar::repository::RecurringEventState& state) {
        auto event = stored_recurring_event();
        event.id = event_id;
        event.has_recurrence = false;
        event.recurrence_id = std::nullopt;
        event.recurrence_revision = std::nullopt;
        state.events.push_back(event);
        excellent_calendar::domain::Reminder reminder;
        reminder.id = reminder_id;
        reminder.target_type = "event";
        reminder.target_id = event_id;
        reminder.remind_at = remind_at;
        reminder.methods = {"popup"};
        reminder.is_enabled = true;
        reminder.status = "pending";
        reminder.source = "manual";
        reminder.created_at = fixture.now;
        reminder.updated_at = fixture.now;
        state.reminders.push_back(reminder);
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(seeded.ok(), "ordinary due Reminder should seed prepared-recovery test");

  auto prepared = fixture.delivery->prepare_delivery(
      {"reminder", reminder_id, std::nullopt, "popup", remind_at});
  require(prepared.ok() && !prepared.value().idempotent_replay,
          "normal delivery should be prepared before recovery starts");

  excellent_calendar::application::ReminderServiceV2 reminder_service(
      fixture.store, [&]() { return fixture.now; },
      excellent_calendar::common::generate_uuid_v4);
  excellent_calendar::application::UpdateReminderV2Command update;
  update.reminder_id = reminder_id;
  update.remind_at = {true, std::optional<std::string>("2026-08-03T08:00:00Z")};
  auto rescheduled = reminder_service.update(update);
  require(!rescheduled.ok() && rescheduled.error().code == "REMINDER_NOT_DELIVERABLE",
          "a prepared attempt must prevent Reminder payload or schedule drift");

  auto planned = fixture.recovery->plan_recovery(
      {excellent_calendar::common::generate_uuid_v4(), "app_start"});
  require(planned.ok() && planned.value().detail_reminders.size() == 1U &&
              planned.value().detail_reminders.front().id == reminder_id &&
              planned.value().prepared_attempt_resolutions.size() == 1U &&
              planned.value().prepared_attempt_resolutions.front().delivery_attempt_id ==
                  *prepared.value().notification.delivery_attempt_id &&
              planned.value().prepared_attempt_resolutions.front().resolution ==
                  "adopted_detail" &&
              !planned.value()
                   .prepared_attempt_resolutions.front()
                   .replacement_delivery_id.has_value(),
          "recovery should adopt the already prepared due Reminder as its detail");
  const auto plan_json =
      excellent_calendar::boundary::contract::plan_recovery_response_v2_to_json(
          planned.value())
          .get<picojson::object>();
  require(plan_json.at("prepared_attempt_resolutions")
                  .get<picojson::array>()
                  .size() == 1U &&
              plan_json.at("prepared_attempt_resolutions")
                      .get<picojson::array>()
                      .front()
                      .get<picojson::object>()
                      .at("resolution")
                      .get<std::string>() == "adopted_detail",
          "v2 plan_recovery JSON must expose prepared attempt arbitration");
  auto during = fixture.store->load();
  const auto adopted = std::find_if(
      during.value().notifications.begin(), during.value().notifications.end(),
      [&](const auto& notification) {
        return notification.delivery_attempt_id ==
               prepared.value().notification.delivery_attempt_id;
      });
  require(adopted != during.value().notifications.end() &&
              !adopted->recovery_batch_id.has_value() &&
              adopted->resolved_by_recovery_batch_id ==
                  std::optional<std::string>(planned.value().batch.id) &&
              adopted->planned_at == prepared.value().notification.planned_at &&
              adopted->title == prepared.value().notification.title &&
              adopted->body == prepared.value().notification.body,
          "recovery planning must retain frozen payload and record a separate resolution owner");

  auto replayed_prepare = fixture.delivery->prepare_delivery(
      {"reminder", reminder_id, planned.value().batch.id, "popup", remind_at});
  require(replayed_prepare.ok() && replayed_prepare.value().idempotent_replay &&
              replayed_prepare.value().notification.delivery_attempt_id ==
                  prepared.value().notification.delivery_attempt_id &&
              !replayed_prepare.value().notification.recovery_batch_id.has_value(),
          "recovery detail must reuse the original frozen prepared attempt");

  auto cancelled = reminder_service.cancel({reminder_id});
  require(!cancelled.ok() && cancelled.error().code == "RECOVERY_BATCH_CONFLICT",
          "user mutation must not strand an active recovery batch member");
  auto completed_event = fixture.workflow->complete_event({event_id, "manual", std::nullopt});
  require(!completed_event.ok() &&
              completed_event.error().code == "RECOVERY_BATCH_CONFLICT",
          "Event lifecycle mutation must not strand an active recovery batch member");

  fixture.now = "2026-08-03T07:01:00Z";
  auto finalized = fixture.delivery->finalize_delivery(
      {*prepared.value().notification.delivery_attempt_id,
       "sent", std::nullopt, std::nullopt});
  require(finalized.ok() && finalized.value().recovery_batch.has_value() &&
              finalized.value().recovery_batch->status == "completed",
          "finalizing the adopted attempt must complete the recovery batch");
}

void test_ordinary_reminders_reject_methods_without_a_delivery_implementation() {
  WorkflowFixture fixture;
  const std::string event_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  auto seeded = fixture.store->execute(
      "event_recurrence_and_first_reminder_create_or_update",
      excellent_calendar::common::generate_uuid_v4(), fixture.now,
      [&](excellent_calendar::repository::RecurringEventState& state) {
        auto event = stored_recurring_event();
        event.id = event_id;
        event.has_recurrence = false;
        event.recurrence_id = std::nullopt;
        event.recurrence_revision = std::nullopt;
        state.events.push_back(event);
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(seeded.ok(), "ordinary Event should seed method validation test");
  excellent_calendar::application::ReminderServiceV2 reminder_service(
      fixture.store, [&]() { return fixture.now; },
      excellent_calendar::common::generate_uuid_v4);
  auto ring = reminder_service.create(
      {"event", event_id, std::optional<std::string>("2026-08-03T08:00:00Z"),
       std::nullopt, {"ring"}, std::nullopt, true, "manual"});
  require(!ring.ok() && ring.error().code == "UNSUPPORTED_REMINDER_METHOD",
          "Core must reject a method that list/prepare/finalize cannot deliver");

  excellent_calendar::domain::Event event;
  event.title = "Unsupported embedded method";
  event.start_at = "2026-08-03T09:00:00Z";
  event.end_at = "2026-08-03T10:00:00Z";
  event.timezone = "Europe/London";
  event.source = "manual";
  excellent_calendar::application::EventReminderDraftInput draft;
  draft.target_type = "event";
  draft.remind_at = "2026-08-03T08:30:00Z";
  draft.methods = {"wechat"};
  draft.message = std::nullopt;
  draft.is_enabled = true;
  draft.source = "manual";
  draft.remind_at_supplied = true;
  draft.message_supplied = true;
  auto embedded = fixture.workflow->create_event({event, std::nullopt, {draft}});
  require(!embedded.ok() && embedded.error().code == "UNSUPPORTED_REMINDER_METHOD",
          "ordinary Event creation must enforce the same deliverable-method policy");
}

void test_reminderless_series_reopen_is_idempotent() {
  WorkflowFixture fixture;
  auto command = fixture.daily_command();
  command.event.start_at.clear();
  command.event.end_at.clear();
  command.event.start_date = "2026-08-03";
  command.event.end_date = "2026-08-04";
  command.event.is_all_day = true;
  command.reminders.clear();
  auto created = fixture.workflow->create_series(command);
  require(created.ok(), "all-day recurring series without Reminder should be created");
  auto completed = fixture.workflow->complete_series({created.value().id, 1});
  require(completed.ok(), "reminderless series should complete");
  fixture.now = "2026-08-04T07:00:00Z";
  auto reopened = fixture.workflow->reopen_series({created.value().id, 1});
  auto replay = fixture.workflow->reopen_series({created.value().id, 1});
  require(reopened.ok() && replay.ok() && replay.value().status == "active" &&
              replay.value().updated_at == reopened.value().updated_at,
          "reopen retry must return the already active series even without Reminder audit rows");
}

void test_occurrence_query_pages_and_attaches_sparse_state() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "daily recurring Event should be created for occurrence query");
  auto state = fixture.store->load();
  require(state.ok(), "recurring state should load");
  const auto& recurrence = state.value().recurrences.front();
  auto first = fixture.recurrence->occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(created.value()),
      recurrence,
      0);
  require(first.ok(), "first occurrence should expand");
  auto completed = fixture.workflow->complete_occurrence(
      {created.value().id,
       1,
       first.value().occurrence_key,
       first.value().occurrence_start_at,
       std::nullopt});
  require(completed.ok(), "first occurrence should complete");

  excellent_calendar::application::ListEventOccurrencesCommand command;
  command.event_id = created.value().id;
  command.recurrence_revision = 1;
  command.is_all_day = false;
  command.range_start_at = "2026-08-03T00:00:00Z";
  command.range_end_at = "2026-08-06T00:00:00Z";
  command.limit = 2;
  auto page1 = fixture.event_query->list_occurrences(command);
  require(page1.ok() && page1.value().items.size() == 2U && page1.value().has_more &&
              page1.value().next_cursor.has_value(),
          "occurrence query should expose a stable first page and cursor");
  require(page1.value().items.front().state.has_value() &&
              page1.value().items.front().state->status == "completed",
          "occurrence query must attach the persisted sparse state");
  command.cursor = page1.value().next_cursor;
  auto page2 = fixture.event_query->list_occurrences(command);
  require(page2.ok() && page2.value().items.size() == 1U && !page2.value().has_more &&
              !page2.value().next_cursor.has_value(),
          "occurrence cursor must resume exclusively without duplicates");
}

void test_event_detail_aggregate_uses_one_storage_snapshot() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "daily recurring Event should be created for detail query");

  auto counting_transaction = std::make_shared<CountingRecurringEventTransaction>(
      fixture.store);
  excellent_calendar::application::RecurringEventQueryService query(
      counting_transaction, fixture.recurrence, fixture.category_repository);
  auto detail = query.get_event_detail(created.value().id);
  require(detail.ok() && detail.value().event.id == created.value().id &&
              detail.value().recurrence.has_value() &&
              detail.value().recurrence->revision == 1 &&
              detail.value().reminders.size() == 1U,
          "Event detail aggregate should contain one consistent Event snapshot");
  require(counting_transaction->load_count() == 1,
          "Event detail aggregate must load Event, Recurrence, and Reminders once");
}

void test_v2_schedulable_query_and_mark_scheduled_use_recurring_store() {
  WorkflowFixture fixture;
  auto created = fixture.workflow->create_series(fixture.daily_command());
  require(created.ok(), "daily recurring Event should be created for scheduler query");

  excellent_calendar::application::ListRecurringSchedulableRemindersCommand command;
  command.from_at = "2026-08-03T00:00:00Z";
  command.to_at = "2026-08-04T00:00:00Z";
  command.supported_methods = {"popup"};
  auto pending = fixture.reminder_query->list_schedulable(command);
  require(pending.ok() && pending.value().items.size() == 1U,
          "v2 scheduler query must read the rolling Reminder from recurring storage");
  const auto reminder_id = pending.value().items.front().id;
  const auto expected_remind_at = pending.value().items.front().remind_at;
  fixture.now = "2026-08-03T07:05:00Z";
  auto stale = fixture.reminder_query->mark_scheduled(
      {reminder_id, "2026-08-03T07:31:00Z", "2026-08-03T07:04:00Z"});
  require(!stale.ok() && stale.error().code == "REMINDER_SCHEDULE_CONFLICT" &&
              stale.error().retryable,
          "stale Alarm acknowledgement must fail with a retryable schedule CAS conflict");
  auto unchanged = fixture.reminder_query->get_reminder(reminder_id);
  require(unchanged.ok() && unchanged.value().status == "pending" &&
              !unchanged.value().scheduled_at.has_value(),
          "failed schedule CAS must not modify the Reminder");
  auto scheduled = fixture.reminder_query->mark_scheduled(
      {reminder_id, expected_remind_at, "2026-08-03T07:04:00Z"});
  require(scheduled.ok() && scheduled.value().status == "scheduled" &&
              scheduled.value().scheduled_at ==
                  std::optional<std::string>("2026-08-03T07:04:00Z"),
          "mark_scheduled must persist scheduler acknowledgement in v2 storage");

  auto pending_only = fixture.reminder_query->list_schedulable(command);
  require(pending_only.ok() && pending_only.value().items.empty(),
          "scheduled Reminder must be excluded unless include_scheduled is true");
  command.include_scheduled = true;
  auto with_scheduled = fixture.reminder_query->list_schedulable(command);
  require(with_scheduled.ok() && with_scheduled.value().items.size() == 1U &&
              with_scheduled.value().items.front().id == reminder_id,
          "scheduler reconciliation must be able to reload scheduled Reminders");

  auto tagged = fixture.store->execute(
      "recovery_batch_reminders_and_summary",
      excellent_calendar::common::generate_uuid_v4(), fixture.now,
      [&](excellent_calendar::repository::RecurringEventState& state) {
        const auto found = std::find_if(
            state.reminders.begin(), state.reminders.end(), [&](const auto& reminder) {
              return reminder.id == reminder_id;
            });
        require(found != state.reminders.end(), "scheduled Reminder should still be stored");
        found->status = std::string(excellent_calendar::domain::kReminderStatusPending);
        found->scheduled_at = std::nullopt;
        found->recovery_batch_id = "22222222-2222-4222-8222-222222222222";
        excellent_calendar::domain::ReminderRecoveryBatch batch;
        batch.id = "22222222-2222-4222-8222-222222222222";
        batch.recovery_request_id = "33333333-3333-4333-8333-333333333333";
        batch.trigger_source = "alarm_reconcile";
        batch.started_at = fixture.now;
        batch.window_start_at = "2026-07-31T07:05:00Z";
        batch.detail_reminder_ids = {reminder_id};
        batch.status = "in_progress";
        state.recovery_batches.push_back(batch);
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success(
            excellent_calendar::common::Unit{});
      });
  require(tagged.ok(), "test should attach a recovery batch to the Reminder");
  auto recovery_owned = fixture.reminder_query->list_schedulable(command);
  require(recovery_owned.ok() && recovery_owned.value().items.empty() &&
              recovery_owned.value().unsupported_reminder_ids.empty(),
          "scheduler must exclude Reminders owned by a recovery batch");
}

void test_rolling_reminder_idempotency_detects_message_drift() {
  auto resolver = create_resolver();
  auto recurrence_service =
      std::make_shared<excellent_calendar::application::RecurrenceService>(resolver);
  excellent_calendar::application::RollingReminderService rolling(recurrence_service);
  auto schedule = timed_schedule(
      "2026-08-03T08:00:00Z", "2026-08-03T09:00:00Z");
  auto recurrence = derive(*recurrence_service, schedule, "daily");
  auto occurrence = recurrence_service->occurrence_at(schedule, recurrence, 0);
  require(occurrence.ok(), "occurrence should expand for idempotency test");
  auto first = rolling.create_for_occurrence(
      occurrence.value(),
      {30, {"popup"}, "first message", true, "manual"},
      "2026-08-03T07:00:00Z");
  auto changed = rolling.create_for_occurrence(
      occurrence.value(),
      {30, {"popup"}, "changed message", true, "manual"},
      "2026-08-03T07:00:00Z");
  require(first.ok() && changed.ok() && first.value().id == changed.value().id,
          "business-identical Reminder coordinates must derive the same ID");
  excellent_calendar::repository::RecurringEventState state;
  require(rolling.insert_idempotent(state, first.value()).ok(),
          "first deterministic Reminder insert should succeed");
  auto conflict = rolling.insert_idempotent(state, changed.value());
  require(!conflict.ok() && conflict.error().code == "REMINDER_IDEMPOTENCY_CONFLICT",
          "same deterministic ID with changed message must not be silently accepted");
}

picojson::object parse_native_v2(const std::string& json) {
  picojson::value value;
  const auto error = picojson::parse(value, json);
  require(error.empty() && value.is<picojson::object>(),
          "v2 boundary must return a JSON object");
  const auto object = value.get<picojson::object>();
  require(object.at("contract_version").is<double>() &&
              object.at("contract_version").get<double>() == 2.0,
          "v2 boundary must emit contract_version=2");
  return object;
}

void test_runtime_timezone_boundary_is_strict_and_batched() {
  TemporaryDirectory directory;
  picojson::object initialize;
  initialize["storage_directory"] = picojson::value(directory.path().generic_string());
  initialize["tzdb_directory"] = picojson::value(
      std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR).generic_string());
  auto initialized = parse_native_v2(
      excellent_calendar::boundary::api::initialize_runtime_v2_json(
          picojson::value(initialize).serialize()));
  require(initialized.at("ok").get<bool>(),
          "timezone boundary test runtime initialization should succeed");

  picojson::object gap_request;
  gap_request["local_datetime"] = picojson::value("2026-03-29T01:30:00");
  gap_request["timezone"] = picojson::value("Europe/London");
  auto gap = parse_native_v2(excellent_calendar::boundary::api::resolve_local_datetime_v2(
      picojson::value(gap_request).serialize()));
  require(gap.at("ok").get<bool>(), "gap request should succeed through the v2 boundary");
  const auto gap_data = gap.at("data").get<picojson::object>();
  require(gap_data.at("utc_instant").get<std::string>() == "2026-03-29T01:00:00Z" &&
              gap_data.at("resolved_local_datetime").get<std::string>() ==
                  "2026-03-29T02:00:00" &&
              gap_data.at("resolution").get<std::string>() == "gap_shifted",
          "gap response must expose the shifted local time and UTC instant");

  gap_request["local_datetime"] = picojson::value("2026-10-25T01:30:00");
  auto fold = parse_native_v2(excellent_calendar::boundary::api::resolve_local_datetime_v2(
      picojson::value(gap_request).serialize()));
  const auto fold_data = fold.at("data").get<picojson::object>();
  require(fold.at("ok").get<bool>() &&
              fold_data.at("utc_instant").get<std::string>() ==
                  "2026-10-25T00:30:00Z" &&
              fold_data.at("resolution").get<std::string>() == "fold_earlier",
          "fold response must choose and report the earlier instant");

  picojson::array instants;
  instants.emplace_back("2026-03-29T00:30:00Z");
  instants.emplace_back("2026-03-29T01:00:00Z");
  instants.emplace_back("2026-03-29T01:00:00Z");
  picojson::object localize_request;
  localize_request["timezone"] = picojson::value("Europe/London");
  localize_request["instants"] = picojson::value(std::move(instants));
  auto localized = parse_native_v2(excellent_calendar::boundary::api::localize_instants_v2(
      picojson::value(localize_request).serialize()));
  require(localized.at("ok").get<bool>(), "batch localization should succeed");
  const auto items = localized.at("data")
                         .get<picojson::object>()
                         .at("items")
                         .get<picojson::array>();
  require(items.size() == 3U &&
              items[0].get<picojson::object>().at("local_datetime").get<std::string>() ==
                  "2026-03-29T00:30:00" &&
              items[1].get<picojson::object>().at("local_datetime").get<std::string>() ==
                  "2026-03-29T02:00:00" &&
              items[1].serialize() == items[2].serialize(),
          "batch localization must preserve order, timezone rules, and duplicates");

  localize_request["instants"] = picojson::value(
      picojson::array{picojson::value("2026-03-29T01:00:00.000Z")});
  auto fractional = parse_native_v2(excellent_calendar::boundary::api::localize_instants_v2(
      picojson::value(localize_request).serialize()));
  require(!fractional.at("ok").get<bool>() &&
              fractional.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "CONTRACT_VALIDATION_FAILED",
          "whole-second Contract must reject fractional UTC instants");

  gap_request["unknown"] = picojson::value(true);
  auto unknown = parse_native_v2(excellent_calendar::boundary::api::resolve_local_datetime_v2(
      picojson::value(gap_request).serialize()));
  require(!unknown.at("ok").get<bool>() &&
              unknown.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "CONTRACT_VALIDATION_FAILED",
          "timezone boundary must reject unknown fields");
}

void test_contract_v2_boundary_supports_ordinary_event_and_reminder_flow() {
  TemporaryDirectory directory;
  picojson::object initialize;
  initialize["storage_directory"] = picojson::value(directory.path().generic_string());
  initialize["tzdb_directory"] = picojson::value(
      std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR).generic_string());
  auto initialized = parse_native_v2(
      excellent_calendar::boundary::api::initialize_runtime_v2_json(
          picojson::value(initialize).serialize()));
  require(initialized.at("ok").get<bool>(),
          "unified v2 runtime initialization should succeed");

  const auto now_epoch = excellent_calendar::common::parse_iso8601_utc_epoch_seconds(
      excellent_calendar::common::utc_now_iso8601());
  require(now_epoch.has_value(), "ordinary boundary test Clock should return UTC time");
  const auto start_at = excellent_calendar::common::format_epoch_seconds_utc_iso8601(
      *now_epoch + 10 * 24 * 60 * 60);
  const auto end_at = excellent_calendar::common::format_epoch_seconds_utc_iso8601(
      *now_epoch + 10 * 24 * 60 * 60 + 60 * 60);
  const auto absolute_remind_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 9 * 24 * 60 * 60);
  const auto advance_remind_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 10 * 24 * 60 * 60 - 60 * 60);
  const auto moved_start_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 11 * 24 * 60 * 60);
  const auto moved_end_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 11 * 24 * 60 * 60 + 60 * 60);
  const auto moved_advance_remind_at =
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 11 * 24 * 60 * 60 - 60 * 60);

  picojson::object create;
  create["title"] = picojson::value("Ordinary v2 event");
  create["content"] = picojson::value("clear me");
  create["start_at"] = picojson::value(start_at);
  create["end_at"] = picojson::value(end_at);
  create["start_date"] = picojson::value();
  create["end_date"] = picojson::value();
  create["is_all_day"] = picojson::value(false);
  create["category_id"] = picojson::value();
  create["importance"] = picojson::value();
  create["location"] = picojson::value("Office");
  create["timezone"] = picojson::value("Etc/UTC");
  create["source"] = picojson::value("manual");
  create["recurrence"] = picojson::value();
  create["reminders"] = picojson::value(picojson::array{});
  auto created = parse_native_v2(
      excellent_calendar::boundary::api::create_event_v2(
          picojson::value(create).serialize()));
  require(created.at("ok").get<bool>(), "ordinary Event should use the v2 writer");
  const auto event_id =
      created.at("data").get<picojson::object>().at("id").get<std::string>();
  require(created.at("data")
                  .get<picojson::object>()
                  .at("recurrence_revision")
                  .is<picojson::null>(),
          "ordinary Event response should carry no recurrence identity");

  // Reopen the runtime before any further operation to prove ordinary Event decoding
  // derives has_recurrence from the nullable recurrence identity.
  auto reopened_runtime = parse_native_v2(
      excellent_calendar::boundary::api::initialize_runtime_v2_json(
          picojson::value(initialize).serialize()));
  require(reopened_runtime.at("ok").get<bool>(),
          "ordinary Event v2 storage should reopen after process restart");

  picojson::object update_event;
  update_event["id"] = picojson::value(event_id);
  update_event["title"] = picojson::value("Ordinary v2 event updated");
  update_event["content"] = picojson::value();
  auto updated_event = parse_native_v2(
      excellent_calendar::boundary::api::update_event_v2(
          picojson::value(update_event).serialize()));
  require(updated_event.at("ok").get<bool>() &&
              updated_event.at("data")
                  .get<picojson::object>()
                  .at("content")
                  .is<picojson::null>(),
          "Core should merge ordinary Event partial updates and preserve explicit null");

  picojson::object create_reminder;
  create_reminder["target_type"] = picojson::value("event");
  create_reminder["target_id"] = picojson::value(event_id);
  create_reminder["remind_at"] = picojson::value(absolute_remind_at);
  create_reminder["advance_minutes"] = picojson::value();
  create_reminder["methods"] =
      picojson::value(picojson::array{picojson::value("popup")});
  create_reminder["message"] = picojson::value("Initial reminder body");
  create_reminder["is_enabled"] = picojson::value(true);
  create_reminder["source"] = picojson::value("manual");
  auto reminder_created = parse_native_v2(
      excellent_calendar::boundary::api::create_reminder_v2(
          picojson::value(create_reminder).serialize()));
  require(reminder_created.at("ok").get<bool>(),
          "ordinary Reminder should be created in the same v2 store");
  const auto reminder_id = reminder_created.at("data")
                               .get<picojson::object>()
                               .at("reminder_id")
                               .get<std::string>();

  picojson::object reminder_identity;
  reminder_identity["reminder_id"] = picojson::value(reminder_id);
  picojson::object mark_scheduled = reminder_identity;
  mark_scheduled["scheduled_at"] =
      picojson::value(excellent_calendar::common::utc_now_iso8601());
  auto missing_schedule_cas = parse_native_v2(
      excellent_calendar::boundary::api::mark_reminder_scheduled_v2(
          picojson::value(mark_scheduled).serialize()));
  require(!missing_schedule_cas.at("ok").get<bool>() &&
              missing_schedule_cas.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "CONTRACT_VALIDATION_FAILED",
          "scheduler acknowledgement must require expected_remind_at");
  mark_scheduled["expected_remind_at"] = picojson::value(absolute_remind_at);
  auto scheduled = parse_native_v2(
      excellent_calendar::boundary::api::mark_reminder_scheduled_v2(
          picojson::value(mark_scheduled).serialize()));
  require(scheduled.at("ok").get<bool>() &&
              scheduled.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "scheduled",
          "ordinary Reminder should use the unified scheduler acknowledgement");

  picojson::object content_only_update;
  content_only_update["reminder_id"] = picojson::value(reminder_id);
  content_only_update["message"] = picojson::value("Updated reminder body");
  auto content_updated = parse_native_v2(
      excellent_calendar::boundary::api::update_reminder_v2(
          picojson::value(content_only_update).serialize()));
  require(content_updated.at("ok").get<bool>() &&
              content_updated.at("data")
                      .get<picojson::object>()
                      .at("status")
                      .get<std::string>() == "scheduled" &&
              !content_updated.at("data")
                   .get<picojson::object>()
                   .at("scheduled_at")
                   .is<picojson::null>(),
          "message-only Reminder update must preserve an existing Alarm schedule");

  picojson::object update_reminder;
  update_reminder["reminder_id"] = picojson::value(reminder_id);
  update_reminder["advance_minutes"] = picojson::value(60.0);
  auto reminder_updated = parse_native_v2(
      excellent_calendar::boundary::api::update_reminder_v2(
          picojson::value(update_reminder).serialize()));
  require(reminder_updated.at("ok").get<bool>() &&
              reminder_updated.at("data")
                      .get<picojson::object>()
                      .at("advance_minutes")
                      .get<double>() == 60.0 &&
              reminder_updated.at("data")
                      .get<picojson::object>()
                      .at("remind_at")
                      .get<std::string>() == advance_remind_at,
          "a supplied non-null Reminder time mode should atomically replace the previous mode");

  auto disabled = parse_native_v2(
      excellent_calendar::boundary::api::disable_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(disabled.at("ok").get<bool>() &&
              !disabled.at("data").get<picojson::object>().at("is_enabled").get<bool>(),
          "ordinary Reminder should support temporary disable");
  picojson::object disabled_update;
  disabled_update["reminder_id"] = picojson::value(reminder_id);
  disabled_update["message"] = picojson::value("Updated while disabled");
  auto updated_while_disabled = parse_native_v2(
      excellent_calendar::boundary::api::update_reminder_v2(
          picojson::value(disabled_update).serialize()));
  require(updated_while_disabled.at("ok").get<bool>() &&
              !updated_while_disabled.at("data")
                   .get<picojson::object>()
                   .at("is_enabled")
                   .get<bool>(),
          "Reminder partial update must not implicitly re-enable a disabled task");
  auto enabled = parse_native_v2(
      excellent_calendar::boundary::api::enable_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(enabled.at("ok").get<bool>() &&
              enabled.at("data").get<picojson::object>().at("is_enabled").get<bool>() &&
              enabled.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "pending",
          "ordinary Reminder should return to pending when enabled");

  picojson::object pagination;
  pagination["page"] = picojson::value(1.0);
  pagination["page_size"] = picojson::value(10.0);
  pagination["cursor"] = picojson::value();
  picojson::object list_reminders;
  list_reminders["target_type"] = picojson::value("event");
  list_reminders["target_id"] = picojson::value(event_id);
  list_reminders["recurrence_revision"] = picojson::value();
  list_reminders["occurrence_key"] = picojson::value();
  list_reminders["methods"] =
      picojson::value(picojson::array{picojson::value("popup")});
  list_reminders["status"] =
      picojson::value(picojson::array{picojson::value("pending")});
  list_reminders["is_enabled"] = picojson::value(true);
  list_reminders["pagination"] = picojson::value(pagination);
  list_reminders["sort_by"] = picojson::value("remind_at");
  list_reminders["sort_direction"] = picojson::value("asc");
  auto reminder_page = parse_native_v2(
      excellent_calendar::boundary::api::list_reminders_v2(
          picojson::value(list_reminders).serialize()));
  require(reminder_page.at("ok").get<bool>() &&
              reminder_page.at("data")
                      .get<picojson::object>()
                      .at("items")
                      .get<picojson::array>()
                      .size() == 1U,
          "Reminder list should query ordinary and recurring tasks from v2 storage");

  picojson::object detail_request;
  detail_request["id"] = picojson::value(event_id);
  auto detail = parse_native_v2(
      excellent_calendar::boundary::api::get_event_detail_v2(
          picojson::value(detail_request).serialize()));
  require(detail.at("ok").get<bool>() &&
              detail.at("data").get<picojson::object>().at("recurrence").is<picojson::null>() &&
              detail.at("data")
                      .get<picojson::object>()
                      .at("reminders")
                      .get<picojson::array>()
                      .size() == 1U,
          "ordinary Event detail should return null recurrence and its v2 Reminders");

  picojson::object search;
  search["has_recurrence"] = picojson::value(false);
  search["status"] = picojson::value(picojson::array{picojson::value("active")});
  search["pagination"] = picojson::value(pagination);
  search["sort_by"] = picojson::value("start");
  search["sort_direction"] = picojson::value("asc");
  auto search_page = parse_native_v2(
      excellent_calendar::boundary::api::search_events_v2(
          picojson::value(search).serialize()));
  require(search_page.at("ok").get<bool>() &&
              search_page.at("data")
                      .get<picojson::object>()
                      .at("items")
                      .get<picojson::array>()
                      .size() == 1U,
          "Event search should include ordinary Events stored by v2");

  picojson::object move_event;
  move_event["id"] = picojson::value(event_id);
  move_event["start_at"] = picojson::value(moved_start_at);
  move_event["end_at"] = picojson::value(moved_end_at);
  move_event["start_date"] = picojson::value();
  move_event["end_date"] = picojson::value();
  move_event["is_all_day"] = picojson::value(false);
  move_event["timezone"] = picojson::value("Etc/UTC");
  auto moved = parse_native_v2(
      excellent_calendar::boundary::api::update_event_v2(
          picojson::value(move_event).serialize()));
  require(moved.at("ok").get<bool>() &&
              moved.at("data").get<picojson::object>().at("start_at").get<std::string>() ==
                  moved_start_at,
          "ordinary Event atomic time update should succeed in v2 Core");
  auto moved_reminder = parse_native_v2(
      excellent_calendar::boundary::api::get_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(moved_reminder.at("ok").get<bool>() &&
              moved_reminder.at("data")
                      .get<picojson::object>()
                      .at("remind_at")
                      .get<std::string>() == moved_advance_remind_at,
          "Event time update must atomically recompute mutable advance Reminders");

  picojson::object complete;
  complete["event_id"] = picojson::value(event_id);
  complete["source"] = picojson::value("manual");
  complete["note"] = picojson::value();
  auto completed = parse_native_v2(
      excellent_calendar::boundary::api::complete_event_v2(
          picojson::value(complete).serialize()));
  require(completed.at("ok").get<bool>() &&
              completed.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "completed",
          "ordinary Event complete should use the unified transaction");
  auto rejected_inactive_target = parse_native_v2(
      excellent_calendar::boundary::api::create_reminder_v2(
          picojson::value(create_reminder).serialize()));
  require(!rejected_inactive_target.at("ok").get<bool>() &&
              rejected_inactive_target.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "REMINDER_TARGET_NOT_FOUND",
          "completed Event must not accept a new schedulable Reminder");
  auto cancelled_by_event = parse_native_v2(
      excellent_calendar::boundary::api::get_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(cancelled_by_event.at("ok").get<bool>() &&
              cancelled_by_event.at("data")
                      .get<picojson::object>()
                      .at("last_cancellation_reason")
                      .get<std::string>() == "event_completed",
          "Event completion should atomically retain and cancel future Reminder history");

  picojson::object reopen;
  reopen["event_id"] = picojson::value(event_id);
  auto reopened = parse_native_v2(
      excellent_calendar::boundary::api::reopen_event_v2(
          picojson::value(reopen).serialize()));
  require(reopened.at("ok").get<bool>() &&
              reopened.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "active",
          "ordinary completed Event should reopen");
  auto reactivated = parse_native_v2(
      excellent_calendar::boundary::api::get_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(reactivated.at("ok").get<bool>() &&
              reactivated.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "pending" &&
              reactivated.at("data")
                      .get<picojson::object>()
                      .at("reactivation_count")
                      .get<double>() == 1.0,
          "Event reopen should restore only its future event_completed Reminder");

  auto cancelled = parse_native_v2(
      excellent_calendar::boundary::api::cancel_reminder_v2(
          picojson::value(reminder_identity).serialize()));
  require(cancelled.at("ok").get<bool>() &&
              cancelled.at("data")
                      .get<picojson::object>()
                      .at("last_cancellation_reason")
                      .get<std::string>() == "user_cancelled",
          "ordinary Reminder user cancellation should preserve audit history");

  picojson::object delete_event;
  delete_event["id"] = picojson::value(event_id);
  delete_event["delete_mode"] = picojson::value("soft");
  delete_event["recurrence_delete_scope"] = picojson::value();
  delete_event["expected_recurrence_revision"] = picojson::value();
  delete_event["reason"] = picojson::value("test cleanup");
  auto deleted = parse_native_v2(
      excellent_calendar::boundary::api::delete_event_v2(
          picojson::value(delete_event).serialize()));
  require(deleted.at("ok").get<bool>() &&
              !deleted.at("data").get<picojson::object>().at("deleted_at").is<picojson::null>(),
          "ordinary Event soft delete should use the v2 writer");
}

void test_contract_v2_boundary_supports_kotlin_recurrence_flow() {
  TemporaryDirectory directory;
  picojson::object initialize;
  initialize["storage_directory"] = picojson::value(directory.path().generic_string());
  initialize["tzdb_directory"] = picojson::value(
      std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR).generic_string());
  auto initialized = parse_native_v2(
      excellent_calendar::boundary::api::initialize_recurring_runtime_v2_json(
          picojson::value(initialize).serialize()));
  require(initialized.at("ok").get<bool>(), "v2 runtime initialization should succeed");

  const auto now_epoch = excellent_calendar::common::parse_iso8601_utc_epoch_seconds(
      excellent_calendar::common::utc_now_iso8601());
  require(now_epoch.has_value(), "test Clock should return UTC time");
  const auto start_at = excellent_calendar::common::format_epoch_seconds_utc_iso8601(
      *now_epoch + 24 * 60 * 60);
  const auto end_at = excellent_calendar::common::format_epoch_seconds_utc_iso8601(
      *now_epoch + 25 * 60 * 60);

  picojson::object recurrence;
  recurrence["frequency"] = picojson::value("daily");
  recurrence["interval"] = picojson::value(1.0);
  recurrence["end_at"] = picojson::value();
  recurrence["count"] = picojson::value();
  picojson::object reminder;
  reminder["target_type"] = picojson::value("event");
  reminder["target_id"] = picojson::value();
  reminder["advance_minutes"] = picojson::value(30.0);
  reminder["methods"] = picojson::value(picojson::array{picojson::value("popup")});
  reminder["message"] = picojson::value("Boundary reminder");
  reminder["is_enabled"] = picojson::value(true);
  reminder["source"] = picojson::value("manual");
  picojson::object create;
  create["title"] = picojson::value("Boundary daily event");
  create["content"] = picojson::value();
  create["start_at"] = picojson::value(start_at);
  create["end_at"] = picojson::value(end_at);
  create["start_date"] = picojson::value();
  create["end_date"] = picojson::value();
  create["is_all_day"] = picojson::value(false);
  create["category_id"] = picojson::value();
  create["importance"] = picojson::value();
  create["location"] = picojson::value();
  create["timezone"] = picojson::value("Etc/UTC");
  create["source"] = picojson::value("manual");
  create["recurrence"] = picojson::value(recurrence);
  create["reminders"] = picojson::value(picojson::array{picojson::value(reminder)});
  auto missing_message_request = create;
  auto missing_message = reminder;
  missing_message.erase("message");
  missing_message_request["reminders"] =
      picojson::value(picojson::array{picojson::value(missing_message)});
  auto missing_message_result = parse_native_v2(
      excellent_calendar::boundary::api::create_event_v2(
          picojson::value(missing_message_request).serialize()));
  require(!missing_message_result.at("ok").get<bool>() &&
              missing_message_result.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "CONTRACT_VALIDATION_FAILED",
          "recurring Reminder template must explicitly supply nullable message");
  auto forbidden_remind_at_request = create;
  auto forbidden_remind_at = reminder;
  forbidden_remind_at["remind_at"] = picojson::value();
  forbidden_remind_at_request["reminders"] =
      picojson::value(picojson::array{picojson::value(forbidden_remind_at)});
  auto forbidden_remind_at_result = parse_native_v2(
      excellent_calendar::boundary::api::create_event_v2(
          picojson::value(forbidden_remind_at_request).serialize()));
  require(!forbidden_remind_at_result.at("ok").get<bool>() &&
              forbidden_remind_at_result.at("error")
                      .get<picojson::object>()
                      .at("code")
                      .get<std::string>() == "CONTRACT_VALIDATION_FAILED",
          "recurring Reminder template must reject even a null remind_at field");
  auto created = parse_native_v2(
      excellent_calendar::boundary::api::create_recurring_event_v2(
          picojson::value(create).serialize()));
  require(created.at("ok").get<bool>(), "v2 recurring Event create should succeed");
  const auto& event = created.at("data").get<picojson::object>();
  const auto event_id = event.at("id").get<std::string>();
  require(event.at("recurrence_revision").get<double>() == 1.0,
          "created v2 Event should expose recurrence revision 1");

  picojson::object schedulable;
  schedulable["from_at"] = picojson::value();
  schedulable["to_at"] = picojson::value();
  schedulable["cursor"] = picojson::value();
  schedulable["limit"] = picojson::value(500.0);
  schedulable["include_scheduled"] = picojson::value(false);
  schedulable["supported_methods"] =
      picojson::value(picojson::array{picojson::value("popup")});
  auto reminders = parse_native_v2(
      excellent_calendar::boundary::api::list_schedulable_recurring_reminders_v2(
          picojson::value(schedulable).serialize()));
  require(reminders.at("ok").get<bool>(), "v2 schedulable query should succeed");
  const auto& reminder_items =
      reminders.at("data").get<picojson::object>().at("items").get<picojson::array>();
  require(reminder_items.size() == 1U,
          "Kotlin scheduler should receive the rolling Reminder through v2 boundary");
  const auto reminder_id = reminder_items.front()
                               .get<picojson::object>()
                               .at("reminder_id")
                               .get<std::string>();
  const auto expected_remind_at = reminder_items.front()
                                      .get<picojson::object>()
                                      .at("remind_at")
                                      .get<std::string>();
  picojson::object detail_request;
  detail_request["id"] = picojson::value(event_id);
  auto detail = parse_native_v2(
      excellent_calendar::boundary::api::get_recurring_event_detail_v2(
          picojson::value(detail_request).serialize()));
  require(detail.at("ok").get<bool>() &&
              detail.at("data")
                      .get<picojson::object>()
                      .at("recurrence")
                      .get<picojson::object>()
                      .at("frequency")
                      .get<std::string>() == "daily",
          "v2 detail query should reload the current recurring aggregate after restart");
  picojson::object get_reminder;
  get_reminder["reminder_id"] = picojson::value(reminder_id);
  auto loaded_reminder = parse_native_v2(
      excellent_calendar::boundary::api::get_recurring_reminder_v2(
          picojson::value(get_reminder).serialize()));
  require(loaded_reminder.at("ok").get<bool>() &&
              loaded_reminder.at("data")
                      .get<picojson::object>()
                      .at("reminder_id")
                      .get<std::string>() == reminder_id,
          "Kotlin alarm callback should reload one v2 Reminder by reminder_id");
  picojson::object mark;
  mark["reminder_id"] = picojson::value(reminder_id);
  mark["expected_remind_at"] = picojson::value(expected_remind_at);
  mark["scheduled_at"] = picojson::value(excellent_calendar::common::utc_now_iso8601());
  auto marked = parse_native_v2(
      excellent_calendar::boundary::api::mark_recurring_reminder_scheduled_v2(
          picojson::value(mark).serialize()));
  require(marked.at("ok").get<bool>() &&
              marked.at("data").get<picojson::object>().at("status").get<std::string>() ==
                  "scheduled",
          "Kotlin scheduler acknowledgement should persist through v2 boundary");

  picojson::object list;
  list["event_id"] = picojson::value(event_id);
  list["recurrence_revision"] = picojson::value(1.0);
  list["is_all_day"] = picojson::value(false);
  list["range_start_at"] = picojson::value(
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(*now_epoch));
  list["range_end_at"] = picojson::value(
      excellent_calendar::common::format_epoch_seconds_utc_iso8601(
          *now_epoch + 4 * 24 * 60 * 60));
  list["range_start_date"] = picojson::value();
  list["range_end_date"] = picojson::value();
  list["cursor"] = picojson::value();
  list["limit"] = picojson::value(2.0);
  auto occurrences = parse_native_v2(
      excellent_calendar::boundary::api::list_event_occurrences_v2(
          picojson::value(list).serialize()));
  require(occurrences.at("ok").get<bool>() &&
              occurrences.at("data")
                      .get<picojson::object>()
                      .at("items")
                      .get<picojson::array>()
                      .size() == 2U,
          "Kotlin occurrence page should be available through v2 boundary");

  picojson::object update;
  update["id"] = picojson::value(event_id);
  update["expected_recurrence_revision"] = picojson::value(1.0);
  update["title"] = picojson::value("Updated boundary event");
  auto updated = parse_native_v2(
      excellent_calendar::boundary::api::update_recurring_event_v2(
          picojson::value(update).serialize()));
  require(updated.at("ok").get<bool>() &&
              updated.at("data")
                      .get<picojson::object>()
                      .at("recurrence_revision")
                      .get<double>() == 1.0,
          "metadata-only partial update should preserve recurrence revision 1");

  recurrence["frequency"] = picojson::value("yearly");
  create["recurrence"] = picojson::value(recurrence);
  auto yearly = parse_native_v2(
      excellent_calendar::boundary::api::create_recurring_event_v2(
          picojson::value(create).serialize()));
  require(!yearly.at("ok").get<bool>() &&
              yearly.at("error").get<picojson::object>().at("code").get<std::string>() ==
                  "FEATURE_NOT_IMPLEMENTED",
          "v2 boundary must preserve Core defensive rejection of yearly recurrence");
}

}  // namespace

int main() {
  try {
    test_contract_uuid_v5_vectors();
    test_london_dst_gap_moves_to_first_legal_instant();
    test_london_dst_fold_chooses_earlier_instant();
    test_timezone_round_trip_and_validation();
    test_daily_uses_local_calendar_across_london_gap();
    test_weekly_derives_single_weekday_and_uses_calendar_week();
    test_monthly_preserves_permanent_anchor();
    test_all_day_recurrence_expands_without_reminder_time();
    test_unsupported_and_bounded_rules_fail_in_core();
    test_timed_recurrence_rejects_nonpositive_local_interval_across_fold();
    test_storage_v2_reload_and_prepared_journal_replay();
    test_v2_transaction_rejects_unprepared_v1_directory_without_partial_writes();
    test_v2_runtime_discards_confirmed_v1_before_initialization();
    test_v2_runtime_refuses_corrupt_v1_without_discarding_or_partial_v2();
    test_v1_discard_classifier_rejects_v2_reminder_enums();
    test_recurring_runtime_initializes_pinned_tzdb_and_v2_services();
    test_failed_v2_reinitialization_clears_previously_published_writers();
    test_create_and_complete_occurrence_rolls_next_reminder_atomically();
    test_series_reopen_starts_after_reopened_at_without_catchup();
    test_terminal_series_rejects_occurrence_mutation_without_reopening_chain();
    test_series_update_creates_revision_and_cancels_old_open_reminder();
    test_series_partial_update_requires_current_revision_without_writes();
    test_same_template_keeps_revision_but_message_change_creates_revision();
    test_updating_completed_series_metadata_keeps_revision_until_reopen();
    test_occurrence_reopen_defers_and_reuses_the_same_successor();
    test_series_reopen_restores_only_one_reminder_per_deferred_template();
    test_reminderless_occurrence_reopen_remains_supported_and_idempotent();
    test_series_cancel_and_delete_cancel_open_chain_with_precise_reason();
    test_all_day_recurring_event_rejects_nonempty_reminders_without_writing();
    test_delivery_prepare_finalize_is_idempotent_and_rolls_successor();
    test_retryable_delivery_failure_keeps_current_reminder_pending();
    test_delivery_finalize_validates_contract_error_retryability();
    test_delivery_finalize_recovers_prepared_workflow_after_restart();
    test_recovery_window_is_inclusive_and_selects_global_newest_twenty();
    test_recovery_counts_old_unexpanded_occurrences_without_bulk_creation();
    test_recovery_expires_old_ordinary_reminder_and_abandons_its_attempt();
    test_recovery_adopts_prepared_attempt_and_blocks_conflicting_mutations();
    test_ordinary_reminders_reject_methods_without_a_delivery_implementation();
    test_reminderless_series_reopen_is_idempotent();
    test_occurrence_query_pages_and_attaches_sparse_state();
    test_event_detail_aggregate_uses_one_storage_snapshot();
    test_v2_schedulable_query_and_mark_scheduled_use_recurring_store();
    test_rolling_reminder_idempotency_detects_message_drift();
    test_runtime_timezone_boundary_is_strict_and_batched();
    test_contract_v2_boundary_supports_ordinary_event_and_reminder_flow();
    test_contract_v2_boundary_supports_kotlin_recurrence_flow();
    std::cout << "recurrence core tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "recurrence core tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
