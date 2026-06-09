#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/event.hpp"
#include "excellent_calendar/repository/event_repository.hpp"

namespace excellent_calendar::application {

struct CreateEventCommand {
  std::string title;
  std::optional<std::string> content;
  std::string start_at;
  std::string end_at;
  bool is_all_day = false;
  std::optional<std::string> category_id;
  std::optional<std::string> importance;
  std::optional<std::string> location;
  std::optional<std::string> timezone;
  std::string source;
};

struct PaginationRequest {
  int page = 1;
  int page_size = 20;
};

struct EventQuery {
  std::optional<std::string> keyword;
  std::optional<std::string> start_at_from;
  std::optional<std::string> start_at_to;
  std::vector<std::string> category_ids;
  std::vector<std::string> importance;
  std::optional<std::string> location;
  std::optional<bool> has_recurrence;
  std::vector<std::string> source;
  bool include_deleted = false;
  PaginationRequest pagination;
  std::string sort_by = "start_at";
  std::string sort_direction = "asc";
};

struct PaginationResponse {
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct EventSearchResult {
  std::vector<domain::Event> items;
  PaginationResponse pagination;
};

class EventService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  EventService(
      std::shared_ptr<repository::EventRepository> repository,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<domain::Event> create_event(const CreateEventCommand& command);

  common::Result<EventSearchResult> search_events(const EventQuery& query);

 private:
  std::shared_ptr<repository::EventRepository> repository_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
