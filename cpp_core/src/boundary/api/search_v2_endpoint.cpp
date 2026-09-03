#include "excellent_calendar/boundary/api/search_api.hpp"

#include <algorithm>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/search_query_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/search_json.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "recurring_v2_api_internal.hpp"

namespace excellent_calendar::boundary::api {
namespace {

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

common::Result<domain::SearchTargetType> parse_target(std::string_view value,
                                                      std::string field) {
  if (value == "event")
    return common::Result<domain::SearchTargetType>::success(
        domain::SearchTargetType::event);
  if (value == "habit")
    return common::Result<domain::SearchTargetType>::success(
        domain::SearchTargetType::habit);
  if (value == "anniversary")
    return common::Result<domain::SearchTargetType>::success(
        domain::SearchTargetType::anniversary);
  return fail<domain::SearchTargetType>(
      detail::contract_error(std::move(field), "enum value is unknown"));
}

common::Result<std::vector<domain::SearchTargetType>> target_array(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  const auto* value = detail::field(object, key);
  if (value == nullptr || !value->is<picojson::array>())
    return fail<std::vector<domain::SearchTargetType>>(
        detail::contract_error(parent + "." + key, "must be an array"));
  const auto& array = value->get<picojson::array>();
  if (array.empty() || array.size() > 3U)
    return fail<std::vector<domain::SearchTargetType>>(
        detail::contract_error(parent + "." + key, "array size is invalid"));
  std::vector<domain::SearchTargetType> result;
  std::set<std::string> unique;
  for (std::size_t index = 0; index < array.size(); ++index) {
    if (!array[index].is<std::string>())
      return fail<std::vector<domain::SearchTargetType>>(
          detail::contract_error(parent + "." + key,
                                 "array item must be a string"));
    if (!unique.insert(array[index].get<std::string>()).second)
      return fail<std::vector<domain::SearchTargetType>>(
          detail::contract_error(parent + "." + key,
                                 "array items must be unique"));
    auto target = parse_target(array[index].get<std::string>(),
                               parent + "." + key);
    if (!target.ok()) return fail<std::vector<domain::SearchTargetType>>(target.error());
    result.push_back(target.value());
  }
  return common::Result<std::vector<domain::SearchTargetType>>::success(
      std::move(result));
}

common::Result<std::optional<domain::LocalDate>> nullable_date(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto text = detail::nullable_string(object, key, parent, true);
  if (!text.ok()) return fail<std::optional<domain::LocalDate>>(text.error());
  if (!text.value().has_value())
    return common::Result<std::optional<domain::LocalDate>>::success(std::nullopt);
  auto parsed = domain::parse_local_date(*text.value());
  return parsed.ok()
             ? common::Result<std::optional<domain::LocalDate>>::success(
                   parsed.value())
             : fail<std::optional<domain::LocalDate>>(detail::contract_error(
                   parent + "." + key, "must be a valid YYYY-MM-DD date"));
}

common::Result<std::optional<std::vector<std::string>>> category_ids(
    const picojson::object& object, const std::string& parent) {
  const auto* value = detail::field(object, "category_ids");
  if (value == nullptr)
    return fail<std::optional<std::vector<std::string>>>(detail::contract_error(
        parent + ".category_ids", "field is required"));
  if (value->is<picojson::null>())
    return common::Result<std::optional<std::vector<std::string>>>::success(
        std::nullopt);
  if (!value->is<picojson::array>())
    return fail<std::optional<std::vector<std::string>>>(detail::contract_error(
        parent + ".category_ids", "must be null or an array"));
  std::vector<std::string> result;
  std::set<std::string> unique;
  const auto& array = value->get<picojson::array>();
  if (array.size() > 100U)
    return fail<std::optional<std::vector<std::string>>>(detail::contract_error(
        parent + ".category_ids", "array is too large"));
  for (const auto& item : array) {
    if (!item.is<std::string>() || item.get<std::string>().empty() ||
        item.get<std::string>().size() > 512U)
      return fail<std::optional<std::vector<std::string>>>(detail::contract_error(
          parent + ".category_ids", "array item is invalid"));
    if (!unique.insert(item.get<std::string>()).second)
      return fail<std::optional<std::vector<std::string>>>(detail::contract_error(
          parent + ".category_ids", "array items must be unique"));
    result.push_back(item.get<std::string>());
  }
  return common::Result<std::optional<std::vector<std::string>>>::success(
      std::move(result));
}

common::Result<application::SearchSort> parse_sort(std::string_view value) {
  if (value == "relevance")
    return common::Result<application::SearchSort>::success(
        application::SearchSort::relevance);
  if (value == "occur_time")
    return common::Result<application::SearchSort>::success(
        application::SearchSort::occur_time);
  if (value == "updated_at")
    return common::Result<application::SearchSort>::success(
        application::SearchSort::updated_at);
  return fail<application::SearchSort>(detail::contract_error(
      "SearchQueryRequest.sort_by", "enum value is unknown"));
}

common::Result<std::vector<application::SearchSectionRequest>> parse_sections(
    const picojson::object& object, const std::string& parent) {
  const auto* value = detail::field(object, "sections");
  if (value == nullptr || !value->is<picojson::array>())
    return fail<std::vector<application::SearchSectionRequest>>(
        detail::contract_error(parent + ".sections", "must be an array"));
  const auto& array = value->get<picojson::array>();
  if (array.empty() || array.size() > 3U)
    return fail<std::vector<application::SearchSectionRequest>>(
        detail::contract_error(parent + ".sections", "array size is invalid"));
  std::vector<application::SearchSectionRequest> result;
  for (const auto& item : array) {
    if (!item.is<picojson::object>())
      return fail<std::vector<application::SearchSectionRequest>>(
          detail::contract_error(parent + ".sections", "item must be an object"));
    const auto& section = item.get<picojson::object>();
    auto known = detail::reject_unknown(
        section, {"target_type", "page_size", "cursor"},
        "SearchSectionRequest");
    if (!known.ok())
      return fail<std::vector<application::SearchSectionRequest>>(known.error());
    auto target_text = detail::require_string(section, "target_type",
                                               "SearchSectionRequest");
    auto page_size =
        detail::require_int(section, "page_size", "SearchSectionRequest");
    auto cursor = detail::nullable_string(section, "cursor",
                                          "SearchSectionRequest", true);
    if (!target_text.ok())
      return fail<std::vector<application::SearchSectionRequest>>(target_text.error());
    if (!page_size.ok())
      return fail<std::vector<application::SearchSectionRequest>>(page_size.error());
    if (!cursor.ok())
      return fail<std::vector<application::SearchSectionRequest>>(cursor.error());
    if (page_size.value() != 20)
      return fail<std::vector<application::SearchSectionRequest>>(
          detail::contract_error("SearchSectionRequest.page_size",
                                 "must equal 20"));
    if (cursor.value().has_value()) {
      const auto& token = *cursor.value();
      const auto suffix = token.rfind("srchcur1.", 0U) == 0U
                              ? token.substr(9U)
                              : std::string();
      const bool alphabet = std::all_of(
          suffix.begin(), suffix.end(), [](unsigned char value) {
            return (value >= 'A' && value <= 'Z') ||
                   (value >= 'a' && value <= 'z') ||
                   (value >= '0' && value <= '9') || value == '-' ||
                   value == '_';
          });
      if (suffix.size() < 20U || suffix.size() > 2048U || !alphabet)
        return fail<std::vector<application::SearchSectionRequest>>(
            detail::contract_error("SearchSectionRequest.cursor",
                                   "token shape is invalid"));
    }
    auto target = parse_target(target_text.value(),
                               "SearchSectionRequest.target_type");
    if (!target.ok())
      return fail<std::vector<application::SearchSectionRequest>>(target.error());
    result.push_back({target.value(), page_size.value(), cursor.value()});
  }
  return common::Result<std::vector<application::SearchSectionRequest>>::success(
      std::move(result));
}

common::Result<application::SearchQuery> parse_query(
    const picojson::object& object) {
  constexpr const char* parent = "SearchQueryRequest";
  auto known = detail::reject_unknown(
      object,
      {"query_generation", "keyword", "timezone", "target_types",
       "date_from", "date_to_exclusive", "category_ids",
       "include_uncategorized", "include_completed", "sort_by", "sections"},
      parent);
  if (!known.ok()) return fail<application::SearchQuery>(known.error());
  auto generation = detail::require_int64(object, "query_generation", parent);
  auto keyword = detail::require_string(object, "keyword", parent);
  auto timezone = detail::require_string(object, "timezone", parent);
  auto targets = target_array(object, "target_types", parent);
  auto from = nullable_date(object, "date_from", parent);
  auto to = nullable_date(object, "date_to_exclusive", parent);
  auto categories = category_ids(object, parent);
  auto uncategorized = detail::require_bool(object, "include_uncategorized", parent);
  auto completed = detail::require_bool(object, "include_completed", parent);
  auto sort_text = detail::require_string(object, "sort_by", parent);
  auto sections = parse_sections(object, parent);
  if (!generation.ok()) return fail<application::SearchQuery>(generation.error());
  if (!keyword.ok()) return fail<application::SearchQuery>(keyword.error());
  if (!timezone.ok()) return fail<application::SearchQuery>(timezone.error());
  if (!targets.ok()) return fail<application::SearchQuery>(targets.error());
  if (!from.ok()) return fail<application::SearchQuery>(from.error());
  if (!to.ok()) return fail<application::SearchQuery>(to.error());
  if (!categories.ok()) return fail<application::SearchQuery>(categories.error());
  if (!uncategorized.ok()) return fail<application::SearchQuery>(uncategorized.error());
  if (!completed.ok()) return fail<application::SearchQuery>(completed.error());
  if (!sort_text.ok()) return fail<application::SearchQuery>(sort_text.error());
  if (!sections.ok()) return fail<application::SearchQuery>(sections.error());
  if (generation.value() < 0 || generation.value() > 9007199254740991LL)
    return fail<application::SearchQuery>(detail::contract_error(
        std::string(parent) + ".query_generation",
        "must be a safe non-negative integer"));
  auto sort = parse_sort(sort_text.value());
  if (!sort.ok()) return fail<application::SearchQuery>(sort.error());
  if (keyword.value().size() > 512U || timezone.value().size() > 255U)
    return fail<application::SearchQuery>(detail::contract_error(
        parent, "string length exceeds contract maximum"));
  application::SearchQuery query;
  query.query_generation = generation.value();
  query.keyword = std::move(keyword.value());
  query.timezone = std::move(timezone.value());
  query.target_types = std::move(targets.value());
  query.date_from = from.value();
  query.date_to_exclusive = to.value();
  query.category_ids = std::move(categories.value());
  query.include_uncategorized = uncategorized.value();
  query.include_completed = completed.value();
  query.sort_by = sort.value();
  query.sections = std::move(sections.value());
  return common::Result<application::SearchQuery>::success(std::move(query));
}

}  // namespace

std::string search_query_v2(std::string_view request_json) {
  return detail::respond_v2([&]() -> common::Result<picojson::value> {
    auto utf8 = domain::normalize_searchable_text(request_json);
    if (!utf8.ok())
      return fail<picojson::value>(detail::contract_error(
          "SearchQueryRequest", "request JSON must be valid UTF-8"));
    auto object = detail::parse_object(request_json);
    if (!object.ok()) return fail<picojson::value>(object.error());
    auto query = parse_query(object.value());
    if (!query.ok()) return fail<picojson::value>(query.error());
    auto service = current_search_query_service();
    if (!service)
      return fail<picojson::value>(storage_not_initialized_error("search.query"));
    auto response = service->query(query.value());
    return response.ok()
               ? common::Result<picojson::value>::success(
                     contract::search_query_response_json(response.value()))
               : fail<picojson::value>(response.error());
  });
}

}  // namespace excellent_calendar::boundary::api
