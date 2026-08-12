#include "excellent_calendar/domain/category.hpp"

#include <algorithm>
#include <cctype>
#include <utility>
#include <vector>

#include "excellent_calendar/common/datetime.hpp"

namespace excellent_calendar::domain {
namespace {

struct CodePointSpan {
  std::uint32_t value = 0;
  std::size_t begin = 0;
  std::size_t end = 0;
};

common::Error contract_error(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", std::move(reason)}});
}

std::optional<std::vector<CodePointSpan>> decode_utf8(std::string_view value) {
  std::vector<CodePointSpan> result;
  result.reserve(value.size());
  for (std::size_t index = 0; index < value.size();) {
    const auto begin = index;
    const auto first = static_cast<unsigned char>(value[index++]);
    std::uint32_t code_point = 0;
    std::size_t continuation_count = 0;
    std::uint32_t minimum = 0;
    if (first <= 0x7fU) {
      code_point = first;
    } else if (first >= 0xc2U && first <= 0xdfU) {
      code_point = first & 0x1fU;
      continuation_count = 1U;
      minimum = 0x80U;
    } else if (first >= 0xe0U && first <= 0xefU) {
      code_point = first & 0x0fU;
      continuation_count = 2U;
      minimum = 0x800U;
    } else if (first >= 0xf0U && first <= 0xf4U) {
      code_point = first & 0x07U;
      continuation_count = 3U;
      minimum = 0x10000U;
    } else {
      return std::nullopt;
    }
    if (index + continuation_count > value.size())
      return std::nullopt;
    for (std::size_t offset = 0; offset < continuation_count; ++offset) {
      const auto next = static_cast<unsigned char>(value[index++]);
      if ((next & 0xc0U) != 0x80U)
        return std::nullopt;
      code_point = (code_point << 6U) | (next & 0x3fU);
    }
    if ((continuation_count != 0U && code_point < minimum) ||
        code_point > 0x10ffffU ||
        (code_point >= 0xd800U && code_point <= 0xdfffU)) {
      return std::nullopt;
    }
    result.push_back(CodePointSpan{code_point, begin, index});
  }
  return result;
}

bool is_unicode_whitespace(std::uint32_t value) {
  return (value >= 0x0009U && value <= 0x000dU) || value == 0x0020U ||
         value == 0x0085U || value == 0x00a0U || value == 0x1680U ||
         (value >= 0x2000U && value <= 0x200aU) || value == 0x2028U ||
         value == 0x2029U || value == 0x202fU || value == 0x205fU ||
         value == 0x3000U || value == 0xfeffU;
}

bool is_lower_hex(char value) {
  return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
}

bool is_hex(char value) {
  return is_lower_hex(value) || (value >= 'A' && value <= 'F');
}

bool is_trimmed_valid_text(std::string_view value, std::size_t maximum_length) {
  const auto count = utf8_code_point_count(value);
  const auto trimmed = trim_unicode_whitespace(value);
  return count.has_value() && *count >= 1U && *count <= maximum_length &&
         trimmed.has_value() && *trimmed == value;
}

} // namespace

std::optional<std::size_t> utf8_code_point_count(std::string_view value) {
  const auto decoded = decode_utf8(value);
  return decoded.has_value() ? std::optional<std::size_t>(decoded->size())
                             : std::nullopt;
}

std::optional<std::string> trim_unicode_whitespace(std::string_view value) {
  const auto decoded = decode_utf8(value);
  if (!decoded.has_value())
    return std::nullopt;
  std::size_t first = 0;
  while (first < decoded->size() &&
         is_unicode_whitespace((*decoded)[first].value))
    ++first;
  std::size_t last = decoded->size();
  while (last > first && is_unicode_whitespace((*decoded)[last - 1U].value))
    --last;
  if (first == last)
    return std::string{};
  return std::string(
      value.substr((*decoded)[first].begin,
                   (*decoded)[last - 1U].end - (*decoded)[first].begin));
}

bool is_canonical_category_uuid_v4(std::string_view value) {
  if (value.size() != 36U || value[8] != '-' || value[13] != '-' ||
      value[18] != '-' || value[23] != '-' || value[14] != '4' ||
      (value[19] != '8' && value[19] != '9' && value[19] != 'a' &&
       value[19] != 'b')) {
    return false;
  }
  for (std::size_t index = 0; index < value.size(); ++index) {
    if (index == 8U || index == 13U || index == 18U || index == 23U)
      continue;
    if (!is_lower_hex(value[index]))
      return false;
  }
  return true;
}

bool is_category_color(std::string_view value, bool canonical_uppercase) {
  if (value.size() != 7U || value.front() != '#')
    return false;
  for (std::size_t index = 1U; index < value.size(); ++index) {
    if (!is_hex(value[index]))
      return false;
    if (canonical_uppercase && value[index] >= 'a' && value[index] <= 'f')
      return false;
  }
  return true;
}

bool is_whole_second_utc(std::string_view value) {
  if (value.size() != 20U || value[4] != '-' || value[7] != '-' ||
      value[10] != 'T' || value[13] != ':' || value[16] != ':' ||
      value[19] != 'Z') {
    return false;
  }
  for (const auto index :
       {0U, 1U, 2U, 3U, 5U, 6U, 8U, 9U, 11U, 12U, 14U, 15U, 17U, 18U}) {
    if (value[index] < '0' || value[index] > '9')
      return false;
  }
  const int year = (value[0] - '0') * 1000 + (value[1] - '0') * 100 +
                   (value[2] - '0') * 10 + (value[3] - '0');
  const int hour = (value[11] - '0') * 10 + (value[12] - '0');
  const int minute = (value[14] - '0') * 10 + (value[15] - '0');
  const int second = (value[17] - '0') * 10 + (value[18] - '0');
  return year >= 1 && hour <= 23 && minute <= 59 && second <= 59 &&
         common::is_iso8601_utc_datetime(value);
}

common::Result<std::string> normalize_category_name(std::string_view value) {
  const auto normalized = trim_unicode_whitespace(value);
  if (!normalized.has_value()) {
    return common::Result<std::string>::failure(contract_error(
        "CreateCategoryRequest.name", "name must be valid UTF-8"));
  }
  if (normalized->empty()) {
    return common::Result<std::string>::failure(common::make_error(
        "CATEGORY_NAME_EMPTY", "Category name cannot be empty",
        {{"field", "name"}}));
  }
  const auto length = utf8_code_point_count(*normalized);
  if (!length.has_value() || *length > 40U) {
    return common::Result<std::string>::failure(
        contract_error("CreateCategoryRequest.name",
                       "name must contain at most 40 characters"));
  }
  return common::Result<std::string>::success(*normalized);
}

common::Result<std::optional<std::string>>
normalize_category_optional_text(const std::optional<std::string> &value,
                                 std::size_t maximum_length,
                                 std::string field) {
  if (!value.has_value()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  const auto normalized = trim_unicode_whitespace(*value);
  if (!normalized.has_value()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(std::move(field), "field must be valid UTF-8"));
  }
  if (normalized->empty()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  const auto length = utf8_code_point_count(*normalized);
  if (!length.has_value() || *length > maximum_length) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(std::move(field), "text field is too long"));
  }
  return common::Result<std::optional<std::string>>::success(*normalized);
}

