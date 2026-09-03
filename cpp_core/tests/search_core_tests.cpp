#include <array>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/domain/search.hpp"
#include "excellent_calendar/application/search_query_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/api/search_api.hpp"
#include "excellent_calendar/common/search_token_crypto.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"
#include "excellent_calendar/repository/search_query_repository.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_repository_adapters.hpp"

namespace {

using excellent_calendar::domain::SearchMatchField;
using excellent_calendar::domain::SearchRelevanceTier;
using excellent_calendar::domain::SearchTargetType;

class FakeSearchRepository final
    : public excellent_calendar::repository::SearchQueryRepository {
 public:
  excellent_calendar::common::Result<excellent_calendar::common::Unit>
  initialize() override {
    return excellent_calendar::common::Result<
        excellent_calendar::common::Unit>::success({});
  }

  excellent_calendar::common::Result<
      excellent_calendar::repository::SearchQuerySnapshot>
  load_snapshot(
      const std::vector<SearchTargetType>& targets,
      const std::optional<std::array<std::int64_t,
          excellent_calendar::repository::kSearchQueryContributingStores.size()>>&
          expected) override {
    std::array<bool, 8> mask{};
    for (const auto target : targets) {
      mask[3] = true;
      if (target == SearchTargetType::event) mask[0] = mask[1] = mask[2] = true;
      if (target == SearchTargetType::habit) mask[4] = mask[5] = true;
      if (target == SearchTargetType::anniversary) mask[6] = mask[7] = true;
    }
    if (expected.has_value()) {
      for (std::size_t index = 0; index < mask.size(); ++index) {
        if (mask[index] && (*expected)[index] != snapshot.generations[index]) {
          return excellent_calendar::common::Result<
              excellent_calendar::repository::SearchQuerySnapshot>::failure(
                  excellent_calendar::common::make_error(
                      "SEARCH_CURSOR_EXPIRED", "Search cursor expired", {}, true));
        }
      }
    }
    auto selected = snapshot;
    if (std::find(targets.begin(), targets.end(), SearchTargetType::event) ==
        targets.end()) {
      selected.events.clear();
      selected.event_recurrences.clear();
      selected.event_occurrence_states.clear();
    }
    if (std::find(targets.begin(), targets.end(), SearchTargetType::habit) ==
        targets.end()) {
      selected.habits.clear();
      selected.habit_recurrences.clear();
    }
    if (std::find(targets.begin(), targets.end(), SearchTargetType::anniversary) ==
        targets.end()) {
      selected.anniversaries.clear();
      selected.anniversary_recurrences.clear();
    }
    return excellent_calendar::common::Result<
        excellent_calendar::repository::SearchQuerySnapshot>::success(
            std::move(selected));
  }

  excellent_calendar::repository::SearchQuerySnapshot snapshot;
};

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

void test_frozen_unicode_normalization() {
  auto normalized = excellent_calendar::domain::normalize_search_keyword(
      "\xE3\x80\x80\xE9\xA1\xB9\xE7\x9B\xAE\xC2\xA0\tMEETING\xE3\x80\x80");
  require(normalized.ok(), "Unicode whitespace keyword must normalize");
  require(normalized.value().display == "项目 MEETING",
          "normalization must trim/collapse frozen whitespace");
  require(normalized.value().comparison == "项目 meeting",
          "comparison must fold ASCII A-Z only");
  require(normalized.value().comparison_tokens.size() == 2U,
          "normalized keyword must tokenize on ASCII space");
}

void test_strict_utf8_rejections() {
  const std::vector<std::string> invalid = {
      std::string("\xC0\xAF", 2), std::string("\xED\xA0\x80", 3),
      std::string("\xF4\x90\x80\x80", 4), std::string("\xE4\xB8", 2)};
  for (const auto& value : invalid) {
    const auto result = excellent_calendar::domain::normalize_search_keyword(value);
    require(!result.ok() && result.error().code == "SEARCH_QUERY_INVALID",
            "malformed keyword UTF-8 must fail explicitly");
  }
  const auto stored =
      excellent_calendar::domain::normalize_searchable_text(invalid.front());
  require(!stored.ok() && stored.error().code == "STORAGE_DATA_CORRUPTED",
          "malformed canonical Store UTF-8 must be corruption");
}

void test_cross_field_and_relevance() {
  auto query = excellent_calendar::domain::normalize_search_keyword("项目 北京");
  require(query.ok(), "search query must normalize");
  auto match = excellent_calendar::domain::match_search_fields(
      query.value(), {{SearchMatchField::title, "项目复盘"},
                      {SearchMatchField::content, "季度会议"},
                      {SearchMatchField::location, "北京"},
                      {SearchMatchField::category_name, "工作"}});
  require(match.ok() && match.value().has_value(),
          "tokens may match across allowed fields with AND semantics");
  require(match.value()->relevance == SearchRelevanceTier::location &&
              match.value()->primary_field == SearchMatchField::location,
          "cross-field relevance must use the worst chosen tier");
  require(match.value()->matched_fields.size() == 2U &&
              match.value()->snippet.has_value() &&
              match.value()->snippet->field == SearchMatchField::location,
          "match projection must expose ordered fields and primary snippet");

  auto exact_query = excellent_calendar::domain::normalize_search_keyword("MEETING");
  auto exact = excellent_calendar::domain::match_search_fields(
      exact_query.value(), {{SearchMatchField::title, "meeting"},
                            {SearchMatchField::content, "ignored"}});
  require(exact.ok() && exact.value().has_value() &&
              exact.value()->relevance == SearchRelevanceTier::title_exact &&
              !exact.value()->snippet.has_value(),
          "ASCII case-insensitive exact title must be top tier");
}

void test_scalar_limits_and_snippet_boundary() {
  const std::string emoji = "\xF0\x9F\x98\x80";
  auto too_many = excellent_calendar::domain::normalize_search_keyword(
      std::string(129U, 'a'));
  require(!too_many.ok(), "keyword above 128 scalars must fail");

  auto query = excellent_calendar::domain::normalize_search_keyword(emoji);
  std::string body;
  for (int index = 0; index < 201; ++index) body += emoji;
  auto match = excellent_calendar::domain::match_search_fields(
      query.value(), {{SearchMatchField::title, "not here"},
                      {SearchMatchField::content, body}});
  require(match.ok() && match.value().has_value() &&
              match.value()->snippet.has_value() &&
              match.value()->snippet->text.size() == 800U &&
              match.value()->snippet->suffix_truncated,
          "snippet must contain at most 200 complete Unicode scalars");
}

std::shared_ptr<excellent_calendar::domain::LocalTimeResolver> resolver() {
  auto created = excellent_calendar::infrastructure::time::
      TzdbLocalTimeResolver::create(EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(created.ok(), "test TZDB resolver must initialize");
  return created.value();
}

excellent_calendar::domain::Event event(std::string id, std::string title,
                                        int second = 0) {
  excellent_calendar::domain::Event value;
  value.id = std::move(id);
  value.title = std::move(title);
  value.content = "项目正文";
  value.start_at = "2026-09-02T01:00:" +
                   std::string(second < 10 ? "0" : "") +
                   std::to_string(second) + "Z";
  value.end_at = "2026-09-02T02:00:" +
                 std::string(second < 10 ? "0" : "") +
                 std::to_string(second) + "Z";
  value.status = "active";
  value.source = "manual";
  value.created_at = "2026-08-01T00:00:00Z";
  value.updated_at = "2026-08-31T00:00:00Z";
  return value;
}

std::string uuid_for(int index) {
  std::ostringstream output;
  output << "10000000-0000-4000-8000-" << std::setfill('0') << std::setw(12)
         << index;
  return output.str();
}

excellent_calendar::application::SearchQuery base_query() {
  excellent_calendar::application::SearchQuery query;
  query.query_generation = 7;
  query.keyword = "\xE3\x80\x80\xE9\xA1\xB9\xE7\x9B\xAE\xE3\x80\x80";
  query.timezone = "Asia/Shanghai";
  query.target_types = {SearchTargetType::event};
  query.category_ids = std::nullopt;
  query.include_completed = true;
  query.sort_by = excellent_calendar::application::SearchSort::relevance;
  query.sections = {{SearchTargetType::event, 20, std::nullopt}};
  return query;
}

void test_hmac_golden_and_tamper() {
  excellent_calendar::common::SearchHmacKey key{};
  for (std::size_t index = 0; index < key.size(); ++index)
    key[index] = static_cast<std::uint8_t>(index);
  const std::vector<std::uint8_t> payload{1, 2, 3};
  const auto token = excellent_calendar::common::encode_authenticated_search_token(
      "srchcur1", "excellent-calendar/search-cursor/v1", payload, key);
  require(token ==
              "srchcur1.AQID-DQFWbBHnpkZHyArZMEeNv2cJPr7oHtIJBPrfCuCQg4",
          "HMAC-SHA-256 token must match the independent golden");
  auto decoded = excellent_calendar::common::decode_authenticated_search_token(
      token, "srchcur1", "excellent-calendar/search-cursor/v1", 2057, key);
  require(decoded.ok() && decoded.value() == payload,
          "authenticated token must round trip");
  auto tampered = token;
  tampered.back() = tampered.back() == 'A' ? 'B' : 'A';
  decoded = excellent_calendar::common::decode_authenticated_search_token(
      tampered, "srchcur1", "excellent-calendar/search-cursor/v1", 2057, key);
  require(!decoded.ok() && decoded.error().code == "SEARCH_CURSOR_INVALID",
          "tampered tag must fail closed");

  const std::vector<std::uint8_t> fixture_payload{
      0x01, 0x00, 0x00, 0x00, 0x0a, 'f', 'i', 'x', 't', 'u', 'r', 'e',
      '-',  'v',  '1'};
  const auto fixture_token =
      excellent_calendar::common::encode_authenticated_search_token(
          "srchcur1", "excellent-calendar/search-cursor/v1", fixture_payload,
          key);
  require(fixture_token ==
              "srchcur1.AQAAAApmaXh0dXJlLXYxt0T0PDe2Oq6ESDRURtet_MVBDLK5EA1vyEMSMw5hRcM",
          "cursor authentication must consume the frozen Contract golden");
  auto wrong_domain =
      excellent_calendar::common::decode_authenticated_search_token(
          "srchsnap1." + fixture_token.substr(9U), "srchsnap1",
          "excellent-calendar/search-snapshot/v1", 522, key);
  require(!wrong_domain.ok() &&
              wrong_domain.error().code == "SEARCH_CURSOR_INVALID",
          "cursor tag must not authenticate under the snapshot domain");
  excellent_calendar::common::SearchHmacKey old_process_key{};
  old_process_key.fill(0x20U);
  auto old_process =
      excellent_calendar::common::decode_authenticated_search_token(
          fixture_token, "srchcur1", "excellent-calendar/search-cursor/v1",
          2057, old_process_key);
  require(!old_process.ok(), "previous-process key must reject the cursor");
  auto padded = excellent_calendar::common::decode_authenticated_search_token(
      fixture_token + "=", "srchcur1",
      "excellent-calendar/search-cursor/v1", 2057, key);
  require(!padded.ok(), "padded non-canonical Base64URL must be rejected");
}

void test_three_section_projection_and_pagination() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  repository->snapshot.events.push_back(event(uuid_for(1), "项目会议"));
  excellent_calendar::domain::HabitRecurrence habit_recurrence;
  habit_recurrence.id = uuid_for(100);
  repository->snapshot.habit_recurrences.push_back(habit_recurrence);
  excellent_calendar::domain::Habit habit;
  habit.id = uuid_for(2);
  habit.title = "项目习惯";
  habit.recurrence_id = habit_recurrence.id;
  habit.start_date = {2026, 8, 1};
  habit.end_date = {2026, 9, 30};
  habit.updated_at = "2026-08-30T00:00:00Z";
  repository->snapshot.habits.push_back(habit);
  excellent_calendar::domain::AnniversaryRecurrence recurrence;
  recurrence.id = uuid_for(101);
  recurrence.frequency = "yearly";
  repository->snapshot.anniversary_recurrences.push_back(recurrence);
  excellent_calendar::domain::Anniversary anniversary;
  anniversary.id = uuid_for(3);
  anniversary.title = "项目纪念日";
  anniversary.date = {2020, 9, 2};
  anniversary.calendar_type = "solar";
  anniversary.recurrence_id = recurrence.id;
  anniversary.updated_at = "2026-08-29T00:00:00Z";
  repository->snapshot.anniversaries.push_back(anniversary);
  excellent_calendar::common::SearchHmacKey key{};
  excellent_calendar::application::SearchQueryService service(
      repository, resolver(),
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          resolver()),
      [] { return std::string("2026-09-01T00:00:00Z"); }, key);
  auto query = base_query();
  query.target_types = {SearchTargetType::event, SearchTargetType::habit,
                        SearchTargetType::anniversary};
  query.sections = {{SearchTargetType::event, 20, std::nullopt},
                    {SearchTargetType::habit, 20, std::nullopt},
                    {SearchTargetType::anniversary, 20, std::nullopt}};
  auto response = service.query(query);
  require(response.ok() && response.value().sections.size() == 3U,
          "initial query must return all requested typed sections");
  require(response.value().normalized_keyword == "项目" &&
              response.value().sections[0].items.size() == 1U &&
              response.value().sections[1].items.size() == 1U &&
              response.value().sections[2].items.size() == 1U,
          "three canonical Stores must project one logical result each");

