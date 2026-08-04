#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"

#include <cmath>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_event_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_delivery_workflow_service.hpp"
#include "excellent_calendar/application/recurring_reminder_query_service.hpp"
#include "excellent_calendar/application/reminder_recovery_workflow_service.hpp"
#include "excellent_calendar/application/reminder_service_v2.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::api {
namespace {

common::Error contract_error(std::string field, std::string reason) {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", std::move(field)}, {"reason", std::move(reason)}});
}

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

common::Result<picojson::object> parse_object(std::string_view request_json) {
  picojson::value value;
  const auto error = picojson::parse(value, std::string(request_json));
  if (!error.empty() || !value.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        contract_error("json", "request must be a valid JSON object"));
  }
  return common::Result<picojson::object>::success(value.get<picojson::object>());
}

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  return found == object.end() ? nullptr : &found->second;
}

common::Result<common::Unit> reject_unknown(
    const picojson::object& object,
    const std::set<std::string>& allowed,
    const std::string& parent) {
  for (const auto& [key, _] : object) {
    if (allowed.count(key) == 0U) {
      return common::Result<common::Unit>::failure(
          contract_error(parent + "." + key, "unknown field"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::string> require_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool nonempty = true) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<std::string>() ||
      (nonempty && value->get<std::string>().empty())) {
    return common::Result<std::string>::failure(
        contract_error(parent + "." + key, "string field is missing or invalid"));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<bool> require_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<bool>()) {
    return common::Result<bool>::failure(
        contract_error(parent + "." + key, "boolean field is missing or invalid"));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<int> require_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<double>() ||
      std::floor(value->get<double>()) != value->get<double>() ||
      value->get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<int>::failure(
        contract_error(parent + "." + key, "integer field is missing or invalid"));
  }
  return common::Result<int>::success(static_cast<int>(value->get<double>()));
}

common::Result<std::optional<std::string>> nullable_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    if (required) {
      return common::Result<std::optional<std::string>>::failure(
          contract_error(parent + "." + key, "required nullable field is missing"));
    }
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key, "field must be string or null"));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<std::optional<int>> nullable_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    if (required) {
      return common::Result<std::optional<int>>::failure(
          contract_error(parent + "." + key, "required nullable field is missing"));
    }
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || std::floor(value->get<double>()) != value->get<double>() ||
      value->get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        contract_error(parent + "." + key, "field must be integer or null"));
  }
  return common::Result<std::optional<int>>::success(
      static_cast<int>(value->get<double>()));
}

common::Result<std::optional<bool>> nullable_bool(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return required
               ? common::Result<std::optional<bool>>::failure(
                     contract_error(parent + "." + key, "required nullable field is missing"))
               : common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (value->is<picojson::null>()) {
    return common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (!value->is<bool>()) {
    return common::Result<std::optional<bool>>::failure(
        contract_error(parent + "." + key, "field must be boolean or null"));
  }
  return common::Result<std::optional<bool>>::success(value->get<bool>());
}

common::Result<std::vector<std::string>> string_array(
    const picojson::object& object,
    const std::string& key,
    const std::string& parent,
    bool required = false,
    bool require_unique = false) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return required
               ? common::Result<std::vector<std::string>>::failure(
                     contract_error(parent + "." + key, "required array is missing"))
               : common::Result<std::vector<std::string>>::success({});
  }
  if (!value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + "." + key, "field must be an array"));
  }
  std::vector<std::string> result;
  std::set<std::string> unique;
  for (const auto& item : value->get<picojson::array>()) {
    if (!item.is<std::string>() ||
        (require_unique && !unique.insert(item.get<std::string>()).second)) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(
              parent + "." + key,
              require_unique ? "array must contain unique strings"
                             : "array must contain strings"));
    }
    result.push_back(item.get<std::string>());
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

