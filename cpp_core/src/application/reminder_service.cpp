#include "excellent_calendar/application/reminder_service.hpp"

#include <algorithm>
#include <cctype>
#include <set>
#include <sstream>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"

namespace excellent_calendar::application {
namespace {

common::Error contract_validation_failed(std::string field, std::string message) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED",
      std::move(message),
      {{"field", std::move(field)}});
}

common::Error reminder_time_invalid(std::string field = "remind_at") {
  return common::make_error(
      "REMINDER_TIME_INVALID",
      "Reminder time is invalid",
      {{"field", std::move(field)}});
}

common::Error reminder_target_not_found(std::string target_type, std::string target_id) {
  return common::make_error(
      "REMINDER_TARGET_NOT_FOUND",
      "Reminder target does not exist",
      {{"target_type", std::move(target_type)}, {"target_id", std::move(target_id)}});
}

common::Error reminder_not_found(std::string id) {
  return common::make_error(
      "REMINDER_NOT_FOUND",
      "Reminder not found",
      {{"id", std::move(id)}});
}

common::Error reminder_method_invalid(std::string field = "methods") {
  return common::make_error(
      "REMINDER_METHOD_INVALID",
      "Reminder method is invalid",
      {{"field", std::move(field)}});
}

common::Error feature_not_implemented(std::string feature) {
  return common::make_error(
      "FEATURE_NOT_IMPLEMENTED",
      "Requested feature is not implemented in this phase",
      {{"feature", std::move(feature)}});
}

common::Error storage_corrupted(std::string field, std::string message) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED",
      "Storage data is corrupted",
      {{"field", std::move(field)}, {"reason", std::move(message)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR",
      "Native internal error",
      {{"reason", std::move(reason)}});
}

