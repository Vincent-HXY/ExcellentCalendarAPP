#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::domain {

enum class SearchTargetType { event, habit, anniversary };

std::string search_target_type_to_string(SearchTargetType value);

enum class SearchMatchField {
  title,
  content,
  description,
  note,
  location,
  category_name,
};

enum class SearchRelevanceTier {
  title_exact = 0,
  title_prefix = 1,
  title_contiguous_query = 2,
  every_token_in_title = 3,
  body_like = 4,
  location = 5,
  category_name = 6,
};

struct NormalizedSearchText {
  std::string display;
  std::string comparison;
  std::vector<std::string> tokens;
  std::vector<std::string> comparison_tokens;
  std::size_t scalar_count = 0;
};

struct SearchSnippet {
  SearchMatchField field = SearchMatchField::content;
  std::string text;
  bool prefix_truncated = false;
  bool suffix_truncated = false;
};

struct SearchMatch {
  SearchRelevanceTier relevance = SearchRelevanceTier::title_exact;
  SearchMatchField primary_field = SearchMatchField::title;
  std::vector<SearchMatchField> matched_fields;
  std::optional<SearchSnippet> snippet;
};

std::string search_match_field_to_string(SearchMatchField value);

common::Result<NormalizedSearchText> normalize_search_keyword(
    std::string_view value);

common::Result<NormalizedSearchText> normalize_searchable_text(
    std::string_view value);

common::Result<std::optional<SearchMatch>> match_search_fields(
    const NormalizedSearchText& query,
    const std::vector<std::pair<SearchMatchField, std::string_view>>& fields);

}  // namespace excellent_calendar::domain
