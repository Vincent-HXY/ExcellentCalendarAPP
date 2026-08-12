#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/category_service.hpp"
#include "excellent_calendar/boundary/api/category_api.hpp"
#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"
#include "excellent_calendar/boundary/contract/category_json.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/repository/category_repository.hpp"
#include "excellent_calendar/storage/json/category_json_codec.hpp"
#include "excellent_calendar/storage/json/json_category_repository.hpp"

namespace {

using excellent_calendar::application::CategoryService;
using excellent_calendar::application::CreateCategoryCommand;
using excellent_calendar::repository::CategoryRepository;
using excellent_calendar::repository::CategoryState;
using excellent_calendar::storage::json::JsonCategoryRepository;

constexpr const char *kId1 = "11111111-1111-4111-8111-111111111111";
constexpr const char *kId2 = "22222222-2222-4222-8222-222222222222";
constexpr const char *kId3 = "33333333-3333-4333-8333-333333333333";
constexpr const char *kId4 = "44444444-4444-4444-8444-444444444444";
constexpr const char *kTime1 = "2026-08-11T01:02:03Z";
constexpr const char *kTime2 = "2026-08-11T01:02:04Z";
constexpr const char *kTime3 = "2026-08-11T01:02:05Z";

void require(bool condition, const std::string &message) {
  if (!condition)
    throw std::runtime_error(message);
}

class TemporaryDirectory {
public:
  explicit TemporaryDirectory(std::string_view label)
      : path_(std::filesystem::temp_directory_path() /
              ("excellent_calendar_category_" + std::string(label) + "_" +
               excellent_calendar::common::generate_uuid_v4())) {
    std::filesystem::create_directories(path_);
  }

  ~TemporaryDirectory() {
    std::error_code ignored;
    std::filesystem::remove_all(path_, ignored);
  }

  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

class InMemoryCategoryRepository final : public CategoryRepository {
public:
  excellent_calendar::common::Result<excellent_calendar::common::Unit>
  initialize() override {
    return excellent_calendar::common::Result<
        excellent_calendar::common::Unit>::success({});
  }

  excellent_calendar::common::Result<CategoryState> load() override {
    return excellent_calendar::common::Result<CategoryState>::success(state);
  }

  excellent_calendar::common::Result<excellent_calendar::common::Unit>
  execute(std::string_view operation, const Operation &action) override {
    if (operation != "category_create") {
      return excellent_calendar::common::
          Result<excellent_calendar::common::Unit>::failure(
              excellent_calendar::common::make_error("NATIVE_INTERNAL_ERROR",
                                                     "Native internal error"));
    }
    auto next = state;
    auto result = action(next);
    if (result.ok())
      state = std::move(next);
    return result;
  }