  repository->snapshot.events.clear();
  for (int index = 1; index <= 21; ++index)
    repository->snapshot.events.push_back(
        event(uuid_for(index), "项目 " + std::to_string(index), index % 60));
  query = base_query();
  auto first = service.query(query);
  require(first.ok() && first.value().sections[0].items.size() == 20U &&
              first.value().sections[0].total_count == 21 &&
              first.value().sections[0].has_more &&
              first.value().sections[0].next_cursor.has_value(),
          "21 results must produce an exact 20-item first page");
  query.query_generation = 8;
  query.sections[0].cursor = first.value().sections[0].next_cursor;
  repository->snapshot.generations[4] += 1;
  auto second = service.query(query);
  require(second.ok() && second.value().sections[0].items.size() == 1U &&
              !second.value().sections[0].has_more &&
              second.value().snapshot_token == first.value().snapshot_token &&
              second.value().evaluated_at == first.value().evaluated_at,
          "unrelated Habit mutation must not expire Event continuation");
  repository->snapshot.generations[0] += 1;
  auto expired = service.query(query);
  require(!expired.ok() && expired.error().code == "SEARCH_CURSOR_EXPIRED",
          "Event Store mutation must expire Event continuation");

  repository->snapshot.generations[0] -= 1;
  query = base_query();
  query.category_ids = std::vector<std::string>{};
  for (int index = 0; index < 100; ++index)
    query.category_ids->push_back(uuid_for(1000 + index));
  for (auto& item : repository->snapshot.events)
    item.category_id = query.category_ids->front();
  auto large_binding = service.query(query);
  require(large_binding.ok() &&
              large_binding.value().sections[0].next_cursor.has_value() &&
              large_binding.value().sections[0].next_cursor->size() <= 2057U,
          "100 Category IDs must still produce a Contract-sized opaque cursor");
  query.sections[0].cursor = large_binding.value().sections[0].next_cursor;
  query.keyword = "different";
  auto mismatch = service.query(query);
  require(!mismatch.ok() &&
              mismatch.error().code == "SEARCH_CURSOR_QUERY_MISMATCH",
          "cursor must bind normalized keyword and filters");
  query.keyword = "项目";
  auto tampered_cursor = *query.sections[0].cursor;
  tampered_cursor.back() = tampered_cursor.back() == 'A' ? 'B' : 'A';
  query.sections[0].cursor = tampered_cursor;
  auto invalid = service.query(query);
  require(!invalid.ok() && invalid.error().code == "SEARCH_CURSOR_INVALID",
          "cursor payload/tag tamper must fail authentication");
}

