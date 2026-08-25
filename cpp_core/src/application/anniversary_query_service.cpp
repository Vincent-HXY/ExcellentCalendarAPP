#include "excellent_calendar/application/anniversary_query_service.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <set>
#include <sstream>
#include <tuple>
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

AnniversaryReminderSettings reminder_settings_for(
    const domain::Anniversary& anniversary,
    const repository::AnniversaryState& state) {
  AnniversaryReminderSettings result;
  result.reminders_enabled = anniversary.reminders_enabled;
  for (const auto& item : state.reminder_templates) {
    if (item.anniversary_id == anniversary.id && !item.deleted_at.has_value()) {
      result.templates.push_back(item);
      if (anniversary.reminders_enabled && item.is_enabled) ++result.active_reminder_count;
    }
  }
  std::sort(result.templates.begin(), result.templates.end(),
            [](const auto& left, const auto& right) {
              return left.template_key < right.template_key;
            });
  return result;
}

std::string stable_hash(std::string_view value) {
  std::uint64_t hash = 1469598103934665603ULL;
  for (const unsigned char byte : value) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  std::ostringstream output;
  output << std::hex << hash;
  return output.str();
}

std::string occurrence_query_fingerprint(const ListAnniversaryOccurrencesQuery& query) {
  std::string value = domain::format_local_date(query.range_start_date) + "|" +
                      domain::format_local_date(query.range_end_date) + "|" + query.timezone;
  for (const auto& item : query.category_ids) value += "|c:" + item;
  for (const auto& item : query.importance) value += "|i:" + item;
  return stable_hash(value);
}

std::string occurrence_cursor(std::string_view occurrence_key,
                              std::string_view snapshot,
                              std::string_view query) {
  return "annocc1." + std::string(occurrence_key) + "_" + std::string(snapshot) + "_" +
         std::string(query);
}

struct ParsedOccurrenceCursor {
  std::string occurrence_key;
  std::string snapshot;
  std::string query;
};

common::Result<ParsedOccurrenceCursor> parse_occurrence_cursor(std::string_view cursor) {
  constexpr std::string_view prefix = "annocc1.";
  if (cursor.size() < prefix.size() + 36U + 4U || cursor.substr(0, prefix.size()) != prefix) {
    return common::Result<ParsedOccurrenceCursor>::failure(common::make_error(
        "ANNIVERSARY_OCCURRENCE_CURSOR_INVALID", "Anniversary occurrence cursor is malformed"));
  }
  const auto first = cursor.find('_', prefix.size());
  const auto second = first == std::string_view::npos ? std::string_view::npos
                                                      : cursor.find('_', first + 1U);
  if (first == std::string_view::npos || second == std::string_view::npos ||
      cursor.find('_', second + 1U) != std::string_view::npos) {
    return common::Result<ParsedOccurrenceCursor>::failure(common::make_error(
        "ANNIVERSARY_OCCURRENCE_CURSOR_INVALID", "Anniversary occurrence cursor is malformed"));
  }
  ParsedOccurrenceCursor parsed{std::string(cursor.substr(prefix.size(), first - prefix.size())),
                                std::string(cursor.substr(first + 1U, second - first - 1U)),
                                std::string(cursor.substr(second + 1U))};
  if (!common::is_uuid(parsed.occurrence_key) || parsed.snapshot.empty() || parsed.query.empty()) {
    return common::Result<ParsedOccurrenceCursor>::failure(common::make_error(
        "ANNIVERSARY_OCCURRENCE_CURSOR_INVALID", "Anniversary occurrence cursor is malformed"));
  }
  return common::Result<ParsedOccurrenceCursor>::success(std::move(parsed));
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
  AnniversaryDetail detail;
  detail.anniversary = *anniversary;
  detail.recurrence = recurrence.value();
  detail.countdown = countdown.value();
  detail.reminder_settings = reminder_settings_for(*anniversary, loaded.value());
  return common::Result<AnniversaryDetail>::success(std::move(detail));
}

