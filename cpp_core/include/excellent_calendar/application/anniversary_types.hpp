#pragma once

#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/domain/anniversary.hpp"

namespace excellent_calendar::application {

struct AnniversaryWriteInput {
  std::string title;
  domain::LocalDate date;
  std::string calendar_type;
  std::optional<std::string> category_id;
  bool repeats_yearly = false;
  std::optional<std::string> note;
  std::optional<std::string> importance;
  std::string timezone;
};

struct CreateAnniversaryCommand {
  AnniversaryWriteInput input;
};

struct UpdateAnniversaryCommand {
  std::string id;
  AnniversaryWriteInput input;
};

struct DeleteAnniversaryCommand {
  std::string id;
};

struct AnniversaryDetail {
  domain::Anniversary anniversary;
  std::optional<domain::AnniversaryRecurrence> recurrence;
  domain::AnniversaryCountdown countdown;
};

struct GetAnniversaryDetailQuery {
  std::string id;
  std::string timezone;
};

struct ListAnniversariesQuery {
  std::string timezone;
  std::vector<std::string> category_ids;
  std::vector<std::string> importance;
  int page = 1;
  int page_size = 20;
  std::optional<std::string> cursor;
  std::string sort_by = "target_occurrence_date";
  std::string sort_direction = "asc";
};

struct AnniversarySummary {
  domain::Anniversary anniversary;
  domain::AnniversaryCountdown countdown;
};

struct AnniversaryListPage {
  std::vector<AnniversarySummary> items;
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct PreviewAnniversaryCountdownQuery {
  domain::LocalDate date;
  std::string calendar_type;
  bool repeats_yearly = false;
  std::string timezone;
};

}  // namespace excellent_calendar::application