std::string read_fixture(std::string_view name) {
  std::ifstream input(std::filesystem::path(EXCELLENT_CALENDAR_SEARCH_FIXTURE_DIR) /
                          std::string(name),
                      std::ios::binary);
  std::ostringstream output;
  output << input.rdbuf();
  require(input.good() || input.eof(), "Search fixture must be readable");
  return output.str();
}

std::pair<bool, std::string> native_result(std::string_view json) {
  picojson::value value;
  const auto parse_error = picojson::parse(value, std::string(json));
  require(parse_error.empty() && value.is<picojson::object>(),
          "Search endpoint must return a NativeResult object");
  const auto& object = value.get<picojson::object>();
  require(object.size() == 5U && object.count("ok") == 1U &&
              object.count("data") == 1U && object.count("error") == 1U &&
              object.count("contract_version") == 1U &&
              object.count("request_id") == 1U,
          "Search endpoint must return exact NativeResult v2 fields");
  const bool ok = object.at("ok").get<bool>();
  if (ok) return {true, ""};
  const auto& error = object.at("error").get<picojson::object>();
  return {false, error.at("code").get<std::string>()};
}

void test_contract_request_fixtures_at_boundary() {
  const auto directory = std::filesystem::temp_directory_path() /
                         ("excellent_calendar_search_boundary_" + uuid_for(900));
  std::filesystem::create_directories(directory);
  auto initialized = excellent_calendar::boundary::api::initialize_recurring_runtime(
      directory.string(), EXCELLENT_CALENDAR_TEST_TZDB_DIR);
  require(initialized.ok(), "Search Boundary runtime must initialize");
  for (const auto* fixture : {"query_three_sections.valid.json",
                              "query_uncategorized_only.valid.json"}) {
    const auto result = native_result(
        excellent_calendar::boundary::api::search_query_v2(read_fixture(fixture)));
    require(result.first, std::string(fixture) + " must succeed at C++ Boundary");
  }
  const std::vector<std::pair<const char*, const char*>> failures{
      {"query_reversed_range.semantic_invalid.json", "SEARCH_QUERY_INVALID"},
      {"query_blank.semantic_invalid.json", "SEARCH_QUERY_INVALID"},
      {"query_section_mismatch.semantic_invalid.json", "SEARCH_QUERY_INVALID"},
      {"query_multi_cursor.semantic_invalid.json", "SEARCH_QUERY_INVALID"},
      {"query_bad_cursor.invalid.json", "CONTRACT_VALIDATION_FAILED"},
      {"query_page_size_100.invalid.json", "CONTRACT_VALIDATION_FAILED"},
      {"query_target_order.semantic_invalid.json", "SEARCH_QUERY_INVALID"},
  };
  for (const auto& [fixture, expected] : failures) {
    const auto result = native_result(
        excellent_calendar::boundary::api::search_query_v2(read_fixture(fixture)));
    require(!result.first && result.second == expected,
            std::string(fixture) + " must return " + expected);
  }
  picojson::value valid_value;
  require(picojson::parse(valid_value,
                          read_fixture("query_three_sections.valid.json"))
              .empty(),
          "Boundary mutation fixture must parse");
  const auto require_contract_failure = [&](picojson::object object,
                                            const std::string& context) {
    const auto result = native_result(
        excellent_calendar::boundary::api::search_query_v2(
            picojson::value(std::move(object)).serialize()));
    require(!result.first && result.second == "CONTRACT_VALIDATION_FAILED",
            context + " must fail strict Boundary validation");
  };
  auto object = valid_value.get<picojson::object>();
  object.erase("keyword");
  require_contract_failure(std::move(object), "missing field");
  object = valid_value.get<picojson::object>();
  object["extra"] = picojson::value(true);
  require_contract_failure(std::move(object), "extra field");
  object = valid_value.get<picojson::object>();
  object["timezone"] = picojson::value();
  require_contract_failure(std::move(object), "null required field");
  object = valid_value.get<picojson::object>();
  object["query_generation"] = picojson::value("7");
  require_contract_failure(std::move(object), "wrong scalar type");
  object = valid_value.get<picojson::object>();
  object["sort_by"] = picojson::value("unknown");
  require_contract_failure(std::move(object), "unknown enum");
  object = valid_value.get<picojson::object>();
  object["date_from"] = picojson::value("2026-02-30");
  object["date_to_exclusive"] = picojson::value("2026-03-01");
  require_contract_failure(std::move(object), "invalid date");
  object = valid_value.get<picojson::object>();
  object["query_generation"] = picojson::value(9007199254740992.0);
  require_contract_failure(std::move(object), "unsafe integer");
  auto invalid_utf8 = read_fixture("query_three_sections.valid.json");
  invalid_utf8.insert(invalid_utf8.find("项目"), std::string("\xC0\xAF", 2));
  const auto utf8_result = native_result(
      excellent_calendar::boundary::api::search_query_v2(invalid_utf8));
  require(!utf8_result.first &&
              utf8_result.second == "CONTRACT_VALIDATION_FAILED",
          "invalid request UTF-8 must fail strict Boundary validation");
  std::error_code ignored;
  std::filesystem::remove_all(directory, ignored);
}