common::Result<std::vector<application::EventReminderDraftInput>>
parse_event_reminder_inputs(const picojson::value& value, const std::string& parent) {
  if (!value.is<picojson::array>()) {
    return common::Result<std::vector<application::EventReminderDraftInput>>::failure(
        contract_error(parent, "reminders must be an array"));
  }
  std::vector<application::EventReminderDraftInput> result;
  const auto& items = value.get<picojson::array>();
  result.reserve(items.size());
  for (std::size_t index = 0; index < items.size(); ++index) {
    const auto item_parent = parent + "[" + std::to_string(index) + "]";
    if (!items[index].is<picojson::object>()) {
      return common::Result<std::vector<application::EventReminderDraftInput>>::failure(
          contract_error(item_parent, "Reminder draft must be an object"));
    }
    const auto& object = items[index].get<picojson::object>();
    auto known = reject_unknown(
        object,
        {"target_type", "target_id", "remind_at", "advance_minutes", "methods",
         "message", "is_enabled", "source"},
        item_parent);
    if (!known.ok()) {
      return common::Result<std::vector<application::EventReminderDraftInput>>::failure(
          known.error());
    }
    auto target_type = require_string(object, "target_type", item_parent);
    auto target_id = nullable_string(object, "target_id", item_parent, false);
    auto remind_at = nullable_string(object, "remind_at", item_parent, false);
    auto advance = nullable_int(object, "advance_minutes", item_parent, false);
    auto methods = string_array(object, "methods", item_parent, true, true);
    auto message = nullable_string(object, "message", item_parent, false);
    auto enabled = require_bool(object, "is_enabled", item_parent);
    auto source = require_string(object, "source", item_parent);
    if (!target_type.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(target_type.error());
    if (!target_id.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(target_id.error());
    if (!remind_at.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(remind_at.error());
    if (!advance.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(advance.error());
    if (!methods.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(methods.error());
    if (!message.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(message.error());
    if (!enabled.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(enabled.error());
    if (!source.ok()) return common::Result<std::vector<application::EventReminderDraftInput>>::failure(source.error());
    result.push_back(application::EventReminderDraftInput{
        target_type.value(), target_id.value(), remind_at.value(), advance.value(),
        methods.value(), message.value(), enabled.value(), source.value(),
        field(object, "remind_at") != nullptr,
        field(object, "advance_minutes") != nullptr,
        field(object, "message") != nullptr});
  }
  return common::Result<std::vector<application::EventReminderDraftInput>>::success(
      std::move(result));
}

common::Result<domain::EventRecurrenceRuleInput> parse_recurrence(
    const picojson::value& value,
    const std::string& parent) {
  if (!value.is<picojson::object>()) {
    return common::Result<domain::EventRecurrenceRuleInput>::failure(
        contract_error(parent, "recurrence must be an object"));
  }
  const auto& object = value.get<picojson::object>();
  auto known = reject_unknown(
      object, {"frequency", "interval", "end_at", "count"}, parent);
  if (!known.ok()) {
    return common::Result<domain::EventRecurrenceRuleInput>::failure(known.error());
  }
  auto frequency = require_string(object, "frequency", parent);
  auto interval = require_int(object, "interval", parent);
  auto end_at = nullable_string(object, "end_at", parent, true);
  auto count = nullable_int(object, "count", parent, true);
  if (!frequency.ok()) return common::Result<domain::EventRecurrenceRuleInput>::failure(frequency.error());
  if (!interval.ok()) return common::Result<domain::EventRecurrenceRuleInput>::failure(interval.error());
  if (!end_at.ok()) return common::Result<domain::EventRecurrenceRuleInput>::failure(end_at.error());
  if (!count.ok()) return common::Result<domain::EventRecurrenceRuleInput>::failure(count.error());
  if (!domain::is_known_recurrence_frequency(frequency.value())) {
    return common::Result<domain::EventRecurrenceRuleInput>::failure(
        contract_error(parent + ".frequency", "unknown recurrence frequency"));
  }
  return common::Result<domain::EventRecurrenceRuleInput>::success(
      {frequency.value(), interval.value(), end_at.value(), count.value()});
}

common::Result<std::vector<domain::RecurringReminderDraft>> parse_recurring_drafts(
    const picojson::value& value,
    const std::string& parent,
    const std::optional<std::string>& expected_target_id = std::nullopt) {
  if (!value.is<picojson::array>()) {
    return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
        contract_error(parent, "reminders must be an array"));
  }
  std::vector<domain::RecurringReminderDraft> result;
  const auto& values = value.get<picojson::array>();
  result.reserve(values.size());
  for (std::size_t index = 0; index < values.size(); ++index) {
    const auto item_parent = parent + "[" + std::to_string(index) + "]";
    if (!values[index].is<picojson::object>()) {
      return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
          contract_error(item_parent, "Reminder template must be an object"));
    }
    const auto& object = values[index].get<picojson::object>();
    auto known = reject_unknown(
        object,
        {"target_type", "target_id", "advance_minutes", "methods", "message",
         "is_enabled", "source"},
        item_parent);
    if (!known.ok()) {
      return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(known.error());
    }
    auto target_type = require_string(object, "target_type", item_parent);
    auto target_id = nullable_string(object, "target_id", item_parent, false);
    auto advance = require_int(object, "advance_minutes", item_parent);
    auto message = nullable_string(object, "message", item_parent, true);
    auto enabled = require_bool(object, "is_enabled", item_parent);
    auto source = require_string(object, "source", item_parent);
    if (!target_type.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(target_type.error());
    if (!target_id.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(target_id.error());
    if (!advance.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(advance.error());
    if (!message.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(message.error());
    if (!enabled.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(enabled.error());
    if (!source.ok()) return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(source.error());
    const auto* methods = field(object, "methods");
    if (target_type.value() != domain::kReminderTargetEvent || advance.value() < 0 ||
        !enabled.value() || !domain::is_valid_reminder_source(source.value()) ||
        methods == nullptr || !methods->is<picojson::array>() ||
        methods->get<picojson::array>().size() != 1U ||
        !methods->get<picojson::array>().front().is<std::string>() ||
        methods->get<picojson::array>().front().get<std::string>() !=
            domain::kReminderMethodPopup ||
        (target_id.value().has_value() &&
         (!expected_target_id.has_value() || target_id.value() != expected_target_id))) {
      return common::Result<std::vector<domain::RecurringReminderDraft>>::failure(
          contract_error(item_parent, "recurring Reminder template is invalid"));
    }
    result.push_back({advance.value(), {"popup"}, message.value(), true, source.value()});
  }
  return common::Result<std::vector<domain::RecurringReminderDraft>>::success(std::move(result));
}

common::Result<domain::Event> parse_event_fields(
    const picojson::object& object,
    const std::string& parent) {
  auto title = require_string(object, "title", parent, false);
  auto start_at = nullable_string(object, "start_at", parent, true);
  auto end_at = nullable_string(object, "end_at", parent, true);
  auto start_date = nullable_string(object, "start_date", parent, true);
  auto end_date = nullable_string(object, "end_date", parent, true);
  auto all_day = require_bool(object, "is_all_day", parent);
  auto timezone = require_string(object, "timezone", parent);
  auto source = require_string(object, "source", parent);
  if (!title.ok()) return common::Result<domain::Event>::failure(title.error());
  if (!start_at.ok()) return common::Result<domain::Event>::failure(start_at.error());
  if (!end_at.ok()) return common::Result<domain::Event>::failure(end_at.error());
  if (!start_date.ok()) return common::Result<domain::Event>::failure(start_date.error());
  if (!end_date.ok()) return common::Result<domain::Event>::failure(end_date.error());
  if (!all_day.ok()) return common::Result<domain::Event>::failure(all_day.error());
  if (!timezone.ok()) return common::Result<domain::Event>::failure(timezone.error());
  if (!source.ok()) return common::Result<domain::Event>::failure(source.error());
  auto content = nullable_string(object, "content", parent, false);
  auto category = nullable_string(object, "category_id", parent, false);
  auto importance = nullable_string(object, "importance", parent, false);
  auto location = nullable_string(object, "location", parent, false);
  if (!content.ok()) return common::Result<domain::Event>::failure(content.error());
  if (!category.ok()) return common::Result<domain::Event>::failure(category.error());
  if (!importance.ok()) return common::Result<domain::Event>::failure(importance.error());
  if (!location.ok()) return common::Result<domain::Event>::failure(location.error());
  const bool timed_shape = !all_day.value() && start_at.value().has_value() &&
                           end_at.value().has_value() && !start_date.value().has_value() &&
                           !end_date.value().has_value();
  const bool all_day_shape = all_day.value() && !start_at.value().has_value() &&
                             !end_at.value().has_value() && start_date.value().has_value() &&
                             end_date.value().has_value();
  if ((!timed_shape && !all_day_shape) ||
      (timed_shape &&
       (!common::is_iso8601_utc_datetime(*start_at.value()) ||
        !common::is_iso8601_utc_datetime(*end_at.value()))) ||
      (all_day_shape &&
       (!domain::parse_local_date(*start_date.value()).ok() ||
        !domain::parse_local_date(*end_date.value()).ok())) ||
      !domain::is_valid_create_event_source(source.value()) ||
      (importance.value().has_value() && !domain::is_valid_importance(*importance.value()))) {
    return common::Result<domain::Event>::failure(
        contract_error(parent, "Event fields or time shape are invalid"));
  }
  domain::Event event;
  event.title = title.value();
  event.content = content.value();
  event.start_at = start_at.value().value_or("");
  event.end_at = end_at.value().value_or("");
  event.start_date = start_date.value();
  event.end_date = end_date.value();
  event.is_all_day = all_day.value();
  event.category_id = category.value();
  event.importance = importance.value();
  event.location = location.value();
  event.timezone = timezone.value();
  event.source = source.value();
  return common::Result<domain::Event>::success(std::move(event));
}

common::Result<application::CreateEventV2Command> parse_create(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::CreateEventV2Command>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"title", "content", "start_at", "end_at", "start_date", "end_date",
       "is_all_day", "category_id", "importance", "location", "timezone", "source",
       "recurrence", "reminders"},
      "CreateEventRequest");
  if (!known.ok()) return common::Result<application::CreateEventV2Command>::failure(known.error());
  auto event = parse_event_fields(object, "CreateEventRequest");
  if (!event.ok()) return common::Result<application::CreateEventV2Command>::failure(event.error());
  const auto* recurrence_value = field(object, "recurrence");
  std::optional<domain::EventRecurrenceRuleInput> recurrence;
  if (recurrence_value != nullptr && !recurrence_value->is<picojson::null>()) {
    auto parsed_recurrence = parse_recurrence(
        *recurrence_value, "CreateEventRequest.recurrence");
    if (!parsed_recurrence.ok()) {
      return common::Result<application::CreateEventV2Command>::failure(
          parsed_recurrence.error());
    }
    recurrence = parsed_recurrence.value();
  }
  std::vector<application::EventReminderDraftInput> reminders;
  if (const auto* value = field(object, "reminders"); value != nullptr) {
    auto parsed_reminders = parse_event_reminder_inputs(
        *value, "CreateEventRequest.reminders");
    if (!parsed_reminders.ok()) {
      return common::Result<application::CreateEventV2Command>::failure(
          parsed_reminders.error());
    }
    reminders = std::move(parsed_reminders.value());
  }
  return common::Result<application::CreateEventV2Command>::success(
      {event.value(), recurrence, std::move(reminders)});
}

common::Result<application::UpdateRecurringEventSeriesCommand> parse_update(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"id", "expected_recurrence_revision", "title", "content", "start_at", "end_at",
       "start_date", "end_date", "is_all_day", "category_id", "importance", "location",
       "timezone", "source", "recurrence", "reminders"},
      "UpdateEventRequest");
  if (!known.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(known.error());
  auto id = require_string(object, "id", "UpdateEventRequest");
  if (!id.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(id.error());
  if (!common::is_uuid(id.value())) {
    return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
        contract_error("UpdateEventRequest.id", "Event identity is invalid"));
  }
  application::UpdateRecurringEventSeriesCommand command;
  command.event_id = id.value();
  if (field(object, "expected_recurrence_revision") != nullptr) {
    auto revision = nullable_int(
        object, "expected_recurrence_revision", "UpdateEventRequest", true);
    if (!revision.ok()) {
      return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
          revision.error());
    }
    command.expected_recurrence_revision = {true, revision.value()};
  }
  if (field(object, "title") != nullptr) {
    auto value = require_string(object, "title", "UpdateEventRequest");
    if (!value.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(value.error());
    command.title = {true, value.value()};
  }
  const auto parse_nullable_patch = [&](
                                        const std::string& key,
                                        application::FieldPatch<std::optional<std::string>>& target)
      -> common::Result<common::Unit> {
    if (field(object, key) == nullptr) return common::Result<common::Unit>::success(common::Unit{});
    auto value = nullable_string(object, key, "UpdateEventRequest", true);
    if (!value.ok()) return common::Result<common::Unit>::failure(value.error());
    target = {true, value.value()};
    return common::Result<common::Unit>::success(common::Unit{});
  };
  for (auto pair : {
           std::pair<std::string,
                     application::FieldPatch<std::optional<std::string>>*>(
               "content", &command.content),
           {"category_id", &command.category_id},
           {"importance", &command.importance},
           {"location", &command.location}}) {
    auto assigned = parse_nullable_patch(pair.first, *pair.second);
    if (!assigned.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(assigned.error());
  }
  if (command.importance.supplied && command.importance.value.has_value() &&
      !domain::is_valid_importance(*command.importance.value)) {
    return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
        contract_error("UpdateEventRequest.importance", "importance is invalid"));
  }
  const std::set<std::string> time_fields{
      "start_at", "end_at", "start_date", "end_date", "is_all_day", "timezone"};
  bool has_time_field = false;
  for (const auto& key : time_fields) has_time_field = has_time_field || field(object, key) != nullptr;
  if (has_time_field) {
    for (const auto& key : time_fields) {
      if (field(object, key) == nullptr) {
        return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
            contract_error("UpdateEventRequest." + key, "atomic time group is incomplete"));
      }
    }
    auto start_at = nullable_string(object, "start_at", "UpdateEventRequest", true);
    auto end_at = nullable_string(object, "end_at", "UpdateEventRequest", true);
    auto start_date = nullable_string(object, "start_date", "UpdateEventRequest", true);
    auto end_date = nullable_string(object, "end_date", "UpdateEventRequest", true);
    auto all_day = require_bool(object, "is_all_day", "UpdateEventRequest");
    auto timezone = require_string(object, "timezone", "UpdateEventRequest");
    if (!start_at.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(start_at.error());
    if (!end_at.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(end_at.error());
    if (!start_date.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(start_date.error());
    if (!end_date.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(end_date.error());
    if (!all_day.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(all_day.error());
    if (!timezone.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(timezone.error());
    const bool timed_shape = !all_day.value() && start_at.value().has_value() &&
                             end_at.value().has_value() && !start_date.value().has_value() &&
                             !end_date.value().has_value();
    const bool all_day_shape = all_day.value() && !start_at.value().has_value() &&
                               !end_at.value().has_value() && start_date.value().has_value() &&
                               end_date.value().has_value();
    if ((!timed_shape && !all_day_shape) ||
        (timed_shape &&
         (!common::is_iso8601_utc_datetime(*start_at.value()) ||
          !common::is_iso8601_utc_datetime(*end_at.value()))) ||
        (all_day_shape &&
         (!domain::parse_local_date(*start_date.value()).ok() ||
          !domain::parse_local_date(*end_date.value()).ok()))) {
      return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
          contract_error("UpdateEventRequest", "Event time shape is invalid"));
    }
    command.time = {
        true,
        application::EventTimeReplacement{
            start_at.value(), end_at.value(), start_date.value(), end_date.value(),
            all_day.value(), timezone.value()}};
  }
  if (field(object, "source") != nullptr) {
    auto source = require_string(object, "source", "UpdateEventRequest");
    if (!source.ok()) return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(source.error());
    if (!domain::is_valid_create_event_source(source.value())) {
      return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(
          contract_error("UpdateEventRequest.source", "source is invalid"));
    }
    command.source = {true, source.value()};
  }
  if (const auto* value = field(object, "recurrence"); value != nullptr) {
    auto parsed_recurrence = parse_recurrence(*value, "UpdateEventRequest.recurrence");
    if (!parsed_recurrence.ok()) {
      return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(parsed_recurrence.error());
    }
    command.recurrence = {true, parsed_recurrence.value()};
  }
  if (const auto* value = field(object, "reminders"); value != nullptr) {
    auto parsed_reminders = parse_event_reminder_inputs(
        *value, "UpdateEventRequest.reminders");
    if (!parsed_reminders.ok()) {
      return common::Result<application::UpdateRecurringEventSeriesCommand>::failure(parsed_reminders.error());
    }
    command.reminders = {true, std::move(parsed_reminders.value())};
  }
  return common::Result<application::UpdateRecurringEventSeriesCommand>::success(
      std::move(command));
}

common::Result<application::OccurrenceOperationCommand> parse_occurrence_operation(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"event_id", "recurrence_revision", "occurrence_key", "occurrence_start_at",
       "occurrence_start_date"},
      "EventOccurrenceOperationRequest");
  if (!known.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(known.error());
  auto event_id = require_string(object, "event_id", "EventOccurrenceOperationRequest");
  auto revision = require_int(object, "recurrence_revision", "EventOccurrenceOperationRequest");
  auto key = require_string(object, "occurrence_key", "EventOccurrenceOperationRequest");
  auto start_at = nullable_string(object, "occurrence_start_at", "EventOccurrenceOperationRequest", true);
  auto start_date = nullable_string(object, "occurrence_start_date", "EventOccurrenceOperationRequest", true);
  if (!event_id.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(event_id.error());
  if (!revision.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(revision.error());
  if (!key.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(key.error());
  if (!start_at.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(start_at.error());
  if (!start_date.ok()) return common::Result<application::OccurrenceOperationCommand>::failure(start_date.error());
  if (!common::is_uuid(event_id.value()) || !common::is_uuid(key.value()) || revision.value() < 1 ||
      start_at.value().has_value() == start_date.value().has_value() ||
      (start_at.value().has_value() && !common::is_iso8601_utc_datetime(*start_at.value())) ||
      (start_date.value().has_value() && !domain::parse_local_date(*start_date.value()).ok())) {
    return common::Result<application::OccurrenceOperationCommand>::failure(
        contract_error("EventOccurrenceOperationRequest", "occurrence identity is invalid"));
  }
  return common::Result<application::OccurrenceOperationCommand>::success(
      {event_id.value(), revision.value(), key.value(), start_at.value(), start_date.value()});
}

common::Result<application::SeriesOperationCommand> parse_series_operation(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::SeriesOperationCommand>::failure(parsed.error());
  auto known = reject_unknown(
      parsed.value(), {"event_id", "recurrence_revision"}, "EventSeriesOperationRequest");
  if (!known.ok()) return common::Result<application::SeriesOperationCommand>::failure(known.error());
  auto id = require_string(parsed.value(), "event_id", "EventSeriesOperationRequest");
  auto revision = require_int(parsed.value(), "recurrence_revision", "EventSeriesOperationRequest");
  if (!id.ok()) return common::Result<application::SeriesOperationCommand>::failure(id.error());
  if (!revision.ok()) return common::Result<application::SeriesOperationCommand>::failure(revision.error());
  if (!common::is_uuid(id.value()) || revision.value() < 1) {
    return common::Result<application::SeriesOperationCommand>::failure(
        contract_error("EventSeriesOperationRequest", "series identity is invalid"));
  }
  return common::Result<application::SeriesOperationCommand>::success(
      {id.value(), revision.value()});
}

template <typename Callback>
std::string respond_v2(Callback callback) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto result = callback();
    return result.ok()
               ? contract::native_success_json_v2(result.value(), request_id)
               : contract::native_failure_json_v2(result.error(), request_id);
  } catch (const std::exception& error) {
    return contract::native_failure_json_v2(internal_error(error.what()), request_id);
  } catch (...) {
    return contract::native_failure_json_v2(internal_error("unknown exception"), request_id);
  }
}

}  // namespace

namespace {

common::Result<application::DeleteEventV2Command> parse_delete(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::DeleteEventV2Command>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"id", "delete_mode", "recurrence_delete_scope", "expected_recurrence_revision", "reason"},
      "DeleteEventRequest");
  if (!known.ok()) return common::Result<application::DeleteEventV2Command>::failure(known.error());
  auto id = require_string(object, "id", "DeleteEventRequest");
  auto mode = require_string(object, "delete_mode", "DeleteEventRequest");
  auto scope = nullable_string(object, "recurrence_delete_scope", "DeleteEventRequest", true);
  auto revision = nullable_int(object, "expected_recurrence_revision", "DeleteEventRequest", true);
  auto reason = nullable_string(object, "reason", "DeleteEventRequest", false);
  if (!id.ok()) return common::Result<application::DeleteEventV2Command>::failure(id.error());
  if (!mode.ok()) return common::Result<application::DeleteEventV2Command>::failure(mode.error());
  if (!scope.ok()) return common::Result<application::DeleteEventV2Command>::failure(scope.error());
  if (!revision.ok()) return common::Result<application::DeleteEventV2Command>::failure(revision.error());
  if (!reason.ok()) return common::Result<application::DeleteEventV2Command>::failure(reason.error());
  if (!common::is_uuid(id.value()) ||
      (mode.value() != "soft" && mode.value() != "hard") ||
      (scope.value().has_value() && *scope.value() != "all_occurrences") ||
      (revision.value().has_value() && *revision.value() < 1)) {
    return common::Result<application::DeleteEventV2Command>::failure(
        contract_error("DeleteEventRequest", "Event delete identity is invalid"));
  }
  return common::Result<application::DeleteEventV2Command>::success(
      {id.value(), mode.value(), scope.value(), revision.value(), reason.value()});
}

common::Result<application::ListEventOccurrencesCommand> parse_occurrence_list(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"event_id", "recurrence_revision", "is_all_day", "range_start_at", "range_end_at",
       "range_start_date", "range_end_date", "cursor", "limit"},
      "ListEventOccurrencesRequest");
  if (!known.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(known.error());
  auto event_id = require_string(object, "event_id", "ListEventOccurrencesRequest");
  auto revision = require_int(object, "recurrence_revision", "ListEventOccurrencesRequest");
  auto all_day = require_bool(object, "is_all_day", "ListEventOccurrencesRequest");
  auto start_at = nullable_string(object, "range_start_at", "ListEventOccurrencesRequest", true);
  auto end_at = nullable_string(object, "range_end_at", "ListEventOccurrencesRequest", true);
  auto start_date = nullable_string(object, "range_start_date", "ListEventOccurrencesRequest", true);
  auto end_date = nullable_string(object, "range_end_date", "ListEventOccurrencesRequest", true);
  auto cursor = nullable_string(object, "cursor", "ListEventOccurrencesRequest", true);
  auto limit = require_int(object, "limit", "ListEventOccurrencesRequest");
  if (!event_id.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(event_id.error());
  if (!revision.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(revision.error());
  if (!all_day.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(all_day.error());
  if (!start_at.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(start_at.error());
  if (!end_at.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(end_at.error());
  if (!start_date.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(start_date.error());
  if (!end_date.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(end_date.error());
  if (!cursor.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(cursor.error());
  if (!limit.ok()) return common::Result<application::ListEventOccurrencesCommand>::failure(limit.error());
  return common::Result<application::ListEventOccurrencesCommand>::success(
      {event_id.value(), revision.value(), all_day.value(), start_at.value(), end_at.value(),
       start_date.value(), end_date.value(), cursor.value(), limit.value()});
}

common::Result<application::ListRecurringSchedulableRemindersCommand> parse_schedulable(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"from_at", "to_at", "cursor", "limit", "include_scheduled", "supported_methods"},
      "ListSchedulableRemindersRequest");
  if (!known.ok()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(known.error());
  }
  application::ListRecurringSchedulableRemindersCommand command;
  auto from = nullable_string(object, "from_at", "ListSchedulableRemindersRequest", false);
  auto to = nullable_string(object, "to_at", "ListSchedulableRemindersRequest", false);
  if (!from.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(from.error());
  if (!to.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(to.error());
  command.from_at = from.value();
  command.to_at = to.value();
  if (const auto* value = field(object, "limit"); value != nullptr) {
    auto limit = require_int(object, "limit", "ListSchedulableRemindersRequest");
    if (!limit.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(limit.error());
    command.limit = limit.value();
  }
  if (const auto* value = field(object, "include_scheduled"); value != nullptr) {
    auto include = require_bool(object, "include_scheduled", "ListSchedulableRemindersRequest");
    if (!include.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(include.error());
    command.include_scheduled = include.value();
  }
  const auto* methods = field(object, "supported_methods");
  if (methods == nullptr || !methods->is<picojson::array>()) {
    return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
        contract_error("ListSchedulableRemindersRequest.supported_methods", "array is required"));
  }
  for (const auto& value : methods->get<picojson::array>()) {
    if (!value.is<std::string>()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
          contract_error("ListSchedulableRemindersRequest.supported_methods", "items must be strings"));
    }
    command.supported_methods.push_back(value.get<std::string>());
  }
  if (const auto* cursor = field(object, "cursor"); cursor != nullptr && !cursor->is<picojson::null>()) {
    if (!cursor->is<picojson::object>()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(
          contract_error("ListSchedulableRemindersRequest.cursor", "cursor must be object or null"));
    }
    auto cursor_known = reject_unknown(
        cursor->get<picojson::object>(), {"remind_at", "reminder_id"},
        "ListSchedulableRemindersRequest.cursor");
    if (!cursor_known.ok()) {
      return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(cursor_known.error());
    }
    auto remind_at = require_string(
        cursor->get<picojson::object>(), "remind_at", "ListSchedulableRemindersRequest.cursor");
    auto reminder_id = require_string(
        cursor->get<picojson::object>(), "reminder_id", "ListSchedulableRemindersRequest.cursor");
    if (!remind_at.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(remind_at.error());
    if (!reminder_id.ok()) return common::Result<application::ListRecurringSchedulableRemindersCommand>::failure(reminder_id.error());
    command.cursor_remind_at = remind_at.value();
    command.cursor_reminder_id = reminder_id.value();
  }
  return common::Result<application::ListRecurringSchedulableRemindersCommand>::success(
      std::move(command));
}

common::Result<application::PrepareDeliveryCommand> parse_prepare(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object, {"kind", "reminder_id", "recovery_batch_id", "method", "expected_remind_at"},
      "PrepareDeliveryRequest");
  if (!known.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(known.error());
  auto kind = require_string(object, "kind", "PrepareDeliveryRequest");
  auto reminder_id = nullable_string(object, "reminder_id", "PrepareDeliveryRequest", true);
  auto batch_id = nullable_string(object, "recovery_batch_id", "PrepareDeliveryRequest", true);
  auto method = require_string(object, "method", "PrepareDeliveryRequest");
  auto remind_at = nullable_string(object, "expected_remind_at", "PrepareDeliveryRequest", true);
  if (!kind.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(kind.error());
  if (!reminder_id.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(reminder_id.error());
  if (!batch_id.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(batch_id.error());
  if (!method.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(method.error());
  if (!remind_at.ok()) return common::Result<application::PrepareDeliveryCommand>::failure(remind_at.error());
  return common::Result<application::PrepareDeliveryCommand>::success(
      {kind.value(), reminder_id.value(), batch_id.value(), method.value(), remind_at.value()});
}

common::Result<application::FinalizeDeliveryCommand> parse_finalize(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(parsed.error());
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object, {"delivery_attempt_id", "outcome", "failure_class", "error_code"},
      "FinalizeDeliveryRequest");
  if (!known.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(known.error());
  auto id = require_string(object, "delivery_attempt_id", "FinalizeDeliveryRequest");
  auto outcome = require_string(object, "outcome", "FinalizeDeliveryRequest");
  auto failure = nullable_string(object, "failure_class", "FinalizeDeliveryRequest", true);
  auto error = nullable_string(object, "error_code", "FinalizeDeliveryRequest", true);
  if (!id.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(id.error());
  if (!outcome.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(outcome.error());
  if (!failure.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(failure.error());
  if (!error.ok()) return common::Result<application::FinalizeDeliveryCommand>::failure(error.error());
  return common::Result<application::FinalizeDeliveryCommand>::success(
      {id.value(), outcome.value(), failure.value(), error.value()});
}

common::Result<application::EventSearchQueryV2> parse_event_search(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::EventSearchQueryV2>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"keyword", "start_at_from", "start_at_to", "start_date_from", "start_date_to",
       "status", "category_ids", "importance", "location", "has_recurrence", "source",
       "include_deleted", "pagination", "sort_by", "sort_direction"},
      "SearchEventRequest");
  if (!known.ok()) {
    return common::Result<application::EventSearchQueryV2>::failure(known.error());
  }
  application::EventSearchQueryV2 query;
  auto keyword = nullable_string(object, "keyword", "SearchEventRequest", false);
  auto start_at_from = nullable_string(object, "start_at_from", "SearchEventRequest", false);
  auto start_at_to = nullable_string(object, "start_at_to", "SearchEventRequest", false);
  auto start_date_from = nullable_string(object, "start_date_from", "SearchEventRequest", false);
  auto start_date_to = nullable_string(object, "start_date_to", "SearchEventRequest", false);
  auto location = nullable_string(object, "location", "SearchEventRequest", false);
  auto recurrence = nullable_bool(object, "has_recurrence", "SearchEventRequest", false);
  auto status = string_array(object, "status", "SearchEventRequest");
  auto categories = string_array(object, "category_ids", "SearchEventRequest");
  auto importance = string_array(object, "importance", "SearchEventRequest");
  auto source = string_array(object, "source", "SearchEventRequest");
  if (!keyword.ok()) return common::Result<application::EventSearchQueryV2>::failure(keyword.error());
  if (!start_at_from.ok()) return common::Result<application::EventSearchQueryV2>::failure(start_at_from.error());
  if (!start_at_to.ok()) return common::Result<application::EventSearchQueryV2>::failure(start_at_to.error());
  if (!start_date_from.ok()) return common::Result<application::EventSearchQueryV2>::failure(start_date_from.error());
  if (!start_date_to.ok()) return common::Result<application::EventSearchQueryV2>::failure(start_date_to.error());
  if (!location.ok()) return common::Result<application::EventSearchQueryV2>::failure(location.error());
  if (!recurrence.ok()) return common::Result<application::EventSearchQueryV2>::failure(recurrence.error());
  if (!status.ok()) return common::Result<application::EventSearchQueryV2>::failure(status.error());
  if (!categories.ok()) return common::Result<application::EventSearchQueryV2>::failure(categories.error());
  if (!importance.ok()) return common::Result<application::EventSearchQueryV2>::failure(importance.error());
  if (!source.ok()) return common::Result<application::EventSearchQueryV2>::failure(source.error());
  query.keyword = keyword.value();
  query.start_at_from = start_at_from.value();
  query.start_at_to = start_at_to.value();
  query.start_date_from = start_date_from.value();
  query.start_date_to = start_date_to.value();
  query.location = location.value();
  query.has_recurrence = recurrence.value();
  query.status = std::move(status.value());
  query.category_ids = std::move(categories.value());
  query.importance = std::move(importance.value());
  query.source = std::move(source.value());
  if (field(object, "include_deleted") != nullptr) {
    auto value = require_bool(object, "include_deleted", "SearchEventRequest");
    if (!value.ok()) return common::Result<application::EventSearchQueryV2>::failure(value.error());
    query.include_deleted = value.value();
  }
  if (const auto* pagination = field(object, "pagination"); pagination != nullptr) {
    if (!pagination->is<picojson::object>()) {
      return common::Result<application::EventSearchQueryV2>::failure(
          contract_error("SearchEventRequest.pagination", "pagination must be an object"));
    }
    const auto& value = pagination->get<picojson::object>();
    auto pagination_known = reject_unknown(
        value, {"page", "page_size", "cursor", "sort_by", "sort_direction"},
        "SearchEventRequest.pagination");
    if (!pagination_known.ok()) {
      return common::Result<application::EventSearchQueryV2>::failure(pagination_known.error());
    }
    if (field(value, "page") != nullptr && !field(value, "page")->is<picojson::null>()) {
      auto page = require_int(value, "page", "SearchEventRequest.pagination");
      if (!page.ok()) return common::Result<application::EventSearchQueryV2>::failure(page.error());
      query.page = page.value();
    }
    if (field(value, "page_size") != nullptr && !field(value, "page_size")->is<picojson::null>()) {
      auto size = require_int(value, "page_size", "SearchEventRequest.pagination");
      if (!size.ok()) return common::Result<application::EventSearchQueryV2>::failure(size.error());
      query.page_size = size.value();
    }
    auto cursor = nullable_string(value, "cursor", "SearchEventRequest.pagination", false);
    auto nested_sort = nullable_string(
        value, "sort_by", "SearchEventRequest.pagination", false);
    auto nested_direction = nullable_string(
        value, "sort_direction", "SearchEventRequest.pagination", false);
    if (!cursor.ok()) return common::Result<application::EventSearchQueryV2>::failure(cursor.error());
    if (!nested_sort.ok()) return common::Result<application::EventSearchQueryV2>::failure(nested_sort.error());
    if (!nested_direction.ok()) return common::Result<application::EventSearchQueryV2>::failure(nested_direction.error());
    query.cursor = cursor.value();
    if (nested_sort.value().has_value()) query.sort_by = *nested_sort.value();
    if (nested_direction.value().has_value()) {
      query.sort_direction = *nested_direction.value();
    }
  }
  auto sort_by = nullable_string(object, "sort_by", "SearchEventRequest", false);
  auto direction = nullable_string(object, "sort_direction", "SearchEventRequest", false);
  if (!sort_by.ok()) return common::Result<application::EventSearchQueryV2>::failure(sort_by.error());
  if (!direction.ok()) return common::Result<application::EventSearchQueryV2>::failure(direction.error());
  if (sort_by.value().has_value()) query.sort_by = *sort_by.value();
  if (direction.value().has_value()) query.sort_direction = *direction.value();
  return common::Result<application::EventSearchQueryV2>::success(std::move(query));
}

common::Result<application::CreateReminderV2Command> parse_create_reminder(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"target_type", "target_id", "remind_at", "advance_minutes", "methods",
       "message", "is_enabled", "source"},
      "CreateReminderRequest");
  if (!known.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        known.error());
  }
  auto target_type = require_string(object, "target_type", "CreateReminderRequest");
  auto target_id = require_string(object, "target_id", "CreateReminderRequest");
  auto remind_at = nullable_string(
      object, "remind_at", "CreateReminderRequest", false);
  auto advance = nullable_int(
      object, "advance_minutes", "CreateReminderRequest", false);
  auto methods = string_array(
      object, "methods", "CreateReminderRequest", true, true);
  auto message = nullable_string(
      object, "message", "CreateReminderRequest", false);
  auto enabled = require_bool(object, "is_enabled", "CreateReminderRequest");
  auto source = require_string(object, "source", "CreateReminderRequest");
  if (!target_type.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        target_type.error());
  }
  if (!target_id.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        target_id.error());
  }
  if (!remind_at.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        remind_at.error());
  }
  if (!advance.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        advance.error());
  }
  if (!methods.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        methods.error());
  }
  if (!message.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        message.error());
  }
  if (!enabled.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        enabled.error());
  }
  if (!source.ok()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        source.error());
  }
  if (remind_at.value().has_value() == advance.value().has_value()) {
    return common::Result<application::CreateReminderV2Command>::failure(
        contract_error(
            "CreateReminderRequest", "exactly one reminder time mode is required"));
  }
  return common::Result<application::CreateReminderV2Command>::success(
      {target_type.value(), target_id.value(), remind_at.value(), advance.value(),
       std::move(methods.value()), message.value(), enabled.value(), source.value()});
}

common::Result<application::UpdateReminderV2Command> parse_update_reminder(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"reminder_id", "target_type", "target_id", "remind_at", "advance_minutes",
       "methods", "message", "source"},
      "UpdateReminderRequest");
  if (!known.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        known.error());
  }
  auto reminder_id = require_string(
      object, "reminder_id", "UpdateReminderRequest");
  if (!reminder_id.ok()) {
    return common::Result<application::UpdateReminderV2Command>::failure(
        reminder_id.error());
  }
  application::UpdateReminderV2Command command;
  command.reminder_id = reminder_id.value();
  if (field(object, "target_type") != nullptr) {
    auto value = require_string(object, "target_type", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.target_type = {true, value.value()};
  }
  if (field(object, "target_id") != nullptr) {
    auto value = require_string(object, "target_id", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.target_id = {true, value.value()};
  }
  if (field(object, "remind_at") != nullptr) {
    auto value = nullable_string(
        object, "remind_at", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.remind_at = {true, value.value()};
  }
  if (field(object, "advance_minutes") != nullptr) {
    auto value = nullable_int(
        object, "advance_minutes", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.advance_minutes = {true, value.value()};
  }
  if (field(object, "methods") != nullptr) {
    auto value = string_array(
        object, "methods", "UpdateReminderRequest", true, true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.methods = {true, std::move(value.value())};
  }
  if (field(object, "message") != nullptr) {
    auto value = nullable_string(
        object, "message", "UpdateReminderRequest", true);
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.message = {true, value.value()};
  }
  if (field(object, "source") != nullptr) {
    auto value = require_string(object, "source", "UpdateReminderRequest");
    if (!value.ok()) {
      return common::Result<application::UpdateReminderV2Command>::failure(
          value.error());
    }
    command.source = {true, value.value()};
  }
  return common::Result<application::UpdateReminderV2Command>::success(
      std::move(command));
}

common::Result<application::ReminderIdV2Command> parse_reminder_id(
    std::string_view request_json,
    const std::string& parent) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(parsed.error());
  }
  auto known = reject_unknown(parsed.value(), {"reminder_id"}, parent);
  if (!known.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(known.error());
  }
  auto reminder_id = require_string(parsed.value(), "reminder_id", parent);
  if (!reminder_id.ok()) {
    return common::Result<application::ReminderIdV2Command>::failure(
        reminder_id.error());
  }
  return common::Result<application::ReminderIdV2Command>::success(
      {reminder_id.value()});
}

common::Result<application::ReminderListQueryV2> parse_reminder_list(
    std::string_view request_json) {
  auto parsed = parse_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::ReminderListQueryV2>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  auto known = reject_unknown(
      object,
      {"target_type", "target_id", "recurrence_revision", "occurrence_key",
       "remind_at_from", "remind_at_to", "methods", "status", "is_enabled",
       "include_deleted", "pagination", "sort_by", "sort_direction"},
      "ListRemindersRequest");
  if (!known.ok()) {
    return common::Result<application::ReminderListQueryV2>::failure(known.error());
  }
  application::ReminderListQueryV2 query;
  auto target_type = nullable_string(
      object, "target_type", "ListRemindersRequest", false);
  auto target_id = nullable_string(
      object, "target_id", "ListRemindersRequest", false);
  auto revision = nullable_int(
      object, "recurrence_revision", "ListRemindersRequest", false);
  auto occurrence_key = nullable_string(
      object, "occurrence_key", "ListRemindersRequest", false);
  auto remind_at_from = nullable_string(
      object, "remind_at_from", "ListRemindersRequest", false);
  auto remind_at_to = nullable_string(
      object, "remind_at_to", "ListRemindersRequest", false);
  auto methods = string_array(object, "methods", "ListRemindersRequest");
  auto status = string_array(object, "status", "ListRemindersRequest");
  auto enabled = nullable_bool(
      object, "is_enabled", "ListRemindersRequest", false);
  if (!target_type.ok()) return common::Result<application::ReminderListQueryV2>::failure(target_type.error());
  if (!target_id.ok()) return common::Result<application::ReminderListQueryV2>::failure(target_id.error());
  if (!revision.ok()) return common::Result<application::ReminderListQueryV2>::failure(revision.error());
  if (!occurrence_key.ok()) return common::Result<application::ReminderListQueryV2>::failure(occurrence_key.error());
  if (!remind_at_from.ok()) return common::Result<application::ReminderListQueryV2>::failure(remind_at_from.error());
  if (!remind_at_to.ok()) return common::Result<application::ReminderListQueryV2>::failure(remind_at_to.error());
  if (!methods.ok()) return common::Result<application::ReminderListQueryV2>::failure(methods.error());
  if (!status.ok()) return common::Result<application::ReminderListQueryV2>::failure(status.error());
  if (!enabled.ok()) return common::Result<application::ReminderListQueryV2>::failure(enabled.error());
  query.target_type = target_type.value();
  query.target_id = target_id.value();
  query.recurrence_revision = revision.value();
  query.occurrence_key = occurrence_key.value();
  query.remind_at_from = remind_at_from.value();
  query.remind_at_to = remind_at_to.value();
  query.methods = std::move(methods.value());
  query.status = std::move(status.value());
  query.is_enabled = enabled.value();
  if (field(object, "include_deleted") != nullptr) {
    auto value = require_bool(object, "include_deleted", "ListRemindersRequest");
    if (!value.ok()) return common::Result<application::ReminderListQueryV2>::failure(value.error());
    query.include_deleted = value.value();
  }
  if (const auto* pagination = field(object, "pagination"); pagination != nullptr) {
    if (!pagination->is<picojson::object>()) {
      return common::Result<application::ReminderListQueryV2>::failure(
          contract_error("ListRemindersRequest.pagination", "pagination must be an object"));
    }
    const auto& value = pagination->get<picojson::object>();
    auto pagination_known = reject_unknown(
        value, {"page", "page_size", "cursor", "sort_by", "sort_direction"},
        "ListRemindersRequest.pagination");
    if (!pagination_known.ok()) {
      return common::Result<application::ReminderListQueryV2>::failure(
          pagination_known.error());
    }
    if (field(value, "page") != nullptr && !field(value, "page")->is<picojson::null>()) {
      auto page = require_int(value, "page", "ListRemindersRequest.pagination");
      if (!page.ok()) return common::Result<application::ReminderListQueryV2>::failure(page.error());
      query.page = page.value();
    }
    if (field(value, "page_size") != nullptr &&
        !field(value, "page_size")->is<picojson::null>()) {
      auto page_size = require_int(
          value, "page_size", "ListRemindersRequest.pagination");
      if (!page_size.ok()) return common::Result<application::ReminderListQueryV2>::failure(page_size.error());
      query.page_size = page_size.value();
    }
    auto cursor = nullable_string(
        value, "cursor", "ListRemindersRequest.pagination", false);
    auto nested_sort = nullable_string(
        value, "sort_by", "ListRemindersRequest.pagination", false);
    auto nested_direction = nullable_string(
        value, "sort_direction", "ListRemindersRequest.pagination", false);
    if (!cursor.ok()) return common::Result<application::ReminderListQueryV2>::failure(cursor.error());
    if (!nested_sort.ok()) return common::Result<application::ReminderListQueryV2>::failure(nested_sort.error());
    if (!nested_direction.ok()) return common::Result<application::ReminderListQueryV2>::failure(nested_direction.error());
    query.cursor = cursor.value();
    if (nested_sort.value().has_value()) query.sort_by = *nested_sort.value();
    if (nested_direction.value().has_value()) {
      query.sort_direction = *nested_direction.value();
    }
  }
  auto sort_by = nullable_string(
      object, "sort_by", "ListRemindersRequest", false);
  auto sort_direction = nullable_string(
      object, "sort_direction", "ListRemindersRequest", false);
  if (!sort_by.ok()) return common::Result<application::ReminderListQueryV2>::failure(sort_by.error());
  if (!sort_direction.ok()) return common::Result<application::ReminderListQueryV2>::failure(sort_direction.error());
  if (sort_by.value().has_value()) query.sort_by = *sort_by.value();
  if (sort_direction.value().has_value()) {
    query.sort_direction = *sort_direction.value();
  }
  return common::Result<application::ReminderListQueryV2>::success(std::move(query));
}

}  // namespace

std::string initialize_runtime_v2_json(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"storage_directory", "tzdb_directory"}, "InitializeRuntimeRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto storage = require_string(parsed.value(), "storage_directory", "InitializeRuntimeRequest");
    auto tzdb = require_string(parsed.value(), "tzdb_directory", "InitializeRuntimeRequest");
    if (!storage.ok()) return common::Result<picojson::value>::failure(storage.error());
    if (!tzdb.ok()) return common::Result<picojson::value>::failure(tzdb.error());
    auto initialized = initialize_recurring_runtime(storage.value(), tzdb.value());
    if (!initialized.ok()) return common::Result<picojson::value>::failure(initialized.error());
    picojson::object data;
    data["initialized"] = picojson::value(initialized.value().initialized);
    data["storage_format_version"] = picojson::value(
        static_cast<double>(initialized.value().storage_format_version));
    data["tzdb_version"] = picojson::value(initialized.value().tzdb_version);
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string initialize_recurring_runtime_v2_json(std::string_view request_json) {
  return initialize_runtime_v2_json(request_json);
}

std::string create_event_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_create(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) return common::Result<picojson::value>::failure(storage_not_initialized_error("event.create"));
    auto created = service->create_event(parsed.value());
    return created.ok()
               ? common::Result<picojson::value>::success(contract::event_response_v2_to_json(created.value()))
               : common::Result<picojson::value>::failure(created.error());
  });
}

std::string create_recurring_event_v2(std::string_view request_json) {
  return create_event_v2(request_json);
}

std::string update_event_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    const auto workflow = current_recurring_event_workflow_service();
    if (!workflow) {
      return common::Result<picojson::value>::failure(storage_not_initialized_error("event.update"));
    }
    auto command = parse_update(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    auto updated = workflow->update_event(command.value());
    return updated.ok()
               ? common::Result<picojson::value>::success(contract::event_response_v2_to_json(updated.value()))
               : common::Result<picojson::value>::failure(updated.error());
  });
}

std::string update_recurring_event_v2(std::string_view request_json) {
  return update_event_v2(request_json);
}

std::string delete_event_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_delete(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) return common::Result<picojson::value>::failure(storage_not_initialized_error("event.delete"));
    auto deleted = service->delete_event(command.value());
    return deleted.ok()
               ? common::Result<picojson::value>::success(contract::event_response_v2_to_json(deleted.value()))
               : common::Result<picojson::value>::failure(deleted.error());
  });
}

std::string delete_recurring_event_v2(std::string_view request_json) {
  return delete_event_v2(request_json);
}

std::string get_event_detail_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"id"}, "GetEventDetailRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "id", "GetEventDetailRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    const auto event_query = current_recurring_event_query_service();
    if (!event_query) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event.detail"));
    }
    auto detail = event_query->get_event_detail(id.value());
    if (!detail.ok()) return common::Result<picojson::value>::failure(detail.error());
    picojson::array reminder_values;
    reminder_values.reserve(detail.value().reminders.size());
    for (const auto& reminder : detail.value().reminders) {
      reminder_values.push_back(contract::reminder_response_v2_to_json(reminder));
    }
    picojson::object data;
    data["event"] = contract::event_response_v2_to_json(detail.value().event);
    data["recurrence"] = detail.value().recurrence.has_value()
                             ? contract::recurrence_response_v2_to_json(
                                   *detail.value().recurrence)
                             : picojson::value();
    data["reminders"] = picojson::value(std::move(reminder_values));
    data["category"] = picojson::value();
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string get_recurring_event_detail_v2(std::string_view request_json) {
  return get_event_detail_v2(request_json);
}

std::string search_events_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto query = parse_event_search(request_json);
    if (!query.ok()) return common::Result<picojson::value>::failure(query.error());
    const auto service = current_recurring_event_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event.search"));
    }
    auto page = service->search_events(query.value());
    if (!page.ok()) return common::Result<picojson::value>::failure(page.error());
    picojson::array items;
    items.reserve(page.value().items.size());
    for (const auto& event : page.value().items) {
      items.push_back(contract::event_response_v2_to_json(event));
    }
    picojson::object pagination;
    pagination["total"] = picojson::value(static_cast<double>(page.value().total));
    pagination["page"] = picojson::value(static_cast<double>(page.value().page));
    pagination["page_size"] = picojson::value(static_cast<double>(page.value().page_size));
    pagination["has_more"] = picojson::value(page.value().has_more);
    pagination["next_cursor"] = page.value().next_cursor.has_value()
                                      ? picojson::value(*page.value().next_cursor)
                                      : picojson::value();
    picojson::object data;
    data["items"] = picojson::value(std::move(items));
    data["pagination"] = picojson::value(std::move(pagination));
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string complete_event_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"event_id", "source", "note"}, "CompleteEventRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto event_id = require_string(parsed.value(), "event_id", "CompleteEventRequest");
    auto source = require_string(parsed.value(), "source", "CompleteEventRequest");
    auto note = nullable_string(parsed.value(), "note", "CompleteEventRequest", false);
    if (!event_id.ok()) return common::Result<picojson::value>::failure(event_id.error());
    if (!source.ok()) return common::Result<picojson::value>::failure(source.error());
    if (!note.ok()) return common::Result<picojson::value>::failure(note.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event.complete"));
    }
    auto completed = service->complete_event({event_id.value(), source.value(), note.value()});
    return completed.ok()
               ? common::Result<picojson::value>::success(
                     contract::event_response_v2_to_json(completed.value()))
               : common::Result<picojson::value>::failure(completed.error());
  });
}

