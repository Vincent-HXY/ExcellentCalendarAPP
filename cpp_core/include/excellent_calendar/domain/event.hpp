#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::domain {

struct Event {
  std::string id;
  std::string title;
  std::optional<std::string> content;
  std::string start_at;
  std::string end_at;
  bool is_all_day = false;
  bool has_recurrence = false;
  std::string status;
  std::optional<std::string> completed_at;
  std::optional<std::string> recurrence_id;
  std::optional<std::string> category_id;
  std::optional<std::string> importance;
  std::optional<std::string> location;
  std::optional<std::string> timezone;
  std::string source;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

}  // namespace excellent_calendar::domain
