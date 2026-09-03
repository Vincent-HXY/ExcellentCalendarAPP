#include "excellent_calendar/application/calendar_view_query_service.hpp"

#include "excellent_calendar/application/completed_recurring_series_eligibility.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "excellent_calendar/application/habit_service.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::application {
namespace {

constexpr int kMaximumRangeDays = 42;
constexpr int kCursorSortRevision = 1;
constexpr std::string_view kSnapshotPrefix = "calsnap1.";
constexpr std::string_view kCursorPrefix = "calcur1.";

struct SnapshotIdentity {
  std::array<std::int64_t,
             repository::kCalendarQueryContributingStores.size()>
      generations{};
  std::string evaluation_clock_utc;
};

struct ParsedCursor {
  std::string date;
  std::string timezone;
  std::string section;
  int page_size = 0;
  int sort_revision = 0;
  std::string snapshot_token;
  std::vector<std::string> last_key;
};

struct SortableItem {
  CalendarDayItem item;
  std::vector<std::string> key;
};

struct DayWindow {
  domain::LocalDate date;
  std::int64_t start_epoch = 0;
  std::int64_t end_epoch = 0;
};

struct ProjectionContext {
  std::string timezone;
  std::string evaluation_clock_utc;
  std::int64_t evaluation_clock_epoch = 0;
  domain::LocalDate evaluation_local_date;
  std::vector<DayWindow> days;
};

struct ReminderIndex {
  std::unordered_set<std::string> event_occurrences;
  std::unordered_map<std::string, std::string> habit_local_times;
  std::unordered_set<std::string> anniversary_occurrences;
};

struct EventFactIndex {
  std::unordered_map<std::string, const domain::Recurrence*> recurrences;
  std::unordered_map<std::string, const domain::EventOccurrenceState*>
      occurrence_states;
};

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

common::Error internal_error(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", std::move(reason)}});
}

common::Error contract_invalid(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error calendar_error(std::string code, std::string message,
                             bool retryable = false) {
  return common::make_error(std::move(code), std::move(message), {}, retryable);
}

common::Error corrupted(std::string reason) {
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored data is malformed or inconsistent",
                            {{"reason", std::move(reason)}});
}

bool less_equal(const domain::LocalDate& left,
                const domain::LocalDate& right) {
  return left < right || left == right;
}

domain::LocalDate date_part(const domain::LocalDateTime& value) {
  return {value.year, value.month, value.day};
}

std::string local_time_text(const domain::LocalDateTime& value) {
  std::ostringstream output;
  output << std::setfill('0') << std::setw(2) << value.hour << ':'
         << std::setw(2) << value.minute;
  return output.str();
}

std::string decimal(std::int64_t value) { return std::to_string(value); }

bool parse_canonical_nonnegative(std::string_view text,
                                 std::int64_t& output) {
  if (text.empty() || (text.size() > 1U && text.front() == '0')) return false;
  std::uint64_t value = 0;
  for (const char ch : text) {
    if (ch < '0' || ch > '9') return false;
    const auto digit = static_cast<unsigned>(ch - '0');
    if (value > (static_cast<std::uint64_t>(
                     std::numeric_limits<std::int64_t>::max()) -
                 digit) /
                    10U) {
      return false;
    }
    value = value * 10U + digit;
  }
  output = static_cast<std::int64_t>(value);
  return true;
}

std::string pack_fields(const std::vector<std::string>& fields) {
  std::string result;
  for (const auto& field : fields) {
    result += std::to_string(field.size());
    result.push_back(':');
    result += field;
  }
  return result;
}

std::string checksum(std::string_view value) {
  std::uint64_t hash = 1469598103934665603ULL;
  for (const unsigned char byte : value) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  std::ostringstream output;
  output << std::hex << std::setfill('0') << std::setw(16) << hash;
  return output.str();
}

std::string pack_checked_fields(std::vector<std::string> fields) {
  fields.push_back(checksum(pack_fields(fields)));
  return pack_fields(fields);
}

common::Result<std::vector<std::string>> unpack_fields(
    std::string_view packed) {
  std::vector<std::string> result;
  std::size_t cursor = 0;
  while (cursor < packed.size()) {
    if (result.size() >= 64U) {
      return common::Result<std::vector<std::string>>::failure(
          internal_error("opaque token contains too many fields"));
    }
    const auto length_start = cursor;
    while (cursor < packed.size() && packed[cursor] >= '0' &&
           packed[cursor] <= '9') {
      ++cursor;
    }
    if (cursor == length_start || cursor >= packed.size() ||
        packed[cursor] != ':' ||
        (cursor - length_start > 1U && packed[length_start] == '0')) {
      return common::Result<std::vector<std::string>>::failure(
          internal_error("opaque token field length is malformed"));
    }
    std::uint64_t length = 0;
    for (std::size_t index = length_start; index < cursor; ++index) {
      const auto digit = static_cast<unsigned>(packed[index] - '0');
      if (length > (std::numeric_limits<std::size_t>::max() - digit) / 10U) {
        return common::Result<std::vector<std::string>>::failure(
            internal_error("opaque token field length overflows"));
      }
      length = length * 10U + digit;
    }
    ++cursor;
    if (length > packed.size() - cursor) {
      return common::Result<std::vector<std::string>>::failure(
          internal_error("opaque token field is truncated"));
    }
    result.emplace_back(packed.substr(cursor, static_cast<std::size_t>(length)));
    cursor += static_cast<std::size_t>(length);
  }
  if (result.size() < 2U) {
    return common::Result<std::vector<std::string>>::failure(
        internal_error("opaque token fields are incomplete"));
  }
  const auto supplied = result.back();
  result.pop_back();
  if (supplied != checksum(pack_fields(result))) {
    return common::Result<std::vector<std::string>>::failure(
        internal_error("opaque token checksum is invalid"));
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

std::string base64url_encode(std::string_view input) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string output;
  output.reserve((input.size() * 4U + 2U) / 3U);
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const unsigned char byte : input) {
    buffer = (buffer << 8U) | byte;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      output.push_back(alphabet[(buffer >> bits) & 0x3FU]);
    }
  }
  if (bits > 0) output.push_back(alphabet[(buffer << (6 - bits)) & 0x3FU]);
  return output;
}

common::Result<std::string> base64url_decode(std::string_view input) {
  if (input.empty() || input.size() % 4U == 1U) {
    return common::Result<std::string>::failure(
        internal_error("opaque token base64url length is invalid"));
  }
  const auto decode = [](char ch) -> int {
    if (ch >= 'A' && ch <= 'Z') return ch - 'A';
    if (ch >= 'a' && ch <= 'z') return ch - 'a' + 26;
    if (ch >= '0' && ch <= '9') return ch - '0' + 52;
    if (ch == '-') return 62;
    if (ch == '_') return 63;
    return -1;
  };
  std::string output;
  output.reserve(input.size() * 3U / 4U);
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const char ch : input) {
    const int value = decode(ch);
    if (value < 0) {
      return common::Result<std::string>::failure(
          internal_error("opaque token contains a non-base64url character"));
    }
    buffer = (buffer << 6U) | static_cast<std::uint32_t>(value);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output.push_back(static_cast<char>((buffer >> bits) & 0xFFU));
    }
  }
  if (bits > 0 && (buffer & ((1U << bits) - 1U)) != 0U) {
    return common::Result<std::string>::failure(
        internal_error("opaque token has non-canonical base64url padding bits"));
  }
  return common::Result<std::string>::success(std::move(output));
}