std::string reopen_event_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"event_id"}, "ReopenEventRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto event_id = require_string(parsed.value(), "event_id", "ReopenEventRequest");
    if (!event_id.ok()) return common::Result<picojson::value>::failure(event_id.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event.reopen"));
    }
    auto reopened = service->reopen_event({event_id.value()});
    return reopened.ok()
               ? common::Result<picojson::value>::success(
                     contract::event_response_v2_to_json(reopened.value()))
               : common::Result<picojson::value>::failure(reopened.error());
  });
}

std::string list_event_occurrences_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_occurrence_list(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_event_query_service();
    if (!service) return common::Result<picojson::value>::failure(storage_not_initialized_error("event.list_occurrences"));
    auto page = service->list_occurrences(command.value());
    return page.ok()
               ? common::Result<picojson::value>::success(contract::occurrence_page_v2_to_json(page.value()))
               : common::Result<picojson::value>::failure(page.error());
  });
}

namespace {

enum class OccurrenceAction { complete, reopen, skip, cancel };

std::string occurrence_action_v2(
    std::string_view request_json,
    OccurrenceAction action) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_occurrence_operation(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event_occurrence"));
    }
    common::Result<domain::EventOccurrenceState> result =
        action == OccurrenceAction::complete
            ? service->complete_occurrence(command.value())
            : action == OccurrenceAction::reopen
                  ? service->reopen_occurrence(command.value())
                  : action == OccurrenceAction::skip
                        ? service->skip_occurrence(command.value())
                        : service->cancel_occurrence(command.value());
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::occurrence_state_response_v2_to_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

enum class SeriesAction { complete, reopen, cancel };

std::string series_action_v2(
    std::string_view request_json,
    SeriesAction action) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_series_operation(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_event_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("event.series"));
    }
    common::Result<domain::Event> result =
        action == SeriesAction::complete
            ? service->complete_series(command.value())
            : action == SeriesAction::reopen
                  ? service->reopen_series(command.value())
                  : service->cancel_series(command.value());
    return result.ok()
               ? common::Result<picojson::value>::success(
                     contract::event_response_v2_to_json(result.value()))
               : common::Result<picojson::value>::failure(result.error());
  });
}

}  // namespace

