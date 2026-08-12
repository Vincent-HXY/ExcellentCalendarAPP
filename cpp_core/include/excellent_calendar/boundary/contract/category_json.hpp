#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/category.hpp"

namespace excellent_calendar::boundary::contract {

struct CreateCategoryRequestDto {
  std::string name;
  std::optional<std::string> description;
  std::string color;
  std::optional<std::string> icon;
  std::optional<std::int64_t> sort_order;
};

struct CategoryResponseDto {
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

struct CategoryListResponseDto {
  std::vector<CategoryResponseDto> items;
};

common::Result<common::Unit>
parse_category_list_request(std::string_view request_json);

common::Result<CreateCategoryRequestDto>
parse_create_category_request(std::string_view request_json);

CategoryResponseDto
category_response_from_domain(const domain::Category &category);

CategoryListResponseDto category_list_response_from_domain(
    const std::vector<domain::Category> &categories);

picojson::value category_response_json(const CategoryResponseDto &response);

picojson::value
category_list_response_json(const CategoryListResponseDto &response);

} // namespace excellent_calendar::boundary::contract