bool has_token_shape(std::string_view token, std::string_view prefix,
                     std::size_t maximum_length) {
  if (token.size() > maximum_length || token.size() < prefix.size() + 20U ||
      token.substr(0, prefix.size()) != prefix) {
    return false;
  }
  return std::all_of(token.begin() + static_cast<std::ptrdiff_t>(prefix.size()),
                     token.end(), [](unsigned char ch) {
                       return std::isalnum(ch) != 0 || ch == '-' || ch == '_';
                     });
}

std::string snapshot_token_for(
    const repository::CalendarQuerySnapshot& snapshot,
    std::string_view evaluation_clock_utc) {
  std::vector<std::string> fields{"calendar_snapshot_v1",
                                  std::string(evaluation_clock_utc)};
  for (const auto generation : snapshot.generations) {
    fields.push_back(decimal(generation));
  }
  return std::string(kSnapshotPrefix) +
         base64url_encode(pack_checked_fields(std::move(fields)));
}

common::Result<SnapshotIdentity> parse_snapshot_token(std::string_view token) {
  if (!has_token_shape(token, kSnapshotPrefix, 521U)) {
    return common::Result<SnapshotIdentity>::failure(calendar_error(
        "CALENDAR_SNAPSHOT_INVALID", "Calendar snapshot token is malformed"));
  }
  auto decoded = base64url_decode(token.substr(kSnapshotPrefix.size()));
  if (!decoded.ok()) {
    return common::Result<SnapshotIdentity>::failure(calendar_error(
        "CALENDAR_SNAPSHOT_INVALID", "Calendar snapshot token is malformed"));
  }
  auto fields = unpack_fields(decoded.value());
  constexpr std::size_t kExpectedFields =
      2U + repository::kCalendarQueryContributingStores.size();
  if (!fields.ok() || fields.value().size() != kExpectedFields ||
      fields.value()[0] != "calendar_snapshot_v1" ||
      !common::is_iso8601_utc_datetime(fields.value()[1])) {
    return common::Result<SnapshotIdentity>::failure(calendar_error(
        "CALENDAR_SNAPSHOT_INVALID", "Calendar snapshot token is malformed"));
  }
  SnapshotIdentity identity;
  identity.evaluation_clock_utc = fields.value()[1];
  for (std::size_t index = 0; index < identity.generations.size(); ++index) {
    if (!parse_canonical_nonnegative(fields.value()[index + 2U],
                                     identity.generations[index])) {
      return common::Result<SnapshotIdentity>::failure(calendar_error(
          "CALENDAR_SNAPSHOT_INVALID", "Calendar snapshot token is malformed"));
    }
  }
  return common::Result<SnapshotIdentity>::success(std::move(identity));
}

bool generations_equal(const SnapshotIdentity& identity,
                       const repository::CalendarQuerySnapshot& snapshot) {
  return identity.generations == snapshot.generations;
}

std::size_t expected_key_count(CalendarSection section) {
  switch (section) {
    case CalendarSection::event:
      return 7U;
    case CalendarSection::habit:
      return 4U;
    case CalendarSection::anniversary:
      return 4U;
  }
  return 0U;
}

std::string cursor_for(const CalendarListDayItemsQuery& query,
                       const std::vector<std::string>& key) {
  std::vector<std::string> fields{
      "calendar_cursor_v1",
      domain::format_local_date(query.date),
      query.timezone,
      calendar_section_to_string(query.section),
      std::to_string(query.page_size),
      std::to_string(kCursorSortRevision),
      query.snapshot_token,
      std::to_string(key.size()),
  };
  fields.insert(fields.end(), key.begin(), key.end());
  return std::string(kCursorPrefix) +
         base64url_encode(pack_checked_fields(std::move(fields)));
}

common::Result<ParsedCursor> parse_cursor(std::string_view token) {
  if (!has_token_shape(token, kCursorPrefix, 2056U)) {
    return common::Result<ParsedCursor>::failure(calendar_error(
        "CALENDAR_CURSOR_INVALID", "Calendar day-items cursor is malformed"));
  }
  auto decoded = base64url_decode(token.substr(kCursorPrefix.size()));
  auto fields = decoded.ok() ? unpack_fields(decoded.value())
                             : fail<std::vector<std::string>>(decoded.error());
  if (!fields.ok() || fields.value().size() < 8U ||
      fields.value()[0] != "calendar_cursor_v1") {
    return common::Result<ParsedCursor>::failure(calendar_error(
        "CALENDAR_CURSOR_INVALID", "Calendar day-items cursor is malformed"));
  }
  std::int64_t page_size = 0;
  std::int64_t sort_revision = 0;
  std::int64_t key_count = 0;
  const auto date = domain::parse_local_date(fields.value()[1]);
  const bool section_valid = fields.value()[3] == "event" ||
                             fields.value()[3] == "habit" ||
                             fields.value()[3] == "anniversary";
  if (!date.ok() || fields.value()[2].empty() || !section_valid ||
      !parse_canonical_nonnegative(fields.value()[4], page_size) ||
      page_size < 1 || page_size > 100 ||
      !parse_canonical_nonnegative(fields.value()[5], sort_revision) ||
      !parse_snapshot_token(fields.value()[6]).ok() ||
      !parse_canonical_nonnegative(fields.value()[7], key_count) ||
      key_count > 16 || fields.value().size() != 8U + key_count) {
    return common::Result<ParsedCursor>::failure(calendar_error(
        "CALENDAR_CURSOR_INVALID", "Calendar day-items cursor is malformed"));
  }
  ParsedCursor cursor;
  cursor.date = fields.value()[1];
  cursor.timezone = fields.value()[2];
  cursor.section = fields.value()[3];
  cursor.page_size = static_cast<int>(page_size);
  cursor.sort_revision = static_cast<int>(sort_revision);
  cursor.snapshot_token = fields.value()[6];
  cursor.last_key.assign(fields.value().begin() + 8, fields.value().end());
  return common::Result<ParsedCursor>::success(std::move(cursor));
}

