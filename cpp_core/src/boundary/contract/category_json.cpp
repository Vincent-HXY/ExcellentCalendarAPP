#include "excellent_calendar/boundary/contract/category_json.hpp"

#include <cmath>
#include <set>
#include <string>
#include <utility>

#include "excellent_calendar/domain/category.hpp"

namespace excellent_calendar::boundary::contract {
namespace {

common::Error contract_error(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Result<picojson::object> parse_object(std::string_view request_json) {
  picojson::value value;
  const auto parse_error = picojson::parse(value, std::string(request_json));
  if (!parse_error.empty() || !value.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        contract_error("json", "request must be a valid JSON object"));
  }
  return common::Result<picojson::object>::success(
      value.get<picojson::object>());
}

common::Result<common::Unit> exact_fields(const picojson::object &object,
                                          const std::set<std::string> &expected,
                                          const std::string &parent) {
  for (const auto &[name, _] : object) {
    if (expected.count(name) == 0U) {
      return common::Result<common::Unit>::failure(
          contract_error(parent + "." + name, "unknown field"));
    }
  }
  for (const auto &name : expected) {
    if (object.find(name) == object.end()) {
      return common::Result<common::Unit>::failure(
          contract_error(parent + "." + name, "required field is missing"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::string> required_text(const picojson::object &object,
                                          const std::string &key,
                                          const std::string &parent,
                                          std::size_t maximum_length,
                                          bool require_nonblank) {
  const auto found = object.find(key);
  if (found == object.end() || !found->second.is<std::string>()) {
    return common::Result<std::string>::failure(
        contract_error(parent + "." + key, "field must be string"));
  }
  const auto &value = found->second.get<std::string>();
  const auto count = domain::utf8_code_point_count(value);
  const auto trimmed = domain::trim_unicode_whitespace(value);
  if (!count.has_value() || *count == 0U || *count > maximum_length ||
      (require_nonblank && (!trimmed.has_value() || trimmed->empty()))) {
    return common::Result<std::string>::failure(contract_error(
        parent + "." + key, "text length or content is invalid"));
  }
  return common::Result<std::string>::success(value);
}

common::Result<std::optional<std::string>>
required_nullable_text(const picojson::object &object, const std::string &key,
                       const std::string &parent, std::size_t maximum_length) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return common::Result<std::optional<std::string>>::failure(contract_error(
        parent + "." + key, "required nullable field is missing"));
  }
  if (found->second.is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!found->second.is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key, "field must be string or null"));
  }
  const auto &value = found->second.get<std::string>();
  const auto count = domain::utf8_code_point_count(value);
  if (!count.has_value() || *count == 0U || *count > maximum_length) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key, "text length is invalid"));
  }
  return common::Result<std::optional<std::string>>::success(value);
}

common::Result<std::optional<std::int64_t>>
required_nullable_non_negative_integer(const picojson::object &object,
                                       const std::string &key,
                                       const std::string &parent) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return common::Result<std::optional<std::int64_t>>::failure(contract_error(
        parent + "." + key, "required nullable field is missing"));
  }
  if (found->second.is<picojson::null>()) {
    return common::Result<std::optional<std::int64_t>>::success(std::nullopt);
  }
  if (!found->second.is<double>() ||
      !std::isfinite(found->second.get<double>()) ||
      std::floor(found->second.get<double>()) != found->second.get<double>() ||
      found->second.get<double>() < 0.0 ||
      found->second.get<double>() >
          static_cast<double>(domain::kMaximumCategorySortOrder)) {
    return common::Result<std::optional<std::int64_t>>::failure(contract_error(
        parent + "." + key,
        "field must be an integer from 0 through 9007199254740991 or null"));
  }
  return common::Result<std::optional<std::int64_t>>::success(
      static_cast<std::int64_t>(found->second.get<double>()));
}

picojson::value nullable_string(const std::optional<std::string> &value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value nullable_integer(const std::optional<std::int64_t> &value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

} // namespace

common::Result<common::Unit>
parse_category_list_request(std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok())
    return common::Result<common::Unit>::failure(parsed.error());
  return exact_fields(parsed.value(), {}, "CategoryListRequest");
}

common::Result<CreateCategoryRequestDto>
parse_create_category_request(std::string_view request_json) {
  constexpr const char *parent = "CreateCategoryRequest";
  auto parsed = parse_object(request_json);
  if (!parsed.ok())
    return common::Result<CreateCategoryRequestDto>::failure(parsed.error());
  auto fields = exact_fields(
      parsed.value(), {"name", "description", "color", "icon", "sort_order"},
      parent);
  if (!fields.ok())
    return common::Result<CreateCategoryRequestDto>::failure(fields.error());
  auto name = required_text(parsed.value(), "name", parent, 40U, true);
  auto description =
      required_nullable_text(parsed.value(), "description", parent, 200U);
  auto color = required_text(parsed.value(), "color", parent, 7U, false);
  auto icon = required_nullable_text(parsed.value(), "icon", parent, 64U);
  auto sort_order = required_nullable_non_negative_integer(
      parsed.value(), "sort_order", parent);
  if (!name.ok())
    return common::Result<CreateCategoryRequestDto>::failure(name.error());
  if (!description.ok()) {
    return common::Result<CreateCategoryRequestDto>::failure(
        description.error());
  }
  if (!color.ok())
    return common::Result<CreateCategoryRequestDto>::failure(color.error());
  if (!icon.ok())
    return common::Result<CreateCategoryRequestDto>::failure(icon.error());
  if (!sort_order.ok()) {
    return common::Result<CreateCategoryRequestDto>::failure(
        sort_order.error());
  }
  if (!domain::is_category_color(color.value(), false)) {
    return common::Result<CreateCategoryRequestDto>::failure(contract_error(
        "CreateCategoryRequest.color", "color must use #RRGGBB"));
  }
  return common::Result<CreateCategoryRequestDto>::success(
      CreateCategoryRequestDto{name.value(), description.value(), color.value(),
                               icon.value(), sort_order.value()});
}

CategoryResponseDto
category_response_from_domain(const domain::Category &category) {
  return CategoryResponseDto{
      category.id,         category.name,       category.description,
      category.color,      category.icon,       category.sort_order,
      category.created_at, category.updated_at, category.deleted_at};
}

CategoryListResponseDto category_list_response_from_domain(
    const std::vector<domain::Category> &categories) {
  CategoryListResponseDto response;
  response.items.reserve(categories.size());
  for (const auto &category : categories) {
    response.items.push_back(category_response_from_domain(category));
  }
  return response;
}

picojson::value category_response_json(const CategoryResponseDto &response) {
  picojson::object object;
  object["id"] = picojson::value(response.id);
  object["name"] = picojson::value(response.name);
  object["description"] = nullable_string(response.description);
  object["color"] = nullable_string(response.color);
  object["icon"] = nullable_string(response.icon);
  object["sort_order"] = nullable_integer(response.sort_order);
  object["created_at"] = picojson::value(response.created_at);
  object["updated_at"] = picojson::value(response.updated_at);
  object["deleted_at"] = nullable_string(response.deleted_at);
  return picojson::value(std::move(object));
}

picojson::value
category_list_response_json(const CategoryListResponseDto &response) {
  picojson::array items;
  items.reserve(response.items.size());
  for (const auto &item : response.items)
    items.push_back(category_response_json(item));
  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  return picojson::value(std::move(object));
}

} // namespace excellent_calendar::boundary::contract