std::string complete_event_occurrence_v2(std::string_view request_json) {
  return occurrence_action_v2(request_json, OccurrenceAction::complete);
}

std::string reopen_event_occurrence_v2(std::string_view request_json) {
  return occurrence_action_v2(request_json, OccurrenceAction::reopen);
}

std::string skip_event_occurrence_v2(std::string_view request_json) {
  return occurrence_action_v2(request_json, OccurrenceAction::skip);
}

std::string cancel_event_occurrence_v2(std::string_view request_json) {
  return occurrence_action_v2(request_json, OccurrenceAction::cancel);
}

std::string complete_event_series_v2(std::string_view request_json) {
  return series_action_v2(request_json, SeriesAction::complete);
}

std::string reopen_event_series_v2(std::string_view request_json) {
  return series_action_v2(request_json, SeriesAction::reopen);
}

std::string cancel_event_series_v2(std::string_view request_json) {
  return series_action_v2(request_json, SeriesAction::cancel);
}

std::string create_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_create_reminder(request_json);
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.create"));
    }
    auto reminder = service->create(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string update_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_update_reminder(request_json);
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.update"));
    }
    auto reminder = service->update(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string cancel_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "CancelReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.cancel"));
    }
    auto reminder = service->cancel(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string list_reminders_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto query = parse_reminder_list(request_json);
    if (!query.ok()) {
      return common::Result<picojson::value>::failure(query.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.list"));
    }
    auto page = service->list(query.value());
    if (!page.ok()) return common::Result<picojson::value>::failure(page.error());
    picojson::array items;
    items.reserve(page.value().items.size());
    for (const auto& reminder : page.value().items) {
      items.push_back(contract::reminder_response_v2_to_json(reminder));
    }
    picojson::object pagination;
    pagination["total"] = picojson::value(static_cast<double>(page.value().total));
    pagination["page"] = picojson::value(static_cast<double>(page.value().page));
    pagination["page_size"] =
        picojson::value(static_cast<double>(page.value().page_size));
    pagination["has_more"] = picojson::value(page.value().has_more);
    pagination["next_cursor"] = page.value().next_cursor.has_value()
                                      ? picojson::value(*page.value().next_cursor)
                                      : picojson::value();
    picojson::object data;
    data["items"] = picojson::value(std::move(items));
    data["pagination"] = picojson::value(std::move(pagination));
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
}

std::string enable_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "EnableReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.enable"));
    }
    auto reminder = service->enable(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string disable_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_reminder_id(request_json, "DisableReminderRequest");
    if (!command.ok()) {
      return common::Result<picojson::value>::failure(command.error());
    }
    const auto service = current_reminder_service_v2();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.disable"));
    }
    auto reminder = service->disable(command.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string list_schedulable_recurring_reminders_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_schedulable(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.list_schedulable"));
    }
    auto page = service->list_schedulable(command.value());
    return page.ok()
               ? common::Result<picojson::value>::success(
                     contract::schedulable_reminder_page_v2_to_json(page.value()))
               : common::Result<picojson::value>::failure(page.error());
  });
}