common::Result<ProjectionContext> projection_context(
    const domain::LocalDate& start, const domain::LocalDate& end,
    std::string timezone, std::string evaluation_clock_utc,
    const domain::LocalTimeResolver& resolver) {
  const auto clock_epoch =
      common::parse_iso8601_utc_epoch_seconds(evaluation_clock_utc);
  auto clock_local = resolver.to_local(evaluation_clock_utc, timezone);
  if (!clock_epoch.has_value() || !clock_local.ok()) {
    return common::Result<ProjectionContext>::failure(
        clock_local.ok() ? internal_error("Calendar evaluation clock is invalid")
                         : clock_local.error());
  }
  ProjectionContext context;
  context.timezone = std::move(timezone);
  context.evaluation_clock_utc = std::move(evaluation_clock_utc);
  context.evaluation_clock_epoch = *clock_epoch;
  context.evaluation_local_date = date_part(clock_local.value());
  for (auto date = start; date < end; date = domain::add_local_days(date, 1)) {
    auto day_start = resolver.to_utc({date.year, date.month, date.day, 0, 0, 0},
                                     context.timezone);
    const auto next = domain::add_local_days(date, 1);
    auto day_end = resolver.to_utc({next.year, next.month, next.day, 0, 0, 0},
                                   context.timezone);
    if (!day_start.ok()) return fail<ProjectionContext>(day_start.error());
    if (!day_end.ok()) return fail<ProjectionContext>(day_end.error());
    const auto start_epoch =
        common::parse_iso8601_utc_epoch_seconds(day_start.value());
    const auto end_epoch =
        common::parse_iso8601_utc_epoch_seconds(day_end.value());
    if (!start_epoch.has_value() || !end_epoch.has_value() ||
        *start_epoch >= *end_epoch) {
      return common::Result<ProjectionContext>::failure(
          internal_error("Calendar local-day boundary is invalid"));
    }
    context.days.push_back({date, *start_epoch, *end_epoch});
  }
  return common::Result<ProjectionContext>::success(std::move(context));
}

std::string event_reminder_key(
    std::string_view event_id, const std::optional<int>& revision,
    const std::optional<std::string>& occurrence_key) {
  return std::string(event_id) + "\n" +
         (revision.has_value() ? std::to_string(*revision) : "-") + "\n" +
         occurrence_key.value_or("-");
}

std::string date_reminder_key(std::string_view target_id,
                              std::string_view occurrence_identity) {
  return std::string(target_id) + "\n" + std::string(occurrence_identity);
}

std::string recurrence_key(std::string_view recurrence_id, int revision) {
  return std::string(recurrence_id) + "\n" + std::to_string(revision);
}

std::string occurrence_state_key(std::string_view event_id, int revision,
                                 std::string_view occurrence_key) {
  return std::string(event_id) + "\n" + std::to_string(revision) + "\n" +
         std::string(occurrence_key);
}

common::Result<EventFactIndex> build_event_fact_index(
    const repository::CalendarQuerySnapshot& snapshot) {
  EventFactIndex result;
  result.recurrences.reserve(snapshot.event_recurrences.size());
  for (const auto& recurrence : snapshot.event_recurrences) {
    if (!result.recurrences
             .emplace(recurrence_key(recurrence.id, recurrence.revision),
                      &recurrence)
             .second) {
      return common::Result<EventFactIndex>::failure(
          corrupted("Calendar Event recurrence identity is duplicated"));
    }
  }
  result.occurrence_states.reserve(snapshot.event_occurrence_states.size());
  for (const auto& state : snapshot.event_occurrence_states) {
    if (!result.occurrence_states
             .emplace(occurrence_state_key(
                          state.event_id, state.recurrence_revision,
                          state.occurrence_key),
                      &state)
             .second) {
      return common::Result<EventFactIndex>::failure(corrupted(
          "Calendar Event occurrence-state identity is duplicated"));
    }
  }
  return common::Result<EventFactIndex>::success(std::move(result));
}

ReminderIndex build_reminder_index(
    const repository::CalendarQuerySnapshot& snapshot) {
  ReminderIndex result;
  for (const auto& reminder : snapshot.reminders) {
    if (!domain::is_open_reminder(reminder)) continue;
    if (reminder.target_type == domain::kReminderTargetEvent) {
      result.event_occurrences.insert(event_reminder_key(
          reminder.target_id, reminder.recurrence_revision,
          reminder.occurrence_key));
    } else if (reminder.target_type == domain::kReminderTargetHabit &&
               reminder.occurrence_date.has_value()) {
      const auto key =
          date_reminder_key(reminder.target_id, *reminder.occurrence_date);
      const auto value = reminder.local_time.value_or("");
      const auto found = result.habit_local_times.find(key);
      if (found == result.habit_local_times.end() ||
          (!value.empty() && (found->second.empty() || value < found->second))) {
        result.habit_local_times[key] = value;
      }
    } else if (reminder.target_type ==
                   domain::kReminderTargetAnniversary &&
               reminder.occurrence_key.has_value()) {
      result.anniversary_occurrences.insert(
          date_reminder_key(reminder.target_id, *reminder.occurrence_key));
    }
  }
  return result;
}

int status_bucket(std::string_view status) {
  if (status == "absent" || status == "partial") return 0;
  if (status == "done") return 1;
  if (status == "skipped") return 2;
  if (status == "missed") return 3;
  return 4;
}

int importance_bucket(const std::optional<std::string>& importance) {
  if (importance == std::optional<std::string>("important_urgent")) return 0;
  if (importance == std::optional<std::string>("important_noturgent")) return 1;
  if (importance == std::optional<std::string>("unimportant_urgent")) return 2;
  if (importance == std::optional<std::string>("unimportant_noturgent")) return 3;
  return 4;
}

std::string nullable_int_key(const std::optional<int>& value) {
  if (!value.has_value()) return "0";
  std::ostringstream output;
  output << '1' << std::setfill('0') << std::setw(10) << *value;
  return output.str();
}

std::string nullable_string_key(const std::optional<std::string>& value) {
  return value.has_value() ? "1" + *value : "0";
}

std::vector<std::string> event_sort_key(const CalendarEventItem& item,
                                        std::string local_start) {
  return {
      item.is_all_day ? "0" : "1",
      item.status == "completed" ? "1" : "0",
      std::move(local_start),
      item.title,
      item.event_id,
      nullable_int_key(item.recurrence_revision),
      nullable_string_key(item.occurrence_key),
  };
}

std::vector<std::string> habit_sort_key(
    const CalendarHabitItem& item, const domain::Habit& habit,
    const std::optional<std::string>& reminder_local_time) {
  return {
      std::to_string(status_bucket(item.status)),
      reminder_local_time.has_value() ? "0" + *reminder_local_time : "1",
      habit.created_at,
      habit.id,
  };
}

std::vector<std::string> anniversary_sort_key(
    const CalendarAnniversaryItem& item) {
  return {
      std::to_string(importance_bucket(item.importance)),
      item.title,
      item.anniversary_id,
      item.occurrence_key,
  };
}

std::string timed_status(std::int64_t start, std::int64_t end,
                         std::int64_t clock) {
  if (clock < start) return "pending";
  if (clock < end) return "in_progress";
  return "overdue";
}

std::string all_day_status(const domain::LocalDate& start,
                           const domain::LocalDate& end,
                           const domain::LocalDate& clock_date) {
  if (clock_date < start) return "pending";
  if (clock_date < end) return "in_progress";
  return "overdue";
}

