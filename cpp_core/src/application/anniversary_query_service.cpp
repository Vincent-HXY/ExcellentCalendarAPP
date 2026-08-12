#include "excellent_calendar/application/anniversary_query_service.hpp"

#include <algorithm>
#include <limits>
#include <set>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::application {
namespace {

struct ProjectionContext {
  std::string now;
  domain::LocalDate today;
};

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error not_found(const std::string& id) {
  return common::make_error(
      "ANNIVERSARY_NOT_FOUND", "Anniversary not found", {{"id", id}});
}

common::Error corrupted(std::string reason) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
      {{"field", "anniversary"}, {"reason", std::move(reason)}});
}

common::Result<ProjectionContext> projection_context(
    const std::shared_ptr<domain::LocalTimeResolver>& resolver,
    const AnniversaryQueryService::Clock& clock,
    const std::string& timezone) {
  if (!resolver || !clock || timezone.empty()) {
    return common::Result<ProjectionContext>::failure(
        contract_invalid("timezone", "timezone is required"));
  }
  auto timezone_valid = resolver->validate_timezone(timezone);
  if (!timezone_valid.ok()) {
    return common::Result<ProjectionContext>::failure(timezone_valid.error());
  }
  const auto now = clock();
  if (!common::is_iso8601_utc_datetime(now)) {
    return common::Result<ProjectionContext>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Anniversary Clock returned an invalid UTC instant"}}));
  }
  auto local = resolver->to_local(now, timezone);
  if (!local.ok()) return common::Result<ProjectionContext>::failure(local.error());
  return common::Result<ProjectionContext>::success(
      ProjectionContext{now, domain::LocalDate{
                                 local.value().year,
                                 local.value().month,
                                 local.value().day}});
}

common::Result<std::optional<domain::AnniversaryRecurrence>> recurrence_for(
    const domain::Anniversary& anniversary,
    const repository::AnniversaryState& state) {
  if (!anniversary.recurrence_id.has_value()) {
    return common::Result<std::optional<domain::AnniversaryRecurrence>>::success(std::nullopt);
  }
  const auto recurrence = std::find_if(
      state.recurrences.begin(), state.recurrences.end(),
      [&](const auto& value) { return value.id == *anniversary.recurrence_id; });
  if (recurrence == state.recurrences.end() || recurrence->deleted_at.has_value() ||
      recurrence->frequency != domain::kAnniversaryRecurrenceYearly ||
      recurrence->interval != 1) {
    return common::Result<std::optional<domain::AnniversaryRecurrence>>::failure(
        corrupted("Active Anniversary recurrence is missing or invalid"));
  }
  return common::Result<std::optional<domain::AnniversaryRecurrence>>::success(*recurrence);
}

common::Result<AnniversarySummary> summary_for(
    const domain::Anniversary& anniversary,
    const repository::AnniversaryState& state,
    const ProjectionContext& context,
    const std::string& timezone) {
  auto recurrence = recurrence_for(anniversary, state);
  if (!recurrence.ok()) {
    return common::Result<AnniversarySummary>::failure(recurrence.error());
  }
  auto countdown = domain::calculate_anniversary_countdown(
      anniversary.date, recurrence.value().has_value(), context.today, timezone, context.now);
  if (!countdown.ok()) {
    return common::Result<AnniversarySummary>::failure(countdown.error());
  }
  return common::Result<AnniversarySummary>::success(
      AnniversarySummary{anniversary, countdown.value()});
}

}  // namespace

AnniversaryQueryService::AnniversaryQueryService(
    std::shared_ptr<repository::AnniversaryTransaction> transaction,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
    Clock clock)
    : transaction_(std::move(transaction)),
      local_time_resolver_(std::move(local_time_resolver)),
      clock_(std::move(clock)) {}

common::Result<AnniversaryDetail> AnniversaryQueryService::detail(
    const GetAnniversaryDetailQuery& query) const {
  if (!transaction_) {
    return common::Result<AnniversaryDetail>::failure(common::make_error(
        "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
        {{"operation", "anniversary.detail"}}));
  }
  if (!common::is_uuid(query.id)) {
    return common::Result<AnniversaryDetail>::failure(
        contract_invalid("id", "id must be a UUID"));
  }
  auto context = projection_context(local_time_resolver_, clock_, query.timezone);
  if (!context.ok()) return common::Result<AnniversaryDetail>::failure(context.error());
  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<AnniversaryDetail>::failure(loaded.error());
  const auto anniversary = std::find_if(
      loaded.value().anniversaries.begin(), loaded.value().anniversaries.end(),
      [&](const auto& value) { return value.id == query.id && !value.deleted_at; });
  if (anniversary == loaded.value().anniversaries.end()) {
    return common::Result<AnniversaryDetail>::failure(not_found(query.id));
  }
  auto recurrence = recurrence_for(*anniversary, loaded.value());
  if (!recurrence.ok()) return common::Result<AnniversaryDetail>::failure(recurrence.error());
  auto countdown = domain::calculate_anniversary_countdown(
      anniversary->date, recurrence.value().has_value(), context.value().today,
      query.timezone, context.value().now);
  if (!countdown.ok()) return common::Result<AnniversaryDetail>::failure(countdown.error());
  return common::Result<AnniversaryDetail>::success(
      AnniversaryDetail{*anniversary, recurrence.value(), countdown.value()});
}

