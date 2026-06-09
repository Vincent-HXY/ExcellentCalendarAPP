#include "excellent_calendar/application/event_service.hpp"

#include <algorithm>
#include <set>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::application {
namespace {

common::Error event_title_empty() {
  return common::make_error(
      "EVENT_TITLE_EMPTY",
      "Event title cannot be empty",
      {{"field", "title"}});
}

common::Error event_time_invalid(std::string field = "start_at") {
  return common::make_error(
      "EVENT_TIME_INVALID",
      "Event start time must be earlier than end time",
      {{"field", std::move(field)}});
}

common::Error contract_validation_failed(std::string field, std::string message) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED",
      std::move(message),
      {{"field", std::move(field)}});
}

bool vector_contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

bool matches_keyword(const domain::Event& event, const std::string& keyword) {
  if (keyword.empty()) {
    return true;
  }
  if (common::contains_case_insensitive_ascii(event.title, keyword)) {
    return true;
  }
  if (event.content.has_value() &&
      common::contains_case_insensitive_ascii(*event.content, keyword)) {
    return true;
  }
  return event.location.has_value() &&
         common::contains_case_insensitive_ascii(*event.location, keyword);
}

bool matches_location(const domain::Event& event, const std::string& location) {
  if (!event.location.has_value()) {
    return false;
  }
  return common::contains_case_insensitive_ascii(*event.location, location);
}

std::optional<std::int64_t> event_time(const std::string& value) {
  return common::parse_iso8601_utc_epoch_seconds(value);
}

int compare_optional_string(const std::optional<std::string>& left,
                            const std::optional<std::string>& right) {
  const std::string left_value = left.value_or("");
  const std::string right_value = right.value_or("");
  if (left_value < right_value) {
    return -1;
  }
  if (left_value > right_value) {
    return 1;
  }
  return 0;
}

int compare_events_by(const domain::Event& left, const domain::Event& right, const std::string& sort_by) {
  if (sort_by == "created_at") {
    return left.created_at.compare(right.created_at);
  }
  if (sort_by == "updated_at") {
    return left.updated_at.compare(right.updated_at);
  }
  if (sort_by == "importance") {
    return domain::importance_rank(left.importance) - domain::importance_rank(right.importance);
  }
  if (sort_by == "title") {
    return left.title.compare(right.title);
  }
  return left.start_at.compare(right.start_at);
}

bool is_supported_sort_by(const std::string& value) {
  return value == "start_at" ||
         value == "created_at" ||
         value == "updated_at" ||
         value == "importance" ||
         value == "title";
}

}  // namespace