std::string visible_event_status(
    const domain::Event& event,
    const std::optional<domain::EventOccurrenceState>& occurrence_state,
    std::int64_t start_epoch, std::int64_t end_epoch,
    const std::optional<domain::LocalDate>& start_date,
    const std::optional<domain::LocalDate>& end_date,
    const ProjectionContext& context) {
  if (occurrence_state.has_value()) {
    if (occurrence_state->status == domain::kOccurrenceCompleted)
      return "completed";
    if (occurrence_state->status == domain::kOccurrenceSkipped)
      return "skipped";
  }
  if (event.status == domain::kEventStatusCompleted) return "completed";
  return start_date.has_value()
             ? all_day_status(*start_date, *end_date,
                              context.evaluation_local_date)
             : timed_status(start_epoch, end_epoch,
                            context.evaluation_clock_epoch);
}

std::optional<domain::EventOccurrenceState> occurrence_state_for(
    const EventFactIndex& facts,
    const domain::EventOccurrence& occurrence) {
  const auto found = facts.occurrence_states.find(occurrence_state_key(
      occurrence.event_id, occurrence.recurrence_revision,
      occurrence.occurrence_key));
  return found == facts.occurrence_states.end()
             ? std::nullopt
             : std::optional<domain::EventOccurrenceState>(*found->second);
}

common::Result<common::Unit> append_event_interval(
    const domain::Event& event,
    const std::optional<domain::EventOccurrence>& occurrence,
    const std::optional<domain::EventOccurrenceState>& occurrence_state,
    const ReminderIndex& reminders, const ProjectionContext& context,
    const domain::LocalTimeResolver& resolver,
    std::vector<std::pair<domain::LocalDate, SortableItem>>& output) {
  if (occurrence_state.has_value() &&
      occurrence_state->status == domain::kOccurrenceCancelled) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  CalendarEventItem prototype;
  prototype.event_id = event.id;
  prototype.title = event.title;
  prototype.is_all_day = event.is_all_day;
  prototype.is_recurring = occurrence.has_value();
  if (occurrence.has_value()) {
    prototype.recurrence_revision = occurrence->recurrence_revision;
    prototype.occurrence_key = occurrence->occurrence_key;
    prototype.occurrence_start_at = occurrence->occurrence_start_at;
    if (occurrence->occurrence_start_date.has_value()) {
      auto parsed = domain::parse_local_date(*occurrence->occurrence_start_date);
      if (!parsed.ok()) return fail<common::Unit>(parsed.error());
      prototype.occurrence_start_date = parsed.value();
    }
  }
  prototype.has_active_reminder =
      reminders.event_occurrences.count(event_reminder_key(
          event.id, prototype.recurrence_revision, prototype.occurrence_key)) !=
      0U;

  if (event.is_all_day) {
    const auto start_text = occurrence.has_value()
                                ? occurrence->occurrence_start_date
                                : event.start_date;
    const auto end_text = occurrence.has_value() ? occurrence->occurrence_end_date
                                                  : event.end_date;
    if (!start_text.has_value() || !end_text.has_value()) {
      return common::Result<common::Unit>::failure(
          corrupted("Calendar all-day Event interval is missing"));
    }
    auto start = domain::parse_local_date(*start_text);
    auto end = domain::parse_local_date(*end_text);
    if (!start.ok()) return fail<common::Unit>(start.error());
    if (!end.ok()) return fail<common::Unit>(end.error());
    prototype.start_date = start.value();
    prototype.end_date = end.value();
    prototype.day_display = "all_day";
    prototype.status = visible_event_status(
        event, occurrence_state, 0, 0, start.value(), end.value(), context);
    for (const auto& day : context.days) {
      if (day.date < end.value() && !(day.date < start.value())) {
        auto item = prototype;
        output.push_back({
            day.date,
            SortableItem{CalendarDayItem(std::move(item)),
                         event_sort_key(prototype,
                                        domain::format_local_date(day.date) +
                                            "T00:00:00")},
        });
      }
    }
    return common::Result<common::Unit>::success(common::Unit{});
  }

  const auto start_text = occurrence.has_value()
                              ? occurrence->occurrence_start_at.value_or("")
                              : event.start_at;
  const auto end_text = occurrence.has_value()
                            ? occurrence->occurrence_end_at.value_or("")
                            : event.end_at;
  const auto start_epoch = common::parse_iso8601_utc_epoch_seconds(start_text);
  const auto end_epoch = common::parse_iso8601_utc_epoch_seconds(end_text);
  if (!start_epoch.has_value() || !end_epoch.has_value() ||
      *start_epoch >= *end_epoch) {
    return common::Result<common::Unit>::failure(
        corrupted("Calendar timed Event interval is invalid"));
  }
  auto local_start = resolver.to_local(start_text, context.timezone);
  auto local_end = resolver.to_local(end_text, context.timezone);
  if (!local_start.ok()) return fail<common::Unit>(local_start.error());
  if (!local_end.ok()) return fail<common::Unit>(local_end.error());
  prototype.start_at = start_text;
  prototype.end_at = end_text;
  prototype.status = visible_event_status(event, occurrence_state, *start_epoch,
                                          *end_epoch, std::nullopt,
                                          std::nullopt, context);
  for (const auto& day : context.days) {
    if (*start_epoch >= day.end_epoch || *end_epoch <= day.start_epoch) continue;
    auto item = prototype;
    if (*start_epoch >= day.start_epoch) {
      item.day_display = "starts_at";
      item.display_local_time = local_time_text(local_start.value());
    } else if (*end_epoch <= day.end_epoch) {
      item.day_display = "ends_at";
      item.display_local_time = local_time_text(local_end.value());
    } else {
      item.day_display = "continues";
    }
    const auto effective_start = std::max(*start_epoch, day.start_epoch);
    output.push_back({
        day.date,
        SortableItem{CalendarDayItem(std::move(item)),
                     event_sort_key(prototype,
                                    common::format_epoch_seconds_utc_iso8601(
                                        effective_start))},
    });
  }
  return common::Result<common::Unit>::success(common::Unit{});
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
    return std::max(
        0, domain::local_days_between(original_start, range_start) -
               duration_days - 2);
  }
  if (recurrence.frequency == domain::kRecurrenceWeekly) {
    const int days = domain::local_days_between(original_start, range_start) -
                     duration_days - 8;
    return std::max(0, days / 7);
  }
  const int duration_months = (duration_days + 27) / 28;
  return std::max(0, month_distance(original_start, range_start) -
                         duration_months - 2);
}

using SummaryFlags = std::vector<bool>;

bool all_flags_set(const SummaryFlags& flags) {
  return std::all_of(flags.begin(), flags.end(), [](bool value) {
    return value;
  });
}

