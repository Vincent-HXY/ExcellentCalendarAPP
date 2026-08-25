#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"

namespace excellent_calendar::domain {

inline constexpr std::string_view kAnniversaryCalendarSolar = "solar";
inline constexpr std::string_view kAnniversaryCalendarLunar = "lunar";
inline constexpr std::string_view kAnniversaryRecurrenceYearly = "yearly";
inline constexpr std::string_view kAnniversaryCountdownRemaining = "remaining";
inline constexpr std::string_view kAnniversaryCountdownElapsed = "elapsed";
inline constexpr std::string_view kAnniversaryCountdownToday = "today";
inline constexpr std::string_view kAnniversaryReminderTimezoneFollowDevice = "follow_device";
inline constexpr std::string_view kAnniversaryReminderMethodPopup = "popup";

inline constexpr std::string_view kAnniversaryOccurrenceNamespace =
    "81d70a6c-365e-5622-9d5a-afefe28c95a0";
inline constexpr std::string_view kAnniversaryReminderTemplateNamespace =
    "9df8756b-f1a2-5b5a-9b36-8c2defa75790";
inline constexpr std::string_view kAnniversaryReminderNamespace =
    "228c4486-53b8-5b2e-8d13-62d9d6cfee56";
inline constexpr std::string_view kAnniversaryCatchUpDeliveryNamespace =
    "f159a148-554a-56d2-a79c-9d4bd9646973";

struct Anniversary {
  std::string id;
  std::string title;
  LocalDate date;
  std::string calendar_type;
  std::optional<std::string> category_id;
  std::optional<std::string> recurrence_id;
  std::optional<std::string> note;
  std::optional<std::string> importance;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
  bool reminders_enabled = false;
};

struct AnniversaryRecurrence {
  std::string id;
  std::string frequency;
  int interval = 1;
  std::string created_at;
  std::optional<std::string> deleted_at;
};

struct AnniversaryCountdown {
  std::string relation;
  int days = 0;
  LocalDate target_occurrence_date;
  int iso_weekday = 1;
  std::string timezone;
  std::string calculated_at;
};

struct AnniversaryReminderTemplate {
  std::string template_key;
  std::string anniversary_id;
  int advance_days = 0;
  std::string local_time;
  std::string timezone_mode = std::string(kAnniversaryReminderTimezoneFollowDevice);
  std::string method = std::string(kAnniversaryReminderMethodPopup);
  bool is_enabled = true;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

struct AnniversaryOccurrence {
  std::string anniversary_id;
  std::string occurrence_key;
  LocalDate occurrence_date;
  LocalDate source_date;
  std::string title;
  std::string calendar_type;
  bool is_repeating = false;
  int years_elapsed = 0;
  std::optional<std::string> category_id;
  std::optional<std::string> importance;
  bool has_active_reminders = false;
  int reminder_count = 0;
};

common::Result<common::Unit> validate_anniversary_input(
    std::string_view title,
    const LocalDate& date,
    std::string_view calendar_type,
    const std::optional<std::string>& category_id,
    const std::optional<std::string>& importance);

common::Result<common::Unit> validate_anniversary(const Anniversary& anniversary);

common::Result<common::Unit> validate_anniversary_recurrence(
    const AnniversaryRecurrence& recurrence);

common::Result<common::Unit> validate_anniversary_reminder_template(
    const AnniversaryReminderTemplate& reminder_template);

common::Result<std::string> anniversary_occurrence_key(
    std::string_view anniversary_id,
    const LocalDate& occurrence_date);

common::Result<std::string> anniversary_reminder_template_key(
    std::string_view anniversary_id,
    int advance_days,
    std::string_view local_time);

common::Result<std::string> anniversary_reminder_id(
    std::string_view anniversary_id,
    std::string_view occurrence_key,
    std::string_view template_key);

common::Result<std::string> anniversary_catch_up_delivery_id(
    std::string_view anniversary_id,
    std::string_view occurrence_key,
    std::vector<std::string> covered_reminder_ids);

LocalDate anniversary_occurrence_in_year(const LocalDate& source_date, int year);

common::Result<AnniversaryCountdown> calculate_anniversary_countdown(
    const LocalDate& anniversary_date,
    bool repeats_yearly,
    const LocalDate& today,
    std::string timezone,
    std::string calculated_at);

}  // namespace excellent_calendar::domain
