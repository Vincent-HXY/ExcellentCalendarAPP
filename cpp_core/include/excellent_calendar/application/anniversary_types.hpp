#pragma once

#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/domain/anniversary.hpp"

namespace excellent_calendar::application {

struct AnniversaryReminderTemplateInput {
  int advance_days = 0;
  std::string local_time;
  std::string method = "popup";
  bool is_enabled = true;
};

struct AnniversaryReminderPlanInput {
  bool reminders_enabled = false;
  std::vector<AnniversaryReminderTemplateInput> templates;
};

struct AnniversaryReminderSettings {
  bool reminders_enabled = false;
  std::vector<domain::AnniversaryReminderTemplate> templates;
  int active_reminder_count = 0;
  bool schedule_reconciliation_required = false;
};

struct AnniversaryWriteInput {
  std::string title;
  domain::LocalDate date;
  std::string calendar_type;
  std::optional<std::string> category_id;
  bool repeats_yearly = false;
  std::optional<std::string> note;
  std::optional<std::string> importance;
  std::string timezone;
  std::optional<AnniversaryReminderPlanInput> reminder_plan;
};

struct CreateAnniversaryCommand {
  AnniversaryWriteInput input;
};

struct UpdateAnniversaryCommand {
  std::string id;
  std::string expected_updated_at;
  AnniversaryWriteInput input;
};

struct DeleteAnniversaryCommand {
  std::string id;
};

struct SetAnniversaryRemindersEnabledCommand {
  std::string id;
  bool reminders_enabled = false;
  std::string timezone;
};

struct AnniversaryDetail {
  domain::Anniversary anniversary;
  std::optional<domain::AnniversaryRecurrence> recurrence;
  domain::AnniversaryCountdown countdown;
  AnniversaryReminderSettings reminder_settings;
};

struct AnniversaryDeleteResult {
  domain::Anniversary anniversary;
  bool schedule_reconciliation_required = false;
  // Compatibility projection for existing in-process callers.
  std::optional<std::string> deleted_at;
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

struct ListAnniversaryOccurrencesQuery {
  domain::LocalDate range_start_date;
  domain::LocalDate range_end_date;
  std::string timezone;
  std::vector<std::string> category_ids;
  std::vector<std::string> importance;
  std::optional<std::string> cursor;
  int page_size = 100;
};

struct AnniversaryOccurrencePage {
  std::vector<domain::AnniversaryOccurrence> items;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

}  // namespace excellent_calendar::application
