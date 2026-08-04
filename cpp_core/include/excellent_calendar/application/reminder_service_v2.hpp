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

template <typename T>
struct ReminderFieldPatch {
  bool supplied = false;
  T value{};
};

struct CreateReminderV2Command {
  std::string target_type;
  std::string target_id;
  std::optional<std::string> remind_at;
  std::optional<int> advance_minutes;
  std::vector<std::string> methods;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string source;
};

struct UpdateReminderV2Command {
  std::string reminder_id;
  ReminderFieldPatch<std::string> target_type;
  ReminderFieldPatch<std::string> target_id;
  ReminderFieldPatch<std::optional<std::string>> remind_at;
  ReminderFieldPatch<std::optional<int>> advance_minutes;
  ReminderFieldPatch<std::vector<std::string>> methods;
  ReminderFieldPatch<std::optional<std::string>> message;
  ReminderFieldPatch<std::string> source;
};

struct ReminderIdV2Command {
  std::string reminder_id;
};

struct ReminderListQueryV2 {
  std::optional<std::string> target_type;
  std::optional<std::string> target_id;
  std::optional<int> recurrence_revision;
  std::optional<std::string> occurrence_key;
  std::optional<std::string> remind_at_from;
  std::optional<std::string> remind_at_to;
  std::vector<std::string> methods;
  std::vector<std::string> status;
  std::optional<bool> is_enabled;
  bool include_deleted = false;
  int page = 1;
  int page_size = 20;
  std::optional<std::string> cursor;
  std::string sort_by = "remind_at";
  std::string sort_direction = "asc";
};

struct ReminderListPageV2 {
  std::vector<domain::Reminder> items;
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

class ReminderServiceV2 {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  ReminderServiceV2(
      std::shared_ptr<repository::RecurringEventTransaction> transaction,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<domain::Reminder> create(const CreateReminderV2Command& command);
  common::Result<domain::Reminder> update(const UpdateReminderV2Command& command);
  common::Result<domain::Reminder> cancel(const ReminderIdV2Command& command);
  common::Result<domain::Reminder> enable(const ReminderIdV2Command& command);
  common::Result<domain::Reminder> disable(const ReminderIdV2Command& command);
  common::Result<ReminderListPageV2> list(const ReminderListQueryV2& query) const;

 private:
  std::shared_ptr<repository::RecurringEventTransaction> transaction_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