  CategoryState state;
};

std::string read_file(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  std::stringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

void write_file(const std::filesystem::path &path, const std::string &content) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output << content;
  output.flush();
  require(output.good(), "test fixture write failed");
}

picojson::object parse_native_result(const std::string &json,
                                     const std::string &context) {
  picojson::value value;
  const auto error = picojson::parse(value, json);
  require(error.empty() && value.is<picojson::object>(),
          context + " must return an object NativeResult");
  auto result = value.get<picojson::object>();
  require(result.size() == 5U && result.count("ok") == 1U &&
              result.count("data") == 1U && result.count("error") == 1U &&
              result.count("contract_version") == 1U &&
              result.count("request_id") == 1U,
          context + " must return the exact NativeResult v2 envelope");
  require(result.at("contract_version").is<double>() &&
              result.at("contract_version").get<double>() == 2.0,
          context + " must return contract_version 2");
  return result;
}

const picojson::object &require_success(const picojson::object &result,
                                        const std::string &context) {
  require(result.at("ok").is<bool>() && result.at("ok").get<bool>() &&
              result.at("data").is<picojson::object>() &&
              result.at("error").is<picojson::null>(),
          context + " must succeed");
  return result.at("data").get<picojson::object>();
}

void require_failure(const picojson::object &result, const std::string &code,
                     const std::string &context) {
  require(result.at("ok").is<bool>() && !result.at("ok").get<bool>() &&
              result.at("data").is<picojson::null>() &&
              result.at("error").is<picojson::object>(),
          context + " must fail through NativeResult");
  const auto &error = result.at("error").get<picojson::object>();
  require(error.at("code").is<std::string>() &&
              error.at("code").get<std::string>() == code,
          context + " must return " + code);
}

picojson::object
create_request(std::string name,
               std::optional<std::string> description = std::nullopt,
               std::string color = "#39afbd",
               std::optional<std::string> icon = std::nullopt,
               std::optional<std::int64_t> sort_order = std::nullopt) {
  picojson::object request;
  request["name"] = picojson::value(std::move(name));
  request["description"] = description.has_value()
                               ? picojson::value(*description)
                               : picojson::value();
  request["color"] = picojson::value(std::move(color));
  request["icon"] =
      icon.has_value() ? picojson::value(*icon) : picojson::value();
  request["sort_order"] =
      sort_order.has_value() ? picojson::value(static_cast<double>(*sort_order))
                             : picojson::value();
  return request;
}

picojson::object
runtime_request(const std::filesystem::path &storage_directory) {
  picojson::object request;
  request["storage_directory"] =
      picojson::value(storage_directory.generic_string());
  request["tzdb_directory"] = picojson::value(
      std::filesystem::path(EXCELLENT_CALENDAR_TEST_TZDB_DIR).generic_string());
  return request;
}

picojson::object
ordinary_event_request(std::string title,
                       std::optional<std::string> category_id) {
  picojson::object event;
  event["title"] = picojson::value(std::move(title));
  event["content"] = picojson::value();
  event["start_at"] = picojson::value("2026-12-01T08:00:00Z");
  event["end_at"] = picojson::value("2026-12-01T09:00:00Z");
  event["start_date"] = picojson::value();
  event["end_date"] = picojson::value();
  event["is_all_day"] = picojson::value(false);
  event["category_id"] = category_id.has_value() ? picojson::value(*category_id)
                                                 : picojson::value();
  event["importance"] = picojson::value();
  event["location"] = picojson::value();
  event["timezone"] = picojson::value("Etc/UTC");
  event["source"] = picojson::value("manual");
  event["recurrence"] = picojson::value();
  event["reminders"] = picojson::value(picojson::array{});
  return event;
}

void test_boundary_contract_codecs_and_unicode() {
  using excellent_calendar::boundary::contract::category_list_response_json;
  using excellent_calendar::boundary::contract::CategoryListResponseDto;
  using excellent_calendar::boundary::contract::CategoryResponseDto;
  using excellent_calendar::boundary::contract::parse_category_list_request;
  using excellent_calendar::boundary::contract::parse_create_category_request;

  require(parse_category_list_request("{}").ok(),
          "empty Category list request must decode");
  require(!parse_category_list_request(R"({"contract_version":2})").ok(),
          "request-side contract_version must be rejected as unknown");

  const std::string unicode_name = u8"\u5de5\u4f5c\U0001f5d3\ufe0f";
  auto request =
      create_request(unicode_name, std::string(u8"  \u9879\u76ee\U0001f680  "),
                     "#39afbd", std::string(u8"\U0001f4c1"), 7);
  auto decoded =
      parse_create_category_request(picojson::value(request).serialize());
  require(decoded.ok() && decoded.value().name == unicode_name &&
              decoded.value().description ==
                  std::optional<std::string>(u8"  \u9879\u76ee\U0001f680  ") &&
              decoded.value().sort_order == 7,
          "Category request codec must preserve Unicode and nullable fields");

  auto safe_integer_maximum = create_request(
      "Maximum sort order", std::nullopt, "#39afbd", std::nullopt,
      excellent_calendar::domain::kMaximumCategorySortOrder);
  auto decoded_maximum = parse_create_category_request(
      picojson::value(safe_integer_maximum).serialize());
  require(decoded_maximum.ok() && decoded_maximum.value().sort_order ==
                                      excellent_calendar::domain::
                                          kMaximumCategorySortOrder,
          "Category request codec must preserve the maximum safe integer");
  auto above_safe_integer = safe_integer_maximum;
  above_safe_integer["sort_order"] = picojson::value(
      static_cast<double>(
          excellent_calendar::domain::kMaximumCategorySortOrder) +
      1.0);
  auto decoded_above = parse_create_category_request(
      picojson::value(above_safe_integer).serialize());
  require(!decoded_above.ok() &&
              decoded_above.error().code == "CONTRACT_VALIDATION_FAILED",
          "Category request codec must reject sort_order above the maximum "
          "safe integer");

  auto empty_name = request;
  empty_name["name"] = picojson::value("   ");
  require(
      !parse_create_category_request(picojson::value(empty_name).serialize())
           .ok(),
      "blank Category name must fail Contract decoding");
  auto invalid_type = request;
  invalid_type["sort_order"] = picojson::value("7");
  require(
      !parse_create_category_request(picojson::value(invalid_type).serialize())
           .ok(),
      "invalid Category field type must fail Contract decoding");
  auto unknown = request;
  unknown["unknown"] = picojson::value(true);
  require(
      !parse_create_category_request(picojson::value(unknown).serialize()).ok(),
      "unknown Category request field must fail Contract decoding");
  require(!parse_create_category_request("[").ok(),
          "malformed Category payload must fail Contract decoding");
  std::string malformed_utf8 = R"({"name":")";
  malformed_utf8.push_back(static_cast<char>(0xc3));
  malformed_utf8 +=
      R"(","description":null,"color":"#39AFBD","icon":null,"sort_order":null})";
  require(!parse_create_category_request(malformed_utf8).ok(),
          "malformed UTF-8 in Category text must fail Contract decoding");

  std::string forty_emoji;
  for (int index = 0; index < 40; ++index)
    forty_emoji += u8"\U0001f4c5";
  auto maximum = create_request(forty_emoji);
  require(
      parse_create_category_request(picojson::value(maximum).serialize()).ok(),
      "Category maxLength must count Unicode code points, not bytes");
  maximum["name"] = picojson::value(forty_emoji + u8"\U0001f4c5");
  require(
      !parse_create_category_request(picojson::value(maximum).serialize()).ok(),
      "Category name over 40 Unicode code points must fail");

  CategoryResponseDto item{kId1,         unicode_name,
                           std::nullopt, std::string("#39AFBD"),
                           std::nullopt, 7,
                           kTime1,       kTime1,
                           std::nullopt};
  auto response = category_list_response_json(CategoryListResponseDto{{item}});
  require(response.is<picojson::object>(),
          "Category list response must encode as object");
  const auto &response_object = response.get<picojson::object>();
  require(response_object.size() == 1U &&
              response_object.at("items").is<picojson::array>() &&
              response_object.at("items").get<picojson::array>().size() == 1U,
          "Category list response codec must emit exact items wrapper");
  const auto &encoded_item = response_object.at("items")
                                 .get<picojson::array>()[0]
                                 .get<picojson::object>();
  require(encoded_item.size() == 9U &&
              encoded_item.at("description").is<picojson::null>() &&
              encoded_item.at("deleted_at").is<picojson::null>() &&
              encoded_item.at("name").get<std::string>() == unicode_name,
          "Category response codec must preserve exact nullable snake_case "
          "projection");
}

