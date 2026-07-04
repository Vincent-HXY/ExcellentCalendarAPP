#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/repository/event_repository.hpp"
#include "excellent_calendar/repository/reminder_repository.hpp"

namespace excellent_calendar::application {

struct CreateReminderCommand {
  std::string target_type;
  std::string target_id;
  std::optional<std::string> remind_at;
  std::optional<int> advance_minutes;
  std::vector<std::string> methods;
  std::optional<std::string> message;
  bool is_enabled = true;
  std::string source;
};

struct CancelReminderCommand {
  std::string id;
  std::optional<std::string> reason;
};

struct MarkReminderScheduledCommand {
  std::string id;
  std::string scheduled_at;
};

struct MarkReminderSentCommand {
  std::string id;
  std::string last_triggered_at;
};

struct MarkReminderFailedCommand {
  std::string id;
  std::string failure_reason;
};

struct ReminderIdCommand {
  std::string id;
};

struct GetReminderCommand {
  std::string id;
};

struct ListSchedulableRemindersCommand {
  std::string from_at;
  std::string to_at;
  int limit = 500;
  bool include_failed = true;
  bool include_scheduled = false;
  std::vector<std::string> supported_methods;
};

struct SchedulableReminderListResult {
  std::vector<domain::Reminder> items;
  bool has_more = false;
  std::vector<std::string> unsupported_reminder_ids;
};

struct ReminderPaginationRequest {
  int page = 1;
  int page_size = 20;
};

struct ReminderQuery {
  std::optional<std::string> target_type;
  std::optional<std::string> target_id;
  std::optional<std::string> remind_at_from;
  std::optional<std::string> remind_at_to;
  std::vector<std::string> methods;
  std::vector<std::string> status;
  std::optional<bool> is_enabled;
  bool include_deleted = false;
  ReminderPaginationRequest pagination;
  std::string sort_by = "remind_at";
  std::string sort_direction = "asc";
};

struct ReminderPaginationResponse {
  int total = 0;
  int page = 1;
  int page_size = 20;
  bool has_more = false;
  std::optional<std::string> next_cursor;
};

struct ReminderListResult {
  std::vector<domain::Reminder> items;
  ReminderPaginationResponse pagination;
};

class ReminderService {
 public:
  using ClockFn = std::function<std::string()>;
  using IdGeneratorFn = std::function<std::string()>;

  ReminderService(
      std::shared_ptr<repository::ReminderRepository> reminder_repository,
      std::shared_ptr<repository::EventRepository> event_repository,
      ClockFn clock,
      IdGeneratorFn id_generator);

  common::Result<domain::Reminder> create_reminder(const CreateReminderCommand& command);

  common::Result<domain::Reminder> get_reminder(const GetReminderCommand& command);

  common::Result<SchedulableReminderListResult> list_schedulable_reminders(
      const ListSchedulableRemindersCommand& command);

  common::Result<domain::Reminder> cancel_reminder(const CancelReminderCommand& command);

  common::Result<domain::Reminder> mark_scheduled(const MarkReminderScheduledCommand& command);

  common::Result<domain::Reminder> mark_sent(const MarkReminderSentCommand& command);

  common::Result<domain::Reminder> mark_failed(const MarkReminderFailedCommand& command);

  common::Result<domain::Reminder> enable_reminder(const ReminderIdCommand& command);

  common::Result<domain::Reminder> disable_reminder(const ReminderIdCommand& command);

  common::Result<ReminderListResult> list_reminders(const ReminderQuery& query);

 private:
  common::Result<domain::Event> require_event_target(const std::string& target_id);

  std::shared_ptr<repository::ReminderRepository> reminder_repository_;
  std::shared_ptr<repository::EventRepository> event_repository_;
  ClockFn clock_;
  IdGeneratorFn id_generator_;
};

}  // namespace excellent_calendar::application