common::Result<std::string> normalize_category_color(std::string_view value) {
  if (!is_category_color(value, false)) {
    return common::Result<std::string>::failure(contract_error(
        "CreateCategoryRequest.color", "color must use #RRGGBB"));
  }
  std::string normalized(value);
  std::transform(
      normalized.begin(), normalized.end(), normalized.begin(),
      [](unsigned char ch) { return static_cast<char>(std::toupper(ch)); });
  return common::Result<std::string>::success(std::move(normalized));
}

common::Result<common::Unit> validate_category(const Category &category) {
  const auto created =
      common::parse_iso8601_utc_epoch_seconds(category.created_at);
  const auto updated =
      common::parse_iso8601_utc_epoch_seconds(category.updated_at);
  const auto deleted =
      category.deleted_at.has_value()
          ? common::parse_iso8601_utc_epoch_seconds(*category.deleted_at)
          : std::optional<std::int64_t>{};
  const bool text_valid =
      is_trimmed_valid_text(category.name, 40U) &&
      (!category.description.has_value() ||
       is_trimmed_valid_text(*category.description, 200U)) &&
      (!category.icon.has_value() ||
       is_trimmed_valid_text(*category.icon, 64U));
  const bool timestamps_valid = is_whole_second_utc(category.created_at) &&
                                is_whole_second_utc(category.updated_at) &&
                                created.has_value() && updated.has_value() &&
                                *created <= *updated &&
                                (!category.deleted_at.has_value() ||
                                 (is_whole_second_utc(*category.deleted_at) &&
                                  deleted.has_value() && *created <= *deleted));
  if (!is_canonical_category_uuid_v4(category.id) || !text_valid ||
      (category.color.has_value() &&
       !is_category_color(*category.color, true)) ||
      (category.sort_order.has_value() &&
       (*category.sort_order < 0 ||
        *category.sort_order > kMaximumCategorySortOrder)) ||
      !timestamps_valid) {
    return common::Result<common::Unit>::failure(
        internal_error("Category domain invariant is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

} // namespace excellent_calendar::domain