std::string get_recurring_reminder_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(parsed.value(), {"reminder_id"}, "GetReminderRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "reminder_id", "GetReminderRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.get"));
    }
    auto reminder = service->get_reminder(id.value());
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string mark_recurring_reminder_scheduled_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"reminder_id", "expected_remind_at", "scheduled_at"},
        "MarkReminderScheduledRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto id = require_string(parsed.value(), "reminder_id", "MarkReminderScheduledRequest");
    auto expected_remind_at = require_string(
        parsed.value(), "expected_remind_at", "MarkReminderScheduledRequest");
    auto scheduled_at = require_string(
        parsed.value(), "scheduled_at", "MarkReminderScheduledRequest");
    if (!id.ok()) return common::Result<picojson::value>::failure(id.error());
    if (!expected_remind_at.ok()) {
      return common::Result<picojson::value>::failure(expected_remind_at.error());
    }
    if (!scheduled_at.ok()) return common::Result<picojson::value>::failure(scheduled_at.error());
    const auto service = current_recurring_reminder_query_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.mark_scheduled"));
    }
    auto reminder = service->mark_scheduled(
        {id.value(), expected_remind_at.value(), scheduled_at.value()});
    return reminder.ok()
               ? common::Result<picojson::value>::success(
                     contract::reminder_response_v2_to_json(reminder.value()))
               : common::Result<picojson::value>::failure(reminder.error());
  });
}