void test_service_rules_and_error_mapping() {
  auto repository = std::make_shared<InMemoryCategoryRepository>();
  std::vector<std::string> ids{kId1, kId2, kId3};
  std::vector<std::string> times{kTime1, kTime2, kTime3};
  std::size_t id_index = 0;
  std::size_t time_index = 0;
  CategoryService service(
      repository, [&] { return times.at(time_index++); },
      [&] { return ids.at(id_index++); });

  auto blank = service.create(CreateCategoryCommand{
      "\t\n", std::nullopt, "#112233", std::nullopt, std::nullopt});
  require(!blank.ok() && blank.error().code == "CATEGORY_NAME_EMPTY",
          "CategoryService must map blank names to CATEGORY_NAME_EMPTY");

  auto first = service.create(
      CreateCategoryCommand{"  Work  ", std::string("   "), "#aabbcc",
                            std::string("  folder  "), std::nullopt});
  require(first.ok() && first.value().name == "Work" &&
              !first.value().description.has_value() &&
              first.value().color == "#AABBCC" &&
              first.value().icon == "folder" && first.value().sort_order == 0 &&
              !first.value().deleted_at.has_value(),
          "CategoryService must normalize text/color and materialize append "
          "order zero");
  auto duplicate_name = service.create(
      CreateCategoryCommand{"Work", std::nullopt, "#445566", std::nullopt, 0});
  require(duplicate_name.ok() && duplicate_name.value().sort_order == 0,
          "duplicate Category names and explicit duplicate sort_order must "
          "remain legal");
  auto appended = service.create(CreateCategoryCommand{
      "Later", std::nullopt, "#778899", std::nullopt, std::nullopt});
  require(appended.ok() && appended.value().sort_order == 1,
          "null sort_order must append after maximum active order under "
          "repository operation");

  repository->state.categories[0].deleted_at = kTime3;
  auto listed = service.list();
  require(
      listed.ok() && listed.value().size() == 2U &&
          listed.value()[0].id == kId2 && listed.value()[1].id == kId3,
      "Category list must omit soft-deleted records and sort by order/time/id");

  repository->state.categories.push_back(excellent_calendar::domain::Category{
      kId4, "Compatibility null order", std::nullopt, "#AABBCC",
      std::nullopt, std::nullopt, kTime1, kTime1, std::nullopt});
  auto with_null_order = service.list();
  require(with_null_order.ok() && with_null_order.value().size() == 3U &&
              with_null_order.value().back().id == kId4 &&
              !with_null_order.value().back().sort_order.has_value(),
          "Category list comparator must keep compatibility null sort_order "
          "values last without using an integer sentinel");
}

