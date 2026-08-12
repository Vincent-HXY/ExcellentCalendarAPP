#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>

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

void test_workflow_lifecycle_persistence_and_queries() {
  TemporaryDirectory directory("workflow");
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
       write_input("Updated yearly", LocalDate{2021, 3, 1}, true, kCategoryId)});
  require(updated_yearly.ok() && updated_yearly.value().recurrence.has_value() &&
              updated_yearly.value().recurrence->id == original_recurrence_id,
          "yearly-to-yearly update must retain recurrence identity");

  auto made_one_time = restarted_workflow.update(
      {anniversary_id,
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

void test_narrow_transaction_recovery_and_rollback() {
  TemporaryDirectory directory("recovery");
  auto base = std::make_shared<JsonAnniversaryTransaction>(directory.path());
  require(base->initialize().ok(), "recovery stores must initialize");

  bool fail_once = true;
  JsonAnniversaryTransaction interrupted(
      directory.path(),
      [&](std::string_view phase) {
        if (phase == "after_anniversaries" && fail_once) {
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
  excellent_calendar::storage::json::JsonRecurringEventTransaction existing_v2(
      additive.path());
  require(existing_v2.initialize().ok(),
          "existing Event/Reminder v2 store set must initialize");
  require(!std::filesystem::exists(additive.path() / "anniversaries.json"),
          "precondition must represent an older v2 directory without Anniversary");

  JsonAnniversaryTransaction anniversary(additive.path());
  require(anniversary.initialize().ok(),
          "Anniversary stores must be added to an existing valid v2 directory");
  require(std::filesystem::exists(additive.path() / "anniversaries.json") &&
              std::filesystem::exists(
                  additive.path() / "anniversary_recurrences.json") &&
              std::filesystem::exists(
                  additive.path() / "anniversary_workflow_transactions.json"),
          "additive initialization must create the three narrow v2 roots");

  TemporaryDirectory corrupt("corrupt");
  JsonAnniversaryTransaction corrupt_transaction(corrupt.path());
  require(corrupt_transaction.initialize().ok(),
          "corruption fixture must initialize valid stores first");
  AtomicJsonFileStore raw(corrupt.path());
  picojson::object invalid;
  invalid["storage_version"] = picojson::value(2.0);
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
  auto created_result = parse_native_result(
      create_anniversary_v2(picojson::value(create_request).serialize()),
      "anniversary.create");
  const auto& created = require_success(created_result, "anniversary.create");
  require_exact_fields(
      created, {"anniversary", "recurrence", "countdown"},
      "AnniversaryDetailResponse");
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
  require(deleted.at("deleted_at").is<std::string>(),
          "delete response must expose the soft-delete instant");
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
    test_workflow_lifecycle_persistence_and_queries();
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