std::string read_bytes(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  std::ostringstream output;
  output << input.rdbuf();
  return output.str();
}

void test_real_sqlite_snapshot_generations_and_zero_write() {
  const auto directory = std::filesystem::temp_directory_path() /
                         ("excellent_calendar_search_sqlite_" + uuid_for(901));
  std::filesystem::create_directories(directory);
  auto opened = excellent_calendar::storage::sqlite::SqliteCalendarDatabase::open(
      directory);
  require(opened.ok(), "real SQLite v5 Search database must open");
  auto repository = std::make_shared<
      excellent_calendar::storage::sqlite::SqliteSearchQueryRepository>(
      opened.value());
  require(repository->initialize().ok(), "Search SQLite repository must initialize");
  const auto before_bytes = read_bytes(opened.value()->database_path());
  auto first = repository->load_snapshot({SearchTargetType::event});
  require(first.ok() && first.value().events.empty() &&
              first.value().habits.empty() &&
              first.value().anniversaries.empty(),
          "Event-only snapshot must not load unrelated target Stores");
  const auto after_bytes = read_bytes(opened.value()->database_path());
  require(before_bytes == after_bytes,
          "deferred Search read transaction must perform zero database writes");

  excellent_calendar::repository::HabitState habit_before;
  excellent_calendar::repository::HabitState habit_after;
  excellent_calendar::domain::HabitRecurrence recurrence;
  recurrence.id = uuid_for(902);
  recurrence.frequency = "daily";
  recurrence.interval = 1;
  recurrence.timezone_mode = "follow_device";
  recurrence.created_at = "2026-09-01T00:00:00Z";
  recurrence.updated_at = recurrence.created_at;
  excellent_calendar::domain::Habit habit;
  habit.id = uuid_for(903);
  habit.title = "项目 SQLite Habit";
  habit.recurrence_id = recurrence.id;
  habit.start_date = {2026, 9, 1};
  habit.end_date = {2026, 9, 10};
  habit.created_at = recurrence.created_at;
  habit.updated_at = recurrence.updated_at;
  habit_after.recurrences.push_back(recurrence);
  habit_after.habits.push_back(habit);
  require(opened.value()->write_habit_changes(habit_before, habit_after).ok(),
          "unrelated Habit mutation fixture must commit");
  auto unaffected = repository->load_snapshot(
      {SearchTargetType::event}, first.value().generations);
  require(unaffected.ok(),
          "Habit mutation must not expire an Event-only Search snapshot");

  excellent_calendar::repository::CategoryState category_before;
  excellent_calendar::repository::CategoryState category_after;
  excellent_calendar::domain::Category category;
  category.id = uuid_for(904);
  category.name = "项目分类";
  category.color = "#112233";
  category.sort_order = 0;
  category.created_at = "2026-09-01T00:00:00Z";
  category.updated_at = category.created_at;
  category_after.categories.push_back(category);
  require(opened.value()
              ->write_category_changes(category_before, category_after)
              .ok(),
          "Category mutation fixture must commit");
  auto expired = repository->load_snapshot(
      {SearchTargetType::event}, first.value().generations);
  require(!expired.ok() && expired.error().code == "SEARCH_CURSOR_EXPIRED",
          "Category mutation must expire every target Search cursor");
  repository.reset();
  opened.value().reset();
  std::error_code ignored;
  std::filesystem::remove_all(directory, ignored);
}

excellent_calendar::application::SearchQueryService make_service(
    const std::shared_ptr<FakeSearchRepository>& repository,
    std::string clock) {
  auto time_resolver = resolver();
  return excellent_calendar::application::SearchQueryService(
      repository, time_resolver,
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          time_resolver),
      [clock = std::move(clock)] { return clock; }, {});
}