bool vector_contains(const std::vector<std::string>& values, const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

common::Result<common::Unit> validate_methods(const std::vector<std::string>& methods) {
  if (methods.empty()) {
    return common::Result<common::Unit>::failure(reminder_method_invalid());
  }
  std::set<std::string> seen;
  for (const auto& method : methods) {
    if (!domain::is_valid_reminder_method(method)) {
      return common::Result<common::Unit>::failure(reminder_method_invalid());
    }
    if (!seen.insert(method).second) {
      return common::Result<common::Unit>::failure(reminder_method_invalid());
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

bool reminder_has_any_method(const domain::Reminder& reminder, const std::vector<std::string>& methods) {
  if (methods.empty()) {
    return true;
  }
  for (const auto& method : methods) {
    if (vector_contains(reminder.methods, method)) {
      return true;
    }
  }
  return false;
}

int compare_reminders_by(const domain::Reminder& left,
                         const domain::Reminder& right,
                         const std::string& sort_by) {
  if (sort_by == "created_at") {
    return left.created_at.compare(right.created_at);
  }
  if (sort_by == "updated_at") {
    return left.updated_at.compare(right.updated_at);
  }
  if (sort_by == "status") {
    return left.status.compare(right.status);
  }
  if (sort_by == "target_type") {
    return left.target_type.compare(right.target_type);
  }
  return left.remind_at.compare(right.remind_at);
}

bool is_supported_sort_by(const std::string& value) {
  return value == "remind_at" ||
         value == "created_at" ||
         value == "updated_at" ||
         value == "status" ||
         value == "target_type";
}

bool is_cancelable_status(const std::string& status) {
  return status == std::string(domain::kReminderStatusPending) ||
         status == std::string(domain::kReminderStatusScheduled) ||
         status == std::string(domain::kReminderStatusFailed);
}

std::string sanitize_failure_reason(const std::string& reason) {
  std::string first_line;
  first_line.reserve(reason.size());
  for (const char ch : reason) {
    if (ch == '\r' || ch == '\n') {
      break;
    }
    if (std::iscntrl(static_cast<unsigned char>(ch))) {
      first_line.push_back(' ');
    } else {
      first_line.push_back(ch);
    }
  }

  std::istringstream input(first_line);
  std::ostringstream output;
  bool first = true;
  std::string token;
  while (input >> token) {
    if (token.find('/') != std::string::npos || token.find('\\') != std::string::npos) {
      token = "[path]";
    }
    if (!first) {
      output << ' ';
    }
    output << token;
    first = false;
  }

  auto cleaned = common::trim_ascii(output.str());
  if (cleaned.empty()) {
    cleaned = "Alarm scheduling failed";
  }
  static constexpr std::size_t kMaxReasonLength = 200;
  if (cleaned.size() > kMaxReasonLength) {
    cleaned.resize(kMaxReasonLength);
  }
  return cleaned;
}

}  // namespace

ReminderService::ReminderService(
    std::shared_ptr<repository::ReminderRepository> reminder_repository,
    std::shared_ptr<repository::EventRepository> event_repository,
    ClockFn clock,
    IdGeneratorFn id_generator)
    : reminder_repository_(std::move(reminder_repository)),
      event_repository_(std::move(event_repository)),
      clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Event> ReminderService::require_event_target(const std::string& target_id) {
  auto found = event_repository_->find_by_id(target_id);
  if (!found.ok()) {
    return common::Result<domain::Event>::failure(found.error());
  }
  if (!found.value().has_value() || found.value()->deleted_at.has_value()) {
    return common::Result<domain::Event>::failure(
        reminder_target_not_found(std::string(domain::kReminderTargetEvent), target_id));
  }
  return common::Result<domain::Event>::success(*found.value());
}

common::Result<domain::Reminder> ReminderService::create_reminder(const CreateReminderCommand& command) {
  if (!domain::is_valid_reminder_target_type(command.target_type)) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("target_type", "CreateReminderRequest.target_type has an unsupported enum value."));
  }
  if (!domain::is_supported_reminder_target_type(command.target_type)) {
    return common::Result<domain::Reminder>::failure(
        feature_not_implemented("reminder.target_type." + command.target_type));
  }
  if (common::trim_ascii(command.target_id).empty()) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("target_id", "CreateReminderRequest.target_id must be non-empty."));
  }
  if (!command.is_enabled) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("is_enabled", "New pending reminders must be enabled."));
  }
  if (!domain::is_valid_reminder_source(command.source)) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("source", "CreateReminderRequest.source has an unsupported enum value."));
  }
  auto methods = validate_methods(command.methods);
  if (!methods.ok()) {
    return common::Result<domain::Reminder>::failure(methods.error());
  }
  if (command.advance_minutes.has_value() && *command.advance_minutes < 0) {
    return common::Result<domain::Reminder>::failure(reminder_time_invalid("advance_minutes"));
  }

  auto target = require_event_target(command.target_id);
  if (!target.ok()) {
    return common::Result<domain::Reminder>::failure(target.error());
  }

  std::string remind_at;
  if (command.remind_at.has_value()) {
    if (!common::is_iso8601_utc_datetime(*command.remind_at)) {
      return common::Result<domain::Reminder>::failure(reminder_time_invalid("remind_at"));
    }
    remind_at = *command.remind_at;
  } else {
    if (!command.advance_minutes.has_value()) {
      return common::Result<domain::Reminder>::failure(reminder_time_invalid("remind_at"));
    }
    const auto target_start = common::parse_iso8601_utc_epoch_seconds(target.value().start_at);
    if (!target_start.has_value()) {
      return common::Result<domain::Reminder>::failure(storage_corrupted("event.start_at", "target event start_at is invalid"));
    }
    const auto offset_seconds = static_cast<std::int64_t>(*command.advance_minutes) * 60;
    if (*target_start < offset_seconds) {
      return common::Result<domain::Reminder>::failure(reminder_time_invalid("advance_minutes"));
    }
    remind_at = common::format_epoch_seconds_utc_iso8601(*target_start - offset_seconds);
  }

  const auto now = clock_();
  const auto now_epoch = common::parse_iso8601_utc_epoch_seconds(now);
  if (!now_epoch.has_value()) {
    return common::Result<domain::Reminder>::failure(
        internal_error("ReminderService clock returned an invalid UTC time"));
  }
  const auto remind_at_epoch = common::parse_iso8601_utc_epoch_seconds(remind_at);
  if (!remind_at_epoch.has_value() || *remind_at_epoch <= *now_epoch) {
    return common::Result<domain::Reminder>::failure(reminder_time_invalid("remind_at"));
  }

  domain::Reminder reminder;
  reminder.id = id_generator_();
  reminder.target_type = command.target_type;
  reminder.target_id = command.target_id;
  reminder.remind_at = remind_at;
  reminder.methods = command.methods;
  reminder.advance_minutes = command.advance_minutes;
  reminder.message = command.message;
  reminder.is_enabled = true;
  reminder.status = std::string(domain::kReminderStatusPending);
  reminder.scheduled_at = std::nullopt;
  reminder.last_triggered_at = std::nullopt;
  reminder.failure_reason = std::nullopt;
  reminder.source = command.source;
  reminder.created_at = now;
  reminder.updated_at = now;
  reminder.deleted_at = std::nullopt;

  return reminder_repository_->create(reminder);
}

