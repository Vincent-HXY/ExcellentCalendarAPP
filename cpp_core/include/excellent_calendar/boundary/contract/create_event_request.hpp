#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::boundary::contract {

struct CreateEventRequest {
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

}  // namespace excellent_calendar::boundary::contract