void test_sort_order_safe_integer_boundaries() {
  using excellent_calendar::boundary::api::create_category_v2;
  using excellent_calendar::boundary::api::initialize_runtime_v2_json;
  using excellent_calendar::boundary::api::list_categories_v2;

  const auto maximum =
      excellent_calendar::domain::kMaximumCategorySortOrder;
  auto memory_repository = std::make_shared<InMemoryCategoryRepository>();
  CategoryService memory_service(
      memory_repository, [] { return std::string(kTime1); },
      [] { return std::string(kId1); });

  auto above_maximum = memory_service.create(CreateCategoryCommand{
      "Too large", std::nullopt, "#112233", std::nullopt, maximum + 1});
  require(!above_maximum.ok() &&
              above_maximum.error().code == "CONTRACT_VALIDATION_FAILED" &&
              memory_repository->state.categories.empty(),
          "CategoryService must reject sort_order above the safe integer "
          "maximum without mutating repository state");

  auto at_maximum = memory_service.create(CreateCategoryCommand{
      "Maximum", std::nullopt, "#112233", std::nullopt, maximum});
  require(at_maximum.ok() && at_maximum.value().sort_order == maximum,
          "CategoryService must accept the maximum safe sort_order");
  const auto before_exhaustion = memory_repository->state.categories;
  auto exhausted = memory_service.create(CreateCategoryCommand{
      "Cannot append", std::nullopt, "#445566", std::nullopt, std::nullopt});
  require(!exhausted.ok() &&
              exhausted.error().code == "CATEGORY_SORT_ORDER_EXHAUSTED" &&
              exhausted.error().message ==
                  "Category sort order has reached the maximum safe integer" &&
              !exhausted.error().retryable &&
              memory_repository->state.categories.size() ==
                  before_exhaustion.size() &&
              memory_repository->state.categories.front().id ==
                  before_exhaustion.front().id,
          "automatic Category append at the maximum must return the frozen "
          "error and write nothing");

  TemporaryDirectory directory("safe_integer_boundary");
  auto repository = std::make_shared<JsonCategoryRepository>(directory.path());
  require(repository->initialize().ok(),
          "safe-integer Category repository fixture must initialize");
  CategoryService service(
      repository, [] { return std::string(kTime1); },
      [] { return std::string(kId1); });
  require(service
              .create(CreateCategoryCommand{"Persisted maximum", std::nullopt,
                                            "#778899", std::nullopt, maximum})
              .ok(),
          "maximum safe Category sort_order must persist");
  auto reopened = std::make_shared<JsonCategoryRepository>(directory.path());
  require(reopened->initialize().ok(),
          "maximum safe Category sort_order must survive restart");
  CategoryService reopened_service(
      reopened, [] { return std::string(kTime2); },
      [] { return std::string(kId2); });
  auto listed = reopened_service.list();
  require(listed.ok() && listed.value().size() == 1U &&
              listed.value().front().sort_order == maximum,
          "maximum safe Category sort_order must round-trip without numeric "
          "loss");
  const auto previous = read_file(directory.path() / "categories.json");
  auto exhausted_after_restart = reopened_service.create(CreateCategoryCommand{
      "Still exhausted", std::nullopt, "#AABBCC", std::nullopt, std::nullopt});
  require(!exhausted_after_restart.ok() &&
              exhausted_after_restart.error().code ==
                  "CATEGORY_SORT_ORDER_EXHAUSTED" &&
              read_file(directory.path() / "categories.json") == previous,
          "automatic append exhaustion after restart must preserve exact "
          "Category store bytes");

  const auto initialize = runtime_request(directory.path());
  require_success(
      parse_native_result(
          initialize_runtime_v2_json(picojson::value(initialize).serialize()),
          "safe-integer runtime initialize"),
      "safe-integer runtime initialize");
  auto boundary_list_result = parse_native_result(
      list_categories_v2("{}"), "category.list maximum safe integer");
  const auto boundary_list = picojson::object(require_success(
      boundary_list_result, "category.list maximum safe integer"));
  const auto &boundary_items =
      boundary_list.at("items").get<picojson::array>();
  require(boundary_items.size() == 1U &&
              boundary_items.front()
                      .get<picojson::object>()
                      .at("sort_order")
                      .get<double>() == static_cast<double>(maximum),
          "Category Boundary response must preserve the maximum safe integer");
  const auto boundary_previous =
      read_file(directory.path() / "categories.json");
  auto boundary_exhausted = parse_native_result(
      create_category_v2(
          picojson::value(create_request("Boundary append")).serialize()),
      "category.create exhausted append");
  require_failure(boundary_exhausted, "CATEGORY_SORT_ORDER_EXHAUSTED",
                  "category.create exhausted append");
  const auto &boundary_error =
      boundary_exhausted.at("error").get<picojson::object>();
  require(boundary_error.at("message").get<std::string>() ==
                  "Category sort order has reached the maximum safe integer" &&
              boundary_error.at("retryable").is<bool>() &&
              !boundary_error.at("retryable").get<bool>() &&
              read_file(directory.path() / "categories.json") ==
                  boundary_previous,
          "Category NativeResult must preserve the frozen exhaustion error and "
          "write nothing");

  auto boundary_above_request = create_request(
      "Boundary too large", std::nullopt, "#39afbd", std::nullopt,
      maximum + 1);
  auto boundary_above = parse_native_result(
      create_category_v2(
          picojson::value(boundary_above_request).serialize()),
      "category.create above safe integer");
  require_failure(boundary_above, "CONTRACT_VALIDATION_FAILED",
                  "category.create above safe integer");
  require(read_file(directory.path() / "categories.json") ==
              boundary_previous,
          "Category Boundary must reject max+1 before storage mutation");
}