common::Result<common::Unit> mark_event_summary_interval(
    const domain::Event& event,
    const std::optional<domain::EventOccurrence>& occurrence,
    const std::optional<domain::EventOccurrenceState>& occurrence_state,
    const ProjectionContext& context, SummaryFlags& flags) {
  if (occurrence_state.has_value() &&
      occurrence_state->status == domain::kOccurrenceCancelled) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  if (event.is_all_day) {
    const auto start_text = occurrence.has_value()
                                ? occurrence->occurrence_start_date
                                : event.start_date;
    const auto end_text = occurrence.has_value()
                              ? occurrence->occurrence_end_date
                              : event.end_date;
    if (!start_text.has_value() || !end_text.has_value()) {
      return common::Result<common::Unit>::failure(
          corrupted("Calendar all-day Event interval is missing"));
    }
    auto start = domain::parse_local_date(*start_text);
    auto end = domain::parse_local_date(*end_text);
    if (!start.ok()) return fail<common::Unit>(start.error());
    if (!end.ok()) return fail<common::Unit>(end.error());
    if (visible_event_status(event, occurrence_state, 0, 0, start.value(),
                             end.value(), context) == "completed") {
      return common::Result<common::Unit>::success(common::Unit{});
    }
    for (std::size_t index = 0; index < context.days.size(); ++index) {
      if (!flags[index] && context.days[index].date < end.value() &&
          !(context.days[index].date < start.value())) {
        flags[index] = true;
      }
    }
    return common::Result<common::Unit>::success(common::Unit{});
  }

  const auto start_text = occurrence.has_value()
                              ? occurrence->occurrence_start_at.value_or("")
                              : event.start_at;
  const auto end_text = occurrence.has_value()
                            ? occurrence->occurrence_end_at.value_or("")
                            : event.end_at;
  const auto start_epoch = common::parse_iso8601_utc_epoch_seconds(start_text);
  const auto end_epoch = common::parse_iso8601_utc_epoch_seconds(end_text);
  if (!start_epoch.has_value() || !end_epoch.has_value() ||
      *start_epoch >= *end_epoch) {
    return common::Result<common::Unit>::failure(
        corrupted("Calendar timed Event interval is invalid"));
  }
  if (visible_event_status(event, occurrence_state, *start_epoch, *end_epoch,
                           std::nullopt, std::nullopt, context) ==
      "completed") {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  for (std::size_t index = 0; index < context.days.size(); ++index) {
    const auto& day = context.days[index];
    if (!flags[index] && *start_epoch < day.end_epoch &&
        *end_epoch > day.start_epoch) {
      flags[index] = true;
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<SummaryFlags> project_event_summary_flags(
    const repository::CalendarQuerySnapshot& snapshot,
    const ProjectionContext& context,
    const domain::LocalTimeResolver& resolver,
    const RecurrenceService& recurrence_service) {
  SummaryFlags flags(context.days.size(), false);
  if (context.days.empty()) {
    return common::Result<SummaryFlags>::success(std::move(flags));
  }
  auto facts = build_event_fact_index(snapshot);
  if (!facts.ok()) return fail<SummaryFlags>(facts.error());
  const auto range_start_epoch = context.days.front().start_epoch;
  const auto range_end_epoch = context.days.back().end_epoch;
  for (const auto& event : snapshot.events) {
    if (event.deleted_at.has_value() ||
        event.status == domain::kEventStatusCancelled ||
        event.status == domain::kEventStatusArchived) {
      continue;
    }
    if (!event.recurrence_id.has_value()) {
      auto marked = mark_event_summary_interval(
          event, std::nullopt, std::nullopt, context, flags);
      if (!marked.ok()) return fail<SummaryFlags>(marked.error());
      if (all_flags_set(flags)) break;
      continue;
    }
    if (!event.recurrence_revision.has_value()) {
      return common::Result<SummaryFlags>::failure(
          corrupted("Calendar Event recurrence revision is missing"));
    }
    const auto recurrence = facts.value().recurrences.find(recurrence_key(
        *event.recurrence_id, *event.recurrence_revision));
    if (recurrence == facts.value().recurrences.end()) {
      return common::Result<SummaryFlags>::failure(
          corrupted("Calendar Event recurrence relationship is missing"));
    }
    const auto* recurrence_value = recurrence->second;
    const auto schedule = domain::recurring_schedule_from_event(event);
    int first_index = 0;
    if (event.is_all_day) {
      if (!event.start_date.has_value() || !event.end_date.has_value()) {
        return common::Result<SummaryFlags>::failure(
            corrupted("Calendar all-day Event interval is missing"));
      }
      auto original_start = domain::parse_local_date(*event.start_date);
      auto original_end = domain::parse_local_date(*event.end_date);
      if (!original_start.ok()) return fail<SummaryFlags>(original_start.error());
      if (!original_end.ok()) return fail<SummaryFlags>(original_end.error());
      first_index = first_candidate_index(
          *recurrence_value, original_start.value(), original_end.value(),
          context.days.front().date);
    } else {
      auto original_start =
          resolver.to_local(event.start_at, recurrence_value->timezone);
      auto original_end =
          resolver.to_local(event.end_at, recurrence_value->timezone);
      auto range_start_local = resolver.to_local(
          common::format_epoch_seconds_utc_iso8601(range_start_epoch),
          recurrence_value->timezone);
      if (!original_start.ok()) return fail<SummaryFlags>(original_start.error());
      if (!original_end.ok()) return fail<SummaryFlags>(original_end.error());
      if (!range_start_local.ok())
        return fail<SummaryFlags>(range_start_local.error());
      first_index = first_candidate_index(
          *recurrence_value, date_part(original_start.value()),
          date_part(original_end.value()), date_part(range_start_local.value()));
    }
    auto occurrences = event.is_all_day
                           ? recurrence_service
                                 .list_all_day_occurrences_from_index(
                                     schedule, *recurrence_value, first_index,
                                     domain::format_local_date(
                                         domain::add_local_days(
                                             context.days.back().date, 1)))
                           : recurrence_service.list_timed_occurrences_from_index(
                                 schedule, *recurrence_value, first_index,
                                 common::format_epoch_seconds_utc_iso8601(
                                     range_end_epoch));
    if (!occurrences.ok()) return fail<SummaryFlags>(occurrences.error());
    for (const auto& occurrence : occurrences.value()) {
      auto visible = completed_recurring_series_occurrence_is_eligible(
          event, occurrence, *recurrence_value, resolver);
      if (!visible.ok()) return fail<SummaryFlags>(visible.error());
      if (!visible.value()) continue;
      const auto state = occurrence_state_for(facts.value(), occurrence);
      auto marked = mark_event_summary_interval(
          event, occurrence, state, context, flags);
      if (!marked.ok()) return fail<SummaryFlags>(marked.error());
      if (all_flags_set(flags)) break;
    }
    if (all_flags_set(flags)) break;
  }
  return common::Result<SummaryFlags>::success(std::move(flags));
}

SummaryFlags project_habit_summary_flags(
    const repository::CalendarQuerySnapshot& snapshot,
    const ProjectionContext& context) {
  SummaryFlags flags(context.days.size(), false);
  HabitDailyStatusProjector daily_statuses(snapshot.habit_check_ins);
  for (const auto& habit : snapshot.habits) {
    if (habit.deleted_at.has_value()) continue;
    const auto effective_end = domain::habit_effective_end_date(habit);
    for (std::size_t index = 0; index < context.days.size(); ++index) {
      if (flags[index]) continue;
      const auto& date = context.days[index].date;
      if (date < habit.start_date || effective_end < date) continue;
      if (daily_statuses
              .project(habit, date, context.evaluation_local_date)
              .status != "done") {
        flags[index] = true;
      }
    }
    if (all_flags_set(flags)) break;
  }
  return flags;
}

std::unordered_set<std::string> active_anniversary_recurrence_ids(
    const repository::CalendarQuerySnapshot& snapshot) {
  std::unordered_set<std::string> result;
  result.reserve(snapshot.anniversary_recurrences.size());
  for (const auto& recurrence : snapshot.anniversary_recurrences) {
    if (!recurrence.deleted_at.has_value()) result.insert(recurrence.id);
  }
  return result;
}

common::Result<SummaryFlags> project_anniversary_summary_flags(
    const repository::CalendarQuerySnapshot& snapshot,
    const ProjectionContext& context) {
  SummaryFlags flags(context.days.size(), false);
  if (context.days.empty()) {
    return common::Result<SummaryFlags>::success(std::move(flags));
  }
  const auto recurrence_ids = active_anniversary_recurrence_ids(snapshot);
  const auto range_start = context.days.front().date;
  const auto range_end = domain::add_local_days(context.days.back().date, 1);
  for (const auto& anniversary : snapshot.anniversaries) {
    if (anniversary.deleted_at.has_value()) continue;
    const bool repeating = anniversary.recurrence_id.has_value();
    if (repeating &&
        recurrence_ids.count(*anniversary.recurrence_id) == 0U) {
      return common::Result<SummaryFlags>::failure(corrupted(
          "Calendar Anniversary recurrence relationship is missing"));
    }
    const int first_year = repeating
                               ? std::max(anniversary.date.year,
                                          range_start.year - 1)
                               : anniversary.date.year;
    const int last_year = repeating ? range_end.year : anniversary.date.year;
    for (int year = first_year; year <= last_year; ++year) {
      const auto date = repeating
                            ? domain::anniversary_occurrence_in_year(
                                  anniversary.date, year)
                            : anniversary.date;
      if (date < range_start || !(date < range_end) ||
          date < anniversary.date) {
        continue;
      }
      const auto offset = domain::local_days_between(range_start, date);
      if (offset >= 0 &&
          static_cast<std::size_t>(offset) < flags.size()) {
        flags[static_cast<std::size_t>(offset)] = true;
      }
      if (!repeating) break;
    }
    if (all_flags_set(flags)) break;
  }
  return common::Result<SummaryFlags>::success(std::move(flags));
}

common::Result<std::vector<std::pair<domain::LocalDate, SortableItem>>>
project_events(const repository::CalendarQuerySnapshot& snapshot,
               const ReminderIndex& reminders,
               const ProjectionContext& context,
               const domain::LocalTimeResolver& resolver,
               const RecurrenceService& recurrence_service) {
  std::vector<std::pair<domain::LocalDate, SortableItem>> result;
  if (context.days.empty()) {
    return common::Result<decltype(result)>::success(std::move(result));
  }
  auto facts = build_event_fact_index(snapshot);
  if (!facts.ok()) return fail<decltype(result)>(facts.error());
  const auto range_start_epoch = context.days.front().start_epoch;
  const auto range_end_epoch = context.days.back().end_epoch;
  for (const auto& event : snapshot.events) {
    if (event.deleted_at.has_value() ||
        event.status == domain::kEventStatusCancelled ||
        event.status == domain::kEventStatusArchived) {
      continue;
    }
    if (!event.recurrence_id.has_value()) {
      auto appended = append_event_interval(event, std::nullopt, std::nullopt,
                                            reminders, context, resolver,
                                            result);
      if (!appended.ok()) return fail<decltype(result)>(appended.error());
      continue;
    }
    if (!event.recurrence_revision.has_value()) {
      return common::Result<decltype(result)>::failure(
          corrupted("Calendar Event recurrence revision is missing"));
    }
    const auto recurrence = facts.value().recurrences.find(recurrence_key(
        *event.recurrence_id, *event.recurrence_revision));
    if (recurrence == facts.value().recurrences.end()) {
      return common::Result<decltype(result)>::failure(
          corrupted("Calendar Event recurrence relationship is missing"));
    }
    const auto* recurrence_value = recurrence->second;
    const auto schedule = domain::recurring_schedule_from_event(event);
    int first_index = 0;
    if (event.is_all_day) {
      if (!event.start_date.has_value() || !event.end_date.has_value()) {
        return common::Result<decltype(result)>::failure(
            corrupted("Calendar all-day Event interval is missing"));
      }
      auto original_start = domain::parse_local_date(*event.start_date);
      auto original_end = domain::parse_local_date(*event.end_date);
      if (!original_start.ok()) return fail<decltype(result)>(original_start.error());
      if (!original_end.ok()) return fail<decltype(result)>(original_end.error());
      first_index = first_candidate_index(*recurrence_value, original_start.value(),
                                          original_end.value(),
                                          context.days.front().date);
    } else {
      auto original_start = resolver.to_local(event.start_at, recurrence_value->timezone);
      auto original_end = resolver.to_local(event.end_at, recurrence_value->timezone);
      auto range_start_local = resolver.to_local(
          common::format_epoch_seconds_utc_iso8601(range_start_epoch),
          recurrence_value->timezone);
      if (!original_start.ok()) return fail<decltype(result)>(original_start.error());
      if (!original_end.ok()) return fail<decltype(result)>(original_end.error());
      if (!range_start_local.ok())
        return fail<decltype(result)>(range_start_local.error());
      first_index = first_candidate_index(
          *recurrence_value, date_part(original_start.value()),
          date_part(original_end.value()), date_part(range_start_local.value()));
    }
    auto occurrences = event.is_all_day
                           ? recurrence_service
                                 .list_all_day_occurrences_from_index(
                                     schedule, *recurrence_value, first_index,
                                     domain::format_local_date(
                                         domain::add_local_days(
                                             context.days.back().date, 1)))
                           : recurrence_service.list_timed_occurrences_from_index(
                                 schedule, *recurrence_value, first_index,
                                 common::format_epoch_seconds_utc_iso8601(
                                     range_end_epoch));
    if (!occurrences.ok()) {
      return fail<decltype(result)>(occurrences.error());
    }
    for (const auto& occurrence : occurrences.value()) {
      auto visible = completed_recurring_series_occurrence_is_eligible(
          event, occurrence, *recurrence_value, resolver);
      if (!visible.ok()) return fail<decltype(result)>(visible.error());
      if (!visible.value()) continue;
      auto state = occurrence_state_for(facts.value(), occurrence);
      auto appended = append_event_interval(event, occurrence, state,
                                            reminders, context, resolver,
                                            result);
      if (!appended.ok()) return fail<decltype(result)>(appended.error());
    }
  }
  return common::Result<decltype(result)>::success(std::move(result));
}

common::Result<std::vector<std::pair<domain::LocalDate, SortableItem>>>
project_habits(const repository::CalendarQuerySnapshot& snapshot,
               const ReminderIndex& reminders,
               const ProjectionContext& context) {
  std::vector<std::pair<domain::LocalDate, SortableItem>> result;
  HabitDailyStatusProjector daily_statuses(snapshot.habit_check_ins);
  for (const auto& habit : snapshot.habits) {
    if (habit.deleted_at.has_value()) continue;
    const auto effective_end = domain::habit_effective_end_date(habit);
    for (const auto& day : context.days) {
      if (day.date < habit.start_date || effective_end < day.date) continue;
      const auto daily = daily_statuses.project(
          habit, day.date, context.evaluation_local_date);
      CalendarHabitItem item;
      item.habit_id = habit.id;
      item.date = day.date;
      item.title = habit.title;
      item.status = daily.status;
      item.target_count_hundredths = habit.target_count_hundredths;
      item.unit = habit.unit;
      if (daily.check_in.has_value()) {
        item.check_in_id = daily.check_in->id;
        item.completed_count_hundredths =
            daily.check_in->completed_count_hundredths;
        if (daily.check_in->target_count_snapshot_hundredths.has_value()) {
          item.target_count_hundredths =
              daily.check_in->target_count_snapshot_hundredths;
          item.unit = daily.check_in->unit_snapshot;
        }
      }
      const auto reminder_key = date_reminder_key(
          habit.id, domain::format_local_date(day.date));
      const auto reminder = reminders.habit_local_times.find(reminder_key);
      const auto reminder_time = reminder == reminders.habit_local_times.end()
                                     ? std::nullopt
                                     : std::optional<std::string>(reminder->second);
      item.has_active_reminder = reminder_time.has_value();
      auto key = habit_sort_key(item, habit, reminder_time);
      result.push_back(
          {day.date, SortableItem{CalendarDayItem(std::move(item)),
                                  std::move(key)}});
    }
  }
  return common::Result<decltype(result)>::success(std::move(result));
}

common::Result<std::vector<std::pair<domain::LocalDate, SortableItem>>>
project_anniversaries(const repository::CalendarQuerySnapshot& snapshot,
                      const ReminderIndex& reminders,
                      const ProjectionContext& context) {
  std::vector<std::pair<domain::LocalDate, SortableItem>> result;
  if (context.days.empty()) {
    return common::Result<decltype(result)>::success(std::move(result));
  }
  const auto recurrence_ids = active_anniversary_recurrence_ids(snapshot);
  const auto range_start = context.days.front().date;
  const auto range_end = domain::add_local_days(context.days.back().date, 1);
  for (const auto& anniversary : snapshot.anniversaries) {
    if (anniversary.deleted_at.has_value()) continue;
    bool repeating = false;
    if (anniversary.recurrence_id.has_value()) {
      if (recurrence_ids.count(*anniversary.recurrence_id) == 0U) {
        return common::Result<decltype(result)>::failure(corrupted(
            "Calendar Anniversary recurrence relationship is missing"));
      }
      repeating = true;
    }
    const int first_year = repeating
                               ? std::max(anniversary.date.year,
                                          range_start.year - 1)
                               : anniversary.date.year;
    const int last_year = repeating ? range_end.year : anniversary.date.year;
    for (int year = first_year; year <= last_year; ++year) {
      const auto date = repeating
                            ? domain::anniversary_occurrence_in_year(
                                  anniversary.date, year)
                            : anniversary.date;
      if (date < range_start || !(date < range_end) ||
          date < anniversary.date) {
        continue;
      }
      auto occurrence_key =
          domain::anniversary_occurrence_key(anniversary.id, date);
      if (!occurrence_key.ok())
        return fail<decltype(result)>(occurrence_key.error());
      CalendarAnniversaryItem item;
      item.anniversary_id = anniversary.id;
      item.occurrence_key = occurrence_key.value();
      item.occurrence_date = date;
      item.source_date = anniversary.date;
      item.title = anniversary.title;
      item.is_repeating = repeating;
      item.years_elapsed = repeating ? date.year - anniversary.date.year : 0;
      item.importance = anniversary.importance;
      item.has_active_reminder =
          reminders.anniversary_occurrences.count(
              date_reminder_key(anniversary.id, item.occurrence_key)) != 0U;
      auto key = anniversary_sort_key(item);
      result.push_back(
          {date, SortableItem{CalendarDayItem(std::move(item)),
                              std::move(key)}});
      if (!repeating) break;
    }
  }
  return common::Result<decltype(result)>::success(std::move(result));
}

bool key_less(const SortableItem& left, const SortableItem& right) {
  return left.key < right.key;
}

common::Result<std::vector<SortableItem>> section_items(
    CalendarSection section, const domain::LocalDate& date,
    const repository::CalendarQuerySnapshot& snapshot,
    const ReminderIndex& reminders, const ProjectionContext& context,
    const domain::LocalTimeResolver& resolver,
    const RecurrenceService& recurrence_service) {
  std::vector<std::pair<domain::LocalDate, SortableItem>> projected;
  if (section == CalendarSection::event) {
    auto result = project_events(snapshot, reminders, context, resolver,
                                 recurrence_service);
    if (!result.ok()) return fail<std::vector<SortableItem>>(result.error());
    projected = std::move(result.value());
  } else if (section == CalendarSection::habit) {
    auto result = project_habits(snapshot, reminders, context);
    if (!result.ok()) return fail<std::vector<SortableItem>>(result.error());
    projected = std::move(result.value());
  } else {
    auto result = project_anniversaries(snapshot, reminders, context);
    if (!result.ok()) return fail<std::vector<SortableItem>>(result.error());
    projected = std::move(result.value());
  }
  std::vector<SortableItem> result;
  for (auto& [projected_date, item] : projected) {
    if (projected_date == date) result.push_back(std::move(item));
  }
  std::sort(result.begin(), result.end(), key_less);
  return common::Result<std::vector<SortableItem>>::success(std::move(result));
}

common::Result<common::Unit> validate_dependencies(
    const std::shared_ptr<repository::CalendarQueryRepository>& repository,
    const std::shared_ptr<domain::LocalTimeResolver>& resolver,
    const std::shared_ptr<RecurrenceService>& recurrence_service) {
  if (!repository) {
    return common::Result<common::Unit>::failure(common::make_error(
        "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
        {{"operation", "calendar.query"}}));
  }
  if (!resolver || !recurrence_service) {
    return common::Result<common::Unit>::failure(
        internal_error("Calendar query dependencies are unavailable"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

std::string calendar_section_to_string(CalendarSection section) {
  switch (section) {
    case CalendarSection::event:
      return "event";
    case CalendarSection::habit:
      return "habit";
    case CalendarSection::anniversary:
      return "anniversary";
  }
  return "event";
}

CalendarViewQueryService::CalendarViewQueryService(
    std::shared_ptr<repository::CalendarQueryRepository> repository,
    std::shared_ptr<domain::LocalTimeResolver> local_time_resolver,
    std::shared_ptr<RecurrenceService> recurrence_service, ClockFn clock)
    : repository_(std::move(repository)),
      local_time_resolver_(std::move(local_time_resolver)),
      recurrence_service_(std::move(recurrence_service)),
      clock_(std::move(clock)) {}

common::Result<CalendarRangeSummary> CalendarViewQueryService::range_summary(
    const CalendarRangeSummaryQuery& query) const {
  auto dependencies = validate_dependencies(repository_, local_time_resolver_,
                                              recurrence_service_);
  if (!dependencies.ok()) return fail<CalendarRangeSummary>(dependencies.error());
  if (!domain::is_valid_local_date(query.range_start_date) ||
      !domain::is_valid_local_date(query.range_end_date)) {
    return common::Result<CalendarRangeSummary>::failure(contract_invalid(
        "range", "range dates must be valid YYYY-MM-DD values"));
  }
  const int days = domain::local_days_between(query.range_start_date,
                                               query.range_end_date);
  if (days <= 0) {
    return common::Result<CalendarRangeSummary>::failure(calendar_error(
        "CALENDAR_RANGE_INVALID",
        "Calendar local-date range is empty or reversed"));
  }
  if (days > kMaximumRangeDays) {
    return common::Result<CalendarRangeSummary>::failure(calendar_error(
        "CALENDAR_RANGE_TOO_LARGE",
        "Calendar local-date range exceeds 42 natural days"));
  }
  auto timezone = local_time_resolver_->validate_timezone(query.timezone);
  if (!timezone.ok()) return fail<CalendarRangeSummary>(timezone.error());
  if (!clock_) {
    return common::Result<CalendarRangeSummary>::failure(
        internal_error("Calendar query clock is unavailable"));
  }
  const auto evaluation_clock = clock_();
  if (!common::is_iso8601_utc_datetime(evaluation_clock)) {
    return common::Result<CalendarRangeSummary>::failure(
        internal_error("Calendar query clock returned an invalid UTC instant"));
  }
  auto snapshot = repository_->load_snapshot();
  if (!snapshot.ok()) return fail<CalendarRangeSummary>(snapshot.error());
  auto context = projection_context(
      query.range_start_date, query.range_end_date, query.timezone,
      evaluation_clock, *local_time_resolver_);
  if (!context.ok()) return fail<CalendarRangeSummary>(context.error());
  auto events = project_event_summary_flags(
      snapshot.value(), context.value(), *local_time_resolver_,
      *recurrence_service_);
  if (!events.ok()) return fail<CalendarRangeSummary>(events.error());
  auto habits =
      project_habit_summary_flags(snapshot.value(), context.value());
  auto anniversaries = project_anniversary_summary_flags(
      snapshot.value(), context.value());
  if (!anniversaries.ok())
    return fail<CalendarRangeSummary>(anniversaries.error());

  CalendarRangeSummary response;
  response.range_start_date = query.range_start_date;
  response.range_end_date = query.range_end_date;
  response.timezone = query.timezone;
  response.snapshot_token =
      snapshot_token_for(snapshot.value(), evaluation_clock);
  for (std::size_t index = 0; index < context.value().days.size(); ++index) {
    CalendarRangeDaySummary day;
    day.date = context.value().days[index].date;
    day.has_open_event = events.value()[index];
    day.has_pending_habit = habits[index];
    day.has_anniversary = anniversaries.value()[index];
    response.days.push_back(std::move(day));
  }
  return common::Result<CalendarRangeSummary>::success(std::move(response));
}

common::Result<CalendarDayItemPage>
CalendarViewQueryService::list_day_items(
    const CalendarListDayItemsQuery& query) const {
  auto dependencies = validate_dependencies(repository_, local_time_resolver_,
                                              recurrence_service_);
  if (!dependencies.ok()) return fail<CalendarDayItemPage>(dependencies.error());
  if (!domain::is_valid_local_date(query.date) || query.page_size < 1 ||
      query.page_size > 100) {
    return common::Result<CalendarDayItemPage>::failure(contract_invalid(
        "date_or_page_size", "date or page_size is invalid"));
  }
  auto timezone = local_time_resolver_->validate_timezone(query.timezone);
  if (!timezone.ok()) return fail<CalendarDayItemPage>(timezone.error());
  auto identity = parse_snapshot_token(query.snapshot_token);
  if (!identity.ok()) return fail<CalendarDayItemPage>(identity.error());
  auto snapshot = repository_->load_snapshot(identity.value().generations);
  if (!snapshot.ok()) return fail<CalendarDayItemPage>(snapshot.error());
  if (!generations_equal(identity.value(), snapshot.value())) {
    return common::Result<CalendarDayItemPage>::failure(calendar_error(
        "CALENDAR_SNAPSHOT_EXPIRED",
        "Calendar snapshot no longer matches the authoritative data generations",
        true));
  }
  std::optional<ParsedCursor> cursor;
  if (query.cursor.has_value()) {
    auto parsed = parse_cursor(*query.cursor);
    if (!parsed.ok()) return fail<CalendarDayItemPage>(parsed.error());
    const bool matches =
        parsed.value().date == domain::format_local_date(query.date) &&
        parsed.value().timezone == query.timezone &&
        parsed.value().section == calendar_section_to_string(query.section) &&
        parsed.value().page_size == query.page_size &&
        parsed.value().sort_revision == kCursorSortRevision &&
        parsed.value().snapshot_token == query.snapshot_token &&
        parsed.value().last_key.size() == expected_key_count(query.section);
    if (!matches) {
      return common::Result<CalendarDayItemPage>::failure(calendar_error(
          "CALENDAR_CURSOR_QUERY_MISMATCH",
          "Calendar day-items cursor does not match the query"));
    }
    cursor = std::move(parsed.value());
  }
  const auto range_end = domain::add_local_days(query.date, 1);
  auto context = projection_context(
      query.date, range_end, query.timezone,
      identity.value().evaluation_clock_utc, *local_time_resolver_);
  if (!context.ok()) return fail<CalendarDayItemPage>(context.error());
  const auto reminders = build_reminder_index(snapshot.value());
  auto items = section_items(query.section, query.date, snapshot.value(),
                             reminders, context.value(), *local_time_resolver_,
                             *recurrence_service_);
  if (!items.ok()) return fail<CalendarDayItemPage>(items.error());

  auto begin = items.value().begin();
  if (cursor.has_value()) {
    const auto found = std::lower_bound(
        items.value().begin(), items.value().end(), cursor->last_key,
        [](const SortableItem& item, const std::vector<std::string>& key) {
          return item.key < key;
        });
    if (found == items.value().end() || found->key != cursor->last_key) {
      return common::Result<CalendarDayItemPage>::failure(calendar_error(
          "CALENDAR_CURSOR_INVALID",
          "Calendar day-items cursor is malformed or non-advancing"));
    }
    begin = found + 1;
  }

  CalendarDayItemPage page;
  page.date = query.date;
  page.timezone = query.timezone;
  page.section = query.section;
  page.snapshot_token = query.snapshot_token;
  page.page_size = query.page_size;
  const auto available = static_cast<std::size_t>(items.value().end() - begin);
  const auto count =
      std::min<std::size_t>(static_cast<std::size_t>(query.page_size),
                            available);
  for (std::size_t index = 0; index < count; ++index) {
    page.items.push_back((begin + static_cast<std::ptrdiff_t>(index))->item);
  }
  page.has_more = count < available;
  if (page.has_more && count > 0U) {
    page.next_cursor = cursor_for(
        query, (begin + static_cast<std::ptrdiff_t>(count - 1U))->key);
  }
  return common::Result<CalendarDayItemPage>::success(std::move(page));
}

}  // namespace excellent_calendar::application
