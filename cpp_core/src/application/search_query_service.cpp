#include "excellent_calendar/application/search_query_service.hpp"

#include "excellent_calendar/application/completed_recurring_series_eligibility.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/recurrence.hpp"

namespace excellent_calendar::application {
namespace {

constexpr std::string_view kCursorDomain =
    "excellent-calendar/search-cursor/v1";
constexpr std::string_view kSnapshotDomain =
    "excellent-calendar/search-snapshot/v1";

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

common::Error query_error(std::string reason) {
  return common::make_error("SEARCH_QUERY_INVALID", "Search query is invalid",
                            {{"reason", std::move(reason)}});
}

common::Error cursor_mismatch(std::string reason) {
  return common::make_error("SEARCH_CURSOR_QUERY_MISMATCH",
                            "Search cursor does not match query",
                            {{"reason", std::move(reason)}});
}

common::Error corrupted(std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored calendar data is corrupted",
                            {{"reason", std::move(reason)}});
}

domain::LocalDate date_part(const domain::LocalDateTime& value) {
  return {value.year, value.month, value.day};
}

std::string date_text(const std::optional<domain::LocalDate>& value) {
  return value.has_value() ? domain::format_local_date(*value) : "";
}

std::string recurrence_key(std::string_view id, int revision) {
  return std::string(id) + "\n" + std::to_string(revision);
}

std::string occurrence_state_key(std::string_view event_id, int revision,
                                 std::string_view occurrence_key) {
  return std::string(event_id) + "\n" + std::to_string(revision) + "\n" +
         std::string(occurrence_key);
}

int month_distance(const domain::LocalDate& from,
                   const domain::LocalDate& to) {
  return (to.year - from.year) * 12 + to.month - from.month;
}

int first_candidate_index(const domain::Recurrence& recurrence,
                          const domain::LocalDate& original_start,
                          const domain::LocalDate& original_end,
                          const domain::LocalDate& range_start) {
  const int duration_days =
      std::max(0, domain::local_days_between(original_start, original_end));
  if (recurrence.frequency == domain::kRecurrenceDaily) {
    return std::max(0, domain::local_days_between(original_start, range_start) -
                           duration_days - 2);
  }
  if (recurrence.frequency == domain::kRecurrenceWeekly) {
    return std::max(0, (domain::local_days_between(original_start, range_start) -
                        duration_days - 8) /
                           7);
  }
  return std::max(0, month_distance(original_start, range_start) -
                         (duration_days + 27) / 28 - 2);
}

int candidate_index_for_date(const domain::Recurrence& recurrence,
                             const domain::LocalDate& original_start,
                             const domain::LocalDate& date) {
  if (recurrence.frequency == domain::kRecurrenceDaily)
    return std::max(0, domain::local_days_between(original_start, date));
  if (recurrence.frequency == domain::kRecurrenceWeekly)
    return std::max(0,
                    domain::local_days_between(original_start, date) / 7);
  return std::max(0, month_distance(original_start, date));
}

common::Result<int> occurrence_state_index(
    const domain::EventOccurrenceState& state,
    const domain::Recurrence& recurrence,
    const domain::LocalDate& original_start, bool is_all_day,
    const domain::LocalTimeResolver& resolver) {
  domain::LocalDate state_date;
  if (is_all_day) {
    if (!state.occurrence_start_date.has_value() ||
        state.occurrence_start_at.has_value())
      return fail<int>(corrupted("all-day occurrence-state time is invalid"));
    auto parsed = domain::parse_local_date(*state.occurrence_start_date);
    if (!parsed.ok()) return fail<int>(parsed.error());
    state_date = parsed.value();
  } else {
    if (!state.occurrence_start_at.has_value() ||
        state.occurrence_start_date.has_value())
      return fail<int>(corrupted("timed occurrence-state time is invalid"));
    auto local = resolver.to_local(*state.occurrence_start_at,
                                   recurrence.timezone);
    if (!local.ok()) return fail<int>(local.error());
    state_date = date_part(local.value());
  }
  const int days = domain::local_days_between(original_start, state_date);
  int index = -1;
  if (recurrence.frequency == domain::kRecurrenceDaily) {
    index = days;
  } else if (recurrence.frequency == domain::kRecurrenceWeekly) {
    if (days % 7 != 0)
      return fail<int>(corrupted("occurrence-state is off recurrence cadence"));
    index = days / 7;
  } else {
    index = month_distance(original_start, state_date);
  }
  if (index < 0 || index >= 1000000)
    return fail<int>(corrupted("occurrence-state index is out of range"));
  domain::LocalDate expected;
  if (recurrence.frequency == domain::kRecurrenceDaily) {
    expected = domain::add_local_days(original_start, index);
  } else if (recurrence.frequency == domain::kRecurrenceWeekly) {
    expected = domain::add_local_days(original_start, index * 7);
  } else {
    expected = domain::add_local_months_with_anchor(
        original_start, index, *recurrence.day_of_month);
  }
  if (!(expected == state_date))
    return fail<int>(corrupted("occurrence-state is off recurrence cadence"));
  return common::Result<int>::success(index);
}

struct BlockedIndexInterval {
  int first = 0;
  int last = 0;
};

std::vector<BlockedIndexInterval> blocked_intervals(std::vector<int> indices) {
  if (indices.empty()) return {};
  std::sort(indices.begin(), indices.end());
  indices.erase(std::unique(indices.begin(), indices.end()), indices.end());
  std::vector<BlockedIndexInterval> result;
  for (const int index : indices) {
    if (result.empty() || index > result.back().last + 1) {
      result.push_back({index, index});
    } else {
      result.back().last = index;
    }
  }
  return result;
}

void add_index_window(std::set<int>& candidates, int first, int last) {
  first = std::max(0, first);
  last = std::min(999999, last);
  for (int index = first; index <= last; ++index) candidates.insert(index);
}

void add_block_boundaries(std::set<int>& candidates,
                          const std::vector<BlockedIndexInterval>& intervals) {
  const std::vector<int> seeds(candidates.begin(), candidates.end());
  for (const int seed : seeds) {
    const auto after = std::upper_bound(
        intervals.begin(), intervals.end(), seed,
        [](int value, const BlockedIndexInterval& interval) {
          return value < interval.first;
        });
    if (after == intervals.begin()) continue;
    const auto& interval = *std::prev(after);
    if (seed < interval.first || seed > interval.last) continue;
    add_index_window(candidates, interval.first - 3, interval.first + 2);
    add_index_window(candidates, interval.last - 2, interval.last + 3);
  }
}

class BinaryWriter {
 public:
  void byte(std::uint8_t value) { bytes_.push_back(value); }
  void boolean(bool value) { byte(value ? 1U : 0U); }
  void integer(std::int64_t value) {
    const auto bits = static_cast<std::uint64_t>(value);
    for (int shift = 56; shift >= 0; shift -= 8) {
      byte(static_cast<std::uint8_t>(bits >> shift));
    }
  }
  void string(std::string_view value) {
    const auto size = static_cast<std::uint32_t>(value.size());
    for (int shift = 24; shift >= 0; shift -= 8) {
      byte(static_cast<std::uint8_t>(size >> shift));
    }
    bytes_.insert(bytes_.end(), value.begin(), value.end());
  }
  const std::vector<std::uint8_t>& bytes() const { return bytes_; }