EventService::EventService(
    std::shared_ptr<repository::EventRepository> repository,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : repository_(std::move(repository)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Event> EventService::create_event(const CreateEventCommand& command) {
  const auto title = common::trim_ascii(command.title);
  if (title.empty()) {
    return common::Result<domain::Event>::failure(event_title_empty());
  }

  const auto start_time = common::parse_iso8601_utc_epoch_seconds(command.start_at);
  const auto end_time = common::parse_iso8601_utc_epoch_seconds(command.end_at);
  if (!start_time.has_value()) {
    return common::Result<domain::Event>::failure(event_time_invalid("start_at"));
  }
  if (!end_time.has_value()) {
    return common::Result<domain::Event>::failure(event_time_invalid("end_at"));
  }
  if (*start_time >= *end_time) {
    return common::Result<domain::Event>::failure(event_time_invalid("start_at"));
  }

  if (command.importance.has_value() && !domain::is_valid_importance(*command.importance)) {
    return common::Result<domain::Event>::failure(
        contract_validation_failed("importance", "CreateEventRequest.importance has an unsupported enum value."));
  }
  if (!domain::is_valid_create_event_source(command.source)) {
    return common::Result<domain::Event>::failure(
        contract_validation_failed("source", "CreateEventRequest.source has an unsupported enum value."));
  }

  const auto now = clock_();
  domain::Event event;
  event.id = id_generator_();
  event.title = title;
  event.content = command.content;
  event.start_at = command.start_at;
  event.end_at = command.end_at;
  event.is_all_day = command.is_all_day;
  event.has_recurrence = false;
  event.status = std::string(domain::kEventStatusActive);
  event.completed_at = std::nullopt;
  event.recurrence_id = std::nullopt;
  event.category_id = command.category_id;
  event.importance = command.importance;
  event.location = command.location;
  event.timezone = command.timezone;
  event.source = command.source;
  event.created_at = now;
  event.updated_at = now;
  event.deleted_at = std::nullopt;

  return repository_->create(event);
}

common::Result<EventSearchResult> EventService::search_events(const EventQuery& query) {
  if (!is_supported_sort_by(query.sort_by)) {
    return common::Result<EventSearchResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search sort_by is invalid", {{"field", "sort_by"}}));
  }
  if (query.sort_direction != "asc" && query.sort_direction != "desc") {
    return common::Result<EventSearchResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search sort_direction is invalid", {{"field", "sort_direction"}}));
  }
  if (query.pagination.page < 1 || query.pagination.page_size < 1 || query.pagination.page_size > 200) {
    return common::Result<EventSearchResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search pagination is invalid", {{"field", "pagination"}}));
  }

  std::optional<std::int64_t> from_time;
  std::optional<std::int64_t> to_time;
  if (query.start_at_from.has_value()) {
    from_time = event_time(*query.start_at_from);
    if (!from_time.has_value()) {
      return common::Result<EventSearchResult>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search start_at_from is invalid", {{"field", "start_at_from"}}));
    }
  }
  if (query.start_at_to.has_value()) {
    to_time = event_time(*query.start_at_to);
    if (!to_time.has_value()) {
      return common::Result<EventSearchResult>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search start_at_to is invalid", {{"field", "start_at_to"}}));
    }
  }
  if (from_time.has_value() && to_time.has_value() && *from_time > *to_time) {
    return common::Result<EventSearchResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search time range is invalid", {{"field", "start_at_from"}}));
  }

  auto repository_result = repository_->find_all();
  if (!repository_result.ok()) {
    return common::Result<EventSearchResult>::failure(repository_result.error());
  }

  std::vector<domain::Event> filtered;
  for (const auto& event : repository_result.value()) {
    if (!query.include_deleted && event.deleted_at.has_value()) {
      continue;
    }
    if (query.keyword.has_value() && !matches_keyword(event, *query.keyword)) {
      continue;
    }
    const auto start = event_time(event.start_at);
    if (!start.has_value()) {
      return common::Result<EventSearchResult>::failure(
          common::make_error("STORAGE_DATA_CORRUPTED", "Stored event start_at is invalid", {{"field", "start_at"}}));
    }
    if (from_time.has_value() && *start < *from_time) {
      continue;
    }
    if (to_time.has_value() && *start > *to_time) {
      continue;
    }
    if (!query.category_ids.empty()) {
      if (!event.category_id.has_value() || !vector_contains(query.category_ids, *event.category_id)) {
        continue;
      }
    }
    if (!query.importance.empty()) {
      if (!event.importance.has_value() || !vector_contains(query.importance, *event.importance)) {
        continue;
      }
    }
    if (query.location.has_value() && !matches_location(event, *query.location)) {
      continue;
    }
    if (query.has_recurrence.has_value() && event.has_recurrence != *query.has_recurrence) {
      continue;
    }
    if (!query.source.empty() && !vector_contains(query.source, event.source)) {
      continue;
    }
    filtered.push_back(event);
  }

  std::stable_sort(filtered.begin(), filtered.end(), [&](const domain::Event& left, const domain::Event& right) {
    const int comparison = compare_events_by(left, right, query.sort_by);
    if (comparison == 0) {
      return false;
    }
    return query.sort_direction == "desc" ? comparison > 0 : comparison < 0;
  });

  const int total = static_cast<int>(filtered.size());
  const int page = query.pagination.page;
  const int page_size = query.pagination.page_size;
  const int offset = (page - 1) * page_size;

  EventSearchResult result;
  result.pagination.total = total;
  result.pagination.page = page;
  result.pagination.page_size = page_size;
  result.pagination.has_more = offset + page_size < total;
  result.pagination.next_cursor = std::nullopt;

  if (offset < total) {
    const int end = std::min(offset + page_size, total);
    result.items.assign(filtered.begin() + offset, filtered.begin() + end);
  }
  return common::Result<EventSearchResult>::success(std::move(result));
}

}  // namespace excellent_calendar::application
