#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "recurring_v2_api_internal.hpp"
#include "excellent_calendar/application/recurring_event_query_service.hpp"
#include "excellent_calendar/application/recurring_event_workflow_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/category_json.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::api {
namespace {

using detail::contract_error;
using detail::field;
using detail::nullable_bool;
using detail::nullable_int;
using detail::nullable_string;
using detail::parse_object;
using detail::reject_unknown;
using detail::require_bool;
using detail::require_int;
using detail::require_string;
using detail::respond_v2;
using detail::string_array;

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

}  // namespace

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
    data["category"] = detail.value().category.has_value()
                           ? contract::category_response_json(
                                 contract::category_response_from_domain(
                                     *detail.value().category))
                           : picojson::value();
    return common::Result<picojson::value>::success(picojson::value(std::move(data)));
  });
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

}  // namespace excellent_calendar::boundary::api