common::Result<AnniversaryListPage> AnniversaryQueryService::list(
    const ListAnniversariesQuery& query) const {
  if (!transaction_) {
    return common::Result<AnniversaryListPage>::failure(common::make_error(
        "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
        {{"operation", "anniversary.list"}}));
  }
  if (query.page < 1 || query.page_size < 1 || query.page_size > 200 ||
      (query.sort_by != "target_occurrence_date" && query.sort_by != "countdown_days") ||
      (query.sort_direction != "asc" && query.sort_direction != "desc")) {
    return common::Result<AnniversaryListPage>::failure(
        contract_invalid("pagination_or_sort", "pagination or sort is invalid"));
  }
  if (query.cursor.has_value()) {
    return common::Result<AnniversaryListPage>::failure(common::make_error(
        "FEATURE_NOT_IMPLEMENTED", "Feature is not implemented",
        {{"feature", "anniversary.list.cursor"}}));
  }
  std::set<std::string> categories;
  for (const auto& id : query.category_ids) {
    if (!common::is_uuid(id) || !categories.insert(id).second) {
      return common::Result<AnniversaryListPage>::failure(
          contract_invalid("category_ids", "category_ids must contain unique UUIDs"));
    }
  }
  std::set<std::string> importance;
  for (const auto& value : query.importance) {
    if (!domain::is_valid_importance(value) || !importance.insert(value).second) {
      return common::Result<AnniversaryListPage>::failure(
          contract_invalid("importance", "importance must contain unique valid values"));
    }
  }

  auto context = projection_context(local_time_resolver_, clock_, query.timezone);
  if (!context.ok()) return common::Result<AnniversaryListPage>::failure(context.error());
  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<AnniversaryListPage>::failure(loaded.error());

  std::vector<AnniversarySummary> items;
  for (const auto& anniversary : loaded.value().anniversaries) {
    if (anniversary.deleted_at.has_value() ||
        (!categories.empty() &&
         (!anniversary.category_id.has_value() ||
          categories.count(*anniversary.category_id) == 0U)) ||
        (!importance.empty() &&
         (!anniversary.importance.has_value() ||
          importance.count(*anniversary.importance) == 0U))) {
      continue;
    }
    auto summary = summary_for(
        anniversary, loaded.value(), context.value(), query.timezone);
    if (!summary.ok()) {
      return common::Result<AnniversaryListPage>::failure(summary.error());
    }
    items.push_back(std::move(summary.value()));
  }

  const bool descending = query.sort_direction == "desc";
  std::sort(items.begin(), items.end(), [&](const auto& left, const auto& right) {
    bool left_before = false;
    bool right_before = false;
    if (query.sort_by == "countdown_days") {
      left_before = left.countdown.days < right.countdown.days;
      right_before = right.countdown.days < left.countdown.days;
    } else {
      left_before = left.countdown.target_occurrence_date <
                    right.countdown.target_occurrence_date;
      right_before = right.countdown.target_occurrence_date <
                     left.countdown.target_occurrence_date;
    }
    if (!left_before && !right_before) return left.anniversary.id < right.anniversary.id;
    return descending ? right_before : left_before;
  });

  if (items.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
    return common::Result<AnniversaryListPage>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Anniversary list is too large"}}));
  }
  AnniversaryListPage page;
  page.total = static_cast<int>(items.size());
  page.page = query.page;
  page.page_size = query.page_size;
  const auto page_index = static_cast<std::size_t>(query.page - 1);
  const auto page_size = static_cast<std::size_t>(query.page_size);
  const auto offset = page_index > std::numeric_limits<std::size_t>::max() / page_size
                          ? items.size()
                          : page_index * page_size;
  if (offset < items.size()) {
    const auto count = std::min(page_size, items.size() - offset);
    page.items.assign(items.begin() + static_cast<std::ptrdiff_t>(offset),
                      items.begin() + static_cast<std::ptrdiff_t>(offset + count));
    page.has_more = offset + count < items.size();
  }
  return common::Result<AnniversaryListPage>::success(std::move(page));
}

common::Result<domain::AnniversaryCountdown> AnniversaryQueryService::preview(
    const PreviewAnniversaryCountdownQuery& query) const {
  auto valid = domain::validate_anniversary_input(
      "preview", query.date, query.calendar_type, std::nullopt, std::nullopt);
  if (!valid.ok()) {
    return common::Result<domain::AnniversaryCountdown>::failure(valid.error());
  }
  auto context = projection_context(local_time_resolver_, clock_, query.timezone);
  if (!context.ok()) {
    return common::Result<domain::AnniversaryCountdown>::failure(context.error());
  }
  return domain::calculate_anniversary_countdown(
      query.date, query.repeats_yearly, context.value().today,
      query.timezone, context.value().now);
}

}  // namespace excellent_calendar::application