void test_event_occurrence_selection_dst_and_status() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  auto recurring_event = event(uuid_for(2000), "项目 recurring");
  recurring_event.start_at = "2026-08-30T01:00:00Z";
  recurring_event.end_at = "2026-08-30T02:00:00Z";
  recurring_event.timezone = "Asia/Shanghai";
  recurring_event.has_recurrence = true;
  recurring_event.recurrence_id = uuid_for(2001);
  recurring_event.recurrence_revision = 1;
  excellent_calendar::domain::Recurrence recurrence;
  recurrence.id = *recurring_event.recurrence_id;
  recurrence.revision = 1;
  recurrence.frequency = "daily";
  recurrence.interval = 1;
  recurrence.start_at = recurring_event.start_at;
  recurrence.timezone = "Asia/Shanghai";
  recurrence.created_at = "2026-08-01T00:00:00Z";
  repository->snapshot.events.push_back(recurring_event);
  repository->snapshot.event_recurrences.push_back(recurrence);
  auto time_resolver = resolver();
  excellent_calendar::application::RecurrenceService expansion(time_resolver);
  auto closed_occurrence = expansion.occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(recurring_event),
      recurrence, 1);
  require(closed_occurrence.ok(), "recurring selection fixture must expand");
  excellent_calendar::domain::EventOccurrenceState state;
  state.event_id = recurring_event.id;
  state.recurrence_revision = 1;
  state.occurrence_key = closed_occurrence.value().occurrence_key;
  state.occurrence_start_at =
      closed_occurrence.value().occurrence_start_at;
  state.status = "completed";
  state.state_changed_at = "2026-08-31T03:00:00Z";
  state.created_at = state.state_changed_at;
  state.updated_at = state.state_changed_at;
  repository->snapshot.event_occurrence_states.push_back(state);
  excellent_calendar::application::SearchQueryService service(
      repository, time_resolver,
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          time_resolver),
      [] { return std::string("2026-08-31T12:00:00Z"); }, {});
  auto query = base_query();
  query.date_from = excellent_calendar::domain::LocalDate{1900, 1, 1};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2100, 1, 1};
  query.include_completed = true;
  auto completed = service.query(query);
  require(completed.ok() && completed.value().sections[0].items.size() == 1U,
          "recurring Event must project one logical item");
  const auto& completed_item = std::get<
      excellent_calendar::application::SearchEventItem>(
      completed.value().sections[0].items.front());
  require(completed_item.status == "completed" &&
              completed_item.occurrence_key ==
                  std::optional<std::string>(state.occurrence_key),
          "nearest closed occurrence must beat farther open occurrences in range");
  query.include_completed = false;
  auto open = service.query(query);
  require(open.ok() && open.value().sections[0].items.size() == 1U,
          "open recurring occurrence projection must succeed");
  const auto& open_item = std::get<excellent_calendar::application::SearchEventItem>(
      open.value().sections[0].items.front());
  require(open_item.status != "completed" &&
              open_item.occurrence_key != completed_item.occurrence_key,
          "include_completed=false must select the nearest eligible open occurrence");

  repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  auto overlap = event(uuid_for(2010), "项目 DST overlap");
  overlap.start_at = "2026-03-28T22:59:59Z";
  overlap.end_at = "2026-03-28T23:00:01Z";
  overlap.timezone = "Europe/Berlin";
  auto outside = event(uuid_for(2011), "项目 DST outside");
  outside.start_at = "2026-03-29T22:00:00Z";
  outside.end_at = "2026-03-29T23:00:00Z";
  outside.timezone = "Europe/Berlin";
  repository->snapshot.events = {overlap, outside};
  auto dst_service = make_service(repository, "2026-03-29T12:00:00Z");
  query = base_query();
  query.timezone = "Europe/Berlin";
  query.date_from = excellent_calendar::domain::LocalDate{2026, 3, 29};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 3, 30};
  auto dst = dst_service.query(query);
  require(dst.ok() && dst.value().sections[0].total_count == 1 &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  dst.value().sections[0].items.front())
                      .target_id == overlap.id,
          "23-hour DST window must use exact half-open instant overlap");

  repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  auto all_day = event(uuid_for(2020), "项目 all day");
  all_day.is_all_day = true;
  all_day.start_at.clear();
  all_day.end_at.clear();
  all_day.start_date = "2026-09-01";
  all_day.end_date = "2026-09-03";
  all_day.timezone = "Asia/Shanghai";
  repository->snapshot.events = {all_day};
  auto all_day_service = make_service(repository, "2026-08-31T16:00:00Z");
  query = base_query();
  auto all_day_result = all_day_service.query(query);
  require(all_day_result.ok() &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  all_day_result.value().sections[0].items.front())
                      .status == "in_progress",
          "all-day status must use request-timezone local date and half-open dates");

  auto timed_same_day = event(uuid_for(2021), "项目 timed same day");
  timed_same_day.start_at = "2026-09-01T20:00:00Z";
  timed_same_day.end_at = "2026-09-01T21:00:00Z";
  timed_same_day.timezone = "Asia/Shanghai";
  auto all_day_same_day = all_day;
  all_day_same_day.start_date = "2026-09-02";
  all_day_same_day.end_date = "2026-09-03";
  repository->snapshot.events = {timed_same_day, all_day_same_day};
  query.sort_by = excellent_calendar::application::SearchSort::occur_time;
  auto mixed = all_day_service.query(query);
  require(mixed.ok() && mixed.value().sections[0].items.size() == 2U &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  mixed.value().sections[0].items.front())
                  .is_all_day,
          "mixed Event occur_time must compare local date then all-day before local time");
}