 private:
  std::vector<std::uint8_t> bytes_;
};

class BinaryReader {
 public:
  explicit BinaryReader(const std::vector<std::uint8_t>& bytes)
      : bytes_(bytes) {}
  bool byte(std::uint8_t& value) {
    if (offset_ >= bytes_.size()) return false;
    value = bytes_[offset_++];
    return true;
  }
  bool boolean(bool& value) {
    std::uint8_t byte_value = 0;
    if (!byte(byte_value) || byte_value > 1U) return false;
    value = byte_value == 1U;
    return true;
  }
  bool integer(std::int64_t& value) {
    if (offset_ + 8U > bytes_.size()) return false;
    std::uint64_t result = 0;
    for (int index = 0; index < 8; ++index) {
      result = (result << 8U) | bytes_[offset_++];
    }
    value = static_cast<std::int64_t>(result);
    return true;
  }
  bool string(std::string& value) {
    if (offset_ + 4U > bytes_.size()) return false;
    std::uint32_t size = 0;
    for (int index = 0; index < 4; ++index) {
      size = (size << 8U) | bytes_[offset_++];
    }
    if (size > 4096U || offset_ + size > bytes_.size()) return false;
    value.assign(reinterpret_cast<const char*>(bytes_.data() + offset_), size);
    offset_ += size;
    return true;
  }
  bool finished() const { return offset_ == bytes_.size(); }

