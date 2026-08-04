#pragma once

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/domain/event_occurrence_state.hpp"
#include "excellent_calendar/domain/recurrence.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

struct EventOccurrenceProjection {
  domain::EventOccurrence occurrence;
  std::optional<domain::EventOccurrenceState> state;
};

struct ListEventOccurrencesCommand {
  std::string event_id;
  int recurrence_revision = 0;
  bool is_all_day = false;
  std::optional<std::string> range_start_at;
  std::optional<std::string> range_end_at;
  std::optional<std::string> range_start_date;
  std::optional<std::string> range_end_date;
  std::optional<std::string> cursor;
  int limit = 200;
};

struct EventOccurrencePage {
  std::vector<EventOccurrenceProjection> items;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct EventSearchQueryV2 {
  std::optional<std::string> keyword;
  std::optional<std::string> start_at_from;
  std::optional<std::string> start_at_to;
  std::optional<std::string> start_date_from;
  std::optional<std::string> start_date_to;
  std::vector<std::string> status;
  std::vector<std::string> category_ids;
  std::vector<std::string> importance;
  std::optional<std::string> location;
  std::optional<bool> has_recurrence;
  std::vector<std::string> source;
  bool include_deleted = false;
  int page = 1;
  int page_size = 20;
  std::optional<std::string> cursor;
  std::string sort_by = "start";
  std::string sort_direction = "asc";
};

struct EventSearchPageV2 {
  std::vector<domain::Event> items;
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct EventDetailAggregate {
  domain::Event event;
  std::optional<domain::Recurrence> recurrence;
  std::vector<domain::Reminder> reminders;
};

class RecurringEventQueryService {
 public:
  RecurringEventQueryService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      std::shared_ptr<RecurrenceService> recurrence_service);

  common::Result<domain::Event> get_event(const std::string& event_id) const;
  common::Result<EventDetailAggregate> get_event_detail(
      const std::string& event_id) const;
  common::Result<EventSearchPageV2> search_events(const EventSearchQueryV2& query) const;
  common::Result<std::optional<domain::Recurrence>> get_recurrence_for_event(
      const std::string& event_id) const;
  common::Result<domain::Recurrence> get_current_recurrence(
      const std::string& event_id) const;
  common::Result<EventOccurrencePage> list_occurrences(
      const ListEventOccurrencesCommand& command) const;

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  std::shared_ptr<RecurrenceService> recurrence_service_;
};

}  // namespace excellent_calendar::application
