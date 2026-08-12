#include "excellent_calendar/boundary/api/category_api.hpp"

#include <utility>

#include "excellent_calendar/application/category_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/category_json.hpp"
#include "recurring_v2_api_internal.hpp"

namespace excellent_calendar::boundary::api {

std::string list_categories_v2(std::string_view request_json) {
  return detail::respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = contract::parse_category_list_request(request_json);
    if (!parsed.ok())
      return common::Result<picojson::value>::failure(parsed.error());
    const auto service = current_category_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("category.list"));
    }
    auto categories = service->list();
    return categories.ok()
               ? common::Result<picojson::value>::success(
                     contract::category_list_response_json(
                         contract::category_list_response_from_domain(
                             categories.value())))
               : common::Result<picojson::value>::failure(categories.error());
  });
}

std::string create_category_v2(std::string_view request_json) {
  return detail::respond_v2([&]() -> common::Result<picojson::value> {
    auto request = contract::parse_create_category_request(request_json);
    if (!request.ok())
      return common::Result<picojson::value>::failure(request.error());
    const auto service = current_category_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("category.create"));
    }
    auto category = service->create(application::CreateCategoryCommand{
        request.value().name, request.value().description,
        request.value().color, request.value().icon,
        request.value().sort_order});
    return category.ok()
               ? common::Result<picojson::value>::success(
                     contract::category_response_json(
                         contract::category_response_from_domain(
                             category.value())))
               : common::Result<picojson::value>::failure(category.error());
  });
}

} // namespace excellent_calendar::boundary::api
