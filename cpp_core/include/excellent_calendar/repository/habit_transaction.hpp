#pragma once

#include <functional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/habit.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::repository {

struct HabitState {
  std::vector<domain::HabitRecurrence> recurrences;
  std::vector<domain::Habit> habits;
  std::vector<domain::HabitCheckIn> check_ins;
  std::vector<domain::HabitReminderTemplate> reminder_templates;
  std::vector<domain::Reminder> reminders;
  std::vector<domain::Notification> notifications;
};

class HabitTransaction {
 public:
  using Operation =
      std::function<common::Result<common::Unit>(HabitState& state)>;

  virtual ~HabitTransaction() = default;
  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<HabitState> load() = 0;
  virtual common::Result<common::Unit> execute(std::string_view operation,
                                               const Operation& action) = 0;
};

}  // namespace excellent_calendar::repository
