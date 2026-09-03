#include "excellent_calendar/application/completed_recurring_series_eligibility.hpp"

#include <cstdint>
#include <optional>
#include <string>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/event_status.hpp"

namespace excellent_calendar::application {
namespace {

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

common::Error corrupted(std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored calendar data is corrupted",
                            {{"reason", std::move(reason)}});
}

common::Result<std::optional<std::int64_t>> completion_cutoff_epoch(
    const domain::Event& event) {
  if (event.status != domain::kEventStatusCompleted) {
    return common::Result<std::optional<std::int64_t>>::success(std::nullopt);
  }
  if (!event.completed_at.has_value()) {
    return fail<std::optional<std::int64_t>>(
        corrupted("Completed recurring Event is missing completed_at"));
  }
  const auto cutoff =
      common::parse_iso8601_utc_epoch_seconds(*event.completed_at);
  if (!cutoff.has_value()) {
    return fail<std::optional<std::int64_t>>(
        corrupted("Completed recurring Event cutoff is invalid"));
  }
  return common::Result<std::optional<std::int64_t>>::success(cutoff);
}

}  // namespace

common::Result<std::optional<domain::LocalDate>>
completed_recurring_series_cutoff_local_date(
    const domain::Event& event, const domain::Recurrence& recurrence,
    const domain::LocalTimeResolver& resolver) {
  auto cutoff = completion_cutoff_epoch(event);
  if (!cutoff.ok()) {
    return fail<std::optional<domain::LocalDate>>(cutoff.error());
  }
  if (!cutoff.value().has_value()) {
    return common::Result<std::optional<domain::LocalDate>>::success(
        std::nullopt);
  }
  auto local = resolver.to_local(*event.completed_at, recurrence.timezone);
  if (!local.ok()) {
    return fail<std::optional<domain::LocalDate>>(local.error());
  }
  return common::Result<std::optional<domain::LocalDate>>::success(
      domain::LocalDate{local.value().year, local.value().month,
                        local.value().day});
}

common::Result<bool> completed_recurring_series_occurrence_is_eligible(
    const domain::Event& event, const domain::EventOccurrence& occurrence,
    const domain::Recurrence& recurrence,
    const domain::LocalTimeResolver& resolver) {
  auto cutoff = completion_cutoff_epoch(event);
  if (!cutoff.ok()) return fail<bool>(cutoff.error());
  if (!cutoff.value().has_value()) {
    return common::Result<bool>::success(true);
  }

  std::optional<std::int64_t> anchor_epoch;
  if (event.is_all_day) {
    if (!occurrence.occurrence_start_date.has_value()) {
      return fail<bool>(corrupted(
          "Completed all-day recurring Event occurrence anchor is missing"));
    }
    auto anchor_date =
        domain::parse_local_date(*occurrence.occurrence_start_date);
    if (!anchor_date.ok()) {
      return fail<bool>(corrupted(
          "Completed all-day recurring Event occurrence anchor is invalid"));
    }
    auto anchor_utc = resolver.to_utc(
        {anchor_date.value().year, anchor_date.value().month,
         anchor_date.value().day, 0, 0, 0},
        recurrence.timezone);
    if (!anchor_utc.ok()) return fail<bool>(anchor_utc.error());
    anchor_epoch =
        common::parse_iso8601_utc_epoch_seconds(anchor_utc.value());
  } else {
    if (!occurrence.occurrence_start_at.has_value()) {
      return fail<bool>(corrupted(
          "Completed timed recurring Event occurrence anchor is missing"));
    }
    anchor_epoch = common::parse_iso8601_utc_epoch_seconds(
        *occurrence.occurrence_start_at);
  }
  if (!anchor_epoch.has_value()) {
    return fail<bool>(corrupted(
        "Completed recurring Event occurrence anchor is invalid"));
  }
  return common::Result<bool>::success(
      *anchor_epoch < *cutoff.value());
}

}  // namespace excellent_calendar::application