common::Result<AnniversaryOccurrencePage> AnniversaryQueryService::list_occurrences(
    const ListAnniversaryOccurrencesQuery& query) const {
  if (!transaction_) {
    return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
        "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
        {{"operation", "anniversary.list_occurrences"}}));
  }
  const int range_days = domain::local_days_between(query.range_start_date, query.range_end_date);
  if (!domain::is_valid_local_date(query.range_start_date) ||
      !domain::is_valid_local_date(query.range_end_date) || range_days <= 0) {
    return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
        "ANNIVERSARY_OCCURRENCE_RANGE_INVALID",
        "Anniversary occurrence date range is empty or reversed"));
  }
  if (range_days > 400) {
    return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
        "ANNIVERSARY_OCCURRENCE_RANGE_TOO_LARGE",
        "Anniversary occurrence date range exceeds 400 natural days"));
  }
  if (query.page_size < 1 || query.page_size > 500) {
    return common::Result<AnniversaryOccurrencePage>::failure(
        contract_invalid("page_size", "page_size must be between 1 and 500"));
  }
  if (!local_time_resolver_) {
    return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Anniversary timezone resolver is unavailable"}}));
  }
  auto timezone = local_time_resolver_->validate_timezone(query.timezone);
  if (!timezone.ok()) return common::Result<AnniversaryOccurrencePage>::failure(timezone.error());
  std::set<std::string> category_filter;
  for (const auto& value : query.category_ids) {
    if (!common::is_uuid(value) || !category_filter.insert(value).second) {
      return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
          "ANNIVERSARY_OCCURRENCE_FILTER_INVALID",
          "Anniversary occurrence filter contains a duplicate or unsupported value"));
    }
  }
  std::set<std::string> importance_filter;
  for (const auto& value : query.importance) {
    if (!domain::is_valid_importance(value) || !importance_filter.insert(value).second) {
      return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
          "ANNIVERSARY_OCCURRENCE_FILTER_INVALID",
          "Anniversary occurrence filter contains a duplicate or unsupported value"));
    }
  }
  auto loaded = transaction_->load_occurrence_snapshot();
  if (!loaded.ok()) return common::Result<AnniversaryOccurrencePage>::failure(loaded.error());
  const auto query_hash = occurrence_query_fingerprint(query);
  const auto& snapshot_hash = loaded.value().generation;
  const auto& state = loaded.value().state;
  std::optional<ParsedOccurrenceCursor> cursor;
  if (query.cursor.has_value()) {
    auto parsed = parse_occurrence_cursor(*query.cursor);
    if (!parsed.ok()) return common::Result<AnniversaryOccurrencePage>::failure(parsed.error());
    if (parsed.value().query != query_hash || parsed.value().snapshot != snapshot_hash) {
      return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
          "ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED",
          "Anniversary occurrence cursor is expired or does not match the query snapshot"));
    }
    cursor = parsed.value();
  }

  std::vector<domain::AnniversaryOccurrence> occurrences;
  for (const auto& anniversary : state.anniversaries) {
    if (anniversary.deleted_at.has_value() ||
        (!category_filter.empty() &&
         (!anniversary.category_id.has_value() ||
          category_filter.count(*anniversary.category_id) == 0U)) ||
        (!importance_filter.empty() &&
         (!anniversary.importance.has_value() ||
          importance_filter.count(*anniversary.importance) == 0U))) {
      continue;
    }
    auto recurrence = recurrence_for(anniversary, state);
    if (!recurrence.ok()) return common::Result<AnniversaryOccurrencePage>::failure(recurrence.error());
    int reminder_count = 0;
    if (anniversary.reminders_enabled) {
      for (const auto& item : state.reminder_templates) {
        if (item.anniversary_id == anniversary.id && item.is_enabled &&
            !item.deleted_at.has_value()) ++reminder_count;
      }
    }
    auto append = [&](const domain::LocalDate& occurrence_date, bool repeating) -> common::Result<common::Unit> {
      if (occurrence_date < query.range_start_date || !(occurrence_date < query.range_end_date) ||
          occurrence_date < anniversary.date) {
        return common::Result<common::Unit>::success(common::Unit{});
      }
      auto key = domain::anniversary_occurrence_key(anniversary.id, occurrence_date);
      if (!key.ok()) return common::Result<common::Unit>::failure(key.error());
      domain::AnniversaryOccurrence value;
      value.anniversary_id = anniversary.id;
      value.occurrence_key = key.value();
      value.occurrence_date = occurrence_date;
      value.source_date = anniversary.date;
      value.title = anniversary.title;
      value.calendar_type = anniversary.calendar_type;
      value.is_repeating = repeating;
      value.years_elapsed = repeating ? occurrence_date.year - anniversary.date.year : 0;
      value.category_id = anniversary.category_id;
      value.importance = anniversary.importance;
      value.reminder_count = reminder_count;
      value.has_active_reminders = reminder_count > 0;
      occurrences.push_back(std::move(value));
      return common::Result<common::Unit>::success(common::Unit{});
    };
    if (!recurrence.value().has_value()) {
      auto added = append(anniversary.date, false);
      if (!added.ok()) return common::Result<AnniversaryOccurrencePage>::failure(added.error());
    } else {
      const int first_year = std::max(anniversary.date.year, query.range_start_date.year - 1);
      for (int year = first_year; year <= query.range_end_date.year; ++year) {
        auto added = append(domain::anniversary_occurrence_in_year(anniversary.date, year), true);
        if (!added.ok()) return common::Result<AnniversaryOccurrencePage>::failure(added.error());
      }
    }
  }
  std::sort(occurrences.begin(), occurrences.end(), [](const auto& left, const auto& right) {
    return std::tie(left.occurrence_date, left.anniversary_id, left.occurrence_key) <
           std::tie(right.occurrence_date, right.anniversary_id, right.occurrence_key);
  });
  std::size_t offset = 0;
  if (cursor.has_value()) {
    const auto found = std::find_if(occurrences.begin(), occurrences.end(), [&](const auto& value) {
      return value.occurrence_key == cursor->occurrence_key;
    });
    if (found == occurrences.end()) {
      return common::Result<AnniversaryOccurrencePage>::failure(common::make_error(
          "ANNIVERSARY_OCCURRENCE_CURSOR_EXPIRED",
          "Anniversary occurrence cursor is expired or does not match the query snapshot"));
    }
    offset = static_cast<std::size_t>(std::distance(occurrences.begin(), found)) + 1U;
  }
  AnniversaryOccurrencePage page;
  const auto count = std::min<std::size_t>(query.page_size, occurrences.size() - offset);
  page.items.assign(occurrences.begin() + static_cast<std::ptrdiff_t>(offset),
                    occurrences.begin() + static_cast<std::ptrdiff_t>(offset + count));
  page.has_more = offset + count < occurrences.size();
  if (page.has_more && !page.items.empty()) {
    page.next_cursor = occurrence_cursor(page.items.back().occurrence_key, snapshot_hash, query_hash);
  }
  return common::Result<AnniversaryOccurrencePage>::success(std::move(page));
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
