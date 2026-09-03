#pragma once

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/common/search_token_crypto.hpp"
#include "excellent_calendar/domain/category.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/search.hpp"
#include "excellent_calendar/repository/search_query_repository.hpp"

namespace excellent_calendar::application {

enum class SearchSort { relevance, occur_time, updated_at };

struct SearchSectionRequest {
  domain::SearchTargetType target_type = domain::SearchTargetType::event;
  int page_size = 20;
  std::optional<std::string> cursor;
};

struct SearchQuery {
  std::int64_t query_generation = 0;
  std::string keyword;
  std::string timezone;
  std::vector<domain::SearchTargetType> target_types;
  std::optional<domain::LocalDate> date_from;
  std::optional<domain::LocalDate> date_to_exclusive;
  std::optional<std::vector<std::string>> category_ids;
  bool include_uncategorized = false;
  bool include_completed = false;
  SearchSort sort_by = SearchSort::relevance;
  std::vector<SearchSectionRequest> sections;
};

struct SearchCategoryProjection {
  std::string id;
  std::string name;
  std::optional<std::string> color;
  std::optional<std::string> icon;
};

struct SearchEventItem {
  std::string target_id;
  std::string title;
  domain::SearchMatch match;
  std::optional<SearchCategoryProjection> category;
  std::string updated_at;
  std::string status;
  bool is_all_day = false;
  bool is_recurring = false;
  std::optional<std::string> occur_at;
  std::optional<domain::LocalDate> occur_date;
  std::optional<std::string> location;
  std::optional<int> recurrence_revision;
  std::optional<std::string> occurrence_key;
};

struct SearchHabitItem {
  std::string target_id;
  std::string title;
  domain::SearchMatch match;
  std::optional<SearchCategoryProjection> category;
  std::string updated_at;
  std::string lifecycle_status;
  domain::LocalDate occur_date;
  domain::LocalDate challenge_start_date;
  domain::LocalDate challenge_end_date;
  std::optional<domain::LocalDate> ended_date;
  int remaining_days = 0;
  std::optional<std::int64_t> target_count_hundredths;
  std::optional<std::string> unit;
};

struct SearchAnniversaryItem {
  std::string target_id;
  std::string title;
  domain::SearchMatch match;
  std::optional<SearchCategoryProjection> category;
  std::string updated_at;
  std::string occurrence_key;
  domain::LocalDate occur_date;
  domain::LocalDate source_date;
  bool is_repeating = false;
  std::string relation;
  int days = 0;
  int years_elapsed = 0;
};

using SearchItem =
    std::variant<SearchEventItem, SearchHabitItem, SearchAnniversaryItem>;

struct SearchSectionResult {
  domain::SearchTargetType target_type = domain::SearchTargetType::event;
  std::vector<SearchItem> items;
  std::int64_t total_count = 0;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct SearchQueryResponse {
  std::int64_t query_generation = 0;
  std::string normalized_keyword;
  std::string timezone;
  std::string evaluated_at;
  std::string snapshot_token;
  std::vector<SearchSectionResult> sections;
};

struct SearchQueryDiagnostics {
  std::size_t sql_statements_executed = 0;
  std::size_t recurrence_candidates_evaluated = 0;
  std::size_t recurrence_state_rows = 0;
};

class SearchQueryService {
 public:
  using ClockFn = std::function<std::string()>;

  SearchQueryService(
      std::shared_ptr<repository::SearchQueryRepository> repository,
      std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
      std::shared_ptr<RecurrenceService> recurrence_service, ClockFn clock,
      common::SearchHmacKey hmac_key);

  common::Result<SearchQueryResponse> query(
      const SearchQuery& query,
      SearchQueryDiagnostics* diagnostics = nullptr) const;

 private:
  std::shared_ptr<repository::SearchQueryRepository> repository_;
  std::shared_ptr<domain::LocalTimeResolver> local_time_resolver_;
  std::shared_ptr<RecurrenceService> recurrence_service_;
  ClockFn clock_;
  common::SearchHmacKey hmac_key_{};
};

std::string search_sort_to_string(SearchSort value);

}  // namespace excellent_calendar::application
