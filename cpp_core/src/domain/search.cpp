#include "excellent_calendar/domain/search.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <unordered_map>

namespace excellent_calendar::domain {
namespace {

struct Scalar {
  std::uint32_t value = 0;
  std::size_t byte_offset = 0;
  std::size_t byte_length = 0;
};

common::Error invalid_text(std::string code, std::string message) {
  return common::make_error(std::move(code), std::move(message),
                            {{"field", "keyword"}});
}

common::Result<std::vector<Scalar>> decode_utf8(std::string_view value,
                                                std::string error_code) {
  std::vector<Scalar> scalars;
  scalars.reserve(value.size());
  for (std::size_t index = 0; index < value.size();) {
    const auto first = static_cast<unsigned char>(value[index]);
    std::uint32_t scalar = 0;
    std::size_t length = 0;
    std::uint32_t minimum = 0;
    if (first <= 0x7FU) {
      scalar = first;
      length = 1;
    } else if (first >= 0xC2U && first <= 0xDFU) {
      scalar = first & 0x1FU;
      length = 2;
      minimum = 0x80U;
    } else if (first >= 0xE0U && first <= 0xEFU) {
      scalar = first & 0x0FU;
      length = 3;
      minimum = 0x800U;
    } else if (first >= 0xF0U && first <= 0xF4U) {
      scalar = first & 0x07U;
      length = 4;
      minimum = 0x10000U;
    } else {
      return common::Result<std::vector<Scalar>>::failure(invalid_text(
          std::move(error_code), "Search text contains invalid UTF-8"));
    }
    if (index + length > value.size()) {
      return common::Result<std::vector<Scalar>>::failure(invalid_text(
          std::move(error_code), "Search text contains truncated UTF-8"));
    }
    for (std::size_t continuation = 1; continuation < length; ++continuation) {
      const auto byte = static_cast<unsigned char>(value[index + continuation]);
      if ((byte & 0xC0U) != 0x80U) {
        return common::Result<std::vector<Scalar>>::failure(invalid_text(
            std::move(error_code), "Search text contains invalid UTF-8"));
      }
      scalar = (scalar << 6U) | (byte & 0x3FU);
    }
    if ((length > 1 && scalar < minimum) || scalar > 0x10FFFFU ||
        (scalar >= 0xD800U && scalar <= 0xDFFFU)) {
      return common::Result<std::vector<Scalar>>::failure(invalid_text(
          std::move(error_code), "Search text contains an invalid Unicode scalar"));
    }
    scalars.push_back({scalar, index, length});
    index += length;
  }
  return common::Result<std::vector<Scalar>>::success(std::move(scalars));
}

bool is_frozen_whitespace(std::uint32_t value) {
  return (value >= 0x09U && value <= 0x0DU) || value == 0x20U ||
         value == 0x85U || value == 0xA0U || value == 0x1680U ||
         (value >= 0x2000U && value <= 0x200AU) || value == 0x2028U ||
         value == 0x2029U || value == 0x202FU || value == 0x205FU ||
         value == 0x3000U;
}

void append_scalar(std::string_view source, const Scalar& scalar,
                   std::string& display, std::string& comparison) {
  display.append(source.substr(scalar.byte_offset, scalar.byte_length));
  if (scalar.value >= 'A' && scalar.value <= 'Z') {
    comparison.push_back(static_cast<char>(scalar.value - 'A' + 'a'));
  } else {
    comparison.append(source.substr(scalar.byte_offset, scalar.byte_length));
  }
}

common::Result<NormalizedSearchText> normalize(std::string_view value,
                                               bool keyword) {
  if (keyword && value.size() > 512U) {
    return common::Result<NormalizedSearchText>::failure(invalid_text(
        "SEARCH_QUERY_INVALID", "Search keyword exceeds 512 UTF-8 bytes"));
  }
  auto decoded = decode_utf8(value,
                             keyword ? "SEARCH_QUERY_INVALID"
                                     : "STORAGE_DATA_CORRUPTED");
  if (!decoded.ok()) {
    return common::Result<NormalizedSearchText>::failure(decoded.error());
  }
  if (keyword && decoded.value().size() > 128U) {
    return common::Result<NormalizedSearchText>::failure(invalid_text(
        "SEARCH_QUERY_INVALID", "Search keyword exceeds 128 Unicode scalars"));
  }

  NormalizedSearchText result;
  result.scalar_count = decoded.value().size();
  bool pending_space = false;
  bool has_content = false;
  for (const auto& scalar : decoded.value()) {
    if (is_frozen_whitespace(scalar.value)) {
      pending_space = has_content;
      continue;
    }
    if (pending_space) {
      result.display.push_back(' ');
      result.comparison.push_back(' ');
      pending_space = false;
    }
    append_scalar(value, scalar, result.display, result.comparison);
    has_content = true;
  }
  if (keyword && result.display.empty()) {
    return common::Result<NormalizedSearchText>::failure(invalid_text(
        "SEARCH_QUERY_INVALID", "Search keyword is empty after normalization"));
  }

  std::size_t start = 0;
  while (start < result.display.size()) {
    const auto display_end = result.display.find(' ', start);
    const auto comparison_end = result.comparison.find(' ', start);
    const auto end = display_end == std::string::npos ? result.display.size()
                                                      : display_end;
    const auto key_end = comparison_end == std::string::npos
                             ? result.comparison.size()
                             : comparison_end;
    result.tokens.push_back(result.display.substr(start, end - start));
    result.comparison_tokens.push_back(
        result.comparison.substr(start, key_end - start));
    if (display_end == std::string::npos) break;
    start = display_end + 1U;
  }
  return common::Result<NormalizedSearchText>::success(std::move(result));
}

int field_precedence(SearchMatchField field) {
  switch (field) {
    case SearchMatchField::title:
      return 0;
    case SearchMatchField::content:
    case SearchMatchField::description:
    case SearchMatchField::note:
      return 1;
    case SearchMatchField::location:
      return 2;
    case SearchMatchField::category_name:
      return 3;
  }
  return std::numeric_limits<int>::max();
}

SearchRelevanceTier tier_for_field(SearchMatchField field) {
  switch (field) {
    case SearchMatchField::title:
      return SearchRelevanceTier::every_token_in_title;
    case SearchMatchField::content:
    case SearchMatchField::description:
    case SearchMatchField::note:
      return SearchRelevanceTier::body_like;
    case SearchMatchField::location:
      return SearchRelevanceTier::location;
    case SearchMatchField::category_name:
      return SearchRelevanceTier::category_name;
  }
  return SearchRelevanceTier::category_name;
}

SearchSnippet make_snippet(SearchMatchField field,
                           const NormalizedSearchText& text,
                           const NormalizedSearchText& query) {
  std::size_t match_byte = 0U;
  for (const auto& token : query.comparison_tokens) {
    const auto found = text.comparison.find(token);
    if (found != std::string::npos) {
      match_byte = found;
      break;
    }
  }
  auto decoded = decode_utf8(text.display, "STORAGE_DATA_CORRUPTED");
  std::size_t match_scalar = 0U;
  while (match_scalar + 1U < decoded.value().size() &&
         decoded.value()[match_scalar + 1U].byte_offset <= match_byte) {
    ++match_scalar;
  }
  const auto start_scalar = match_scalar > 40U ? match_scalar - 40U : 0U;
  const auto end_scalar =
      std::min(decoded.value().size(), start_scalar + 200U);
  const auto start_byte = decoded.value().empty()
                              ? 0U
                              : decoded.value()[start_scalar].byte_offset;
  const auto end_byte = end_scalar == decoded.value().size()
                            ? text.display.size()
                            : decoded.value()[end_scalar].byte_offset;
  SearchSnippet snippet;
  snippet.field = field;
  snippet.text = text.display.substr(start_byte, end_byte - start_byte);
  snippet.prefix_truncated = start_scalar > 0U;
  snippet.suffix_truncated = end_scalar < decoded.value().size();
  return snippet;
}

}  // namespace

std::string search_target_type_to_string(SearchTargetType value) {
  switch (value) {
    case SearchTargetType::event:
      return "event";
    case SearchTargetType::habit:
      return "habit";
    case SearchTargetType::anniversary:
      return "anniversary";
  }
  return "event";
}

std::string search_match_field_to_string(SearchMatchField value) {
  switch (value) {
    case SearchMatchField::title:
      return "title";
    case SearchMatchField::content:
      return "content";
    case SearchMatchField::description:
      return "description";
    case SearchMatchField::note:
      return "note";
    case SearchMatchField::location:
      return "location";
    case SearchMatchField::category_name:
      return "category_name";
  }
  return "title";
}

common::Result<NormalizedSearchText> normalize_search_keyword(
    std::string_view value) {
  return normalize(value, true);
}

common::Result<NormalizedSearchText> normalize_searchable_text(
    std::string_view value) {
  return normalize(value, false);
}

common::Result<std::optional<SearchMatch>> match_search_fields(
    const NormalizedSearchText& query,
    const std::vector<std::pair<SearchMatchField, std::string_view>>& fields) {
  struct FieldText {
    SearchMatchField field;
    NormalizedSearchText text;
  };
  std::vector<FieldText> normalized_fields;
  normalized_fields.reserve(fields.size());
  for (const auto& [field, value] : fields) {
    auto normalized = normalize_searchable_text(value);
    if (!normalized.ok()) {
      return common::Result<std::optional<SearchMatch>>::failure(
          normalized.error());
    }
    normalized_fields.push_back({field, std::move(normalized.value())});
  }
  const auto title = std::find_if(
      normalized_fields.begin(), normalized_fields.end(),
      [](const auto& value) { return value.field == SearchMatchField::title; });

  SearchMatch match;
  bool title_wide = false;
  if (title != normalized_fields.end()) {
    if (title->text.comparison == query.comparison) {
      match.relevance = SearchRelevanceTier::title_exact;
      title_wide = true;
    } else if (title->text.comparison.rfind(query.comparison, 0U) == 0U) {
      match.relevance = SearchRelevanceTier::title_prefix;
      title_wide = true;
    } else if (title->text.comparison.find(query.comparison) !=
               std::string::npos) {
      match.relevance = SearchRelevanceTier::title_contiguous_query;
      title_wide = true;
    } else if (std::all_of(query.comparison_tokens.begin(),
                           query.comparison_tokens.end(), [&](const auto& token) {
                             return title->text.comparison.find(token) !=
                                    std::string::npos;
                           })) {
      match.relevance = SearchRelevanceTier::every_token_in_title;
      title_wide = true;
    }
  }
  if (title_wide) {
    match.primary_field = SearchMatchField::title;
    match.matched_fields.push_back(SearchMatchField::title);
    return common::Result<std::optional<SearchMatch>>::success(
        std::optional<SearchMatch>(std::move(match)));
  }

  std::vector<SearchMatchField> chosen;
  for (const auto& token : query.comparison_tokens) {
    const FieldText* best = nullptr;
    for (const auto& field : normalized_fields) {
      if (field.text.comparison.find(token) == std::string::npos) continue;
      if (best == nullptr || field_precedence(field.field) <
                                 field_precedence(best->field)) {
        best = &field;
      }
    }
    if (best == nullptr) {
      return common::Result<std::optional<SearchMatch>>::success(std::nullopt);
    }
    chosen.push_back(best->field);
  }
  const auto primary = *std::max_element(
      chosen.begin(), chosen.end(), [](auto left, auto right) {
        return field_precedence(left) < field_precedence(right);
      });
  match.primary_field = primary;
  match.relevance = tier_for_field(primary);
  for (const auto& field : normalized_fields) {
    if (std::find(chosen.begin(), chosen.end(), field.field) != chosen.end()) {
      match.matched_fields.push_back(field.field);
    }
  }
  const auto primary_text = std::find_if(
      normalized_fields.begin(), normalized_fields.end(),
      [&](const auto& value) { return value.field == primary; });
  if (primary_text != normalized_fields.end() && primary != SearchMatchField::title) {
    match.snippet = make_snippet(primary, primary_text->text, query);
  }
  return common::Result<std::optional<SearchMatch>>::success(
      std::optional<SearchMatch>(std::move(match)));
}

}  // namespace excellent_calendar::domain