void test_completed_recurring_series_cutoff() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);

  auto overlaps_cutoff = event(uuid_for(2030), "项目 cutoff overlap");
  overlaps_cutoff.start_at = "2026-08-13T02:00:00Z";
  overlaps_cutoff.end_at = "2026-08-13T04:00:00Z";
  overlaps_cutoff.timezone = "Asia/Shanghai";
  overlaps_cutoff.has_recurrence = true;
  overlaps_cutoff.recurrence_id = uuid_for(2031);
  overlaps_cutoff.recurrence_revision = 1;
  overlaps_cutoff.status = "completed";
  overlaps_cutoff.completed_at = "2026-08-15T03:00:00Z";

  auto exact_cutoff = event(uuid_for(2032), "项目 cutoff exact");
  exact_cutoff.start_at = "2026-08-15T03:00:00Z";
  exact_cutoff.end_at = "2026-08-15T04:00:00Z";
  exact_cutoff.timezone = "Asia/Shanghai";
  exact_cutoff.has_recurrence = true;
  exact_cutoff.recurrence_id = uuid_for(2033);
  exact_cutoff.recurrence_revision = 1;
  exact_cutoff.status = "completed";
  exact_cutoff.completed_at = "2026-08-15T03:00:00Z";

  repository->snapshot.events = {overlaps_cutoff, exact_cutoff};
  for (const auto& value : repository->snapshot.events) {
    excellent_calendar::domain::Recurrence recurrence;
    recurrence.id = *value.recurrence_id;
    recurrence.revision = 1;
    recurrence.frequency = "daily";
    recurrence.interval = 1;
    recurrence.start_at = value.start_at;
    recurrence.timezone = *value.timezone;
    recurrence.created_at = "2026-08-01T00:00:00Z";
    repository->snapshot.event_recurrences.push_back(std::move(recurrence));
  }

  auto service = make_service(repository, "2026-09-01T12:00:00Z");
  auto query = base_query();
  auto response = service.query(query);
  require(response.ok(), "completed recurring Search query must succeed");
  const auto& section = response.value().sections.front();
  require(section.total_count == 1 && section.items.size() == 1U,
          "series with no occurrence before completed_at must be absent");
  const auto& selected =
      std::get<excellent_calendar::application::SearchEventItem>(
          section.items.front());
  require(selected.target_id == overlaps_cutoff.id &&
              selected.occur_at ==
                  std::optional<std::string>("2026-08-15T02:00:00Z"),
          "no-date Search must select the last occurrence strictly before "
          "completed_at and retain its full interval");

  query.date_from = excellent_calendar::domain::LocalDate{2026, 8, 15};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 8, 16};
  auto completion_day = service.query(query);
  require(completion_day.ok() &&
              completion_day.value().sections.front().total_count == 1 &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  completion_day.value().sections.front().items.front())
                      .occur_at == selected.occur_at,
          "an occurrence starting before cutoff must keep its full interval "
          "for date overlap");

  query.date_from = excellent_calendar::domain::LocalDate{2026, 8, 16};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 8, 17};
  auto after_cutoff = service.query(query);
  require(after_cutoff.ok() &&
              after_cutoff.value().sections.front().items.empty(),
          "occurrences starting after completed_at must not exist in Search");

  query.date_from.reset();
  query.date_to_exclusive.reset();
  query.include_completed = false;
  auto hidden_completed = service.query(query);
  require(hidden_completed.ok() &&
              hidden_completed.value().sections.front().items.empty(),
          "include_completed=false must run after cutoff and hide retained "
          "completed occurrences");

  auto future_repository = std::make_shared<FakeSearchRepository>();
  future_repository->snapshot.generations.fill(1);
  auto completed_before_query_clock = overlaps_cutoff;
  completed_before_query_clock.id = uuid_for(2034);
  completed_before_query_clock.recurrence_id = uuid_for(2035);
  completed_before_query_clock.completed_at = "2026-08-20T03:00:00Z";
  auto future_recurrence = repository->snapshot.event_recurrences.front();
  future_recurrence.id = *completed_before_query_clock.recurrence_id;
  future_repository->snapshot.events.push_back(completed_before_query_clock);
  future_repository->snapshot.event_recurrences.push_back(future_recurrence);
  auto future_clock_service =
      make_service(future_repository, "2026-08-14T00:00:00Z");
  query = base_query();
  auto future_clock_result = future_clock_service.query(query);
  require(future_clock_result.ok() &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  future_clock_result.value().sections.front().items.front())
                      .occur_at ==
                  std::optional<std::string>("2026-08-20T02:00:00Z"),
          "completed series without a date range must select its last eligible "
          "occurrence even when the frozen query clock is earlier than cutoff");
}

void test_completed_all_day_cutoff_timezone_and_explicit_state() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);

  auto all_day = event(uuid_for(2040), "项目 all-day cutoff");
  all_day.start_at.clear();
  all_day.end_at.clear();
  all_day.start_date = "2026-10-31";
  all_day.end_date = "2026-11-02";
  all_day.is_all_day = true;
  all_day.timezone = "America/Los_Angeles";
  all_day.has_recurrence = true;
  all_day.recurrence_id = uuid_for(2041);
  all_day.recurrence_revision = 1;
  all_day.status = "completed";
  all_day.completed_at = "2026-11-01T07:00:00Z";

  excellent_calendar::domain::Recurrence recurrence;
  recurrence.id = *all_day.recurrence_id;
  recurrence.revision = 1;
  recurrence.frequency = "daily";
  recurrence.interval = 1;
  recurrence.start_date = all_day.start_date;
  recurrence.timezone = *all_day.timezone;
  recurrence.created_at = "2026-10-01T00:00:00Z";
  repository->snapshot.events.push_back(all_day);
  repository->snapshot.event_recurrences.push_back(recurrence);

  auto time_resolver = resolver();
  excellent_calendar::application::RecurrenceService expansion(time_resolver);
  auto exact_cutoff = expansion.occurrence_at(
      excellent_calendar::domain::recurring_schedule_from_event(all_day),
      recurrence, 1);
  require(exact_cutoff.ok() &&
              exact_cutoff.value().occurrence_start_date ==
                  std::optional<std::string>("2026-11-01"),
          "all-day exact-cutoff fixture must expand across the DST fold");
  excellent_calendar::domain::EventOccurrenceState post_cutoff_state;
  post_cutoff_state.event_id = all_day.id;
  post_cutoff_state.recurrence_revision = 1;
  post_cutoff_state.occurrence_key = exact_cutoff.value().occurrence_key;
  post_cutoff_state.occurrence_start_date =
      exact_cutoff.value().occurrence_start_date;
  post_cutoff_state.status = "skipped";
  post_cutoff_state.state_changed_at = "2026-11-01T08:00:00Z";
  post_cutoff_state.created_at = post_cutoff_state.state_changed_at;
  post_cutoff_state.updated_at = post_cutoff_state.state_changed_at;
  repository->snapshot.event_occurrence_states.push_back(
      std::move(post_cutoff_state));

  excellent_calendar::application::SearchQueryService service(
      repository, time_resolver,
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          time_resolver),
      [] { return std::string("2026-11-01T12:00:00Z"); }, {});
  auto query = base_query();
  query.timezone = "America/Los_Angeles";
  query.date_from = excellent_calendar::domain::LocalDate{2026, 11, 1};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 11, 2};
  auto retained = service.query(query);
  require(retained.ok() && retained.value().sections.front().total_count == 1,
          "all-day occurrence before recurrence-zone midnight cutoff must be retained");
  const auto& retained_item =
      std::get<excellent_calendar::application::SearchEventItem>(
          retained.value().sections.front().items.front());
  require(retained_item.occur_date ==
              std::optional<excellent_calendar::domain::LocalDate>(
                  {2026, 10, 31}) &&
              retained_item.status == "completed",
          "pre-cutoff all-day occurrence must retain its cross-cutoff, "
          "cross-DST interval");

  query.date_from = excellent_calendar::domain::LocalDate{2026, 11, 2};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 11, 3};
  auto state_cannot_restore = service.query(query);
  require(state_cannot_restore.ok() &&
              state_cannot_restore.value().sections.front().items.empty(),
          "an explicit skipped/completed state must not restore an "
          "occurrence at or after cutoff");

  query.date_from = excellent_calendar::domain::LocalDate{2026, 11, 1};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 11, 2};
  query.include_completed = false;
  auto hidden = service.query(query);
  require(hidden.ok() && hidden.value().sections.front().items.empty(),
          "include_completed=false must hide retained all-day completion history");

  auto future_repository = std::make_shared<FakeSearchRepository>();
  future_repository->snapshot.generations.fill(1);
  auto future_cutoff = all_day;
  future_cutoff.id = uuid_for(2042);
  future_cutoff.recurrence_id = uuid_for(2043);
  future_cutoff.start_date = "2026-10-01";
  future_cutoff.end_date = "2026-10-02";
  future_cutoff.completed_at = "2026-11-10T08:00:00Z";
  auto future_rule = recurrence;
  future_rule.id = *future_cutoff.recurrence_id;
  future_rule.start_date = future_cutoff.start_date;
  future_repository->snapshot.events.push_back(future_cutoff);
  future_repository->snapshot.event_recurrences.push_back(future_rule);
  excellent_calendar::application::SearchQueryService future_service(
      future_repository, time_resolver,
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          time_resolver),
      [] { return std::string("2026-11-01T12:00:00Z"); }, {});
  query = base_query();
  query.timezone = "America/Los_Angeles";
  query.date_from = excellent_calendar::domain::LocalDate{2026, 11, 1};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2026, 11, 2};
  auto range_before_cutoff = future_service.query(query);
  require(range_before_cutoff.ok() &&
              std::get<excellent_calendar::application::SearchEventItem>(
                  range_before_cutoff.value().sections.front().items.front())
                      .occur_date ==
                  std::optional<excellent_calendar::domain::LocalDate>(
                      {2026, 11, 1}),
          "a date-filtered all-day query must seek inside the requested range "
          "when completed_at is later than the frozen query clock");
}