common::Result<domain::Reminder> ReminderService::cancel_reminder(const CancelReminderCommand& command) {
  if (common::trim_ascii(command.id).empty()) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("id", "CancelReminderRequest.id must be non-empty."));
  }

  auto found = reminder_repository_->find_by_id(command.id);
  if (!found.ok()) {
    return common::Result<domain::Reminder>::failure(found.error());
  }
  if (!found.value().has_value()) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(command.id));
  }

  auto reminder = *found.value();
  if (reminder.status == std::string(domain::kReminderStatusCancelled)) {
    return common::Result<domain::Reminder>::success(reminder);
  }
  if (reminder.deleted_at.has_value()) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(command.id));
  }
  if (!is_cancelable_status(reminder.status)) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("status", "Reminder status cannot be cancelled."));
  }

  const auto now = clock_();
  reminder.status = std::string(domain::kReminderStatusCancelled);
  reminder.is_enabled = false;
  reminder.deleted_at = now;
  reminder.updated_at = now;
  return reminder_repository_->update(reminder);
}

common::Result<domain::Reminder> ReminderService::mark_scheduled(const std::string& id) {
  if (common::trim_ascii(id).empty()) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("id", "Reminder id must be non-empty."));
  }
  auto found = reminder_repository_->find_by_id(id);
  if (!found.ok()) {
    return common::Result<domain::Reminder>::failure(found.error());
  }
  if (!found.value().has_value() || found.value()->deleted_at.has_value() ||
      found.value()->status == std::string(domain::kReminderStatusCancelled)) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(id));
  }
  if (!found.value()->is_enabled) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("is_enabled", "Disabled reminders cannot be scheduled."));
  }

  auto reminder = *found.value();
  const auto now = clock_();
  reminder.status = std::string(domain::kReminderStatusScheduled);
  reminder.scheduled_at = now;
  reminder.failure_reason = std::nullopt;
  reminder.updated_at = now;
  return reminder_repository_->update(reminder);
}

common::Result<domain::Reminder> ReminderService::mark_failed(const std::string& id,
                                                              const std::string& failure_reason) {
  if (common::trim_ascii(id).empty()) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("id", "Reminder id must be non-empty."));
  }
  auto found = reminder_repository_->find_by_id(id);
  if (!found.ok()) {
    return common::Result<domain::Reminder>::failure(found.error());
  }
  if (!found.value().has_value() || found.value()->deleted_at.has_value() ||
      found.value()->status == std::string(domain::kReminderStatusCancelled)) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(id));
  }
  if (!found.value()->is_enabled) {
    return common::Result<domain::Reminder>::failure(
        contract_validation_failed("is_enabled", "Disabled reminders cannot be marked failed."));
  }

  auto reminder = *found.value();
  reminder.status = std::string(domain::kReminderStatusFailed);
  reminder.failure_reason = sanitize_failure_reason(failure_reason);
  reminder.updated_at = clock_();
  return reminder_repository_->update(reminder);
}

