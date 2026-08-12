#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"

#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "recurring_v2_api_internal.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::boundary::api {

using detail::contract_error;
using detail::parse_object;
using detail::reject_unknown;
using detail::require_string;
using detail::respond_v2;
using detail::string_array;

std::string initialize_runtime_v2_json(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"storage_directory", "tzdb_directory"}, "InitializeRuntimeRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto storage = require_string(parsed.value(), "storage_directory", "InitializeRuntimeRequest");
    auto tzdb = require_string(parsed.value(), "tzdb_directory", "InitializeRuntimeRequest");
    if (!storage.ok()) return common::Result<picojson::value>::failure(storage.error());
    if (!tzdb.ok()) return common::Result<picojson::value>::failure(tzdb.error());
    auto initialized = initialize_recurring_runtime(storage.value(), tzdb.value());
    if (!initialized.ok()) return common::Result<picojson::value>::failure(initialized.error());
    picojson::object data;
    data["initialized"] = picojson::value(initialized.value().initialized);
    data["storage_format_version"] = picojson::value(
        static_cast<double>(initialized.value().storage_format_version));
    data["tzdb_version"] = picojson::value(initialized.value().tzdb_version);
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string resolve_local_datetime_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"local_datetime", "timezone"}, "ResolveLocalDateTimeRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto local_value = require_string(
        parsed.value(), "local_datetime", "ResolveLocalDateTimeRequest");
    auto timezone = require_string(parsed.value(), "timezone", "ResolveLocalDateTimeRequest");
    if (!local_value.ok()) return common::Result<picojson::value>::failure(local_value.error());
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if (timezone.value().size() > 255U) {
      return common::Result<picojson::value>::failure(
          contract_error("ResolveLocalDateTimeRequest.timezone", "timezone is too long"));
    }
    auto local = domain::parse_local_date_time(local_value.value());
    if (!local.ok()) return common::Result<picojson::value>::failure(local.error());
    const auto resolver = current_local_time_resolver();
    if (!resolver) {
      return common::Result<picojson::value>::failure(common::make_error(
          "TIMEZONE_DATABASE_UNAVAILABLE",
          "Bundled timezone database is missing, corrupted, or has the wrong version",
          {{"operation", "runtime.resolve_local_datetime"}}));
    }
    auto resolved = resolver->resolve_local_datetime(local.value(), timezone.value());
    if (!resolved.ok()) return common::Result<picojson::value>::failure(resolved.error());
    picojson::object data;
    data["requested_local_datetime"] = picojson::value(
        domain::format_local_date_time(resolved.value().requested_local_datetime));
    data["resolved_local_datetime"] = picojson::value(
        domain::format_local_date_time(resolved.value().resolved_local_datetime));
    data["utc_instant"] = picojson::value(resolved.value().utc_instant);
    data["timezone"] = picojson::value(timezone.value());
    data["resolution"] = picojson::value(
        domain::local_date_time_resolution_to_string(resolved.value().resolution));
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string localize_instants_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"timezone", "instants"}, "LocalizeInstantsRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto timezone = require_string(parsed.value(), "timezone", "LocalizeInstantsRequest");
    auto instants = string_array(
        parsed.value(), "instants", "LocalizeInstantsRequest", true, false);
    if (!timezone.ok()) return common::Result<picojson::value>::failure(timezone.error());
    if (!instants.ok()) return common::Result<picojson::value>::failure(instants.error());
    if (timezone.value().size() > 255U) {
      return common::Result<picojson::value>::failure(
          contract_error("LocalizeInstantsRequest.timezone", "timezone is too long"));
    }
    if (instants.value().empty() || instants.value().size() > 400U) {
      return common::Result<picojson::value>::failure(contract_error(
          "LocalizeInstantsRequest.instants", "array size must be between 1 and 400"));
    }
    const auto resolver = current_local_time_resolver();
    if (!resolver) {
      return common::Result<picojson::value>::failure(common::make_error(
          "TIMEZONE_DATABASE_UNAVAILABLE",
          "Bundled timezone database is missing, corrupted, or has the wrong version",
          {{"operation", "runtime.localize_instants"}}));
    }
    picojson::array items;
    items.reserve(instants.value().size());
    for (std::size_t index = 0; index < instants.value().size(); ++index) {
      const auto& instant = instants.value()[index];
      if (instant.size() != 20U || !common::is_iso8601_utc_datetime(instant)) {
        return common::Result<picojson::value>::failure(contract_error(
            "LocalizeInstantsRequest.instants[" + std::to_string(index) + "]",
            "instant must be a whole-second UTC date-time"));
      }
      auto local = resolver->to_local(instant, timezone.value());
      if (!local.ok()) return common::Result<picojson::value>::failure(local.error());
      picojson::object item;
      item["instant"] = picojson::value(instant);
      item["local_datetime"] = picojson::value(domain::format_local_date_time(local.value()));
      items.emplace_back(std::move(item));
    }
    picojson::object data;
    data["timezone"] = picojson::value(timezone.value());
    data["items"] = picojson::value(std::move(items));
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

}  // namespace excellent_calendar::boundary::api