void test_repository_persistence_sort_and_restart() {
  TemporaryDirectory directory("repository");
  auto repository = std::make_shared<JsonCategoryRepository>(directory.path());
  auto initialized = repository->initialize();
  require(initialized.ok(),
          "Category repository initialization must create empty v2 store");
  require(read_file(directory.path() / "categories.json") ==
              R"({"categories":[],"storage_version":2})",
          "new Category store must use the exact empty v2 root");

  std::vector<std::string> ids{kId3, kId1, kId2};
  std::vector<std::string> times{kTime2, kTime1, kTime1};
  std::size_t id_index = 0;
  std::size_t time_index = 0;
  CategoryService service(
      repository, [&] { return times.at(time_index++); },
      [&] { return ids.at(id_index++); });
  require(service
              .create(CreateCategoryCommand{"Third id", std::nullopt, "#111111",
                                            std::nullopt, 4})
              .ok(),
          "first persisted Category create must succeed");
  require(service
              .create(CreateCategoryCommand{"First id", std::nullopt, "#222222",
                                            std::nullopt, 1})
              .ok(),
          "second persisted Category create must succeed");
  require(
      service
          .create(CreateCategoryCommand{u8"\u4e2d\u6587\U0001f4c5",
                                        std::string(u8"\u6301\u4e45\u5316"),
                                        "#abcdef", std::nullopt, std::nullopt})
          .ok(),
      "Unicode persisted Category create must succeed");

  picojson::value root;
  const auto parse_error =
      picojson::parse(root, read_file(directory.path() / "categories.json"));
  require(parse_error.empty() && root.is<picojson::object>(),
          "persisted categories.json must remain valid JSON");
  const auto &records =
      root.get<picojson::object>().at("categories").get<picojson::array>();
  require(records.size() == 3U &&
              records[0].get<picojson::object>().at("id").get<std::string>() ==
                  kId1 &&
              records[1].get<picojson::object>().at("id").get<std::string>() ==
                  kId2 &&
              records[2].get<picojson::object>().at("id").get<std::string>() ==
                  kId3,
          "Category snapshot must serialize records by id ascending");

  auto reopened_repository =
      std::make_shared<JsonCategoryRepository>(directory.path());
  require(reopened_repository->initialize().ok(),
          "Category repository must reopen its persisted v2 snapshot");
  CategoryService reopened(
      reopened_repository, [] { return std::string(kTime3); },
      [] { return std::string(kId2); });
  auto listed = reopened.list();
  require(listed.ok() && listed.value().size() == 3U &&
              listed.value()[0].id == kId1 && listed.value()[1].id == kId3 &&
              listed.value()[2].id == kId2 &&
              listed.value()[2].name == u8"\u4e2d\u6587\U0001f4c5",
          "Category repository restart must recover Unicode data and Contract "
          "ordering");
}

void test_storage_corruption_unknown_version_and_write_failure() {
  {
    TemporaryDirectory directory("unknown_version");
    const auto path = directory.path() / "categories.json";
    const std::string original = R"({"categories":[],"storage_version":99})";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(!initialized.ok() &&
                initialized.error().code == "STORAGE_DATA_CORRUPTED" &&
                read_file(path) == original,
            "unknown Category storage version must fail without rewriting the "
            "file");
  }
  {
    TemporaryDirectory directory("unknown_field");
    const auto path = directory.path() / "categories.json";
    const std::string original =
        R"({"categories":[],"storage_version":2,"unknown":true})";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(
        !initialized.ok() &&
            initialized.error().code == "STORAGE_DATA_CORRUPTED" &&
            read_file(path) == original,
        "unknown Category storage field must fail without rewriting the file");
  }
  {
    TemporaryDirectory directory("malformed");
    const auto path = directory.path() / "categories.json";
    const std::string original = "{broken";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(!initialized.ok() &&
                initialized.error().code == "STORAGE_DATA_CORRUPTED" &&
                read_file(path) == original,
            "malformed Category storage must fail without rewriting the file");
  }
  {
    TemporaryDirectory directory("damaged_record");
    const auto path = directory.path() / "categories.json";
    const std::string original =
        R"({"categories":[{"id":"11111111-1111-4111-8111-111111111111","name":"Work","description":null,"color":"#abcdef","icon":null,"sort_order":0,"created_at":"2026-08-11T01:02:03Z","updated_at":"2026-08-11T01:02:03Z","deleted_at":null,"unknown":true}],"storage_version":2})";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(!initialized.ok() &&
                initialized.error().code == "STORAGE_DATA_CORRUPTED" &&
                read_file(path) == original,
            "damaged Category record must fail strict decoding without "
            "rewriting the file");
  }
  {
    TemporaryDirectory directory("sort_order_above_safe_integer");
    const auto path = directory.path() / "categories.json";
    const std::string original =
        R"({"categories":[{"id":"11111111-1111-4111-8111-111111111111","name":"Work","description":null,"color":"#ABCDEF","icon":null,"sort_order":9007199254740992,"created_at":"2026-08-11T01:02:03Z","updated_at":"2026-08-11T01:02:03Z","deleted_at":null}],"storage_version":2})";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(!initialized.ok() &&
                initialized.error().code == "STORAGE_DATA_CORRUPTED" &&
                read_file(path) == original,
            "persisted Category sort_order above the safe integer maximum "
            "must fail explicitly without rewriting the file");
  }
  {
    TemporaryDirectory directory("contract_timestamp_order");
    const auto path = directory.path() / "categories.json";
    const std::string original =
        R"({"categories":[{"id":"11111111-1111-4111-8111-111111111111","name":"Work","description":null,"color":"#ABCDEF","icon":null,"sort_order":0,"created_at":"2026-08-11T01:02:03Z","updated_at":"2026-08-11T01:02:05Z","deleted_at":"2026-08-11T01:02:04Z"}],"storage_version":2})";
    write_file(path, original);
    JsonCategoryRepository repository(directory.path());
    auto initialized = repository.initialize();
    require(initialized.ok() && read_file(path) == original,
            "Category storage must require deleted_at not earlier than "
            "created_at without inventing an updated_at ordering rule");
  }
  {
    TemporaryDirectory directory("write_failure");
    auto repository =
        std::make_shared<JsonCategoryRepository>(directory.path());
    require(repository->initialize().ok(),
            "write-failure fixture must initialize");
    CategoryService service(
        repository, [] { return std::string(kTime1); },
        [] { return std::string(kId1); });
    const auto previous = read_file(directory.path() / "categories.json");
    std::filesystem::create_directory(directory.path() / "categories.json.tmp");
    auto created = service.create(CreateCategoryCommand{
        "Cannot commit", std::nullopt, "#123456", std::nullopt, std::nullopt});
    require(!created.ok() && created.error().code == "STORAGE_IO_ERROR" &&
                read_file(directory.path() / "categories.json") == previous,
            "Category write failure must leave the previous snapshot "
            "authoritative");
    std::filesystem::remove(directory.path() / "categories.json.tmp");
    auto reopened = std::make_shared<JsonCategoryRepository>(directory.path());
    require(reopened->initialize().ok(),
            "Category store must reopen after an interrupted failed write");
    CategoryService reopened_service(
        reopened, [] { return std::string(kTime2); },
        [] { return std::string(kId2); });
    auto listed = reopened_service.list();
    require(listed.ok() && listed.value().empty(),
            "failed Category write must not become visible after restart");
  }
}

