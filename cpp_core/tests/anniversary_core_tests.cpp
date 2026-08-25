#include <array>
#include <atomic>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <iostream>
#include <memory>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/anniversary_query_service.hpp"
#include "excellent_calendar/application/anniversary_workflow_service.hpp"
#include "excellent_calendar/boundary/api/anniversary_api.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/domain/anniversary.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/json/calendar_core_v3_storage_bootstrap.hpp"
#include "excellent_calendar/storage/json/json_anniversary_transaction.hpp"
#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"

namespace {

using excellent_calendar::application::AnniversaryWriteInput;
using excellent_calendar::domain::LocalDate;
using excellent_calendar::storage::json::AtomicJsonFileStore;
using excellent_calendar::storage::json::JsonAnniversaryTransaction;

constexpr const char* kNow = "2026-08-08T04:05:06Z";
constexpr const char* kTimezone = "Asia/Shanghai";
constexpr const char* kCategoryId = "33333333-3333-4333-8333-333333333333";

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

void prepare_v3_storage(const std::filesystem::path& path) {
  auto prepared =
      excellent_calendar::storage::json::prepare_calendar_core_v3_storage(path);
  require(prepared.ok(), prepared.ok() ? "" : prepared.error().message);
}

class TemporaryDirectory {
 public:
  explicit TemporaryDirectory(std::string_view label)
      : path_(std::filesystem::temp_directory_path() /
              ("excellent_calendar_anniversary_" + std::string(label) + "_" +
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

std::shared_ptr<excellent_calendar::infrastructure::time::TzdbLocalTimeResolver>
resolver() {
  auto created =
      excellent_calendar::infrastructure::time::TzdbLocalTimeResolver::create(
          EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(created.ok(), created.ok() ? "" : created.error().message);
  return created.value();
}

AnniversaryWriteInput write_input(
    std::string title,
    LocalDate date,
    bool yearly,
    std::optional<std::string> category = std::nullopt) {
  return AnniversaryWriteInput{
      std::move(title),
      date,
      "solar",
      std::move(category),
      yearly,
      std::nullopt,
      std::string("important_noturgent"),
      kTimezone};
}

picojson::object parse_native_result(
    const std::string& json,
    const std::string& context) {
  picojson::value value;
  const auto parse_error = picojson::parse(value, json);
  require(parse_error.empty() && value.is<picojson::object>(),
          context + " must return an object NativeResult");
  const auto result = value.get<picojson::object>();
  require(result.size() == 5U && result.count("ok") == 1U &&
              result.count("data") == 1U && result.count("error") == 1U &&
              result.count("contract_version") == 1U &&
              result.count("request_id") == 1U,
          context + " must return the exact NativeResult envelope");
  require(result.at("contract_version").is<double>() &&
              result.at("contract_version").get<double>() == 2.0,
          context + " must return contract_version 2");
  return result;
}

const picojson::object& require_success(
    const picojson::object& result,
    const std::string& context) {
  require(result.at("ok").is<bool>() && result.at("ok").get<bool>() &&
              result.at("error").is<picojson::null>() &&
              result.at("data").is<picojson::object>(),
          context + " must succeed");
  return result.at("data").get<picojson::object>();
}

void require_failure(
    const picojson::object& result,
    const std::string& code,
    const std::string& context) {
  require(result.at("ok").is<bool>() && !result.at("ok").get<bool>() &&
              result.at("data").is<picojson::null>() &&
              result.at("error").is<picojson::object>(),
          context + " must fail through NativeResult");
  const auto& error = result.at("error").get<picojson::object>();
  require(error.at("code").is<std::string>() &&
              error.at("code").get<std::string>() == code,
          context + " must return " + code);
}

void require_exact_fields(
    const picojson::object& object,
    std::set<std::string> fields,
    const std::string& context) {
  require(object.size() == fields.size(), context + " field count is wrong");
  for (const auto& field : fields) {
    require(object.count(field) == 1U, context + "." + field + " is missing");
  }
}

picojson::object boundary_write_request(
    std::optional<std::string> id,
    std::string title,
    bool yearly,
    std::string calendar_type = "solar") {
  picojson::object request;
  if (id.has_value()) request["id"] = picojson::value(*id);
  request["title"] = picojson::value(std::move(title));
  request["date"] = picojson::value("2020-02-29");
  request["calendar_type"] = picojson::value(std::move(calendar_type));
  request["category_id"] = picojson::value(kCategoryId);
  if (yearly) {
    picojson::object recurrence;
    recurrence["frequency"] = picojson::value("yearly");
    recurrence["interval"] = picojson::value(1.0);
    request["recurrence"] = picojson::value(std::move(recurrence));
  } else {
    request["recurrence"] = picojson::value();
  }
  request["note"] = picojson::value();
  request["importance"] = picojson::value("important_noturgent");
  request["timezone"] = picojson::value(kTimezone);
  return request;
}

void test_date_only_countdown_edges() {
  using excellent_calendar::domain::calculate_anniversary_countdown;

  auto today = calculate_anniversary_countdown(
      LocalDate{2026, 8, 8}, false, LocalDate{2026, 8, 8}, kTimezone, kNow);
  require(today.ok() && today.value().relation == "today" &&
              today.value().days == 0 &&
              today.value().target_occurrence_date == LocalDate{2026, 8, 8},
          "one-time Anniversary on the local date must be today");

  auto elapsed = calculate_anniversary_countdown(
      LocalDate{2026, 8, 1}, false, LocalDate{2026, 8, 8}, kTimezone, kNow);
  require(elapsed.ok() && elapsed.value().relation == "elapsed" &&
              elapsed.value().days == 7,
          "past one-time Anniversary must expose elapsed local days");

  auto cross_year = calculate_anniversary_countdown(
      LocalDate{2020, 1, 1}, true, LocalDate{2026, 12, 31}, kTimezone, kNow);
  require(cross_year.ok() && cross_year.value().relation == "remaining" &&
              cross_year.value().days == 1 &&
              cross_year.value().target_occurrence_date == LocalDate{2027, 1, 1},
          "yearly Anniversary must cross the year using date-only arithmetic");

  auto leap_clamp = calculate_anniversary_countdown(
      LocalDate{2020, 2, 29}, true, LocalDate{2026, 2, 28}, kTimezone, kNow);
  require(leap_clamp.ok() && leap_clamp.value().relation == "today" &&
              leap_clamp.value().target_occurrence_date == LocalDate{2026, 2, 28},
          "February 29 must clamp to February end in a non-leap target year");

  auto invalid = calculate_anniversary_countdown(
      LocalDate{2026, 2, 30}, false, LocalDate{2026, 8, 8}, kTimezone, kNow);
  require(!invalid.ok() && invalid.error().code == "ANNIVERSARY_DATE_INVALID",
          "invalid date-only input must fail in the Core");
}

void test_anniversary_r1_identity_vectors() {
  auto occurrence = excellent_calendar::domain::anniversary_occurrence_key(
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", LocalDate{2026, 9, 1});
  require(occurrence.ok() && occurrence.value() == "60f0df06-830c-52d2-a659-e8848aa200cd",
          "Anniversary occurrence UUIDv5 must match the frozen golden vector");
  auto reminder_template = excellent_calendar::domain::anniversary_reminder_template_key(
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", 7, "09:00");
  require(reminder_template.ok() &&
              reminder_template.value() == "f6bf77d5-9a34-5897-a38e-75321fac0f8f",
          "Anniversary template UUIDv5 must match the frozen golden vector");
  auto reminder = excellent_calendar::domain::anniversary_reminder_id(
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", occurrence.value(),
      reminder_template.value());
  require(reminder.ok() && reminder.value() == "3b9c75fd-9073-5338-954a-d00ca35c5bf2",
          "Anniversary Reminder UUIDv5 must match the frozen golden vector");
  auto delivery = excellent_calendar::domain::anniversary_catch_up_delivery_id(
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", occurrence.value(),
      {"59c487fb-2737-5c31-8c5c-6ba157dc77a6",
       "3b9c75fd-9073-5338-954a-d00ca35c5bf2"});
  require(delivery.ok() && delivery.value() == "5a5e9379-77c9-51f3-a0fb-8f09440b557a",
          "Anniversary aggregate membership must sort before UUIDv5 generation");
}

void test_reminder_plan_lifecycle_and_occurrence_paging() {
  TemporaryDirectory directory("reminder_plan");
  prepare_v3_storage(directory.path());
  auto transaction = std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(transaction->initialize().ok(), "Anniversary Reminder stores must initialize");
  auto clock = [] { return std::string(kNow); };
  auto id_index = std::make_shared<std::size_t>(0U);
  auto id_generator = [id_index] {
    constexpr std::array<std::string_view, 3> fixed_ids = {
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        "cccccccc-cccc-4ccc-8ccc-cccccccccccc"};
    if (*id_index < fixed_ids.size()) {
      return std::string(fixed_ids[(*id_index)++]);
    }
    return excellent_calendar::common::generate_uuid_v4();
  };
  auto time_resolver = resolver();
  excellent_calendar::application::AnniversaryWorkflowService workflow(
      transaction, time_resolver, clock, id_generator);
  excellent_calendar::application::AnniversaryQueryService query(
      transaction, time_resolver, clock);

  auto input = write_input("R1 anniversary", LocalDate{2020, 9, 1}, true, kCategoryId);
  excellent_calendar::application::AnniversaryReminderPlanInput plan;
  plan.reminders_enabled = true;
  plan.templates.push_back({7, "09:00", "popup", true});
  plan.templates.push_back({0, "23:59", "popup", true});
  input.reminder_plan = plan;
  auto created = workflow.create({input});
  require(created.ok() && created.value().reminder_settings.reminders_enabled &&
              created.value().reminder_settings.templates.size() == 2U &&
              created.value().reminder_settings.active_reminder_count == 2 &&
              created.value().reminder_settings.schedule_reconciliation_required,
          "create must atomically persist the complete Anniversary Reminder plan");
  const auto anniversary_id = created.value().anniversary.id;
  auto loaded = transaction->load();
  require(loaded.ok() && loaded.value().reminder_templates.size() == 2U &&
              loaded.value().reminders.size() == 2U,
          "each enabled yearly template must materialize one open rolling Reminder");
  for (const auto& reminder : loaded.value().reminders) {
    require(reminder.target_type == "anniversary" && reminder.template_key.has_value() &&
                reminder.occurrence_date == std::optional<std::string>("2026-09-01") &&
                reminder.occurrence_start_at == std::nullopt &&
                reminder.recurrence_revision == std::nullopt,
            "Anniversary Reminder must use date-only target-specific identity fields");
  }

  auto paused = workflow.set_reminders_enabled({anniversary_id, false, kTimezone});
  require(paused.ok() && !paused.value().reminder_settings.reminders_enabled &&
              paused.value().reminder_settings.active_reminder_count == 0,
          "pause must retain templates while disabling the complete plan");
  loaded = transaction->load();
  require(loaded.ok() && std::all_of(loaded.value().reminders.begin(),
                                    loaded.value().reminders.end(), [](const auto& reminder) {
                                      return reminder.status == "cancelled" &&
                                             reminder.cancellation_reason ==
                                                 std::optional<std::string>("anniversary_paused");
                                    }),
          "pause must terminate every future open Anniversary Reminder");
  auto resumed = workflow.set_reminders_enabled({anniversary_id, true, kTimezone});
  require(resumed.ok() && resumed.value().reminder_settings.active_reminder_count == 2,
          "resume must rematerialize the first meaningful deterministic tasks");
  loaded = transaction->load();
  require(loaded.ok() && loaded.value().reminders.size() == 2U &&
              std::all_of(loaded.value().reminders.begin(), loaded.value().reminders.end(),
                          [](const auto& reminder) {
                            return reminder.status == "pending" &&
                                   reminder.reactivation_count == 1;
                          }),
          "resume must reactivate matching deterministic Reminder identities without duplicates");

  excellent_calendar::application::ListAnniversaryOccurrencesQuery occurrence_query;
  occurrence_query.range_start_date = {2026, 8, 1};
  occurrence_query.range_end_date = {2027, 9, 2};
  occurrence_query.timezone = kTimezone;
  occurrence_query.page_size = 1;
  auto first_page = query.list_occurrences(occurrence_query);
  require(first_page.ok() && first_page.value().items.size() == 1U &&
              first_page.value().has_more && first_page.value().next_cursor.has_value() &&
              first_page.value().items.front().occurrence_date == LocalDate{2026, 9, 1} &&
              first_page.value().items.front().reminder_count == 2,
          "occurrence query must project current Reminder summary facts and a stable cursor");
  constexpr std::string_view kCrossLayerCursorGolden =
      "annocc1.60f0df06-830c-52d2-a659-e8848aa200cd_3-1-1_55ed42b28911a7e6";
  require(*first_page.value().next_cursor == kCrossLayerCursorGolden,
          "fixed C++ occurrence inputs must preserve the shared cross-layer cursor golden");
  require(
      std::regex_match(
          *first_page.value().next_cursor,
          std::regex(R"(^annocc1\.[A-Za-z0-9_-]{20,2048}$)")),
      "generated occurrence cursor must satisfy the frozen cross-layer grammar");
  occurrence_query.cursor = first_page.value().next_cursor;
  auto second_page = query.list_occurrences(occurrence_query);
  require(second_page.ok() && second_page.value().items.size() == 1U &&
              !second_page.value().has_more &&
              second_page.value().items.front().occurrence_date == LocalDate{2027, 9, 1},
          "occurrence cursor must page without duplicates or omissions");

  const auto capture_first_cursor = [&]() {
    occurrence_query.cursor.reset();
    auto page = query.list_occurrences(occurrence_query);
    require(page.ok() && page.value().has_more &&
                page.value().next_cursor.has_value(),
            "generation cursor fixture must produce a second page");
    return *page.value().next_cursor;
  };
  const auto require_expired = [&](const std::string& cursor,
                                   const std::string& context) {
    occurrence_query.cursor = cursor;
    auto result = query.list_occurrences(occurrence_query);
    require(!result.ok() &&
                result.error().code ==
                    "ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED",
            context);
  };

  const auto filter_cursor = capture_first_cursor();
  auto filter_changed = transaction->execute(
      "anniversary_update", "18181818-1818-4818-8818-181818181818", kNow,
      [&](excellent_calendar::repository::AnniversaryState& state) {
        auto item = std::find_if(
            state.anniversaries.begin(), state.anniversaries.end(),
            [&](const auto& value) { return value.id == anniversary_id; });
        require(item != state.anniversaries.end(),
                "generation fixture Anniversary must exist");
        item->importance = "unimportant_urgent";
        return excellent_calendar::common::Result<
            excellent_calendar::common::Unit>::success({});
      });
  require(filter_changed.ok(),
          "same-second occurrence filter field change must commit");
  require_expired(
      filter_cursor,
      "same-second importance change must expire the previous occurrence cursor");

  const auto template_cursor = capture_first_cursor();
  auto template_changed = transaction->execute(
      "anniversary_update", "19191919-1919-4919-8919-191919191919", kNow,
      [&](excellent_calendar::repository::AnniversaryState& state) {
        auto item = std::find_if(
            state.reminder_templates.begin(), state.reminder_templates.end(),
            [&](const auto& value) {
              return value.anniversary_id == anniversary_id && value.is_enabled;
            });
        require(item != state.reminder_templates.end(),
                "generation fixture enabled template must exist");
        const auto template_key = item->template_key;
        item->is_enabled = false;
        for (auto& reminder : state.reminders) {
          if (reminder.target_type == "anniversary" &&
              reminder.target_id == anniversary_id &&
              reminder.template_key ==
                  std::optional<std::string>(template_key) &&
              (reminder.status == "pending" ||
               reminder.status == "scheduled")) {
            reminder.is_enabled = false;
            reminder.status = "cancelled";
            reminder.scheduled_at.reset();
            reminder.cancellation_reason =
                "anniversary_template_disabled";
            reminder.last_cancelled_at = kNow;
            reminder.updated_at = kNow;
          }
        }
        return excellent_calendar::common::Result<
            excellent_calendar::common::Unit>::success({});
      });
  require(template_changed.ok(),
          "same-second Reminder template change must commit");
  require_expired(
      template_cursor,
      "same-second template change must expire the previous occurrence cursor");

  const auto restored_cursor = capture_first_cursor();
  auto before_delete = transaction->load();
  require(before_delete.ok(), "pre-delete generation snapshot must load");
  auto removed = workflow.remove({anniversary_id});
  require(removed.ok() && removed.value().deleted_at.has_value(),
          removed.ok()
              ? "generation fixture must soft-delete the Anniversary"
              : "generation fixture delete failed: " + removed.error().code +
                    ": " + removed.error().message);
  auto restored = transaction->execute(
      "anniversary_update", "20202020-2020-4020-8020-202020202020", kNow,
      [&](excellent_calendar::repository::AnniversaryState& state) {
        state = before_delete.value();
        return excellent_calendar::common::Result<
            excellent_calendar::common::Unit>::success({});
      });
  require(restored.ok(),
          "generation fixture must restore the exact pre-delete Store snapshot");
  require_expired(
      restored_cursor,
      "delete and exact restore must still expire the previous occurrence cursor");

  occurrence_query.cursor = capture_first_cursor();
  occurrence_query.range_end_date = {2027, 9, 3};
  auto expired_cursor = query.list_occurrences(occurrence_query);
  require(!expired_cursor.ok() &&
              expired_cursor.error().code == "ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED",
          "occurrence cursor must bind the complete query shape");

  occurrence_query.cursor.reset();
  occurrence_query.range_start_date = {2026, 1, 1};
  occurrence_query.range_end_date = {2027, 2, 6};
  auto oversized = query.list_occurrences(occurrence_query);
  require(!oversized.ok() && oversized.error().code ==
                                 "ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE",
          "occurrence query must reject windows larger than 400 natural days");
}

void test_workflow_lifecycle_persistence_and_queries() {
  TemporaryDirectory directory("workflow");
  prepare_v3_storage(directory.path());
  auto transaction = std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(transaction->initialize().ok(), "Anniversary stores must initialize");
  auto time_resolver = resolver();
  auto clock = [] { return std::string(kNow); };
  auto id_generator = [] { return excellent_calendar::common::generate_uuid_v4(); };
  excellent_calendar::application::AnniversaryWorkflowService workflow(
      transaction, time_resolver, clock, id_generator);

  auto created = workflow.create({write_input(
      "  Project anniversary  ", LocalDate{2020, 2, 29}, true, kCategoryId)});
  require(created.ok() && created.value().anniversary.title == "Project anniversary" &&
              created.value().anniversary.recurrence_id.has_value() &&
              created.value().recurrence.has_value() &&
              created.value().countdown.timezone == kTimezone,
          "create must atomically persist Anniversary and its yearly rule");
  const auto anniversary_id = created.value().anniversary.id;
  const auto original_recurrence_id = *created.value().anniversary.recurrence_id;
  const auto created_updated_at = created.value().anniversary.updated_at;

  auto reopened = std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(reopened->initialize().ok(), "Anniversary stores must reopen after restart");
  auto loaded = reopened->load();
  require(loaded.ok() && loaded.value().anniversaries.size() == 1U &&
              loaded.value().recurrences.size() == 1U &&
              loaded.value().anniversaries.front().id == anniversary_id,
          "created Anniversary must survive repository recreation");

  excellent_calendar::application::AnniversaryWorkflowService restarted_workflow(
      reopened, time_resolver, clock, id_generator);
  excellent_calendar::application::AnniversaryQueryService query(
      reopened, time_resolver, clock);
  auto detail = query.detail({anniversary_id, kTimezone});
  require(detail.ok() && detail.value().recurrence.has_value() &&
              detail.value().recurrence->id == original_recurrence_id,
          "detail must rehydrate the exclusively owned recurrence");

  auto updated_yearly = restarted_workflow.update(
      {anniversary_id,
       created_updated_at,
       write_input("Updated yearly", LocalDate{2021, 3, 1}, true, kCategoryId)});
  if (!updated_yearly.ok()) {
    std::string details;
    for (const auto& [key, value] : updated_yearly.error().details) {
      details += " " + key + "=" + value;
    }
    require(false, updated_yearly.error().code + ": " +
                       updated_yearly.error().message + details);
  }
  require(updated_yearly.ok() && updated_yearly.value().recurrence.has_value() &&
              updated_yearly.value().recurrence->id == original_recurrence_id &&
              updated_yearly.value().anniversary.updated_at != created_updated_at,
          "yearly-to-yearly update must retain recurrence identity");

  auto stale_update = restarted_workflow.update(
      {anniversary_id,
       created_updated_at,
       write_input("Stale update", LocalDate{2022, 3, 1}, true, kCategoryId)});
  require(!stale_update.ok() &&
              stale_update.error().code == "ANNIVERSARY_UPDATE_CONFLICT",
          "a stale expected_updated_at must fail without overwriting the committed update");

  auto made_one_time = restarted_workflow.update(
      {anniversary_id,
       updated_yearly.value().anniversary.updated_at,
       write_input("One time", LocalDate{2026, 8, 9}, false, kCategoryId)});
  require(made_one_time.ok() &&
              !made_one_time.value().anniversary.recurrence_id.has_value() &&
              !made_one_time.value().recurrence.has_value(),
          "yearly-to-one-time update must clear the recurrence projection");
  loaded = reopened->load();
  require(loaded.ok() && loaded.value().recurrences.size() == 1U &&
              loaded.value().recurrences.front().deleted_at.has_value(),
          "yearly-to-one-time update must soft-delete the old rule atomically");

  auto made_yearly = restarted_workflow.update(
      {anniversary_id,
       made_one_time.value().anniversary.updated_at,
       write_input("Yearly again", LocalDate{2026, 8, 9}, true, kCategoryId)});
  require(made_yearly.ok() && made_yearly.value().recurrence.has_value() &&
              made_yearly.value().recurrence->id != original_recurrence_id,
          "one-time-to-yearly update must create a new recurrence identity");

  auto listed = query.list({kTimezone, {kCategoryId}, {"important_noturgent"}});
  require(listed.ok() && listed.value().total == 1 && listed.value().items.size() == 1U,
          "list must filter active Anniversary facts and calculate countdowns");

  auto removed = restarted_workflow.remove({anniversary_id});
  require(removed.ok() && removed.value().deleted_at.has_value(),
          "delete must soft-delete the Anniversary");
  auto missing = query.detail({anniversary_id, kTimezone});
  require(!missing.ok() && missing.error().code == "ANNIVERSARY_NOT_FOUND",
          "soft-deleted Anniversary must be absent from detail");
  listed = query.list({kTimezone});
  require(listed.ok() && listed.value().items.empty() && listed.value().total == 0,
          "soft-deleted Anniversary must be absent from ordinary list");
  auto repeated_delete = restarted_workflow.remove({anniversary_id});
  require(!repeated_delete.ok() &&
              repeated_delete.error().code == "ANNIVERSARY_NOT_FOUND",
          "repeated delete must fail without another mutation");
}

void test_reminder_toggle_advances_version_and_rejects_stale_plans() {
  TemporaryDirectory directory("toggle_version");
  prepare_v3_storage(directory.path());
  auto transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(transaction->initialize().ok(),
          "Anniversary toggle version Store must initialize");
  auto time_resolver = resolver();
  auto clock = [] { return std::string(kNow); };
  auto id_generator = [] {
    return excellent_calendar::common::generate_uuid_v4();
  };
  excellent_calendar::application::AnniversaryWorkflowService workflow(
      transaction, time_resolver, clock, id_generator);

  auto original_input = write_input(
      "Reminder editor baseline", LocalDate{2020, 9, 1}, true, kCategoryId);
  excellent_calendar::application::AnniversaryReminderPlanInput plan;
  plan.reminders_enabled = true;
  plan.templates.push_back({7, "09:00", "popup", true});
  original_input.reminder_plan = plan;
  auto created = workflow.create({original_input});
  require(created.ok(), created.ok() ? "" : created.error().message);
  const auto anniversary_id = created.value().anniversary.id;
  const auto editor_token = created.value().anniversary.updated_at;

  auto paused = workflow.set_reminders_enabled(
      {anniversary_id, false, kTimezone});
  require(paused.ok() &&
              paused.value().anniversary.updated_at ==
                  "2026-08-08T04:05:07Z",
          "same-second create then toggle must advance the Anniversary version");
  auto stale_after_toggle = workflow.update(
      {anniversary_id, editor_token, original_input});
  require(!stale_after_toggle.ok() &&
              stale_after_toggle.error().code ==
                  "ANNIVERSARY_UPDATE_CONFLICT",
          "a pre-toggle editor token must not restore the old Reminder plan");
  auto persisted = transaction->load();
  require(persisted.ok() &&
              !persisted.value().anniversaries.front().reminders_enabled &&
              persisted.value().anniversaries.front().title ==
                  "Reminder editor baseline",
          "the rejected pre-toggle editor must perform zero writes");

  auto committed_input = original_input;
  committed_input.title = "Committed editor update";
  auto committed_update = workflow.update(
      {anniversary_id, paused.value().anniversary.updated_at, committed_input});
  require(committed_update.ok() &&
              committed_update.value().anniversary.updated_at ==
                  "2026-08-08T04:05:08Z",
          "same-second update must advance from the toggle version");
  auto paused_after_update = workflow.set_reminders_enabled(
      {anniversary_id, false, kTimezone});
  require(paused_after_update.ok() &&
              paused_after_update.value().anniversary.updated_at ==
                  "2026-08-08T04:05:09Z",
          "same-second toggle after update must never regress the version");

  auto stale_plan_input = original_input;
  stale_plan_input.title = "Stale plan overwrite";
  auto stale_after_update_toggle = workflow.update(
      {anniversary_id,
       committed_update.value().anniversary.updated_at,
       stale_plan_input});
  require(!stale_after_update_toggle.ok() &&
              stale_after_update_toggle.error().code ==
                  "ANNIVERSARY_UPDATE_CONFLICT",
          "an editor token captured before a later toggle must be rejected");
  persisted = transaction->load();
  require(persisted.ok() &&
              persisted.value().anniversaries.front().updated_at ==
                  paused_after_update.value().anniversary.updated_at &&
              persisted.value().anniversaries.front().title ==
                  "Committed editor update" &&
              !persisted.value().anniversaries.front().reminders_enabled,
          "the rejected stale plan must preserve the latest title, plan state, and token");
}

void test_toggle_and_update_concurrency_preserves_latest_plan() {
  TemporaryDirectory directory("toggle_update_concurrency");
  prepare_v3_storage(directory.path());
  auto initial_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(initial_transaction->initialize().ok(),
          "toggle/update concurrency Store must initialize");
  auto time_resolver = resolver();
  auto clock = [] { return std::string(kNow); };
  auto id_generator = [] {
    return excellent_calendar::common::generate_uuid_v4();
  };
  excellent_calendar::application::AnniversaryWorkflowService initial_workflow(
      initial_transaction, time_resolver, clock, id_generator);
  auto input = write_input(
      "Concurrent baseline", LocalDate{2020, 9, 1}, true, kCategoryId);
  excellent_calendar::application::AnniversaryReminderPlanInput plan;
  plan.reminders_enabled = true;
  plan.templates.push_back({0, "09:00", "popup", true});
  input.reminder_plan = plan;
  auto created = initial_workflow.create({input});
  require(created.ok(), created.ok() ? "" : created.error().message);

  auto update_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  auto toggle_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(update_transaction->initialize().ok() &&
              toggle_transaction->initialize().ok(),
          "both toggle/update concurrent writers must initialize");
  excellent_calendar::application::AnniversaryWorkflowService update_workflow(
      update_transaction, time_resolver, clock, id_generator);
  excellent_calendar::application::AnniversaryWorkflowService toggle_workflow(
      toggle_transaction, time_resolver, clock, id_generator);

  struct Outcome {
    bool ok = false;
    std::string code;
    std::string updated_at;
  };
  Outcome update_outcome;
  Outcome toggle_outcome;
  std::atomic<int> ready{0};
  std::atomic<bool> start{false};
  const auto anniversary_id = created.value().anniversary.id;
  const auto editor_token = created.value().anniversary.updated_at;
  auto edited_input = input;
  edited_input.title = "Concurrent editor";

  std::thread update_thread([&] {
    ready.fetch_add(1, std::memory_order_release);
    while (!start.load(std::memory_order_acquire)) {
      std::this_thread::yield();
    }
    auto result = update_workflow.update(
        {anniversary_id, editor_token, edited_input});
    update_outcome.ok = result.ok();
    if (result.ok()) {
      update_outcome.updated_at = result.value().anniversary.updated_at;
    } else {
      update_outcome.code = result.error().code;
    }
  });
  std::thread toggle_thread([&] {
    ready.fetch_add(1, std::memory_order_release);
    while (!start.load(std::memory_order_acquire)) {
      std::this_thread::yield();
    }
    auto result = toggle_workflow.set_reminders_enabled(
        {anniversary_id, false, kTimezone});
    toggle_outcome.ok = result.ok();
    if (result.ok()) {
      toggle_outcome.updated_at = result.value().anniversary.updated_at;
    } else {
      toggle_outcome.code = result.error().code;
    }
  });
  while (ready.load(std::memory_order_acquire) != 2) {
    std::this_thread::yield();
  }
  start.store(true, std::memory_order_release);
  update_thread.join();
  toggle_thread.join();

  require(toggle_outcome.ok &&
              (!update_outcome.ok
                   ? update_outcome.code == "ANNIVERSARY_UPDATE_CONFLICT"
                   : update_outcome.updated_at != toggle_outcome.updated_at),
          "the serialized toggle must either stale the editor or advance beyond it");
  auto persisted = initial_transaction->load();
  require(persisted.ok() &&
              !persisted.value().anniversaries.front().reminders_enabled &&
              persisted.value().anniversaries.front().updated_at ==
                  toggle_outcome.updated_at &&
              persisted.value().anniversaries.front().title ==
                  (update_outcome.ok ? "Concurrent editor"
                                     : "Concurrent baseline"),
          "toggle/update concurrency must preserve the serialized latest plan without token reuse");
}

void test_update_optimistic_concurrency_serializes_stale_writers() {
  TemporaryDirectory directory("update_concurrency");
  prepare_v3_storage(directory.path());
  auto initial_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(initial_transaction->initialize().ok(),
          "Anniversary concurrency Store must initialize");
  auto time_resolver = resolver();
  auto clock = [] { return std::string(kNow); };
  auto id_generator = [] {
    return excellent_calendar::common::generate_uuid_v4();
  };
  excellent_calendar::application::AnniversaryWorkflowService initial_workflow(
      initial_transaction, time_resolver, clock, id_generator);
  auto created = initial_workflow.create({write_input(
      "Concurrency baseline", LocalDate{2020, 9, 1}, true, kCategoryId)});
  require(created.ok(), created.ok() ? "" : created.error().message);

  auto first_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  auto second_transaction =
      std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(first_transaction->initialize().ok() &&
              second_transaction->initialize().ok(),
          "both concurrent Anniversary writers must initialize");
  excellent_calendar::application::AnniversaryWorkflowService first_workflow(
      first_transaction, time_resolver, clock, id_generator);
  excellent_calendar::application::AnniversaryWorkflowService second_workflow(
      second_transaction, time_resolver, clock, id_generator);

  struct Outcome {
    bool ok = false;
    std::string code;
    std::string title;
    std::string updated_at;
  };
  Outcome first;
  Outcome second;
  std::atomic<int> ready{0};
  std::atomic<bool> start{false};
  const auto anniversary_id = created.value().anniversary.id;
  const auto expected_updated_at = created.value().anniversary.updated_at;
  const auto run = [&](excellent_calendar::application::AnniversaryWorkflowService& workflow,
                       std::string title, Outcome& outcome) {
    ready.fetch_add(1, std::memory_order_release);
    while (!start.load(std::memory_order_acquire)) {
      std::this_thread::yield();
    }
    auto result = workflow.update(
        {anniversary_id, expected_updated_at,
         write_input(std::move(title), LocalDate{2020, 9, 1}, true, kCategoryId)});
    outcome.ok = result.ok();
    if (result.ok()) {
      outcome.title = result.value().anniversary.title;
      outcome.updated_at = result.value().anniversary.updated_at;
    } else {
      outcome.code = result.error().code;
    }
  };
  std::thread first_thread(run, std::ref(first_workflow), "Writer one",
                           std::ref(first));
  std::thread second_thread(run, std::ref(second_workflow), "Writer two",
                            std::ref(second));
  while (ready.load(std::memory_order_acquire) != 2) {
    std::this_thread::yield();
  }
  start.store(true, std::memory_order_release);
  first_thread.join();
  second_thread.join();

  require(first.ok != second.ok,
          "exactly one concurrent writer using the same expected_updated_at must commit");
  const auto& rejected = first.ok ? second : first;
  const auto& accepted = first.ok ? first : second;
  require(rejected.code == "ANNIVERSARY_UPDATE_CONFLICT" &&
              accepted.updated_at != expected_updated_at,
          "the serialized stale writer must fail with a stable conflict and no token reuse");
  auto persisted = first_transaction->load();
  require(persisted.ok() && persisted.value().anniversaries.size() == 1U &&
              persisted.value().anniversaries.front().title == accepted.title &&
              persisted.value().anniversaries.front().updated_at == accepted.updated_at,
          "the rejected concurrent update must not overwrite any committed field");
}

void test_narrow_transaction_recovery_and_rollback() {
  TemporaryDirectory directory("recovery");
  prepare_v3_storage(directory.path());
  auto base = std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(base->initialize().ok(), "recovery stores must initialize");

  bool fail_once = true;
  JsonAnniversaryTransaction interrupted(
      directory.path(),
      [&](std::string_view phase) {
        if (phase == "after_store:anniversaries.json" && fail_once) {
          fail_once = false;
          return excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
              excellent_calendar::common::make_error(
                  "STORAGE_IO_ERROR", "simulated interruption"));
        }
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success({});
      });
  const auto anniversary_id = excellent_calendar::common::generate_uuid_v4();
  const auto recurrence_id = excellent_calendar::common::generate_uuid_v4();
  auto interrupted_result = interrupted.execute(
      "anniversary_create", excellent_calendar::common::generate_uuid_v4(), kNow,
      [&](excellent_calendar::repository::AnniversaryState& state) {
        state.recurrences.push_back(
            {recurrence_id, "yearly", 1, kNow, std::nullopt});
        state.anniversaries.push_back(
            {anniversary_id,
             "Recovered",
             LocalDate{2020, 2, 29},
             "solar",
             std::nullopt,
             recurrence_id,
             std::nullopt,
             std::string("important_noturgent"),
             kNow,
             kNow,
             std::nullopt});
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::success({});
      });
  require(!interrupted_result.ok(),
          "simulated interruption must stop before both stores are applied");

  JsonAnniversaryTransaction recovered(directory.path());
  require(recovered.initialize().ok(),
          "prepared Anniversary transaction must replay during initialization");
  auto loaded = recovered.load();
  require(loaded.ok() && loaded.value().anniversaries.size() == 1U &&
              loaded.value().recurrences.size() == 1U &&
              loaded.value().anniversaries.front().recurrence_id == recurrence_id,
          "journal replay must restore a complete two-store state");

  auto rejected = recovered.execute(
      "anniversary_update", excellent_calendar::common::generate_uuid_v4(), kNow,
      [](excellent_calendar::repository::AnniversaryState& state) {
        state.anniversaries.front().title = "Must not persist";
        return excellent_calendar::common::Result<excellent_calendar::common::Unit>::failure(
            excellent_calendar::common::make_error(
                "CONTRACT_VALIDATION_FAILED", "rejected action"));
      });
  require(!rejected.ok(), "failed workflow action must not write a prepared journal");
  loaded = recovered.load();
  require(loaded.ok() && loaded.value().anniversaries.front().title == "Recovered",
          "failed workflow action must leave both stores unchanged");
}

void test_additive_initialization_and_corruption_failure() {
  TemporaryDirectory additive("additive");
  AtomicJsonFileStore legacy(additive.path());
  require(legacy.initialize().ok(), "legacy v2 fixture must initialize");
  for (const auto& [file, collection] :
       std::vector<std::pair<std::string, std::string>>{
           {"events.json", "events"},
           {"recurrence_versions.json", "recurrence_versions"},
           {"event_occurrence_states.json", "event_occurrence_states"},
           {"reminders.json", "reminders"},
           {"notifications.json", "notifications"},
           {"reminder_recovery_batches.json", "reminder_recovery_batches"}}) {
    picojson::object root;
    root["storage_version"] = picojson::value(2.0);
    root[collection] = picojson::value(picojson::array{});
    require(legacy.write_json_file(file, picojson::value(root)).ok(),
            "legacy v2 Store fixture must be written");
  }
  prepare_v3_storage(additive.path());

  JsonAnniversaryTransaction anniversary(additive.path());
  require(anniversary.initialize().ok(),
          "missing Anniversary Stores must be added by v2-to-v3 migration");
  require(std::filesystem::exists(additive.path() / "anniversaries.json") &&
              std::filesystem::exists(
                   additive.path() / "anniversary_recurrences.json") &&
              std::filesystem::exists(
                  additive.path() / "calendar_workflow_transactions.json"),
          "migration must create Anniversary roots and the unified journal");

  TemporaryDirectory corrupt("corrupt");
  prepare_v3_storage(corrupt.path());
  JsonAnniversaryTransaction corrupt_transaction(corrupt.path());
  require(corrupt_transaction.initialize().ok(),
          "corruption fixture must initialize valid stores first");
  AtomicJsonFileStore raw(corrupt.path());
  picojson::object invalid;
  invalid["storage_version"] = picojson::value(3.0);
  invalid["anniversaries"] = picojson::value("not-an-array");
  require(raw.write_json_file("anniversaries.json", picojson::value(invalid)).ok(),
          "corruption fixture must overwrite the Anniversary root");
  auto loaded = corrupt_transaction.load();
  require(!loaded.ok() && loaded.error().code == "STORAGE_DATA_CORRUPTED",
          "corrupt Anniversary storage must fail explicitly without resetting data");
}

void test_boundary_contract_and_persistent_round_trip() {
  using namespace excellent_calendar::boundary::api;

  TemporaryDirectory directory("boundary");
  picojson::object initialize_request;
  initialize_request["storage_directory"] =
      picojson::value(directory.path().generic_string());
  initialize_request["tzdb_directory"] =
      picojson::value(std::string(EXCELLENT_CALENDAR_TEST_TZDB_DIR));
  auto initialized_result = parse_native_result(
      initialize_runtime_v2_json(picojson::value(initialize_request).serialize()),
      "runtime.initialize");
  require_success(initialized_result, "runtime.initialize");

  auto create_request = boundary_write_request(
      std::nullopt, "Boundary anniversary", true);
  picojson::object reminder_template;
  reminder_template["advance_days"] = picojson::value(7.0);
  reminder_template["local_time"] = picojson::value("09:00");
  reminder_template["method"] = picojson::value("popup");
  reminder_template["is_enabled"] = picojson::value(true);
  picojson::object reminder_plan;
  reminder_plan["reminders_enabled"] = picojson::value(true);
  reminder_plan["templates"] = picojson::value(
      picojson::array{picojson::value(std::move(reminder_template))});
  create_request["reminder_plan"] = picojson::value(std::move(reminder_plan));
  auto created_result = parse_native_result(
      create_anniversary_v2(picojson::value(create_request).serialize()),
      "anniversary.create");
  const auto& created = require_success(created_result, "anniversary.create");
  require_exact_fields(
      created, {"anniversary", "recurrence", "countdown", "reminder_settings"},
      "AnniversaryDetailResponse");
  require_exact_fields(
      created.at("reminder_settings").get<picojson::object>(),
      {"reminders_enabled", "templates", "active_reminder_count",
       "schedule_reconciliation_required"},
      "AnniversaryReminderSettingsResponse");
  const auto& anniversary = created.at("anniversary").get<picojson::object>();
  require_exact_fields(
      anniversary,
      {"id", "title", "date", "calendar_type", "category_id",
       "recurrence_id", "note", "importance", "created_at", "updated_at",
       "deleted_at"},
      "AnniversaryResponse");
  const auto anniversary_id = anniversary.at("id").get<std::string>();
  require(anniversary.at("date").get<std::string>() == "2020-02-29" &&
              created.at("recurrence").is<picojson::object>() &&
              created.at("countdown")
                      .get<picojson::object>()
                      .at("timezone")
                      .get<std::string>() == kTimezone,
          "create response must preserve date facts and return a dynamic countdown");
  const auto& created_settings = created.at("reminder_settings").get<picojson::object>();
  require(created_settings.at("reminders_enabled").get<bool>() &&
              created_settings.at("templates").get<picojson::array>().size() == 1U &&
              created_settings.at("active_reminder_count").get<double>() == 1.0,
          "Boundary create must decode and encode the frozen reminder_plan shape");

  initialized_result = parse_native_result(
      initialize_runtime_v2_json(picojson::value(initialize_request).serialize()),
      "runtime.initialize restart");
  require_success(initialized_result, "runtime.initialize restart");
  picojson::object detail_request;
  detail_request["id"] = picojson::value(anniversary_id);
  detail_request["timezone"] = picojson::value(kTimezone);
  auto detail_result = parse_native_result(
      get_anniversary_detail_v2(picojson::value(detail_request).serialize()),
      "anniversary.detail after restart");
  const auto& detail = require_success(
      detail_result, "anniversary.detail after restart");
  require(detail.at("anniversary")
                  .get<picojson::object>()
                  .at("id")
                  .get<std::string>() == anniversary_id,
          "detail after runtime restart must read the persisted record");

  picojson::object occurrence_request;
  occurrence_request["range_start_date"] = picojson::value("2026-01-01");
  occurrence_request["range_end_date"] = picojson::value("2027-02-05");
  occurrence_request["timezone"] = picojson::value(kTimezone);
  occurrence_request["category_ids"] = picojson::value(picojson::array{});
  occurrence_request["importance"] = picojson::value(picojson::array{});
  occurrence_request["cursor"] = picojson::value();
  occurrence_request["page_size"] = picojson::value(10.0);
  const auto occurrence_result = parse_native_result(
      list_anniversary_occurrences_v2(
          picojson::value(occurrence_request).serialize()),
      "anniversary.list_occurrences");
  const auto& occurrence_page = require_success(
      occurrence_result, "anniversary.list_occurrences");
  require_exact_fields(occurrence_page, {"items", "has_more", "next_cursor"},
                       "AnniversaryOccurrenceListResponse");
  require(occurrence_page.at("items").get<picojson::array>().size() == 1U,
          "Boundary occurrence query must return the date-only February 29 projection");

  picojson::object toggle_request;
  toggle_request["id"] = picojson::value(anniversary_id);
  toggle_request["reminders_enabled"] = picojson::value(false);
  toggle_request["timezone"] = picojson::value(kTimezone);
  const auto toggle_result = parse_native_result(
      set_anniversary_reminders_enabled_v2(
          picojson::value(toggle_request).serialize()),
      "anniversary.set_reminders_enabled");
  const auto& toggled = require_success(
      toggle_result, "anniversary.set_reminders_enabled");
  require(!toggled.at("reminder_settings")
               .get<picojson::object>()
               .at("reminders_enabled")
               .get<bool>(),
          "Boundary toggle must pause without deleting template configuration");

  auto second_create_request = boundary_write_request(
      std::nullopt, "Year-end anniversary", true);
  second_create_request["date"] = picojson::value("2020-12-31");
  require_success(
      parse_native_result(
          create_anniversary_v2(
              picojson::value(second_create_request).serialize()),
          "anniversary.create second list record"),
      "anniversary.create second list record");

  picojson::object list_request;
  list_request["timezone"] = picojson::value(kTimezone);
  list_request["category_ids"] = picojson::value(
      picojson::array{picojson::value(kCategoryId)});
  list_request["importance"] = picojson::value(
      picojson::array{picojson::value("important_noturgent")});
  picojson::object pagination;
  pagination["page"] = picojson::value(1.0);
  pagination["page_size"] = picojson::value(20.0);
  pagination["cursor"] = picojson::value();
  list_request["pagination"] = picojson::value(std::move(pagination));
  const auto countdown_days = [](const picojson::value& item) {
    return item.get<picojson::object>()
        .at("countdown")
        .get<picojson::object>()
        .at("days")
        .get<double>();
  };
  const auto default_list_request = list_request;
  auto default_list_result = parse_native_result(
      list_anniversaries_v2(
          picojson::value(default_list_request).serialize()),
      "anniversary.list default sort");
  const auto& default_list = require_success(
      default_list_result,
      "anniversary.list default sort");
  const auto& default_items = default_list.at("items").get<picojson::array>();
  require(default_items.size() == 2U &&
              countdown_days(default_items[0]) < countdown_days(default_items[1]),
          "missing top-level sort must default to ascending target occurrence");

  list_request["sort_by"] = picojson::value("countdown_days");
  list_request["sort_direction"] = picojson::value("desc");
  auto list_result = parse_native_result(
      list_anniversaries_v2(picojson::value(list_request).serialize()),
      "anniversary.list");
  const auto& list = require_success(list_result, "anniversary.list");
  const auto& sorted_items = list.at("items").get<picojson::array>();
  require(sorted_items.size() == 2U &&
              countdown_days(sorted_items[0]) > countdown_days(sorted_items[1]) &&
              list.at("pagination")
                      .get<picojson::object>()
                      .at("total")
                      .get<double>() == 2.0,
          "list must use the top-level sort and preserve array filters");

  auto nested_sort_request = default_list_request;
  nested_sort_request["pagination"]
      .get<picojson::object>()["sort_by"] = picojson::value("title");
  require_failure(
      parse_native_result(
          list_anniversaries_v2(
              picojson::value(nested_sort_request).serialize()),
          "anniversary.list nested sort"),
      "CONTRACT_VALIDATION_FAILED", "anniversary.list nested sort");

  auto conflicting_sort_request = list_request;
  auto& conflicting_pagination =
      conflicting_sort_request["pagination"].get<picojson::object>();
  conflicting_pagination["sort_by"] =
      picojson::value("target_occurrence_date");
  conflicting_pagination["sort_direction"] = picojson::value("asc");
  require_failure(
      parse_native_result(
          list_anniversaries_v2(
              picojson::value(conflicting_sort_request).serialize()),
          "anniversary.list conflicting sort locations"),
      "CONTRACT_VALIDATION_FAILED",
      "anniversary.list conflicting sort locations");

  auto cursor_request = list_request;
  cursor_request["pagination"]
      .get<picojson::object>()["cursor"] = picojson::value("opaque-cursor");
  require_failure(
      parse_native_result(
          list_anniversaries_v2(picojson::value(cursor_request).serialize()),
          "anniversary.list reserved cursor"),
      "FEATURE_NOT_IMPLEMENTED", "anniversary.list reserved cursor");

  auto update_request = boundary_write_request(
      anniversary_id, "Updated through boundary", false);
  update_request["expected_updated_at"] = anniversary.at("updated_at");
  auto missing_update_token = update_request;
  missing_update_token.erase("expected_updated_at");
  require_failure(
      parse_native_result(
          update_anniversary_v2(
              picojson::value(missing_update_token).serialize()),
          "anniversary.update missing expected_updated_at"),
      "CONTRACT_VALIDATION_FAILED",
      "anniversary.update missing expected_updated_at");
  require_failure(
      parse_native_result(
          update_anniversary_v2(picojson::value(update_request).serialize()),
          "anniversary.update stale after reminder toggle"),
      "ANNIVERSARY_UPDATE_CONFLICT",
      "anniversary.update stale after reminder toggle");
  update_request["expected_updated_at"] =
      toggled.at("anniversary")
          .get<picojson::object>()
          .at("updated_at");
  auto update_result = parse_native_result(
      update_anniversary_v2(picojson::value(update_request).serialize()),
      "anniversary.update");
  const auto& updated = require_success(update_result, "anniversary.update");
  require(updated.at("recurrence").is<picojson::null>() &&
              updated.at("anniversary")
                  .get<picojson::object>()
                  .at("recurrence_id")
                  .is<picojson::null>(),
          "update must preserve nullable recurrence fields exactly");
  require(updated.at("anniversary")
                  .get<picojson::object>()
                  .at("updated_at")
                  .get<std::string>() !=
              anniversary.at("updated_at").get<std::string>(),
          "successful update must issue a new updated_at token within the same clock second");
  require_failure(
      parse_native_result(
          update_anniversary_v2(picojson::value(update_request).serialize()),
          "anniversary.update stale expected_updated_at"),
      "ANNIVERSARY_UPDATE_CONFLICT",
      "anniversary.update stale expected_updated_at");

  picojson::object preview_request;
  preview_request["date"] = picojson::value("2020-02-29");
  preview_request["calendar_type"] = picojson::value("solar");
  picojson::object preview_recurrence;
  preview_recurrence["frequency"] = picojson::value("yearly");
  preview_recurrence["interval"] = picojson::value(1.0);
  preview_request["recurrence"] = picojson::value(std::move(preview_recurrence));
  preview_request["timezone"] = picojson::value(kTimezone);
  auto preview_result = parse_native_result(
      preview_anniversary_countdown_v2(
          picojson::value(preview_request).serialize()),
      "anniversary.preview_countdown");
  const auto& preview = require_success(
      preview_result, "anniversary.preview_countdown");
  require_exact_fields(
      preview,
      {"relation", "days", "target_occurrence_date", "iso_weekday",
       "timezone", "calculated_at"},
      "AnniversaryCountdownResponse");

  auto missing_timezone = create_request;
  missing_timezone.erase("timezone");
  require_failure(
      parse_native_result(
          create_anniversary_v2(picojson::value(missing_timezone).serialize()),
          "anniversary.create missing timezone"),
      "CONTRACT_VALIDATION_FAILED", "anniversary.create missing timezone");
  auto lunar = boundary_write_request(
      std::nullopt, "Lunar unsupported", false, "lunar");
  require_failure(
      parse_native_result(
          create_anniversary_v2(picojson::value(lunar).serialize()),
          "anniversary.create lunar"),
      "ANNIVERSARY_CALENDAR_UNSUPPORTED", "anniversary.create lunar");
  require_failure(
      parse_native_result(create_anniversary_v2("[]"),
                          "anniversary.create non-object"),
      "CONTRACT_VALIDATION_FAILED", "anniversary.create non-object");

  picojson::object delete_request;
  delete_request["id"] = picojson::value(anniversary_id);
  auto delete_result = parse_native_result(
      delete_anniversary_v2(picojson::value(delete_request).serialize()),
      "anniversary.delete");
  const auto& deleted = require_success(delete_result, "anniversary.delete");
  require_exact_fields(
      deleted, {"anniversary", "schedule_reconciliation_required"},
      "AnniversaryDeleteCommitResponse");
  require(deleted.at("anniversary").get<picojson::object>().at("deleted_at").is<std::string>(),
          "delete response must expose the soft-delete instant in the deleted Anniversary");
  require_failure(
      parse_native_result(
          get_anniversary_detail_v2(picojson::value(detail_request).serialize()),
          "anniversary.detail deleted"),
      "ANNIVERSARY_NOT_FOUND", "anniversary.detail deleted");
}

}  // namespace

int main() {
  try {
    test_date_only_countdown_edges();
    test_anniversary_r1_identity_vectors();
    test_reminder_plan_lifecycle_and_occurrence_paging();
    test_workflow_lifecycle_persistence_and_queries();
    test_reminder_toggle_advances_version_and_rejects_stale_plans();
    test_toggle_and_update_concurrency_preserves_latest_plan();
    test_update_optimistic_concurrency_serializes_stale_writers();
    test_narrow_transaction_recovery_and_rollback();
    test_additive_initialization_and_corruption_failure();
    test_boundary_contract_and_persistent_round_trip();
    std::cout << "anniversary core tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "anniversary core tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