common::Result<ReminderListResult> ReminderService::list_reminders(const ReminderQuery& query) {
  if (!is_supported_sort_by(query.sort_by)) {
    return common::Result<ReminderListResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Reminder sort_by is invalid", {{"field", "sort_by"}}));
  }
  if (query.sort_direction != "asc" && query.sort_direction != "desc") {
    return common::Result<ReminderListResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Reminder sort_direction is invalid", {{"field", "sort_direction"}}));
  }
  if (query.pagination.page < 1 || query.pagination.page_size < 1 || query.pagination.page_size > 200) {
    return common::Result<ReminderListResult>::failure(
        common::make_error("SEARCH_QUERY_INVALID", "Reminder pagination is invalid", {{"field", "pagination"}}));
  }

  std::optional<std::int64_t> from_time;
  std::optional<std::int64_t> to_time;
  if (query.remind_at_from.has_value()) {
    from_time = common::parse_iso8601_utc_epoch_seconds(*query.remind_at_from);
    if (!from_time.has_value()) {
      return common::Result<ReminderListResult>::failure(reminder_time_invalid("remind_at_from"));
    }
  }
  if (query.remind_at_to.has_value()) {
    to_time = common::parse_iso8601_utc_epoch_seconds(*query.remind_at_to);
    if (!to_time.has_value()) {
      return common::Result<ReminderListResult>::failure(reminder_time_invalid("remind_at_to"));
    }
  }
  if (from_time.has_value() && to_time.has_value() && *from_time > *to_time) {
    return common::Result<ReminderListResult>::failure(reminder_time_invalid("remind_at_from"));
  }

  auto loaded = reminder_repository_->find_all();
  if (!loaded.ok()) {
    return common::Result<ReminderListResult>::failure(loaded.error());
  }

  std::vector<domain::Reminder> filtered;
  for (const auto& reminder : loaded.value()) {
    if (!query.include_deleted && reminder.deleted_at.has_value()) {
      continue;
    }
    if (query.target_type.has_value() && reminder.target_type != *query.target_type) {
      continue;
    }
    if (query.target_id.has_value() && reminder.target_id != *query.target_id) {
      continue;
    }
    const auto reminder_time = common::parse_iso8601_utc_epoch_seconds(reminder.remind_at);
    if (!reminder_time.has_value()) {
      return common::Result<ReminderListResult>::failure(
          storage_corrupted("remind_at", "stored reminder remind_at is invalid"));
    }
    if (from_time.has_value() && *reminder_time < *from_time) {
      continue;
    }
    if (to_time.has_value() && *reminder_time > *to_time) {
      continue;
    }
    if (!reminder_has_any_method(reminder, query.methods)) {
      continue;
    }
    if (!query.status.empty() && !vector_contains(query.status, reminder.status)) {
      continue;
    }
    if (query.is_enabled.has_value() && reminder.is_enabled != *query.is_enabled) {
      continue;
    }
    filtered.push_back(reminder);
  }

  std::stable_sort(filtered.begin(), filtered.end(), [&](const domain::Reminder& left, const domain::Reminder& right) {
    const int comparison = compare_reminders_by(left, right, query.sort_by);
    if (comparison == 0) {
      return false;
    }
    return query.sort_direction == "desc" ? comparison > 0 : comparison < 0;
  });

  ReminderListResult result;
  result.pagination.total = static_cast<int>(filtered.size());
  result.pagination.page = query.pagination.page;
  result.pagination.page_size = query.pagination.page_size;
  const int offset = (query.pagination.page - 1) * query.pagination.page_size;
  result.pagination.has_more = offset + query.pagination.page_size < result.pagination.total;
  result.pagination.next_cursor = std::nullopt;

  if (offset < result.pagination.total) {
    const int end = std::min(offset + query.pagination.page_size, result.pagination.total);
    result.items.assign(filtered.begin() + offset, filtered.begin() + end);
  }
  return common::Result<ReminderListResult>::success(std::move(result));
}

}  // namespace excellent_calendar::application