void test_completed_series_cutoff_total_and_cursor() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  for (int index = 0; index < 21; ++index) {
    auto value = event(uuid_for(2200 + index),
                       "项目 cutoff page " + std::to_string(index));
    value.start_at = "2026-08-13T02:00:00Z";
    value.end_at = "2026-08-13T04:00:00Z";
    value.timezone = "Asia/Shanghai";
    value.has_recurrence = true;
    value.recurrence_id = uuid_for(2300 + index);
    value.recurrence_revision = 1;
    value.status = "completed";
    value.completed_at = "2026-08-15T03:00:00Z";
    excellent_calendar::domain::Recurrence recurrence;
    recurrence.id = *value.recurrence_id;
    recurrence.revision = 1;
    recurrence.frequency = "daily";
    recurrence.interval = 1;
    recurrence.start_at = value.start_at;
    recurrence.timezone = *value.timezone;
    recurrence.created_at = "2026-08-01T00:00:00Z";
    repository->snapshot.events.push_back(std::move(value));
    repository->snapshot.event_recurrences.push_back(std::move(recurrence));
  }
  auto no_eligible = event(uuid_for(2400), "项目 cutoff page excluded");
  no_eligible.start_at = "2026-08-15T03:00:00Z";
  no_eligible.end_at = "2026-08-15T04:00:00Z";
  no_eligible.timezone = "Asia/Shanghai";
  no_eligible.has_recurrence = true;
  no_eligible.recurrence_id = uuid_for(2401);
  no_eligible.recurrence_revision = 1;
  no_eligible.status = "completed";
  no_eligible.completed_at = "2026-08-15T03:00:00Z";
  excellent_calendar::domain::Recurrence excluded_recurrence;
  excluded_recurrence.id = *no_eligible.recurrence_id;
  excluded_recurrence.revision = 1;
  excluded_recurrence.frequency = "daily";
  excluded_recurrence.interval = 1;
  excluded_recurrence.start_at = no_eligible.start_at;
  excluded_recurrence.timezone = *no_eligible.timezone;
  excluded_recurrence.created_at = "2026-08-01T00:00:00Z";
  repository->snapshot.events.push_back(no_eligible);
  repository->snapshot.event_recurrences.push_back(excluded_recurrence);

  auto service = make_service(repository, "2026-09-01T12:00:00Z");
  auto query = base_query();
  auto first = service.query(query);
  require(first.ok() && first.value().sections.front().total_count == 21 &&
              first.value().sections.front().items.size() == 20U &&
              first.value().sections.front().has_more &&
              first.value().sections.front().next_cursor.has_value(),
          "cutoff eligibility must feed exact total before first-page cursor creation");

  std::set<std::string> identities;
  for (const auto& item : first.value().sections.front().items) {
    identities.insert(
        std::get<excellent_calendar::application::SearchEventItem>(item)
            .target_id);
  }
  query.query_generation += 1;
  query.sections.front().cursor =
      first.value().sections.front().next_cursor;
  auto second = service.query(query);
  require(second.ok() && second.value().sections.front().total_count == 21 &&
              second.value().sections.front().items.size() == 1U &&
              !second.value().sections.front().has_more &&
              !second.value().sections.front().next_cursor.has_value(),
          "cutoff-filtered total must stay constant through the cursor chain");
  identities.insert(
      std::get<excellent_calendar::application::SearchEventItem>(
          second.value().sections.front().items.front())
          .target_id);
  require(identities.size() == 21U &&
              identities.find(no_eligible.id) == identities.end(),
          "cutoff filtering must produce no duplicate, missing, or restored "
          "identity across pages");
}

