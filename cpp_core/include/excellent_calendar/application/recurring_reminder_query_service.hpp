#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/recurring_event_transaction.hpp"

namespace excellent_calendar::application {

struct ListRecurringSchedulableRemindersCommand {
  std::optional<std::string> from_at;
  std::optional<std::string> to_at;
  std::optional<std::string> cursor_remind_at;
  std::optional<std::string> cursor_reminder_id;
  int limit = 500;
  bool include_scheduled = false;
  std::vector<std::string> supported_methods;
};

struct RecurringSchedulableReminderPage {
  std::vector<domain::Reminder> items;
  bool has_more = false;
  std::optional<std::string> next_cursor_remind_at;
  std::optional<std::string> next_cursor_reminder_id;
  std::vector<std::string> unsupported_reminder_ids;
};

struct MarkRecurringReminderScheduledCommand {
  std::string reminder_id;
  std::string expected_remind_at;
  std::string scheduled_at;
};

class RecurringReminderQueryService {
 public:
  using ClockFn = std::function<std::string()>;

  RecurringReminderQueryService(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      ClockFn clock);

  common::Result<domain::Reminder> get_reminder(const std::string& reminder_id) const;
  common::Result<std::vector<domain::RecurringReminderDraft>> list_templates(
      const std::string& event_id,
      int recurrence_revision) const;
  common::Result<std::vector<domain::Reminder>> list_current_for_event(
      const std::string& event_id,
      int recurrence_revision) const;
  common::Result<std::vector<domain::Reminder>> list_for_event(
      const std::string& event_id,
      std::optional<int> recurrence_revision) const;
  common::Result<RecurringSchedulableReminderPage> list_schedulable(
      const ListRecurringSchedulableRemindersCommand& command) const;
  common::Result<domain::Reminder> mark_scheduled(
      const MarkRecurringReminderScheduledCommand& command);

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  ClockFn clock_;
};

}  // namespace excellent_calendar::application