 private:
  const std::vector<std::uint8_t>& bytes_;
  std::size_t offset_ = 0;
};

struct SnapshotIdentity {
  std::string evaluated_at;
  std::vector<domain::SearchTargetType> targets;
  std::array<std::int64_t, repository::kSearchQueryContributingStores.size()>
      generations{};
};

void write_target(BinaryWriter& writer, domain::SearchTargetType target) {
  writer.byte(static_cast<std::uint8_t>(target));
}

bool read_target(BinaryReader& reader, domain::SearchTargetType& target) {
  std::uint8_t value = 0;
  if (!reader.byte(value) || value > 2U) return false;
  target = static_cast<domain::SearchTargetType>(value);
  return true;
}

std::string snapshot_token_for(
    const SnapshotIdentity& identity, const common::SearchHmacKey& key) {
  BinaryWriter writer;
  writer.byte(1U);
  writer.string(identity.evaluated_at);
  writer.byte(static_cast<std::uint8_t>(identity.targets.size()));
  for (const auto target : identity.targets) write_target(writer, target);
  for (const auto generation : identity.generations) writer.integer(generation);
  return common::encode_authenticated_search_token(
      "srchsnap1", kSnapshotDomain, writer.bytes(), key);
}

common::Result<SnapshotIdentity> parse_snapshot_token(
    std::string_view token, const common::SearchHmacKey& key) {
  auto payload = common::decode_authenticated_search_token(
      token, "srchsnap1", kSnapshotDomain, 522U, key);
  if (!payload.ok()) return fail<SnapshotIdentity>(payload.error());
  BinaryReader reader(payload.value());
  std::uint8_t version = 0;
  std::uint8_t target_count = 0;
  SnapshotIdentity identity;
  if (!reader.byte(version) || version != 1U ||
      !reader.string(identity.evaluated_at) || !reader.byte(target_count) ||
      target_count < 1U || target_count > 3U) {
    return fail<SnapshotIdentity>(common::make_error(
        "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
  }
  for (std::uint8_t index = 0; index < target_count; ++index) {
    domain::SearchTargetType target;
    if (!read_target(reader, target)) {
      return fail<SnapshotIdentity>(common::make_error(
          "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
    }
    identity.targets.push_back(target);
  }
  for (auto& generation : identity.generations) {
    if (!reader.integer(generation) || generation < 0) {
      return fail<SnapshotIdentity>(common::make_error(
          "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
    }
  }
  return reader.finished()
             ? common::Result<SnapshotIdentity>::success(std::move(identity))
             : fail<SnapshotIdentity>(common::make_error(
                   "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
}

std::string canonical_query_binding(const SearchQuery& query,
                                    const domain::NormalizedSearchText& keyword,
                                    domain::SearchTargetType section_target) {
  BinaryWriter writer;
  writer.byte(1U);
  writer.string(keyword.comparison);
  writer.byte(static_cast<std::uint8_t>(query.target_types.size()));
  for (const auto target : query.target_types) write_target(writer, target);
  writer.string(date_text(query.date_from));
  writer.string(date_text(query.date_to_exclusive));
  if (!query.category_ids.has_value()) {
    writer.byte(0U);
  } else {
    writer.byte(query.category_ids->empty() ? 1U : 2U);
    writer.byte(static_cast<std::uint8_t>(query.category_ids->size()));
    for (const auto& id : *query.category_ids) writer.string(id);
  }
  writer.boolean(query.include_uncategorized);
  writer.boolean(query.include_completed);
  writer.byte(static_cast<std::uint8_t>(query.sort_by));
  write_target(writer, section_target);
  writer.string(query.timezone);
  writer.integer(20);
  writer.integer(2);
  writer.integer(2);
  return std::string(reinterpret_cast<const char*>(writer.bytes().data()),
                     writer.bytes().size());
}

struct CursorIdentity {
  std::string binding;
  std::string evaluated_at;
  std::string snapshot_token;
  std::string last_sort_key;
};

std::string cursor_token_for(const CursorIdentity& cursor,
                             const common::SearchHmacKey& key) {
  BinaryWriter writer;
  writer.byte(1U);
  writer.string(cursor.binding);
  writer.string(cursor.evaluated_at);
  writer.string(cursor.snapshot_token);
  writer.string(cursor.last_sort_key);
  return common::encode_authenticated_search_token("srchcur1", kCursorDomain,
                                                    writer.bytes(), key);
}

common::Result<CursorIdentity> parse_cursor_token(
    std::string_view token, const common::SearchHmacKey& key) {
  auto payload = common::decode_authenticated_search_token(
      token, "srchcur1", kCursorDomain, 2057U, key);
  if (!payload.ok()) return fail<CursorIdentity>(payload.error());
  BinaryReader reader(payload.value());
  std::uint8_t version = 0;
  CursorIdentity cursor;
  if (!reader.byte(version) || version != 1U ||
      !reader.string(cursor.binding) || !reader.string(cursor.evaluated_at) ||
      !reader.string(cursor.snapshot_token) ||
      !reader.string(cursor.last_sort_key) || !reader.finished()) {
    return fail<CursorIdentity>(common::make_error(
        "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
  }
  return common::Result<CursorIdentity>::success(std::move(cursor));
}

bool canonical_targets(const std::vector<domain::SearchTargetType>& targets) {
  if (targets.empty() || targets.size() > 3U) return false;
  for (std::size_t index = 0; index < targets.size(); ++index) {
    if (static_cast<std::size_t>(targets[index]) >= 3U ||
        (index > 0U && static_cast<int>(targets[index - 1U]) >=
                           static_cast<int>(targets[index]))) {
      return false;
    }
  }
  return true;
}

common::Result<common::Unit> validate_query_shape(const SearchQuery& query) {
  if (query.query_generation < 0 || query.query_generation > 9007199254740991LL)
    return fail<common::Unit>(query_error("query_generation is out of range"));
  if (!canonical_targets(query.target_types))
    return fail<common::Unit>(query_error("target_types are not canonical"));
  if (query.date_from.has_value() != query.date_to_exclusive.has_value() ||
      (query.date_from.has_value() &&
       !(*query.date_from < *query.date_to_exclusive))) {
    return fail<common::Unit>(query_error("date range is invalid"));
  }
  if (!query.category_ids.has_value()) {
    if (query.include_uncategorized)
      return fail<common::Unit>(query_error("category filter mode is invalid"));
  } else {
    if (query.category_ids->empty() && !query.include_uncategorized)
      return fail<common::Unit>(query_error("category filter is empty"));
    if (query.category_ids->size() > 100U)
      return fail<common::Unit>(query_error("category filter is too large"));
    std::set<std::string> unique;
    for (const auto& id : *query.category_ids) {
      if (id.empty() || id.size() > 512U || !unique.insert(id).second)
        return fail<common::Unit>(query_error("category IDs are invalid"));
    }
  }
  if (query.sections.empty() || query.sections.size() > 3U)
    return fail<common::Unit>(query_error("sections are invalid"));
  std::vector<domain::SearchTargetType> section_targets;
  int cursor_count = 0;
  for (const auto& section : query.sections) {
    if (section.page_size != 20)
      return fail<common::Unit>(query_error("page_size must equal 20"));
    if (std::find(query.target_types.begin(), query.target_types.end(),
                  section.target_type) == query.target_types.end())
      return fail<common::Unit>(query_error("section target is not requested"));
    section_targets.push_back(section.target_type);
    cursor_count += section.cursor.has_value() ? 1 : 0;
  }
  if (!canonical_targets(section_targets))
    return fail<common::Unit>(query_error("section targets are not canonical"));
  if (query.sections.size() > 1U &&
      (cursor_count != 0 || section_targets != query.target_types))
    return fail<common::Unit>(
        query_error("multi-section request shape is invalid"));
  if (cursor_count > 0 && query.sections.size() != 1U)
    return fail<common::Unit>(query_error("continuation must have one section"));
  return common::Result<common::Unit>::success(common::Unit{});
}

struct QueryContext {
  std::string evaluated_at;
  std::int64_t evaluated_epoch = 0;
  domain::LocalDate today;
  std::optional<std::int64_t> range_start_epoch;
  std::optional<std::int64_t> range_end_epoch;
};

common::Result<QueryContext> build_context(
    const SearchQuery& query, std::string evaluated_at,
    const domain::LocalTimeResolver& resolver) {
  auto timezone = resolver.validate_timezone(query.timezone);
  if (!timezone.ok()) return fail<QueryContext>(timezone.error());
  const auto epoch = common::parse_iso8601_utc_epoch_seconds(evaluated_at);
  auto local = resolver.to_local(evaluated_at, query.timezone);
  if (!epoch.has_value() || !local.ok()) {
    return local.ok() ? fail<QueryContext>(common::make_error(
                            "NATIVE_INTERNAL_ERROR",
                            "Search evaluation clock is invalid"))
                      : fail<QueryContext>(local.error());
  }
  QueryContext context;
  context.evaluated_at = std::move(evaluated_at);
  context.evaluated_epoch = *epoch;
  context.today = date_part(local.value());
  if (query.date_from.has_value()) {
    auto start = resolver.resolve_local_datetime(
        {query.date_from->year, query.date_from->month, query.date_from->day,
         0, 0, 0},
        query.timezone);
    auto end = resolver.resolve_local_datetime(
        {query.date_to_exclusive->year, query.date_to_exclusive->month,
         query.date_to_exclusive->day, 0, 0, 0},
        query.timezone);
    if (!start.ok()) return fail<QueryContext>(start.error());
    if (!end.ok()) return fail<QueryContext>(end.error());
    context.range_start_epoch =
        common::parse_iso8601_utc_epoch_seconds(start.value().utc_instant);
    context.range_end_epoch =
        common::parse_iso8601_utc_epoch_seconds(end.value().utc_instant);
    if (!context.range_start_epoch.has_value() ||
        !context.range_end_epoch.has_value() ||
        *context.range_start_epoch >= *context.range_end_epoch) {
      return fail<QueryContext>(query_error("resolved date range is invalid"));
    }
  }
  return common::Result<QueryContext>::success(std::move(context));
}

struct CategoryIndex {
  std::unordered_map<std::string, SearchCategoryProjection> active;
};

common::Result<common::Unit> validate_searchable_store_text(
    const repository::SearchQuerySnapshot& snapshot,
    const std::vector<domain::SearchTargetType>& targets) {
  for (const auto& category : snapshot.categories) {
    auto value = domain::normalize_searchable_text(category.name);
    if (!value.ok())
      return fail<common::Unit>(
          corrupted("Category contains invalid UTF-8: " + category.id));
  }
  if (std::find(targets.begin(), targets.end(), domain::SearchTargetType::event) !=
      targets.end()) {
    for (const auto& event : snapshot.events) {
      const std::array<std::string_view, 3> fields{{
          event.title,
          event.content.has_value() ? std::string_view(*event.content)
                                    : std::string_view(),
          event.location.has_value() ? std::string_view(*event.location)
                                     : std::string_view()}};
      for (const auto field : fields) {
        auto value = domain::normalize_searchable_text(field);
        if (!value.ok())
          return fail<common::Unit>(
              corrupted("Event contains invalid UTF-8: " + event.id));
      }
    }
  }
  if (std::find(targets.begin(), targets.end(), domain::SearchTargetType::habit) !=
      targets.end()) {
    for (const auto& habit : snapshot.habits) {
      const std::array<std::string_view, 2> fields{{
          habit.title,
          habit.description.has_value() ? std::string_view(*habit.description)
                                        : std::string_view()}};
      for (const auto field : fields) {
        auto value = domain::normalize_searchable_text(field);
        if (!value.ok())
          return fail<common::Unit>(
              corrupted("Habit contains invalid UTF-8: " + habit.id));
      }
    }
  }
  if (std::find(targets.begin(), targets.end(),
                domain::SearchTargetType::anniversary) != targets.end()) {
    for (const auto& anniversary : snapshot.anniversaries) {
      const std::array<std::string_view, 2> fields{{
          anniversary.title,
          anniversary.note.has_value() ? std::string_view(*anniversary.note)
                                       : std::string_view()}};
      for (const auto field : fields) {
        auto value = domain::normalize_searchable_text(field);
        if (!value.ok())
          return fail<common::Unit>(corrupted(
              "Anniversary contains invalid UTF-8: " + anniversary.id));
      }
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<CategoryIndex> build_categories(
    const repository::SearchQuerySnapshot& snapshot) {
  CategoryIndex result;
  for (const auto& category : snapshot.categories) {
    if (category.deleted_at.has_value()) continue;
    SearchCategoryProjection projection{category.id, category.name,
                                        category.color, category.icon};
    if (!result.active.emplace(category.id, std::move(projection)).second)
      return fail<CategoryIndex>(corrupted("Category identity is duplicated"));
  }
  return common::Result<CategoryIndex>::success(std::move(result));
}

std::optional<SearchCategoryProjection> category_for(
    const std::optional<std::string>& id, const CategoryIndex& categories) {
  if (!id.has_value()) return std::nullopt;
  const auto found = categories.active.find(*id);
  return found == categories.active.end()
             ? std::nullopt
             : std::optional<SearchCategoryProjection>(found->second);
}

bool category_filter_matches(const std::optional<std::string>& id,
                             const SearchQuery& query) {
  if (!query.category_ids.has_value()) return true;
  if (!id.has_value()) return query.include_uncategorized;
  return std::find(query.category_ids->begin(), query.category_ids->end(), *id) !=
         query.category_ids->end();
}

std::string category_name(
    const std::optional<SearchCategoryProjection>& category) {
  return category.has_value() ? category->name : "";
}

struct Candidate {
  SearchItem item;
  int relevance = 0;
  int completion = 0;
  int temporal_bucket = 2;
  std::int64_t temporal_distance = 0;
  std::string updated_at;
  std::string target_id;
  std::string mixed_time_key;
  bool event_time = false;
  std::int64_t event_day_distance = 0;
  bool event_all_day = false;
};

bool candidate_less(const Candidate& left, const Candidate& right,
                    SearchSort sort) {
  if (sort == SearchSort::updated_at) {
    if (left.updated_at != right.updated_at)
      return left.updated_at > right.updated_at;
    return left.target_id < right.target_id;
  }
  if (sort == SearchSort::relevance) {
    if (left.relevance != right.relevance)
      return left.relevance < right.relevance;
    if (left.completion != right.completion)
      return left.completion < right.completion;
  }
  if (left.temporal_bucket != right.temporal_bucket)
    return left.temporal_bucket < right.temporal_bucket;
  if (left.event_time && right.event_time) {
    if (left.event_day_distance != right.event_day_distance)
      return left.event_day_distance < right.event_day_distance;
    if (left.event_all_day != right.event_all_day)
      return left.event_all_day;
    if (left.temporal_distance != right.temporal_distance)
      return left.temporal_distance < right.temporal_distance;
  } else {
    if (left.temporal_distance != right.temporal_distance)
      return left.temporal_distance < right.temporal_distance;
  }
  if (sort == SearchSort::relevance && left.updated_at != right.updated_at)
    return left.updated_at > right.updated_at;
  return left.target_id < right.target_id;
}

std::string candidate_sort_key(const Candidate& candidate, SearchSort sort) {
  BinaryWriter writer;
  writer.byte(1U);
  writer.byte(static_cast<std::uint8_t>(sort));
  writer.integer(candidate.relevance);
  writer.integer(candidate.completion);
  writer.integer(candidate.temporal_bucket);
  writer.integer(candidate.temporal_distance);
  writer.string(candidate.updated_at);
  writer.string(candidate.target_id);
  writer.string(candidate.mixed_time_key);
  writer.boolean(candidate.event_time);
  writer.integer(candidate.event_day_distance);
  writer.boolean(candidate.event_all_day);
  return std::string(reinterpret_cast<const char*>(writer.bytes().data()),
                     writer.bytes().size());
}

struct EventOccurrenceProjection {
  std::optional<domain::EventOccurrence> occurrence;
  std::optional<domain::EventOccurrenceState> state;
  std::string status;
  std::optional<std::int64_t> start_epoch;
  std::optional<std::int64_t> end_epoch;
  std::optional<domain::LocalDate> start_date;
  std::optional<domain::LocalDate> end_date;
  domain::LocalDate occupied_start;
  domain::LocalDate occupied_end_exclusive;
  int selection_distance = 0;
  bool current_or_future = false;
  std::string local_start_key;
};

std::string event_status(
    const domain::Event& event,
    const std::optional<domain::EventOccurrenceState>& state,
    const EventOccurrenceProjection& projection, const QueryContext& context) {
  if (state.has_value()) {
    if (state->status == domain::kOccurrenceCompleted) return "completed";
    if (state->status == domain::kOccurrenceSkipped) return "skipped";
  }
  if (event.status == domain::kEventStatusCompleted)
    return "completed";
  if (event.is_all_day) {
    if (context.today < *projection.start_date) return "pending";
    if (context.today < *projection.end_date) return "in_progress";
    return "overdue";
  }
  if (context.evaluated_epoch < *projection.start_epoch) return "pending";
  if (context.evaluated_epoch < *projection.end_epoch) return "in_progress";
  return "overdue";
}

common::Result<EventOccurrenceProjection> project_occurrence(
    const domain::Event& event,
    const std::optional<domain::EventOccurrence>& occurrence,
    const std::optional<domain::EventOccurrenceState>& state,
    const QueryContext& context, const SearchQuery& query,
    const domain::LocalTimeResolver& resolver) {
  EventOccurrenceProjection projection;
  projection.occurrence = occurrence;
  projection.state = state;
  if (event.is_all_day) {
    const auto start_text = occurrence.has_value()
                                ? occurrence->occurrence_start_date
                                : event.start_date;
    const auto end_text = occurrence.has_value() ? occurrence->occurrence_end_date
                                                  : event.end_date;
    if (!start_text.has_value() || !end_text.has_value())
      return fail<EventOccurrenceProjection>(
          corrupted("all-day Event interval is missing"));
    auto start = domain::parse_local_date(*start_text);
    auto end = domain::parse_local_date(*end_text);
    if (!start.ok()) return fail<EventOccurrenceProjection>(start.error());
    if (!end.ok()) return fail<EventOccurrenceProjection>(end.error());
    projection.start_date = start.value();
    projection.end_date = end.value();
    projection.occupied_start = start.value();
    projection.occupied_end_exclusive = end.value();
    projection.local_start_key = domain::format_local_date(start.value()) + "\n0";
  } else {
    const auto start_text = occurrence.has_value()
                                ? occurrence->occurrence_start_at.value_or("")
                                : event.start_at;
    const auto end_text = occurrence.has_value()
                              ? occurrence->occurrence_end_at.value_or("")
                              : event.end_at;
    projection.start_epoch = common::parse_iso8601_utc_epoch_seconds(start_text);
    projection.end_epoch = common::parse_iso8601_utc_epoch_seconds(end_text);
    if (!projection.start_epoch.has_value() ||
        !projection.end_epoch.has_value() ||
        *projection.start_epoch >= *projection.end_epoch)
      return fail<EventOccurrenceProjection>(
          corrupted("timed Event interval is invalid"));
    auto local_start = resolver.to_local(start_text, query.timezone);
    auto local_end = resolver.to_local(end_text, query.timezone);
    if (!local_start.ok()) return fail<EventOccurrenceProjection>(local_start.error());
    if (!local_end.ok()) return fail<EventOccurrenceProjection>(local_end.error());
    projection.occupied_start = date_part(local_start.value());
    projection.occupied_end_exclusive = date_part(local_end.value());
    if (local_end.value().hour != 0 || local_end.value().minute != 0 ||
        local_end.value().second != 0) {
      projection.occupied_end_exclusive =
          domain::add_local_days(projection.occupied_end_exclusive, 1);
    }
    std::ostringstream local_key;
    local_key << domain::format_local_date(projection.occupied_start)
              << "\n1\n" << std::setfill('0') << std::setw(2)
              << local_start.value().hour << ':' << std::setw(2)
              << local_start.value().minute << ':' << std::setw(2)
              << local_start.value().second;
    projection.local_start_key = local_key.str();
  }
  projection.status = event_status(event, state, projection, context);
  if (!(context.today < projection.occupied_start) &&
      context.today < projection.occupied_end_exclusive) {
    projection.selection_distance = 0;
    projection.current_or_future = true;
  } else if (context.today < projection.occupied_start) {
    projection.selection_distance =
        domain::local_days_between(context.today, projection.occupied_start);
    projection.current_or_future = true;
  } else {
    const auto last = domain::add_local_days(projection.occupied_end_exclusive, -1);
    projection.selection_distance =
        domain::local_days_between(last, context.today);
  }
  if (!event.is_all_day) {
    projection.current_or_future =
        context.evaluated_epoch < *projection.end_epoch;
  }
  return common::Result<EventOccurrenceProjection>::success(
      std::move(projection));
}

bool event_range_matches(const EventOccurrenceProjection& occurrence,
                         const SearchQuery& query,
                         const QueryContext& context) {
  if (!query.date_from.has_value()) return true;
  if (occurrence.start_date.has_value()) {
    return *occurrence.start_date < *query.date_to_exclusive &&
           *query.date_from < *occurrence.end_date;
  }
  return *occurrence.start_epoch < *context.range_end_epoch &&
         *occurrence.end_epoch > *context.range_start_epoch;
}

common::Result<std::vector<Candidate>> project_events(
    const repository::SearchQuerySnapshot& snapshot, const CategoryIndex& categories,
    const SearchQuery& query, const domain::NormalizedSearchText& keyword,
    const QueryContext& context, const domain::LocalTimeResolver& resolver,
    const RecurrenceService& recurrence_service,
    SearchQueryDiagnostics* diagnostics) {
  std::unordered_map<std::string, const domain::Recurrence*> recurrences;
  for (const auto& recurrence : snapshot.event_recurrences) {
    if (!recurrences.emplace(recurrence_key(recurrence.id, recurrence.revision),
                             &recurrence)
             .second)
      return fail<std::vector<Candidate>>(
          corrupted("Event recurrence identity is duplicated"));
  }
  std::unordered_map<std::string, const domain::EventOccurrenceState*> states;
  std::unordered_map<
      std::string, std::vector<const domain::EventOccurrenceState*>>
      states_by_series;
  for (const auto& state : snapshot.event_occurrence_states) {
    if (!states.emplace(occurrence_state_key(state.event_id,
                                              state.recurrence_revision,
                                              state.occurrence_key),
                        &state)
             .second)
      return fail<std::vector<Candidate>>(
          corrupted("Event occurrence-state identity is duplicated"));
    states_by_series[recurrence_key(state.event_id,
                                    state.recurrence_revision)]
        .push_back(&state);
  }

  std::vector<Candidate> result;
  result.reserve(snapshot.events.size());
  for (const auto& event : snapshot.events) {
    if (event.deleted_at.has_value() ||
        event.status == domain::kEventStatusCancelled ||
        event.status == domain::kEventStatusArchived ||
        !category_filter_matches(event.category_id, query))
      continue;
    const auto category = category_for(event.category_id, categories);
    const auto current_category_name = category_name(category);
    auto match = domain::match_search_fields(
        keyword, {{domain::SearchMatchField::title, event.title},
                  {domain::SearchMatchField::content,
                   event.content.has_value() ? std::string_view(*event.content)
                                             : std::string_view()},
                  {domain::SearchMatchField::location,
                   event.location.has_value() ? std::string_view(*event.location)
                                              : std::string_view()},
                  {domain::SearchMatchField::category_name,
                   current_category_name}});
    if (!match.ok()) return fail<std::vector<Candidate>>(match.error());
    if (!match.value().has_value()) continue;

    std::vector<EventOccurrenceProjection> occurrences;
    if (!event.recurrence_id.has_value()) {
      auto projected = project_occurrence(event, std::nullopt, std::nullopt,
                                          context, query, resolver);
      if (!projected.ok()) return fail<std::vector<Candidate>>(projected.error());
      if (event_range_matches(projected.value(), query, context) &&
          (query.include_completed ||
           (projected.value().status != "completed" &&
            projected.value().status != "skipped")))
        occurrences.push_back(std::move(projected.value()));
    } else {
      if (!event.recurrence_revision.has_value())
        return fail<std::vector<Candidate>>(
            corrupted("Event recurrence revision is missing"));
      const auto found = recurrences.find(
          recurrence_key(*event.recurrence_id, *event.recurrence_revision));
      if (found == recurrences.end())
        return fail<std::vector<Candidate>>(
            corrupted("Event recurrence relationship is missing"));
      const auto& recurrence = *found->second;
      const auto schedule = domain::recurring_schedule_from_event(event);
      auto cutoff_date = completed_recurring_series_cutoff_local_date(
          event, recurrence, resolver);
      if (!cutoff_date.ok())
        return fail<std::vector<Candidate>>(cutoff_date.error());
      domain::LocalDate seek_date = context.today;
      if (!query.date_from.has_value() && cutoff_date.value().has_value())
        seek_date = *cutoff_date.value();
      if (query.date_from.has_value()) {
        if (context.today < *query.date_from) {
          seek_date = *query.date_from;
        } else if (!(context.today < *query.date_to_exclusive)) {
          seek_date = domain::add_local_days(*query.date_to_exclusive, -1);
        }
      }
      int first = 0;
      domain::LocalDate original_start_date;
      if (event.is_all_day) {
        auto original_start = domain::parse_local_date(*event.start_date);
        auto original_end = domain::parse_local_date(*event.end_date);
        if (!original_start.ok()) return fail<std::vector<Candidate>>(original_start.error());
        if (!original_end.ok()) return fail<std::vector<Candidate>>(original_end.error());
        original_start_date = original_start.value();
        first = first_candidate_index(recurrence, original_start.value(),
                                      original_end.value(), seek_date);
      } else {
        auto original_start = resolver.to_local(event.start_at, recurrence.timezone);
        auto original_end = resolver.to_local(event.end_at, recurrence.timezone);
        if (!original_start.ok()) return fail<std::vector<Candidate>>(original_start.error());
        if (!original_end.ok()) return fail<std::vector<Candidate>>(original_end.error());
        original_start_date = date_part(original_start.value());
        if (query.date_from.has_value()) {
          const auto seek_epoch = context.today < *query.date_from
                                      ? *context.range_start_epoch
                                  : !(context.today < *query.date_to_exclusive)
                                      ? *context.range_end_epoch - 1
                                      : context.evaluated_epoch;
          auto seek_local = resolver.to_local(
              common::format_epoch_seconds_utc_iso8601(seek_epoch),
              recurrence.timezone);
          if (!seek_local.ok()) return fail<std::vector<Candidate>>(seek_local.error());
          seek_date = date_part(seek_local.value());
        } else if (!cutoff_date.value().has_value()) {
          auto seek_local = resolver.to_local(context.evaluated_at,
                                               recurrence.timezone);
          if (!seek_local.ok())
            return fail<std::vector<Candidate>>(seek_local.error());
          seek_date = date_part(seek_local.value());
        }
        first = first_candidate_index(recurrence, date_part(original_start.value()),
                                      date_part(original_end.value()), seek_date);
      }

      std::unordered_map<int, const domain::EventOccurrenceState*>
          states_by_index;
      std::vector<int> eligibility_blocked;
      std::vector<int> open_blocked;
      const auto series_found = states_by_series.find(
          recurrence_key(event.id, *event.recurrence_revision));
      if (series_found != states_by_series.end()) {
        for (const auto* state : series_found->second) {
          auto indexed = occurrence_state_index(
              *state, recurrence, original_start_date, event.is_all_day,
              resolver);
          if (!indexed.ok())
            return fail<std::vector<Candidate>>(indexed.error());
          if (!states_by_index.emplace(indexed.value(), state).second)
            return fail<std::vector<Candidate>>(
                corrupted("Event occurrence-state index is duplicated"));
          const bool closed = state->status == domain::kOccurrenceCompleted ||
                              state->status == domain::kOccurrenceSkipped;
          const bool cancelled =
              state->status == domain::kOccurrenceCancelled;
          if (cancelled || (!query.include_completed && closed))
            eligibility_blocked.push_back(indexed.value());
          if (cancelled || closed) open_blocked.push_back(indexed.value());
        }
      }

      std::set<int> candidate_indices;
      add_index_window(candidate_indices, first, first + 8);
      const int near =
          candidate_index_for_date(recurrence, original_start_date, seek_date);
      add_index_window(candidate_indices, near - 4, near + 8);
      if (cutoff_date.value().has_value()) {
        const int cutoff_near = candidate_index_for_date(
            recurrence, original_start_date, *cutoff_date.value());
        add_index_window(candidate_indices, cutoff_near - 4, cutoff_near + 4);
      }
      add_block_boundaries(candidate_indices,
                           blocked_intervals(std::move(eligibility_blocked)));
      if (!query.date_from.has_value())
        add_block_boundaries(candidate_indices,
                             blocked_intervals(std::move(open_blocked)));

      std::vector<domain::EventOccurrence> expanded;
      expanded.reserve(candidate_indices.size());
      for (const int index : candidate_indices) {
        auto loaded = recurrence_service.occurrence_at(schedule, recurrence, index);
        if (!loaded.ok()) return fail<std::vector<Candidate>>(loaded.error());
        if (diagnostics != nullptr)
          ++diagnostics->recurrence_candidates_evaluated;
        expanded.push_back(std::move(loaded.value()));
      }
      for (const auto& occurrence : expanded) {
        std::optional<domain::EventOccurrenceState> state;
        const auto index = occurrence_state_index(
            domain::EventOccurrenceState{
                event.id,
                occurrence.recurrence_revision,
                occurrence.occurrence_key,
                occurrence.occurrence_start_at,
                occurrence.occurrence_start_date,
                domain::kOccurrenceScheduled.data(),
                "",
                std::nullopt,
                "",
                ""},
            recurrence, original_start_date, event.is_all_day, resolver);
        if (!index.ok()) return fail<std::vector<Candidate>>(index.error());
        const auto state_found = states_by_index.find(index.value());
        if (state_found != states_by_index.end()) {
          if (state_found->second->occurrence_key != occurrence.occurrence_key)
            return fail<std::vector<Candidate>>(
                corrupted("Event occurrence-state key is inconsistent"));
          state = *state_found->second;
        }
        if (state.has_value() && state->status == domain::kOccurrenceCancelled)
          continue;
        auto eligible = completed_recurring_series_occurrence_is_eligible(
            event, occurrence, recurrence, resolver);
        if (!eligible.ok())
          return fail<std::vector<Candidate>>(eligible.error());
        if (!eligible.value()) continue;
        auto projected = project_occurrence(event, occurrence, state, context,
                                            query, resolver);
        if (!projected.ok())
          return fail<std::vector<Candidate>>(projected.error());
        if (!event_range_matches(projected.value(), query, context)) continue;
        if (!query.include_completed &&
            (projected.value().status == "completed" ||
             projected.value().status == "skipped"))
          continue;
        occurrences.push_back(std::move(projected.value()));
      }
    }
    if (occurrences.empty()) continue;
    const bool select_last_before_cutoff =
        !query.date_from.has_value() && event.recurrence_id.has_value() &&
        event.status == domain::kEventStatusCompleted;
    const auto selected = std::min_element(
        occurrences.begin(), occurrences.end(), [&](const auto& left, const auto& right) {
          if (select_last_before_cutoff) {
            if (event.is_all_day &&
                !(*left.start_date == *right.start_date))
              return *right.start_date < *left.start_date;
            if (!event.is_all_day && left.start_epoch != right.start_epoch)
              return *left.start_epoch > *right.start_epoch;
          }
          if (!query.date_from.has_value()) {
            const bool left_open_future =
                left.current_or_future && left.status != "completed" &&
                left.status != "skipped";
            const bool right_open_future =
                right.current_or_future && right.status != "completed" &&
                right.status != "skipped";
            if (left_open_future != right_open_future) return left_open_future;
          }
          if (left.selection_distance != right.selection_distance)
            return left.selection_distance < right.selection_distance;
          if (left.current_or_future != right.current_or_future)
            return left.current_or_future;
          if (left.local_start_key != right.local_start_key)
            return left.local_start_key < right.local_start_key;
          const auto left_revision = left.occurrence.has_value()
                                         ? left.occurrence->recurrence_revision
                                         : 0;
          const auto right_revision = right.occurrence.has_value()
                                          ? right.occurrence->recurrence_revision
                                          : 0;
          if (left_revision != right_revision) return left_revision < right_revision;
          return left.occurrence.has_value() && right.occurrence.has_value() &&
                 left.occurrence->occurrence_key < right.occurrence->occurrence_key;
        });

    SearchEventItem item;
    item.target_id = event.id;
    item.title = event.title;
    item.match = *match.value();
    item.category = category;
    item.updated_at = event.updated_at;
    item.status = selected->status;
    item.is_all_day = event.is_all_day;
    item.is_recurring = selected->occurrence.has_value();
    item.location = event.location;
    if (event.is_all_day) {
      item.occur_date = selected->start_date;
    } else {
      item.occur_at = selected->occurrence.has_value()
                          ? selected->occurrence->occurrence_start_at
                          : std::optional<std::string>(event.start_at);
    }
    if (selected->occurrence.has_value()) {
      item.recurrence_revision = selected->occurrence->recurrence_revision;
      item.occurrence_key = selected->occurrence->occurrence_key;
    }
    Candidate candidate;
    candidate.item = std::move(item);
    candidate.relevance = static_cast<int>(match.value()->relevance);
    candidate.completion =
        selected->status == "completed" || selected->status == "skipped" ? 1 : 0;
    if (event.is_all_day) {
      if (!(context.today < *selected->start_date) &&
          context.today < *selected->end_date) {
        candidate.temporal_bucket = 0;
        candidate.temporal_distance = 0;
      } else if (context.today < *selected->start_date) {
        candidate.temporal_bucket = 0;
        candidate.temporal_distance =
            static_cast<std::int64_t>(domain::local_days_between(
                context.today, *selected->start_date)) *
            86400;
      } else {
        candidate.temporal_bucket = 1;
        candidate.temporal_distance =
            static_cast<std::int64_t>(domain::local_days_between(
                domain::add_local_days(*selected->end_date, -1),
                context.today)) *
            86400;
      }
    } else if (context.evaluated_epoch < *selected->start_epoch) {
      candidate.temporal_bucket = 0;
      candidate.temporal_distance =
          *selected->start_epoch - context.evaluated_epoch;
    } else if (context.evaluated_epoch < *selected->end_epoch) {
      candidate.temporal_bucket = 0;
      candidate.temporal_distance = 0;
    } else {
      candidate.temporal_bucket = 1;
      candidate.temporal_distance = context.evaluated_epoch - *selected->end_epoch;
    }
    candidate.updated_at = event.updated_at;
    candidate.target_id = event.id;
    candidate.mixed_time_key = selected->local_start_key;
    candidate.event_time = true;
    candidate.event_day_distance = selected->selection_distance;
    candidate.event_all_day = event.is_all_day;
    result.push_back(std::move(candidate));
  }
  return common::Result<std::vector<Candidate>>::success(std::move(result));
}

domain::LocalDate closest_date(const domain::LocalDate& start,
                               const domain::LocalDate& end_inclusive,
                               const domain::LocalDate& today) {
  if (today < start) return start;
  if (end_inclusive < today) return end_inclusive;
  return today;
}

common::Result<std::vector<Candidate>> project_habits(
    const repository::SearchQuerySnapshot& snapshot, const CategoryIndex& categories,
    const SearchQuery& query, const domain::NormalizedSearchText& keyword,
    const QueryContext& context) {
  std::unordered_set<std::string> recurrence_ids;
  for (const auto& recurrence : snapshot.habit_recurrences) {
    if (!recurrence.deleted_at.has_value()) recurrence_ids.insert(recurrence.id);
  }
  std::vector<Candidate> result;
  result.reserve(snapshot.habits.size());
  for (const auto& habit : snapshot.habits) {
    if (habit.deleted_at.has_value() ||
        !category_filter_matches(habit.category_id, query))
      continue;
    if (recurrence_ids.count(habit.recurrence_id) == 0U)
      return fail<std::vector<Candidate>>(
          corrupted("Habit recurrence relationship is missing"));
    const auto lifecycle = domain::habit_lifecycle(habit, context.today);
    const auto lifecycle_text = domain::habit_lifecycle_to_string(lifecycle);
    const bool closed = lifecycle == domain::HabitLifecycle::completed ||
                        lifecycle == domain::HabitLifecycle::ended_early;
    if (!query.include_completed && closed) continue;
    const auto category = category_for(habit.category_id, categories);
    const auto current_category_name = category_name(category);
    auto match = domain::match_search_fields(
        keyword, {{domain::SearchMatchField::title, habit.title},
                  {domain::SearchMatchField::description,
                   habit.description.has_value()
                       ? std::string_view(*habit.description)
                       : std::string_view()},
                  {domain::SearchMatchField::category_name,
                   current_category_name}});
    if (!match.ok()) return fail<std::vector<Candidate>>(match.error());
    if (!match.value().has_value()) continue;
    auto start = habit.start_date;
    auto end = domain::habit_effective_end_date(habit);
    if (query.date_from.has_value()) {
      start = start < *query.date_from ? *query.date_from : start;
      const auto filter_end = domain::add_local_days(*query.date_to_exclusive, -1);
      end = filter_end < end ? filter_end : end;
      if (end < start) continue;
    }
    const auto occur_date = closest_date(start, end, context.today);
    SearchHabitItem item;
    item.target_id = habit.id;
    item.title = habit.title;
    item.match = *match.value();
    item.category = category;
    item.updated_at = habit.updated_at;
    item.lifecycle_status = lifecycle_text;
    item.occur_date = occur_date;
    item.challenge_start_date = habit.start_date;
    item.challenge_end_date = habit.end_date;
    item.ended_date = habit.ended_date;
    item.remaining_days =
        closed
            ? 0
            : (lifecycle == domain::HabitLifecycle::upcoming
                   ? domain::local_days_between(habit.start_date,
                                                habit.end_date) +
                         1
                   : domain::local_days_between(
                         context.today, domain::habit_effective_end_date(habit)) +
                         1);
    item.target_count_hundredths = habit.target_count_hundredths;
    item.unit = habit.unit;
    Candidate candidate;
    candidate.item = std::move(item);
    candidate.relevance = static_cast<int>(match.value()->relevance);
    candidate.completion = closed ? 1 : 0;
    candidate.temporal_bucket = occur_date < context.today ? 1 : 0;
    candidate.temporal_distance = std::abs(
        domain::local_days_between(context.today, occur_date));
    candidate.updated_at = habit.updated_at;
    candidate.target_id = habit.id;
    result.push_back(std::move(candidate));
  }
  return common::Result<std::vector<Candidate>>::success(std::move(result));
}

common::Result<std::vector<Candidate>> project_anniversaries(
    const repository::SearchQuerySnapshot& snapshot, const CategoryIndex& categories,
    const SearchQuery& query, const domain::NormalizedSearchText& keyword,
    const QueryContext& context) {
  std::unordered_set<std::string> recurrence_ids;
  for (const auto& recurrence : snapshot.anniversary_recurrences) {
    if (!recurrence.deleted_at.has_value()) recurrence_ids.insert(recurrence.id);
  }
  std::vector<Candidate> result;
  result.reserve(snapshot.anniversaries.size());
  for (const auto& anniversary : snapshot.anniversaries) {
    if (anniversary.deleted_at.has_value() ||
        !category_filter_matches(anniversary.category_id, query))
      continue;
    const bool repeating = anniversary.recurrence_id.has_value();
    if (repeating && recurrence_ids.count(*anniversary.recurrence_id) == 0U)
      return fail<std::vector<Candidate>>(
          corrupted("Anniversary recurrence relationship is missing"));
    const auto category = category_for(anniversary.category_id, categories);
    const auto current_category_name = category_name(category);
    auto match = domain::match_search_fields(
        keyword, {{domain::SearchMatchField::title, anniversary.title},
                  {domain::SearchMatchField::note,
                   anniversary.note.has_value()
                       ? std::string_view(*anniversary.note)
                       : std::string_view()},
                  {domain::SearchMatchField::category_name,
                   current_category_name}});
    if (!match.ok()) return fail<std::vector<Candidate>>(match.error());
    if (!match.value().has_value()) continue;

    std::vector<domain::LocalDate> candidates;
    if (!repeating) {
      candidates.push_back(anniversary.date);
    } else {
      const int min_year = query.date_from.has_value()
                               ? std::max(anniversary.date.year,
                                          query.date_from->year - 1)
                               : std::max(anniversary.date.year,
                                          context.today.year - 1);
      const int max_year = query.date_to_exclusive.has_value()
                               ? query.date_to_exclusive->year
                               : std::max(anniversary.date.year,
                                          context.today.year + 1);
      if (max_year < min_year) continue;
      const int pivot = std::clamp(context.today.year, min_year, max_year);
      for (int year = std::max(min_year, pivot - 1);
           year <= std::min(max_year, pivot + 1); ++year) {
        const auto date =
            domain::anniversary_occurrence_in_year(anniversary.date, year);
        if (!(date < anniversary.date)) candidates.push_back(date);
      }
      if (query.date_from.has_value()) {
        const std::array<int, 2> edges{{min_year, max_year}};
        for (const auto year : edges) {
          const auto date =
              domain::anniversary_occurrence_in_year(anniversary.date, year);
          if (std::find(candidates.begin(), candidates.end(), date) ==
              candidates.end())
            candidates.push_back(date);
        }
      }
    }
    candidates.erase(
        std::remove_if(candidates.begin(), candidates.end(), [&](const auto& date) {
          return query.date_from.has_value() &&
                 (date < *query.date_from || ! (date < *query.date_to_exclusive));
        }),
        candidates.end());
    if (candidates.empty()) continue;
    const auto selected = std::min_element(
        candidates.begin(), candidates.end(), [&](const auto& left, const auto& right) {
          if (!query.date_from.has_value()) {
            const bool left_future = !(left < context.today);
            const bool right_future = !(right < context.today);
            if (left_future != right_future) return left_future;
          }
          const auto left_distance = std::abs(
              domain::local_days_between(context.today, left));
          const auto right_distance = std::abs(
              domain::local_days_between(context.today, right));
          return left_distance != right_distance ? left_distance < right_distance
                                                 : left < right;
        });
    auto occurrence_key =
        domain::anniversary_occurrence_key(anniversary.id, *selected);
    if (!occurrence_key.ok())
      return fail<std::vector<Candidate>>(occurrence_key.error());
    const int signed_days = domain::local_days_between(context.today, *selected);
    SearchAnniversaryItem item;
    item.target_id = anniversary.id;
    item.title = anniversary.title;
    item.match = *match.value();
    item.category = category;
    item.updated_at = anniversary.updated_at;
    item.occurrence_key = occurrence_key.value();
    item.occur_date = *selected;
    item.source_date = anniversary.date;
    item.is_repeating = repeating;
    item.relation = signed_days > 0 ? "remaining"
                    : signed_days < 0 ? "elapsed"
                                      : "today";
    item.days = std::abs(signed_days);
    item.years_elapsed = repeating ? selected->year - anniversary.date.year : 0;
    Candidate candidate;
    candidate.item = std::move(item);
    candidate.relevance = static_cast<int>(match.value()->relevance);
    candidate.temporal_bucket = signed_days < 0 ? 1 : 0;
    candidate.temporal_distance = std::abs(signed_days);
    candidate.updated_at = anniversary.updated_at;
    candidate.target_id = anniversary.id;
    result.push_back(std::move(candidate));
  }
  return common::Result<std::vector<Candidate>>::success(std::move(result));
}

common::Result<std::vector<Candidate>> project_section(
    domain::SearchTargetType target,
    const repository::SearchQuerySnapshot& snapshot, const CategoryIndex& categories,
    const SearchQuery& query, const domain::NormalizedSearchText& keyword,
    const QueryContext& context, const domain::LocalTimeResolver& resolver,
    const RecurrenceService& recurrence_service,
    SearchQueryDiagnostics* diagnostics) {
  if (target == domain::SearchTargetType::event)
    return project_events(snapshot, categories, query, keyword, context,
                           resolver, recurrence_service, diagnostics);
  if (target == domain::SearchTargetType::habit)
    return project_habits(snapshot, categories, query, keyword, context);
  return project_anniversaries(snapshot, categories, query, keyword, context);
}

}  // namespace

std::string search_sort_to_string(SearchSort value) {
  switch (value) {
    case SearchSort::relevance:
      return "relevance";
    case SearchSort::occur_time:
      return "occur_time";
    case SearchSort::updated_at:
      return "updated_at";
  }
  return "relevance";
}

SearchQueryService::SearchQueryService(
    std::shared_ptr<repository::SearchQueryRepository> repository,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
    std::shared_ptr<RecurrenceService> recurrence_service, ClockFn clock,
    common::SearchHmacKey hmac_key)
    : repository_(std::move(repository)),
      local_time_resolver_(std::move(local_time_resolver)),
      recurrence_service_(std::move(recurrence_service)),
      clock_(std::move(clock)),
      hmac_key_(hmac_key) {}

common::Result<SearchQueryResponse> SearchQueryService::query(
    const SearchQuery& query, SearchQueryDiagnostics* diagnostics) const {
  if (diagnostics != nullptr) *diagnostics = {};
  auto valid = validate_query_shape(query);
  if (!valid.ok()) return fail<SearchQueryResponse>(valid.error());
  auto normalized = domain::normalize_search_keyword(query.keyword);
  if (!normalized.ok()) return fail<SearchQueryResponse>(normalized.error());

  const auto& first_section = query.sections.front();
  std::optional<CursorIdentity> cursor;
  std::optional<SnapshotIdentity> expected_snapshot;
  std::string evaluated_at;
  std::string snapshot_token;
  std::vector<domain::SearchTargetType> load_targets = query.target_types;
  if (first_section.cursor.has_value()) {
    auto decoded = parse_cursor_token(*first_section.cursor, hmac_key_);
    if (!decoded.ok()) return fail<SearchQueryResponse>(decoded.error());
    const auto expected_binding =
        common::search_binding_digest(
            canonical_query_binding(query, normalized.value(),
                                    first_section.target_type),
            hmac_key_);
    if (decoded.value().binding != expected_binding)
      return fail<SearchQueryResponse>(cursor_mismatch("query binding changed"));
    auto snapshot =
        parse_snapshot_token(decoded.value().snapshot_token, hmac_key_);
    if (!snapshot.ok()) return fail<SearchQueryResponse>(snapshot.error());
    if (snapshot.value().evaluated_at != decoded.value().evaluated_at ||
        std::find(snapshot.value().targets.begin(), snapshot.value().targets.end(),
                  first_section.target_type) == snapshot.value().targets.end())
      return fail<SearchQueryResponse>(cursor_mismatch("snapshot binding changed"));
    evaluated_at = decoded.value().evaluated_at;
    snapshot_token = decoded.value().snapshot_token;
    cursor = std::move(decoded.value());
    expected_snapshot = std::move(snapshot.value());
    load_targets = {first_section.target_type};
  } else {
    evaluated_at = clock_();
  }
  auto context = build_context(query, evaluated_at, *local_time_resolver_);
  if (!context.ok()) return fail<SearchQueryResponse>(context.error());
  auto snapshot = repository_->load_snapshot(
      load_targets,
      expected_snapshot.has_value()
          ? std::optional(expected_snapshot->generations)
          : std::nullopt);
  if (!snapshot.ok()) return fail<SearchQueryResponse>(snapshot.error());
  if (diagnostics != nullptr) {
    diagnostics->sql_statements_executed =
        snapshot.value().sql_statements_executed;
    diagnostics->recurrence_state_rows =
        snapshot.value().event_occurrence_states.size();
  }
  if (!expected_snapshot.has_value()) {
    SnapshotIdentity identity{evaluated_at, query.target_types,
                              snapshot.value().generations};
    snapshot_token = snapshot_token_for(identity, hmac_key_);
  }
  auto categories = build_categories(snapshot.value());
  if (!categories.ok()) return fail<SearchQueryResponse>(categories.error());
  auto valid_store_text =
      validate_searchable_store_text(snapshot.value(), load_targets);
  if (!valid_store_text.ok())
    return fail<SearchQueryResponse>(valid_store_text.error());

  SearchQueryResponse response;
  response.query_generation = query.query_generation;
  response.normalized_keyword = normalized.value().display;
  response.timezone = query.timezone;
  response.evaluated_at = evaluated_at;
  response.snapshot_token = snapshot_token;
  for (const auto& section : query.sections) {
    auto candidates = project_section(
        section.target_type, snapshot.value(), categories.value(), query,
        normalized.value(), context.value(), *local_time_resolver_,
        *recurrence_service_, diagnostics);
    if (!candidates.ok()) return fail<SearchQueryResponse>(candidates.error());
    std::stable_sort(candidates.value().begin(), candidates.value().end(),
                     [&](const auto& left, const auto& right) {
                       return candidate_less(left, right, query.sort_by);
                     });
    std::size_t start = 0U;
    if (cursor.has_value()) {
      const auto found = std::find_if(
          candidates.value().begin(), candidates.value().end(),
          [&](const auto& value) {
            return candidate_sort_key(value, query.sort_by) ==
                   cursor->last_sort_key;
          });
      if (found == candidates.value().end())
        return fail<SearchQueryResponse>(common::make_error(
            "SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
      start = static_cast<std::size_t>(
                  std::distance(candidates.value().begin(), found)) +
              1U;
    }
    SearchSectionResult output;
    output.target_type = section.target_type;
    output.total_count = static_cast<std::int64_t>(candidates.value().size());
    const auto end =
        std::min(candidates.value().size(), start + static_cast<std::size_t>(20));
    for (std::size_t index = start; index < end; ++index)
      output.items.push_back(candidates.value()[index].item);
    output.has_more = end < candidates.value().size();
    if (output.has_more) {
      const auto& last = candidates.value()[end - 1U];
      CursorIdentity next{
          common::search_binding_digest(
              canonical_query_binding(query, normalized.value(),
                                      section.target_type),
              hmac_key_),
          evaluated_at, snapshot_token,
          candidate_sort_key(last, query.sort_by)};
      output.next_cursor = cursor_token_for(next, hmac_key_);
    }
    response.sections.push_back(std::move(output));
  }
  return common::Result<SearchQueryResponse>::success(std::move(response));
}

}  // namespace excellent_calendar::application
