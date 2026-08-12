#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::domain {

inline constexpr std::int64_t kMaximumCategorySortOrder =
    9007199254740991LL;

struct Category {
  std::string id;
  std::string name;
  std::optional<std::string> description;
  std::optional<std::string> color;
  std::optional<std::string> icon;
  std::optional<std::int64_t> sort_order;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

std::optional<std::size_t> utf8_code_point_count(std::string_view value);

std::optional<std::string> trim_unicode_whitespace(std::string_view value);

bool is_canonical_category_uuid_v4(std::string_view value);

bool is_category_color(std::string_view value, bool canonical_uppercase);

bool is_whole_second_utc(std::string_view value);

common::Result<std::string> normalize_category_name(std::string_view value);

common::Result<std::optional<std::string>>
normalize_category_optional_text(const std::optional<std::string> &value,
                                 std::size_t maximum_length, std::string field);

common::Result<std::string> normalize_category_color(std::string_view value);

common::Result<common::Unit> validate_category(const Category &category);

} // namespace excellent_calendar::domain
