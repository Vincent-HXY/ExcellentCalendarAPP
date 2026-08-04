#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"

#include <chrono>
#include <exception>
#include <fstream>
#include <mutex>

#include <date/date.h>
#include <date/tz.h>

#include "excellent_calendar/common/datetime.hpp"

namespace excellent_calendar::infrastructure::time {
namespace {

std::mutex g_tzdb_initialization_mutex;

common::Error tzdb_unavailable(std::string reason) {
  return common::make_error(
      "TIMEZONE_DATABASE_UNAVAILABLE",
      "Bundled timezone database is missing, corrupted, or has the wrong version",
      {{"reason", std::move(reason)}});
}

common::Error timezone_invalid(std::string timezone) {
  return common::make_error(
      "TIMEZONE_ID_INVALID",
      "Timezone ID is not present in the bundled IANA database",
      {{"timezone", std::move(timezone)}});
}

const date::time_zone* locate(std::string_view timezone) {
  return date::locate_zone(std::string(timezone));
}

}  // namespace

TzdbLocalTimeResolver::TzdbLocalTimeResolver(std::string version)
    : version_(std::move(version)) {}

common::Result<std::shared_ptr<TzdbLocalTimeResolver>> TzdbLocalTimeResolver::create(
    const std::filesystem::path& tzdb_directory,
    std::string expected_version) {
  std::lock_guard<std::mutex> lock(g_tzdb_initialization_mutex);
  try {
    const auto version_file = tzdb_directory / "version";
    std::ifstream input(version_file, std::ios::binary);
    std::string declared_version;
    if (!input || !std::getline(input, declared_version)) {
      return common::Result<std::shared_ptr<TzdbLocalTimeResolver>>::failure(
          tzdb_unavailable("version file is missing"));
    }
    if (!declared_version.empty() && declared_version.back() == '\r') declared_version.pop_back();
    if (declared_version != expected_version) {
      return common::Result<std::shared_ptr<TzdbLocalTimeResolver>>::failure(
          tzdb_unavailable("expected " + expected_version + " but found " + declared_version));
    }

    date::set_install(tzdb_directory.u8string());
    const auto& database = date::reload_tzdb();
    if (database.version != expected_version) {
      return common::Result<std::shared_ptr<TzdbLocalTimeResolver>>::failure(
          tzdb_unavailable("loaded version is " + database.version));
    }
    return common::Result<std::shared_ptr<TzdbLocalTimeResolver>>::success(
        std::shared_ptr<TzdbLocalTimeResolver>(
            new TzdbLocalTimeResolver(std::move(expected_version))));
  } catch (const std::exception& error) {
    return common::Result<std::shared_ptr<TzdbLocalTimeResolver>>::failure(
        tzdb_unavailable(error.what()));
  }
}

common::Result<common::Unit> TzdbLocalTimeResolver::validate_timezone(
    std::string_view timezone) const {
  try {
    static_cast<void>(locate(timezone));
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (...) {
    return common::Result<common::Unit>::failure(timezone_invalid(std::string(timezone)));
  }
}

common::Result<domain::LocalDateTime> TzdbLocalTimeResolver::to_local(
    std::string_view utc_instant,
    std::string_view timezone) const {
  const auto epoch = common::parse_iso8601_utc_epoch_seconds(utc_instant);
  if (!epoch.has_value()) {
    return common::Result<domain::LocalDateTime>::failure(common::make_error(
        "CONTRACT_VALIDATION_FAILED", "UTC instant is invalid", {{"field", "datetime"}}));
  }
  try {
    const date::sys_seconds instant{std::chrono::seconds{*epoch}};
    const auto local = locate(timezone)->to_local(instant);
    const auto local_day = date::floor<date::days>(local);
    const date::year_month_day calendar{local_day};
    const auto clock = date::make_time(local - local_day);
    domain::LocalDateTime result;
    result.year = static_cast<int>(calendar.year());
    result.month = static_cast<unsigned>(calendar.month());
    result.day = static_cast<unsigned>(calendar.day());
    result.hour = static_cast<int>(clock.hours().count());
    result.minute = static_cast<int>(clock.minutes().count());
    result.second = static_cast<int>(clock.seconds().count());
    return common::Result<domain::LocalDateTime>::success(result);
  } catch (...) {
    return common::Result<domain::LocalDateTime>::failure(timezone_invalid(std::string(timezone)));
  }
}

common::Result<std::string> TzdbLocalTimeResolver::to_utc(
    const domain::LocalDateTime& local,
    std::string_view timezone) const {
  if (!domain::is_valid_local_date_time(local)) {
    return common::Result<std::string>::failure(common::make_error(
        "RECURRENCE_RULE_INVALID", "Local date-time is invalid", {{"field", "local_datetime"}}));
  }
  try {
    const auto local_day = date::local_days{
        date::year{local.year} / static_cast<unsigned>(local.month) /
        static_cast<unsigned>(local.day)};
    const auto local_instant = date::local_seconds{
        local_day.time_since_epoch() + std::chrono::hours{local.hour} +
        std::chrono::minutes{local.minute} + std::chrono::seconds{local.second}};
    const auto* zone = locate(timezone);
    const auto info = zone->get_info(local_instant);
    date::sys_seconds instant;
    if (info.result == date::local_info::nonexistent) {
      // The first legal instant after the gap is the transition instant.
      instant = date::floor<std::chrono::seconds>(info.first.end);
    } else if (info.result == date::local_info::ambiguous) {
      instant = date::floor<std::chrono::seconds>(zone->to_sys(local_instant, date::choose::earliest));
    } else {
      instant = date::floor<std::chrono::seconds>(zone->to_sys(local_instant));
    }
    return common::Result<std::string>::success(
        common::format_epoch_seconds_utc_iso8601(instant.time_since_epoch().count()));
  } catch (...) {
    return common::Result<std::string>::failure(timezone_invalid(std::string(timezone)));
  }
}

std::string TzdbLocalTimeResolver::tzdb_version() const {
  return version_;
}

}  // namespace excellent_calendar::infrastructure::time