void test_atomic_write_failure_injection_and_retry() {
  const std::vector<std::string> phases = {
      "write", "temp_fsync", "replace", "directory_fsync"};
  for (const auto &phase : phases) {
    TemporaryDirectory directory("atomic_" + phase);
    bool armed = false;
    bool fired = false;
    JsonCategoryRepository::FailureHook failure_hook =
        [&](std::string_view actual_phase) {
          if (armed && !fired && actual_phase == phase) {
            fired = true;
            return excellent_calendar::common::
                Result<excellent_calendar::common::Unit>::failure(
                    excellent_calendar::common::make_error(
                        "STORAGE_IO_ERROR",
                        "Storage input/output operation failed",
                        {{"operation", std::string(actual_phase)},
                         {"reason", "injected Category write failure"}},
                        true));
          }
          return excellent_calendar::common::
              Result<excellent_calendar::common::Unit>::success({});
        };
    auto repository = std::make_shared<JsonCategoryRepository>(
        directory.path(),
        std::shared_ptr<
            excellent_calendar::storage::RuntimeStorageLease>{},
        failure_hook);
    require(repository->initialize().ok(),
            phase + " failure fixture must initialize");
    std::vector<std::string> ids{kId1, kId2};
    std::size_t id_index = 0;
    CategoryService service(
        repository, [] { return std::string(kTime1); },
        [&] { return ids.at(id_index++); });
    require(service
                .create(CreateCategoryCommand{"Existing", std::nullopt,
                                              "#112233", std::nullopt, 0})
                .ok(),
            phase + " failure fixture must persist its old snapshot");
    const auto path = directory.path() / "categories.json";
    const auto previous = read_file(path);

    armed = true;
    auto failed = service.create(CreateCategoryCommand{
        "Retry once", std::nullopt, "#445566", std::nullopt, 1});
    require(!failed.ok() && failed.error().code == "STORAGE_IO_ERROR" &&
                fired && read_file(path) == previous,
            phase +
                " failure must return STORAGE_IO_ERROR with the previous "
                "Category snapshot still authoritative");
    require(!std::filesystem::exists(path.string() + ".tmp") &&
                !std::filesystem::exists(path.string() + ".rollback"),
            phase + " failure must clean temporary recovery artifacts");

    auto reopened = std::make_shared<JsonCategoryRepository>(directory.path());
    require(reopened->initialize().ok(),
            phase + " failure snapshot must reopen after restart");
    CategoryService reopened_service(
        reopened, [] { return std::string(kTime2); },
        [] { return std::string(kId3); });
    auto before_retry = reopened_service.list();
    require(before_retry.ok() && before_retry.value().size() == 1U &&
                before_retry.value().front().id == kId1,
            phase + " failed Category must not become visible after restart");
    require(reopened_service
                .create(CreateCategoryCommand{"Retry once", std::nullopt,
                                              "#445566", std::nullopt, 1})
                .ok(),
            phase + " retry must succeed");
    auto after_retry = reopened_service.list();
    require(after_retry.ok() && after_retry.value().size() == 2U &&
                after_retry.value()[0].id == kId1 &&
                after_retry.value()[1].id == kId3,
            phase +
                " retry must create exactly one Category and never expose "
                "the failed attempt");
  }
}

