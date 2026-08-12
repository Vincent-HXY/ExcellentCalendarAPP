#include "excellent_calendar/application/recurring_event_query_service.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <set>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::application {
namespace {

constexpr int kMaximumExpansionCount = 1000000;

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error event_not_found(const std::string& id) {
  return common::make_error("EVENT_NOT_FOUND", "Event not found", {{"event_id", id}});
}

common::Error revision_conflict(int expected, int actual) {
  return common::make_error(
      "RECURRENCE_REVISION_CONFLICT",
      "Expected recurrence revision does not match the Event current revision",
      {{"expected", std::to_string(expected)}, {"actual", std::to_string(actual)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

const domain::Event* find_event(const repository::RecurringEventState& state,
                                const std::string& id) {
  const auto found = std::find_if(state.events.begin(), state.events.end(),
                                  [&](const auto& event) { return event.id == id; });
  return found == state.events.end() ? nullptr : &*found;
}

const domain::Recurrence* find_recurrence(const repository::RecurringEventState& state,
                                          const domain::Event& event,
                                          int revision) {
  if (!event.recurrence_id.has_value()) return nullptr;
  const auto found = std::find_if(
      state.recurrences.begin(), state.recurrences.end(), [&](const auto& recurrence) {
        return recurrence.id == *event.recurrence_id && recurrence.revision == revision;
      });
  return found == state.recurrences.end() ? nullptr : &*found;
}

std::optional<domain::EventOccurrenceState> occurrence_state_for(
    const repository::RecurringEventState& state,
    const domain::EventOccurrence& occurrence) {
  const auto found = std::find_if(
      state.occurrence_states.begin(), state.occurrence_states.end(), [&](const auto& value) {
        return value.event_id == occurrence.event_id &&
               value.recurrence_revision == occurrence.recurrence_revision &&
               value.occurrence_key == occurrence.occurrence_key;
      });
  return found == state.occurrence_states.end()
             ? std::optional<domain::EventOccurrenceState>{}
             : std::optional<domain::EventOccurrenceState>{*found};
}

bool contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

bool matches_keyword(const domain::Event& event, const std::string& keyword) {
  return keyword.empty() || common::contains_case_insensitive_ascii(event.title, keyword) ||
         (event.content.has_value() &&
          common::contains_case_insensitive_ascii(*event.content, keyword)) ||
         (event.location.has_value() &&
          common::contains_case_insensitive_ascii(*event.location, keyword));
}

std::string start_sort_key(const domain::Event& event) {
  return event.is_all_day ? event.start_date.value_or("") + "T00:00:00"
                          : event.start_at;
}

int compare_event(const domain::Event& left,
                  const domain::Event& right,
                  const std::string& sort_by) {
  if (sort_by == "created_at") return left.created_at.compare(right.created_at);
  if (sort_by == "updated_at") return left.updated_at.compare(right.updated_at);
  if (sort_by == "importance") {
    return domain::importance_rank(left.importance) - domain::importance_rank(right.importance);
  }
  if (sort_by == "title") return left.title.compare(right.title);
  return start_sort_key(left).compare(start_sort_key(right));
}

}  // namespace

RecurringEventQueryService::RecurringEventQueryService(
    std::shared_ptr<repository::RecurringEventTransaction> transaction,
    std::shared_ptr<RecurrenceService> recurrence_service,
    std::shared_ptr<repository::CategoryRepository> category_repository)
    : transaction_(std::move(transaction)),
      recurrence_service_(std::move(recurrence_service)),
      category_repository_(std::move(category_repository)) {}

common::Result<domain::Event> RecurringEventQueryService::get_event(
    const std::string& event_id) const {
  if (!common::is_uuid(event_id)) {
    return common::Result<domain::Event>::failure(
        contract_invalid("event_id", "event_id must be a UUID"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<domain::Event>::failure(loaded.error());
  const auto* event = find_event(loaded.value(), event_id);
  if (event == nullptr || event->deleted_at.has_value()) {
    return common::Result<domain::Event>::failure(event_not_found(event_id));
  }
  return common::Result<domain::Event>::success(*event);
}

common::Result<EventDetailAggregate> RecurringEventQueryService::get_event_detail(
    const std::string& event_id) const {
  if (!common::is_uuid(event_id)) {
    return common::Result<EventDetailAggregate>::failure(
        contract_invalid("event_id", "event_id must be a UUID"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<EventDetailAggregate>::failure(loaded.error());
  }
  const auto* event = find_event(loaded.value(), event_id);
  if (event == nullptr || event->deleted_at.has_value()) {
    return common::Result<EventDetailAggregate>::failure(event_not_found(event_id));
  }

  EventDetailAggregate detail;
  detail.event = *event;
  if (event->recurrence_revision.has_value()) {
    const auto* recurrence = find_recurrence(
        loaded.value(), *event, *event->recurrence_revision);
    if (recurrence == nullptr) {
      return common::Result<EventDetailAggregate>::failure(
          internal_error("Event current recurrence revision is missing"));
    }
    detail.recurrence = *recurrence;
  }
  for (const auto& reminder : loaded.value().reminders) {
    if (reminder.target_type == domain::kReminderTargetEvent &&
        reminder.target_id == event_id &&
        reminder.recurrence_revision == event->recurrence_revision &&
        !reminder.deleted_at.has_value()) {
      detail.reminders.push_back(reminder);
    }
  }
  std::sort(detail.reminders.begin(), detail.reminders.end(),
            [](const auto& left, const auto& right) {
              if (left.remind_at != right.remind_at) {
                return left.remind_at < right.remind_at;
              }
              return left.id < right.id;
            });
  if (event->category_id.has_value()) {
    if (!category_repository_) {
      return common::Result<EventDetailAggregate>::failure(
          internal_error("CategoryRepository is unavailable for Event detail"));
    }
    auto categories = category_repository_->load();
    if (!categories.ok()) {
      return common::Result<EventDetailAggregate>::failure(categories.error());
    }
    const auto category = std::find_if(
        categories.value().categories.begin(),
        categories.value().categories.end(), [&](const auto& candidate) {
          return candidate.id == *event->category_id &&
                 !candidate.deleted_at.has_value();
        });
    if (category != categories.value().categories.end()) {
      detail.category = *category;
    }
  }
  return common::Result<EventDetailAggregate>::success(std::move(detail));
}

common::Result<EventSearchPageV2> RecurringEventQueryService::search_events(
    const EventSearchQueryV2& query) const {
  if (query.page < 1 || query.page_size < 1 || query.page_size > 200 ||
      (query.sort_by != "start" && query.sort_by != "created_at" &&
       query.sort_by != "updated_at" && query.sort_by != "importance" &&
       query.sort_by != "title") ||
      (query.sort_direction != "asc" && query.sort_direction != "desc")) {
    return common::Result<EventSearchPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "pagination_or_sort"}}));
  }
  if (query.cursor.has_value()) {
    return common::Result<EventSearchPageV2>::failure(common::make_error(
        "FEATURE_NOT_IMPLEMENTED", "Requested feature is not implemented in this phase",
        {{"feature", "event.search.cursor"}}));
  }
  for (const auto& status : query.status) {
    if (!domain::is_valid_event_status(status)) {
      return common::Result<EventSearchPageV2>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                             {{"field", "status"}}));
    }
  }
  for (const auto& value : query.importance) {
    if (!domain::is_valid_importance(value)) {
      return common::Result<EventSearchPageV2>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                             {{"field", "importance"}}));
    }
  }
  for (const auto& value : query.source) {
    if (!domain::is_valid_create_event_source(value)) {
      return common::Result<EventSearchPageV2>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                             {{"field", "source"}}));
    }
  }
  const auto from_at = query.start_at_from.has_value()
                           ? common::parse_iso8601_utc_epoch_seconds(*query.start_at_from)
                           : std::optional<std::int64_t>{};
  const auto to_at = query.start_at_to.has_value()
                         ? common::parse_iso8601_utc_epoch_seconds(*query.start_at_to)
                         : std::optional<std::int64_t>{};
  if ((query.start_at_from.has_value() && !from_at.has_value()) ||
      (query.start_at_to.has_value() && !to_at.has_value()) ||
      (from_at.has_value() && to_at.has_value() && *from_at > *to_at) ||
      (query.start_date_from.has_value() &&
       !domain::parse_local_date(*query.start_date_from).ok()) ||
      (query.start_date_to.has_value() &&
       !domain::parse_local_date(*query.start_date_to).ok()) ||
      (query.start_date_from.has_value() && query.start_date_to.has_value() &&
       *query.start_date_from > *query.start_date_to)) {
    return common::Result<EventSearchPageV2>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                           {{"field", "time_range"}}));
  }

  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<EventSearchPageV2>::failure(loaded.error());
  std::vector<domain::Event> filtered;
  for (const auto& event : loaded.value().events) {
    if (!query.include_deleted && event.deleted_at.has_value()) continue;
    if (query.status.empty()) {
      if (event.status != domain::kEventStatusActive) continue;
    } else if (!contains(query.status, event.status)) {
      continue;
    }
    if (query.keyword.has_value() && !matches_keyword(event, *query.keyword)) continue;
    if (query.has_recurrence.has_value() &&
        event.has_recurrence != *query.has_recurrence) continue;
    if (!query.category_ids.empty() &&
        (!event.category_id.has_value() || !contains(query.category_ids, *event.category_id))) {
      continue;
    }
    if (!query.importance.empty() &&
        (!event.importance.has_value() || !contains(query.importance, *event.importance))) {
      continue;
    }
    if (query.location.has_value() &&
        (!event.location.has_value() ||
         !common::contains_case_insensitive_ascii(*event.location, *query.location))) {
      continue;
    }
    if (!query.source.empty() && !contains(query.source, event.source)) continue;
    if (event.is_all_day) {
      if ((query.start_at_from.has_value() || query.start_at_to.has_value()) &&
          !query.start_date_from.has_value() && !query.start_date_to.has_value()) {
        continue;
      }
      if (query.start_date_from.has_value() && *event.start_date < *query.start_date_from) continue;
      if (query.start_date_to.has_value() && *event.start_date > *query.start_date_to) continue;
    } else {
      if ((query.start_date_from.has_value() || query.start_date_to.has_value()) &&
          !query.start_at_from.has_value() && !query.start_at_to.has_value()) {
        continue;
      }
      const auto start = common::parse_iso8601_utc_epoch_seconds(event.start_at);
      if (!start.has_value()) {
        return common::Result<EventSearchPageV2>::failure(common::make_error(
            "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
            {{"field", "Event.start_at"}}));
      }
      if (from_at.has_value() && *start < *from_at) continue;
      if (to_at.has_value() && *start > *to_at) continue;
    }
    filtered.push_back(event);
  }
  std::stable_sort(filtered.begin(), filtered.end(), [&](const auto& left, const auto& right) {
    const int comparison = compare_event(left, right, query.sort_by);
    if (comparison == 0) {
      return query.sort_direction == "desc" ? left.id > right.id : left.id < right.id;
    }
    return query.sort_direction == "desc" ? comparison > 0 : comparison < 0;
  });
  EventSearchPageV2 page;
  page.total = static_cast<int>(filtered.size());
  page.page = query.page;
  page.page_size = query.page_size;
  const auto page_index = static_cast<std::size_t>(query.page - 1);
  const auto page_size = static_cast<std::size_t>(query.page_size);
  const auto offset = page_index > std::numeric_limits<std::size_t>::max() / page_size
                          ? std::numeric_limits<std::size_t>::max()
                          : page_index * page_size;
  page.has_more = offset < filtered.size() && page_size < filtered.size() - offset;
  if (offset < filtered.size()) {
    const auto end = offset + std::min(page_size, filtered.size() - offset);
    page.items.assign(filtered.begin() + static_cast<std::ptrdiff_t>(offset),
                      filtered.begin() + static_cast<std::ptrdiff_t>(end));
  }
  return common::Result<EventSearchPageV2>::success(std::move(page));
}