std::string prepare_recurring_reminder_delivery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_prepare(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_delivery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.prepare_delivery"));
    }
    auto prepared = service->prepare_delivery(command.value());
    return prepared.ok()
               ? common::Result<picojson::value>::success(
                     contract::prepare_delivery_response_v2_to_json(prepared.value()))
               : common::Result<picojson::value>::failure(prepared.error());
  });
}

std::string finalize_recurring_reminder_delivery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto command = parse_finalize(request_json);
    if (!command.ok()) return common::Result<picojson::value>::failure(command.error());
    const auto service = current_recurring_reminder_delivery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.finalize_delivery"));
    }
    auto finalized = service->finalize_delivery(command.value());
    return finalized.ok()
               ? common::Result<picojson::value>::success(
                     contract::finalize_delivery_response_v2_to_json(finalized.value()))
               : common::Result<picojson::value>::failure(finalized.error());
  });
}

std::string plan_recurring_reminder_recovery_v2(std::string_view request_json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_object(request_json);
    if (!parsed.ok()) return common::Result<picojson::value>::failure(parsed.error());
    auto known = reject_unknown(
        parsed.value(), {"recovery_request_id", "trigger_source"}, "PlanRecoveryRequest");
    if (!known.ok()) return common::Result<picojson::value>::failure(known.error());
    auto request_id = require_string(parsed.value(), "recovery_request_id", "PlanRecoveryRequest");
    auto source = require_string(parsed.value(), "trigger_source", "PlanRecoveryRequest");
    if (!request_id.ok()) return common::Result<picojson::value>::failure(request_id.error());
    if (!source.ok()) return common::Result<picojson::value>::failure(source.error());
    const auto service = current_reminder_recovery_workflow_service();
    if (!service) {
      return common::Result<picojson::value>::failure(
          storage_not_initialized_error("reminder.plan_recovery"));
    }
    auto planned = service->plan_recovery({request_id.value(), source.value()});
    return planned.ok()
               ? common::Result<picojson::value>::success(
                     contract::plan_recovery_response_v2_to_json(planned.value()))
               : common::Result<picojson::value>::failure(planned.error());
  });
}

std::string get_reminder_v2(std::string_view request_json) {
  return get_recurring_reminder_v2(request_json);
}

std::string list_schedulable_reminders_v2(std::string_view request_json) {
  return list_schedulable_recurring_reminders_v2(request_json);
}

std::string mark_reminder_scheduled_v2(std::string_view request_json) {
  return mark_recurring_reminder_scheduled_v2(request_json);
}

std::string prepare_reminder_delivery_v2(std::string_view request_json) {
  return prepare_recurring_reminder_delivery_v2(request_json);
}

std::string finalize_reminder_delivery_v2(std::string_view request_json) {
  return finalize_recurring_reminder_delivery_v2(request_json);
}

std::string plan_reminder_recovery_v2(std::string_view request_json) {
  return plan_recurring_reminder_recovery_v2(request_json);
}

}  // namespace excellent_calendar::boundary::api