void test_additive_runtime_initialization_preserves_existing_v2_data() {
  using excellent_calendar::boundary::api::create_event_v2;
  using excellent_calendar::boundary::api::get_event_detail_v2;
  using excellent_calendar::boundary::api::initialize_runtime_v2_json;

  TemporaryDirectory directory("additive_runtime");
  const auto initialize = runtime_request(directory.path());
  require_success(
      parse_native_result(
          initialize_runtime_v2_json(picojson::value(initialize).serialize()),
          "additive runtime initial initialize"),
      "additive runtime initial initialize");
  const auto &created = require_success(
      parse_native_result(
          create_event_v2(
              picojson::value(ordinary_event_request("Existing v2 event",
                                                     std::string(kId1)))
                  .serialize()),
          "additive runtime event create"),
      "additive runtime event create");
  const auto event_id = created.at("id").get<std::string>();
  const auto events_before = read_file(directory.path() / "events.json");

  require(std::filesystem::remove(directory.path() / "categories.json"),
          "additive runtime fixture must remove only categories.json");
  require_success(
      parse_native_result(
          initialize_runtime_v2_json(picojson::value(initialize).serialize()),
          "additive runtime reinitialize"),
      "additive runtime reinitialize");
  require(read_file(directory.path() / "categories.json") ==
                  R"({"categories":[],"storage_version":2})" &&
              read_file(directory.path() / "events.json") == events_before,
          "missing Category store must be added empty without rewriting Event "
          "storage");
  picojson::object detail_request;
  detail_request["id"] = picojson::value(event_id);
  const auto &detail = require_success(
      parse_native_result(
          get_event_detail_v2(picojson::value(detail_request).serialize()),
          "additive runtime event detail"),
      "additive runtime event detail");
  require(detail.at("event")
                  .get<picojson::object>()
                  .at("category_id")
                  .get<std::string>() == kId1,
          "additive Category initialization must not clear an existing Event "
          "category_id");

  const auto category_path = directory.path() / "categories.json";
  const std::string corrupted =
      R"({"categories":[],"storage_version":2,"unknown":true})";
  write_file(category_path, corrupted);
  const auto failed = parse_native_result(
      initialize_runtime_v2_json(picojson::value(initialize).serialize()),
      "corrupted Category runtime initialize");
  require_failure(failed, "STORAGE_DATA_CORRUPTED",
                  "corrupted Category runtime initialize");
  require(read_file(category_path) == corrupted &&
              read_file(directory.path() / "events.json") == events_before,
          "corrupted Category initialization must preserve Category and Event "
          "files");
}