common::Result<std::optional<domain::Recurrence>>
RecurringEventQueryService::get_recurrence_for_event(const std::string& event_id) const {
  if (!common::is_uuid(event_id)) {
    return common::Result<std::optional<domain::Recurrence>>::failure(
        contract_invalid("event_id", "event_id must be a UUID"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Recurrence>>::failure(loaded.error());
  }
  const auto* event = find_event(loaded.value(), event_id);
  if (event == nullptr || event->deleted_at.has_value()) {
    return common::Result<std::optional<domain::Recurrence>>::failure(
        event_not_found(event_id));
  }
  if (!event->recurrence_revision.has_value()) {
    return common::Result<std::optional<domain::Recurrence>>::success(std::nullopt);
  }
  const auto* recurrence = find_recurrence(
      loaded.value(), *event, *event->recurrence_revision);
  if (recurrence == nullptr) {
    return common::Result<std::optional<domain::Recurrence>>::failure(
        internal_error("Event current recurrence revision is missing"));
  }
  return common::Result<std::optional<domain::Recurrence>>::success(*recurrence);
}

common::Result<domain::Recurrence> RecurringEventQueryService::get_current_recurrence(
    const std::string& event_id) const {
  if (!common::is_uuid(event_id)) {
    return common::Result<domain::Recurrence>::failure(
        contract_invalid("event_id", "event_id must be a UUID"));
  }
  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<domain::Recurrence>::failure(loaded.error());
  const auto* event = find_event(loaded.value(), event_id);
  if (event == nullptr || event->deleted_at.has_value()) {
    return common::Result<domain::Recurrence>::failure(event_not_found(event_id));
  }
  if (!event->recurrence_revision.has_value()) {
    return common::Result<domain::Recurrence>::failure(
        internal_error("Event is not recurring in recurring storage"));
  }
  const auto* recurrence = find_recurrence(
      loaded.value(), *event, *event->recurrence_revision);
  if (recurrence == nullptr) {
    return common::Result<domain::Recurrence>::failure(
        internal_error("Event current recurrence revision is missing"));
  }
  return common::Result<domain::Recurrence>::success(*recurrence);
}

common::Result<EventOccurrencePage> RecurringEventQueryService::list_occurrences(
    const ListEventOccurrencesCommand& command) const {
  if (!common::is_uuid(command.event_id) || command.recurrence_revision < 1 ||
      command.limit < 1 || command.limit > 200) {
    return common::Result<EventOccurrencePage>::failure(
        contract_invalid("ListEventOccurrencesRequest", "identity or limit is invalid"));
  }
  const bool timed_shape = !command.is_all_day && command.range_start_at.has_value() &&
                           command.range_end_at.has_value() &&
                           !command.range_start_date.has_value() &&
                           !command.range_end_date.has_value();
  const bool all_day_shape = command.is_all_day && !command.range_start_at.has_value() &&
                             !command.range_end_at.has_value() &&
                             command.range_start_date.has_value() &&
                             command.range_end_date.has_value();
  std::optional<std::int64_t> range_start_epoch;
  std::optional<std::int64_t> range_end_epoch;
  std::optional<domain::LocalDate> range_start_date;
  std::optional<domain::LocalDate> range_end_date;
  if (timed_shape) {
    range_start_epoch = common::parse_iso8601_utc_epoch_seconds(*command.range_start_at);
    range_end_epoch = common::parse_iso8601_utc_epoch_seconds(*command.range_end_at);
    if (!range_start_epoch.has_value() || !range_end_epoch.has_value() ||
        *range_start_epoch >= *range_end_epoch) {
      return common::Result<EventOccurrencePage>::failure(
          contract_invalid("range", "timed range must be a positive half-open UTC interval"));
    }
  } else if (all_day_shape) {
    const auto start = domain::parse_local_date(*command.range_start_date);
    const auto end = domain::parse_local_date(*command.range_end_date);
    if (!start.ok() || !end.ok() || !(start.value() < end.value())) {
      return common::Result<EventOccurrencePage>::failure(
          contract_invalid("range", "all-day range must be a positive half-open date interval"));
    }
    range_start_date = start.value();
    range_end_date = end.value();
  } else {
    return common::Result<EventOccurrencePage>::failure(
        contract_invalid("range", "range shape must match is_all_day"));
  }

  auto loaded = transaction_->load();
  if (!loaded.ok()) return common::Result<EventOccurrencePage>::failure(loaded.error());
  const auto* event = find_event(loaded.value(), command.event_id);
  if (event == nullptr || event->deleted_at.has_value()) {
    return common::Result<EventOccurrencePage>::failure(event_not_found(command.event_id));
  }
  if (event->is_all_day != command.is_all_day) {
    return common::Result<EventOccurrencePage>::failure(
        contract_invalid("is_all_day", "query shape conflicts with the stored Event"));
  }
  const int actual_revision = event->recurrence_revision.value_or(0);
  if (actual_revision != command.recurrence_revision) {
    return common::Result<EventOccurrencePage>::failure(
        revision_conflict(command.recurrence_revision, actual_revision));
  }
  const auto* recurrence = find_recurrence(
      loaded.value(), *event, command.recurrence_revision);
  if (recurrence == nullptr) {
    return common::Result<EventOccurrencePage>::failure(
        internal_error("Event current recurrence revision is missing"));
  }

  EventOccurrencePage page;
  bool cursor_seen = !command.cursor.has_value();
  bool reached_range_end = false;
  for (int index = 0; index < kMaximumExpansionCount; ++index) {
    auto occurrence = recurrence_service_->occurrence_at(
        domain::recurring_schedule_from_event(*event), *recurrence, index);
    if (!occurrence.ok()) {
      return common::Result<EventOccurrencePage>::failure(occurrence.error());
    }
    bool before_range = false;
    if (timed_shape) {
      const auto start = common::parse_iso8601_utc_epoch_seconds(
          *occurrence.value().occurrence_start_at);
      if (!start.has_value()) {
        return common::Result<EventOccurrencePage>::failure(
            internal_error("expanded occurrence instant is invalid"));
      }
      before_range = *start < *range_start_epoch;
      reached_range_end = *start >= *range_end_epoch;
    } else {
      const auto start = domain::parse_local_date(
          *occurrence.value().occurrence_start_date);
      if (!start.ok()) return common::Result<EventOccurrencePage>::failure(start.error());
      before_range = start.value() < *range_start_date;
      reached_range_end = !(start.value() < *range_end_date);
    }
    if (reached_range_end) break;
    if (before_range) continue;
    if (!cursor_seen) {
      if (occurrence.value().occurrence_key == *command.cursor) cursor_seen = true;
      continue;
    }
    page.items.push_back(EventOccurrenceProjection{
        occurrence.value(), occurrence_state_for(loaded.value(), occurrence.value())});
    if (page.items.size() > static_cast<std::size_t>(command.limit)) break;
  }
  if (!cursor_seen) {
    return common::Result<EventOccurrencePage>::failure(
        contract_invalid("cursor", "cursor is not an occurrence in the requested window"));
  }
  if (!reached_range_end && page.items.size() <= static_cast<std::size_t>(command.limit)) {
    return common::Result<EventOccurrencePage>::failure(
        internal_error("occurrence expansion exceeded safe bound"));
  }
  page.has_more = page.items.size() > static_cast<std::size_t>(command.limit);
  if (page.has_more) {
    page.items.resize(static_cast<std::size_t>(command.limit));
    page.next_cursor = page.items.back().occurrence.occurrence_key;
  }
  return common::Result<EventOccurrencePage>::success(std::move(page));
}

}  // namespace excellent_calendar::application