void test_long_occurrence_state_history_has_bounded_expansion() {
  constexpr int kClosedOccurrences = 100000;
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  auto recurring_event = event(uuid_for(2050), "项目 long history");
  recurring_event.is_all_day = true;
  recurring_event.start_at.clear();
  recurring_event.end_at.clear();
  recurring_event.start_date = "1900-01-01";
  recurring_event.end_date = "1900-01-02";
  recurring_event.timezone = "Asia/Shanghai";
  recurring_event.has_recurrence = true;
  recurring_event.recurrence_id = uuid_for(2051);
  recurring_event.recurrence_revision = 1;
  excellent_calendar::domain::Recurrence recurrence;
  recurrence.id = *recurring_event.recurrence_id;
  recurrence.revision = 1;
  recurrence.frequency = "daily";
  recurrence.interval = 1;
  recurrence.start_date = recurring_event.start_date;
  recurrence.timezone = "Asia/Shanghai";
  recurrence.created_at = "1900-01-01T00:00:00Z";
  repository->snapshot.events.push_back(recurring_event);
  repository->snapshot.event_recurrences.push_back(recurrence);

  auto time_resolver = resolver();
  excellent_calendar::application::RecurrenceService expansion(time_resolver);
  const auto schedule =
      excellent_calendar::domain::recurring_schedule_from_event(recurring_event);
  const auto original = excellent_calendar::domain::LocalDate{1900, 1, 1};
  const auto today = excellent_calendar::domain::LocalDate{2026, 9, 1};
  const int near = excellent_calendar::domain::local_days_between(original, today);
  std::map<int, std::string> candidate_keys;
  for (const int index : {0, 1, 2, near - 4, near - 3, near - 2, near - 1,
                          near, near + 1, near + 2, near + 3, near + 4,
                          near + 5, near + 6, near + 7, near + 8,
                          kClosedOccurrences - 3, kClosedOccurrences - 2,
                          kClosedOccurrences - 1}) {
    auto occurrence = expansion.occurrence_at(schedule, recurrence, index);
    require(occurrence.ok(), "long-history candidate fixture must expand");
    candidate_keys.emplace(index, occurrence.value().occurrence_key);
  }
  repository->snapshot.event_occurrence_states.reserve(kClosedOccurrences);
  for (int index = 0; index < kClosedOccurrences; ++index) {
    excellent_calendar::domain::EventOccurrenceState state;
    state.event_id = recurring_event.id;
    state.recurrence_revision = 1;
    const auto key = candidate_keys.find(index);
    state.occurrence_key = key == candidate_keys.end()
                               ? "state-" + std::to_string(index)
                               : key->second;
    state.occurrence_start_date = excellent_calendar::domain::format_local_date(
        excellent_calendar::domain::add_local_days(original, index));
    state.status = "completed";
    state.state_changed_at = "2026-09-01T00:00:00Z";
    state.created_at = state.state_changed_at;
    state.updated_at = state.state_changed_at;
    repository->snapshot.event_occurrence_states.push_back(std::move(state));
  }

  excellent_calendar::application::SearchQueryService service(
      repository, time_resolver,
      std::make_shared<excellent_calendar::application::RecurrenceService>(
          time_resolver),
      [] { return std::string("2026-09-01T00:00:00Z"); }, {});
  auto query = base_query();
  query.include_completed = false;
  excellent_calendar::application::SearchQueryDiagnostics diagnostics;
  auto response = service.query(query, &diagnostics);
  require(response.ok() && response.value().sections[0].items.size() == 1U,
          "long closed history must still find the next open occurrence");
  const auto& selected =
      std::get<excellent_calendar::application::SearchEventItem>(
          response.value().sections[0].items.front());
  require(selected.occur_date == excellent_calendar::domain::add_local_days(
                                     original, kClosedOccurrences),
          "bounded seek must jump beyond the contiguous closed interval");
  require(diagnostics.recurrence_state_rows == kClosedOccurrences &&
              diagnostics.recurrence_candidates_evaluated <= 32U,
          "occurrence expansion count must stay fixed as state history grows");
  std::cout << "SEARCH_LONG_HISTORY recurrence_state_rows="
            << diagnostics.recurrence_state_rows
            << " recurrence_candidates="
            << diagnostics.recurrence_candidates_evaluated << '\n';
}

void test_anniversary_leap_projection() {
  auto repository = std::make_shared<FakeSearchRepository>();
  repository->snapshot.generations.fill(1);
  excellent_calendar::domain::AnniversaryRecurrence recurrence;
  recurrence.id = uuid_for(2100);
  recurrence.frequency = "yearly";
  repository->snapshot.anniversary_recurrences.push_back(recurrence);
  excellent_calendar::domain::Anniversary anniversary;
  anniversary.id = uuid_for(2101);
  anniversary.title = "项目 leap";
  anniversary.date = {2000, 2, 29};
  anniversary.calendar_type = "solar";
  anniversary.recurrence_id = recurrence.id;
  anniversary.updated_at = "2099-01-01T00:00:00Z";
  repository->snapshot.anniversaries.push_back(anniversary);
  auto service = make_service(repository, "2100-02-27T16:00:00Z");
  auto query = base_query();
  query.target_types = {SearchTargetType::anniversary};
  query.sections = {{SearchTargetType::anniversary, 20, std::nullopt}};
  query.date_from = excellent_calendar::domain::LocalDate{2100, 2, 28};
  query.date_to_exclusive = excellent_calendar::domain::LocalDate{2100, 3, 1};
  auto response = service.query(query);
  require(response.ok() && response.value().sections[0].items.size() == 1U,
          "2100 leap-day Anniversary must remain queryable");
  const auto& item = std::get<excellent_calendar::application::SearchAnniversaryItem>(
      response.value().sections[0].items.front());
  require(item.occur_date == excellent_calendar::domain::LocalDate{2100, 2, 28} &&
              item.years_elapsed == 100 && item.relation == "today",
          "existing 2100 non-leap rule and date-only countdown must be reused");
}

}  // namespace

int main() {
  try {
    test_frozen_unicode_normalization();
    test_strict_utf8_rejections();
    test_cross_field_and_relevance();
    test_scalar_limits_and_snippet_boundary();
    test_hmac_golden_and_tamper();
    test_three_section_projection_and_pagination();
    test_contract_request_fixtures_at_boundary();
    test_real_sqlite_snapshot_generations_and_zero_write();
    test_event_occurrence_selection_dst_and_status();
    test_completed_recurring_series_cutoff();
    test_completed_all_day_cutoff_timezone_and_explicit_state();
    test_completed_series_cutoff_total_and_cursor();
    test_long_occurrence_state_history_has_bounded_expansion();
    test_anniversary_leap_projection();
    std::cout << "Search core tests passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Search core tests failed: " << error.what() << '\n';
    return 1;
  }
}