void test_boundary_storage_restart_and_event_category_id() {
  using excellent_calendar::boundary::api::create_category_v2;
  using excellent_calendar::boundary::api::create_event_v2;
  using excellent_calendar::boundary::api::get_event_detail_v2;
  using excellent_calendar::boundary::api::initialize_runtime_v2_json;
  using excellent_calendar::boundary::api::list_categories_v2;
  using excellent_calendar::boundary::api::update_event_v2;

  TemporaryDirectory directory("boundary");
  const auto initialize = runtime_request(directory.path());
  auto initialized = parse_native_result(
      initialize_runtime_v2_json(picojson::value(initialize).serialize()),
      "runtime.initialize");
  require_success(initialized, "runtime.initialize");

  const std::string name = u8"\u5bb6\u5ead\U0001f3e1";
  auto category_result = parse_native_result(
      create_category_v2(
          picojson::value(
              create_request(name,
                             std::string(u8"  \u4e2d\u6587\u63cf\u8ff0  "),
                             "#39afbd", std::string(u8"\U0001f3e0")))
              .serialize()),
      "category.create");
  const auto &category = require_success(category_result, "category.create");
  const auto category_id = category.at("id").get<std::string>();
  require(
      excellent_calendar::domain::is_canonical_category_uuid_v4(category_id) &&
          category.at("name").get<std::string>() == name &&
          category.at("description").get<std::string>() ==
              u8"\u4e2d\u6587\u63cf\u8ff0" &&
          category.at("color").get<std::string>() == "#39AFBD" &&
          category.at("sort_order").get<double>() == 0.0 &&
          category.at("deleted_at").is<picojson::null>(),
      "Category boundary must return canonical C++ generated fields");
  require(std::filesystem::exists(directory.path() / "categories.json"),
          "category.create must write categories.json in the injected runtime "
          "directory");

  require_failure(parse_native_result(create_category_v2("{}"),
                                      "category.create missing fields"),
                  "CONTRACT_VALIDATION_FAILED",
                  "category.create missing fields");
  auto wrong_version = create_request("Wrong version");
  wrong_version["contract_version"] = picojson::value(1.0);
  require_failure(
      parse_native_result(
          create_category_v2(picojson::value(wrong_version).serialize()),
          "category.create wrong version field"),
      "CONTRACT_VALIDATION_FAILED", "category.create wrong version field");
  require_failure(parse_native_result(list_categories_v2(R"({"unknown":true})"),
                                      "category.list unknown field"),
                  "CONTRACT_VALIDATION_FAILED", "category.list unknown field");

  auto event =
      ordinary_event_request("Category persistence event", category_id);
  auto event_result =
      parse_native_result(create_event_v2(picojson::value(event).serialize()),
                          "event.create with category");
  const auto &created_event =
      require_success(event_result, "event.create with category");
  const auto event_id = created_event.at("id").get<std::string>();
  require(created_event.at("category_id").get<std::string>() == category_id,
          "Event boundary must preserve category_id on create");

  picojson::object update_event;
  update_event["id"] = picojson::value(event_id);
  update_event["title"] = picojson::value("Category persistence event updated");
  const auto &updated_event = require_success(
      parse_native_result(
          update_event_v2(picojson::value(update_event).serialize()),
          "event.update with retained category"),
      "event.update with retained category");
  require(updated_event.at("category_id").get<std::string>() == category_id,
          "partial Event update must not drop category_id");

  auto reopened = parse_native_result(
      initialize_runtime_v2_json(picojson::value(initialize).serialize()),
      "runtime.reinitialize");
  require_success(reopened, "runtime.reinitialize");
  const auto &listed =
      require_success(parse_native_result(list_categories_v2("{}"),
                                          "category.list after restart"),
                      "category.list after restart");
  const auto &items = listed.at("items").get<picojson::array>();
  require(items.size() == 1U &&
              items[0].get<picojson::object>().at("id").get<std::string>() ==
                  category_id &&
              items[0].get<picojson::object>().at("name").get<std::string>() ==
                  name,
          "Category boundary must recover persisted Unicode data "
          "after runtime restart");

  const auto load_detail = [&](const std::string &id,
                               const std::string &context) {
    picojson::object request;
    request["id"] = picojson::value(id);
    auto result = parse_native_result(
        get_event_detail_v2(picojson::value(request).serialize()), context);
    return picojson::object(require_success(result, context));
  };
  const auto detail = load_detail(event_id, "event.detail after restart");
  require(detail.at("event")
                  .get<picojson::object>()
                  .at("category_id")
                  .get<std::string>() == category_id,
          "Event category_id must survive Boundary, Domain, storage, and "
          "runtime restart");
  require(detail.at("category").is<picojson::object>() &&
              detail.at("category").get<picojson::object>().size() == 9U &&
              detail.at("category")
                      .get<picojson::object>()
                      .at("id")
                      .get<std::string>() == category_id &&
              detail.at("category")
                  .get<picojson::object>()
                  .at("deleted_at")
                  .is<picojson::null>(),
          "Event detail must aggregate the active Category after runtime "
          "restart");

  auto dangling_result = parse_native_result(
      create_event_v2(
          picojson::value(ordinary_event_request("Dangling Category",
                                                 std::string(kId2)))
              .serialize()),
      "event.create with dangling category");
  const auto dangling_event =
      picojson::object(require_success(dangling_result,
                                      "event.create with dangling category"));
  const auto dangling_detail = load_detail(
      dangling_event.at("id").get<std::string>(),
      "event.detail with dangling category");
  require(dangling_detail.at("category").is<picojson::null>() &&
              dangling_detail.at("event")
                      .get<picojson::object>()
                      .at("category_id")
                      .get<std::string>() == kId2,
          "dangling Category projection must be null without clearing the "
          "Event category_id");

  auto unclassified_result = parse_native_result(
      create_event_v2(
          picojson::value(
              ordinary_event_request("Unclassified Event", std::nullopt))
              .serialize()),
      "event.create without category");
  const auto unclassified_event = picojson::object(
      require_success(unclassified_result, "event.create without category"));
  const auto unclassified_detail = load_detail(
      unclassified_event.at("id").get<std::string>(),
      "event.detail without category");
  require(unclassified_detail.at("category").is<picojson::null>() &&
              unclassified_detail.at("event")
                  .get<picojson::object>()
                  .at("category_id")
                  .is<picojson::null>(),
          "unclassified Event detail must preserve the null association");

  const auto category_path = directory.path() / "categories.json";
  picojson::value category_root;
  require(picojson::parse(category_root, read_file(category_path)).empty() &&
              category_root.is<picojson::object>(),
          "soft-delete Category fixture must parse");
  auto &category_records = category_root.get<picojson::object>()
                               .at("categories")
                               .get<picojson::array>();
  require(category_records.size() == 1U,
          "soft-delete Category fixture must contain one record");
  auto &category_record = category_records.front().get<picojson::object>();
  category_record["deleted_at"] = category_record.at("updated_at");
  write_file(category_path, category_root.serialize());
  require_success(
      parse_native_result(
          initialize_runtime_v2_json(picojson::value(initialize).serialize()),
          "runtime.reinitialize after Category soft delete"),
      "runtime.reinitialize after Category soft delete");
  const auto deleted_detail =
      load_detail(event_id, "event.detail with soft-deleted category");
  require(deleted_detail.at("category").is<picojson::null>() &&
              deleted_detail.at("event")
                      .get<picojson::object>()
                      .at("category_id")
                      .get<std::string>() == category_id,
          "soft-deleted Category projection must be null without clearing the "
          "persisted Event category_id");
}

} // namespace

int main() {
  try {
    test_boundary_contract_codecs_and_unicode();
    test_service_rules_and_error_mapping();
    test_sort_order_safe_integer_boundaries();
    test_repository_persistence_sort_and_restart();
    test_storage_corruption_unknown_version_and_write_failure();
    test_atomic_write_failure_injection_and_retry();
    test_additive_runtime_initialization_preserves_existing_v2_data();
    test_boundary_storage_restart_and_event_category_id();
    std::cout << "category core tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "category core tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
