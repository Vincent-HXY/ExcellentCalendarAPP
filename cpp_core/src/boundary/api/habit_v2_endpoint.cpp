#include "excellent_calendar/boundary/api/habit_api.hpp"

#include <optional>
#include <set>
#include <string>
#include <utility>

#include <picojson/picojson.h>

#include "recurring_v2_api_internal.hpp"
#include "excellent_calendar/application/habit_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/habit_json.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/habit.hpp"

namespace excellent_calendar::boundary::api {
namespace {

using detail::contract_error;
using detail::field;
using detail::nullable_int;
using detail::nullable_int64;
using detail::nullable_string;
using detail::parse_object;
using detail::reject_unknown;
using detail::require_bool;
using detail::require_int;
using detail::require_string;
using detail::respond_v2;
using detail::string_array;

template <typename T>
common::Result<T> fail(const common::Error& error) {
  return common::Result<T>::failure(error);
}

bool has_hundredths_suffix(std::string_view key) {
  constexpr std::string_view suffix = "_hundredths";
  return key.size() >= suffix.size() &&
         key.substr(key.size() - suffix.size()) == suffix;
}

bool is_integer_lexeme(std::string_view value) {
  if (value.empty()) return false;
  std::size_t index = value.front() == '-' ? 1U : 0U;
  if (index == value.size()) return false;
  if (value[index] == '0') return index + 1U == value.size();
  if (value[index] < '1' || value[index] > '9') return false;
  for (++index; index < value.size(); ++index) {
    if (value[index] < '0' || value[index] > '9') return false;
  }
  return true;
}

common::Result<common::Unit> validate_hundredths_lexemes(
    std::string_view json) {
  std::size_t cursor = 0;
  const auto skip_space = [&]() {
    while (cursor < json.size() &&
           (json[cursor] == ' ' || json[cursor] == '\t' ||
            json[cursor] == '\r' || json[cursor] == '\n')) {
      ++cursor;
    }
  };
  skip_space();
  if (cursor >= json.size() || json[cursor] != '{')
    return common::Result<common::Unit>::success(common::Unit{});
  ++cursor;
  while (cursor < json.size()) {
    skip_space();
    if (cursor >= json.size() || json[cursor] == '}') break;
    if (json[cursor] != '"')
      return common::Result<common::Unit>::success(common::Unit{});
    const auto key_start = cursor++;
    bool escaped = false;
    while (cursor < json.size()) {
      const char current = json[cursor++];
      if (escaped) {
        escaped = false;
      } else if (current == '\\') {
        escaped = true;
      } else if (current == '"') {
        break;
      }
    }
    picojson::value decoded_key;
    const auto key_error = picojson::parse(
        decoded_key,
        std::string(json.substr(key_start, cursor - key_start)));
    if (!key_error.empty() || !decoded_key.is<std::string>())
      return common::Result<common::Unit>::success(common::Unit{});
    skip_space();
    if (cursor >= json.size() || json[cursor] != ':')
      return common::Result<common::Unit>::success(common::Unit{});
    ++cursor;
    skip_space();
    const auto value_start = cursor;
    int nested_depth = 0;
    bool in_string = false;
    escaped = false;
    while (cursor < json.size()) {
      const char current = json[cursor];
      if (in_string) {
        if (escaped) {
          escaped = false;
        } else if (current == '\\') {
          escaped = true;
        } else if (current == '"') {
          in_string = false;
        }
        ++cursor;
        continue;
      }
      if (current == '"') {
        in_string = true;
        ++cursor;
      } else if (current == '{' || current == '[') {
        ++nested_depth;
        ++cursor;
      } else if (current == '}' || current == ']') {
        if (nested_depth == 0) break;
        --nested_depth;
        ++cursor;
      } else if (current == ',' && nested_depth == 0) {
        break;
      } else {
        ++cursor;
      }
    }
    auto value_end = cursor;
    while (value_start < value_end &&
           (json[value_end - 1U] == ' ' || json[value_end - 1U] == '\t' ||
            json[value_end - 1U] == '\r' || json[value_end - 1U] == '\n')) {
      --value_end;
    }
    const auto value = json.substr(value_start, value_end - value_start);
    if (has_hundredths_suffix(decoded_key.get<std::string>()) &&
        !value.empty() &&
        (value.front() == '-' ||
         (value.front() >= '0' && value.front() <= '9')) &&
        !is_integer_lexeme(value)) {
      return common::Result<common::Unit>::failure(contract_error(
          decoded_key.get<std::string>(),
          "hundredths fields require an integer JSON token"));
    }
    if (cursor < json.size() && json[cursor] == ',') ++cursor;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<picojson::object> parse_habit_object(std::string_view json) {
  auto parsed = parse_object(json);
  if (!parsed.ok()) return parsed;
  auto lexemes = validate_hundredths_lexemes(json);
  return lexemes.ok()
             ? parsed
             : common::Result<picojson::object>::failure(lexemes.error());
}

common::Result<domain::LocalDate> required_date(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto raw = require_string(object, key, parent);
  if (!raw.ok()) return fail<domain::LocalDate>(raw.error());
  auto parsed = domain::parse_local_date(raw.value());
  return parsed.ok() ? parsed : fail<domain::LocalDate>(
      contract_error(parent + "." + key, "date must be valid YYYY-MM-DD"));
}

common::Result<std::string> required_uuid(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto value = require_string(object, key, parent);
  if (!value.ok()) return value;
  return common::is_uuid(value.value())
             ? value
             : fail<std::string>(contract_error(parent + "." + key,
                                                "field must be a UUID"));
}

common::Result<std::string> required_utc(
    const picojson::object& object, const std::string& key,
    const std::string& parent) {
  auto value = require_string(object, key, parent);
  if (!value.ok()) return value;
  return common::is_iso8601_utc_datetime(value.value())
             ? value
             : fail<std::string>(contract_error(
                   parent + "." + key, "field must be a UTC date-time"));
}

common::Result<application::HabitReminderPlan> parse_reminder(
    const picojson::value& value, const std::string& parent) {
  if (!value.is<picojson::object>())
    return fail<application::HabitReminderPlan>(
        contract_error(parent, "reminder must be an object"));
  const auto& object = value.get<picojson::object>();
  auto known = reject_unknown(
      object, {"is_enabled", "local_time", "timezone_mode", "method"}, parent);
  if (!known.ok()) return fail<application::HabitReminderPlan>(known.error());
  auto enabled = require_bool(object, "is_enabled", parent);
  auto local_time = nullable_string(object, "local_time", parent, true);
  auto timezone_mode = require_string(object, "timezone_mode", parent);
  auto method = require_string(object, "method", parent);
  if (!enabled.ok()) return fail<application::HabitReminderPlan>(enabled.error());
  if (!local_time.ok()) return fail<application::HabitReminderPlan>(local_time.error());
  if (!timezone_mode.ok()) return fail<application::HabitReminderPlan>(timezone_mode.error());
  if (!method.ok()) return fail<application::HabitReminderPlan>(method.error());
  bool time_valid = false;
  if (local_time.value() && local_time.value()->size() == 5U &&
      (*local_time.value())[2] == ':') {
    const auto& text = *local_time.value();
    const bool digits = text[0] >= '0' && text[0] <= '9' &&
                        text[1] >= '0' && text[1] <= '9' &&
                        text[3] >= '0' && text[3] <= '9' &&
                        text[4] >= '0' && text[4] <= '9';
    if (digits) {
      const int hour = (text[0] - '0') * 10 + text[1] - '0';
      const int minute = (text[3] - '0') * 10 + text[4] - '0';
      time_valid = hour <= 23 && minute <= 59;
    }
  }
  if (timezone_mode.value() != "follow_device" || method.value() != "popup" ||
      (enabled.value() != time_valid) ||
      (!enabled.value() && local_time.value().has_value())) {
    return fail<application::HabitReminderPlan>(contract_error(
        parent, "reminder plan combination is invalid"));
  }
  return common::Result<application::HabitReminderPlan>::success(
      {enabled.value(), local_time.value(), timezone_mode.value(), method.value()});
}

common::Result<common::Unit> parse_recurrence(
    const picojson::value& value, application::CreateHabitCommand& command,
    const std::string& parent) {
  if (!value.is<picojson::object>())
    return fail<common::Unit>(contract_error(parent, "recurrence must be an object"));
  const auto& object = value.get<picojson::object>();
  auto known = reject_unknown(object, {"frequency", "interval", "timezone_mode"}, parent);
  if (!known.ok()) return known;
  auto frequency = require_string(object, "frequency", parent);
  auto interval = require_int(object, "interval", parent);
  auto timezone_mode = require_string(object, "timezone_mode", parent);
  if (!frequency.ok()) return fail<common::Unit>(frequency.error());
  if (!interval.ok()) return fail<common::Unit>(interval.error());
  if (!timezone_mode.ok()) return fail<common::Unit>(timezone_mode.error());
  if (frequency.value() != "daily" || interval.value() != 1 ||
      timezone_mode.value() != "follow_device")
    return fail<common::Unit>(contract_error(parent, "only daily/1/follow_device is supported"));
  command.recurrence_frequency = frequency.value();
  command.recurrence_interval = interval.value();
  command.recurrence_timezone_mode = timezone_mode.value();
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<application::CreateHabitCommand> parse_create(
    const picojson::object& object) {
  constexpr const char* parent = "CreateHabitRequest";
  auto known = reject_unknown(object,
      {"title", "description", "category_id", "recurrence",
       "target_count_hundredths", "unit", "start_date", "end_date",
       "reminder", "timezone"}, parent);
  if (!known.ok()) return fail<application::CreateHabitCommand>(known.error());
  auto title = require_string(object, "title", parent, false);
  auto description = nullable_string(object, "description", parent, true);
  auto category = nullable_string(object, "category_id", parent, true);
  auto target = nullable_int64(object, "target_count_hundredths", parent, true);
  auto unit = nullable_string(object, "unit", parent, true);
  auto start = required_date(object, "start_date", parent);
  auto end = required_date(object, "end_date", parent);
  auto timezone = require_string(object, "timezone", parent);
  const auto* recurrence_value = field(object, "recurrence");
  const auto* reminder_value = field(object, "reminder");
  if (!title.ok()) return fail<application::CreateHabitCommand>(title.error());
  if (!description.ok()) return fail<application::CreateHabitCommand>(description.error());
  if (!category.ok()) return fail<application::CreateHabitCommand>(category.error());
  if (!target.ok()) return fail<application::CreateHabitCommand>(target.error());
  if (!unit.ok()) return fail<application::CreateHabitCommand>(unit.error());
  if (!start.ok()) return fail<application::CreateHabitCommand>(start.error());
  if (!end.ok()) return fail<application::CreateHabitCommand>(end.error());
  if (!timezone.ok()) return fail<application::CreateHabitCommand>(timezone.error());
  if (recurrence_value == nullptr || reminder_value == nullptr)
    return fail<application::CreateHabitCommand>(contract_error(parent, "required nested field is missing"));
  auto reminder = parse_reminder(*reminder_value, std::string(parent) + ".reminder");
  if (!reminder.ok()) return fail<application::CreateHabitCommand>(reminder.error());
  if (target.value().has_value() != unit.value().has_value() ||
      (target.value() && (*target.value() < 1 || *target.value() > domain::kHabitMaxHundredths)))
    return fail<application::CreateHabitCommand>(contract_error(parent, "target and unit combination is invalid"));
  application::CreateHabitCommand command;
  command.title = title.value();
  command.description = description.value();
  command.category_id = category.value();
  command.target_count_hundredths = target.value();
  command.unit = unit.value();
  command.start_date = start.value();
  command.end_date = end.value();
  command.reminder = reminder.value();
  command.timezone = timezone.value();
  auto recurrence = parse_recurrence(*recurrence_value, command,
                                     std::string(parent) + ".recurrence");
  return recurrence.ok() ? common::Result<application::CreateHabitCommand>::success(std::move(command))
                         : fail<application::CreateHabitCommand>(recurrence.error());
}

common::Result<application::UpdateHabitCommand> parse_update(
    const picojson::object& object) {
  constexpr const char* parent = "UpdateHabitRequest";
  auto known = reject_unknown(object,
      {"id", "expected_updated_at", "title", "description", "category_id",
       "target_count_hundredths", "unit", "start_date", "end_date",
       "reminder", "timezone"}, parent);
  if (!known.ok()) return fail<application::UpdateHabitCommand>(known.error());
  auto id = required_uuid(object, "id", parent);
  auto expected = required_utc(object, "expected_updated_at", parent);
  auto title = require_string(object, "title", parent, false);
  auto description = nullable_string(object, "description", parent, true);
  auto category = nullable_string(object, "category_id", parent, true);
  auto target = nullable_int64(object, "target_count_hundredths", parent, true);
  auto unit = nullable_string(object, "unit", parent, true);
  auto start = required_date(object, "start_date", parent);
  auto end = required_date(object, "end_date", parent);
  auto timezone = require_string(object, "timezone", parent);
  if (!id.ok()) return fail<application::UpdateHabitCommand>(id.error());
  if (!expected.ok()) return fail<application::UpdateHabitCommand>(expected.error());
  if (!title.ok()) return fail<application::UpdateHabitCommand>(title.error());
  if (!description.ok()) return fail<application::UpdateHabitCommand>(description.error());
  if (!category.ok()) return fail<application::UpdateHabitCommand>(category.error());
  if (!target.ok()) return fail<application::UpdateHabitCommand>(target.error());
  if (!unit.ok()) return fail<application::UpdateHabitCommand>(unit.error());
  if (!start.ok()) return fail<application::UpdateHabitCommand>(start.error());
  if (!end.ok()) return fail<application::UpdateHabitCommand>(end.error());
  if (!timezone.ok()) return fail<application::UpdateHabitCommand>(timezone.error());
  if (target.value().has_value() != unit.value().has_value() ||
      (target.value() && (*target.value() < 1 || *target.value() > domain::kHabitMaxHundredths)))
    return fail<application::UpdateHabitCommand>(contract_error(parent, "target and unit combination is invalid"));
  application::UpdateHabitCommand command{id.value(), expected.value(), title.value(),
      description.value(), category.value(), target.value(), unit.value(),
      start.value(), end.value(), std::nullopt, timezone.value()};
  if (const auto* value = field(object, "reminder"); value != nullptr) {
    auto reminder = parse_reminder(*value, std::string(parent) + ".reminder");
    if (!reminder.ok()) return fail<application::UpdateHabitCommand>(reminder.error());
    command.reminder = reminder.value();
  }
  return common::Result<application::UpdateHabitCommand>::success(std::move(command));
}

common::Result<application::HabitIdentityCommand> parse_identity(
    const picojson::object& object, const std::string& parent) {
  auto known = reject_unknown(object, {"id", "expected_updated_at", "timezone"}, parent);
  if (!known.ok()) return fail<application::HabitIdentityCommand>(known.error());
  auto id = required_uuid(object, "id", parent);
  auto expected = required_utc(object, "expected_updated_at", parent);
  auto timezone = require_string(object, "timezone", parent);
  if (!id.ok()) return fail<application::HabitIdentityCommand>(id.error());
  if (!expected.ok()) return fail<application::HabitIdentityCommand>(expected.error());
  if (!timezone.ok()) return fail<application::HabitIdentityCommand>(timezone.error());
  return common::Result<application::HabitIdentityCommand>::success(
      {id.value(), expected.value(), timezone.value()});
}

template <typename T, typename Fn>
std::string endpoint(std::string_view json, std::string operation,
                     Fn&& callback) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_habit_object(json);
    if (!parsed.ok()) return fail<picojson::value>(parsed.error());
    auto service = current_habit_service();
    if (!service) return fail<picojson::value>(storage_not_initialized_error(std::move(operation)));
    auto result = callback(*service, parsed.value());
    return result.ok() ? common::Result<picojson::value>::success(T(result.value()))
                       : fail<picojson::value>(result.error());
  });
}

}  // namespace

std::string create_habit_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_habit_object(json); if (!parsed.ok()) return fail<picojson::value>(parsed.error());
    auto command = parse_create(parsed.value()); if (!command.ok()) return fail<picojson::value>(command.error());
    auto service = current_habit_service(); if (!service) return fail<picojson::value>(storage_not_initialized_error("habit.create"));
    auto result = service->create(command.value());
    return result.ok() ? common::Result<picojson::value>::success(contract::habit_mutation_commit_response_json(result.value())) : fail<picojson::value>(result.error());
  });
}

std::string update_habit_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_habit_object(json); if (!parsed.ok()) return fail<picojson::value>(parsed.error());
    auto command = parse_update(parsed.value()); if (!command.ok()) return fail<picojson::value>(command.error());
    auto service = current_habit_service(); if (!service) return fail<picojson::value>(storage_not_initialized_error("habit.update"));
    auto result = service->update(command.value());
    return result.ok() ? common::Result<picojson::value>::success(contract::habit_mutation_commit_response_json(result.value())) : fail<picojson::value>(result.error());
  });
}

std::string list_habits_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_habit_object(json); if (!parsed.ok()) return fail<picojson::value>(parsed.error());
    constexpr const char* parent = "ListHabitsRequest";
    auto known = reject_unknown(parsed.value(), {"timezone", "lifecycle_statuses", "category_ids", "pagination"}, parent);
    if (!known.ok()) return fail<picojson::value>(known.error());
    auto timezone = require_string(parsed.value(), "timezone", parent);
    auto lifecycles = string_array(parsed.value(), "lifecycle_statuses", parent, false, true);
    auto categories = string_array(parsed.value(), "category_ids", parent, false, true);
    if (!timezone.ok()) return fail<picojson::value>(timezone.error());
    if (!lifecycles.ok()) return fail<picojson::value>(lifecycles.error());
    if (!categories.ok()) return fail<picojson::value>(categories.error());
    if ((field(parsed.value(), "lifecycle_statuses") && (lifecycles.value().empty() || lifecycles.value().size() > 4U)) ||
        (field(parsed.value(), "category_ids") && (categories.value().empty() || categories.value().size() > 100U)))
      return fail<picojson::value>(contract_error(parent, "filter size is invalid"));
    for (const auto& value : lifecycles.value())
      if (value != "upcoming" && value != "active" && value != "completed" && value != "ended_early")
        return fail<picojson::value>(contract_error("ListHabitsRequest.lifecycle_statuses", "unknown lifecycle"));
    for (const auto& value : categories.value())
      if (value.empty() || value.size() > 512U)
        return fail<picojson::value>(contract_error(
            "ListHabitsRequest.category_ids", "category id length is invalid"));
    application::ListHabitsQuery query; query.timezone = timezone.value(); query.lifecycle_statuses = lifecycles.value(); query.category_ids = categories.value();
    if (const auto* value = field(parsed.value(), "pagination"); value != nullptr) {
      if (!value->is<picojson::object>()) return fail<picojson::value>(contract_error("ListHabitsRequest.pagination", "pagination must be object"));
      const auto& page = value->get<picojson::object>();
      auto page_known = reject_unknown(page, {"page", "page_size", "cursor", "sort_by", "sort_direction"}, "ListHabitsRequest.pagination");
      if (!page_known.ok()) return fail<picojson::value>(page_known.error());
      auto number = nullable_int64(page, "page", "ListHabitsRequest.pagination", false);
      auto size = nullable_int(page, "page_size", "ListHabitsRequest.pagination", false);
      auto cursor = nullable_string(page, "cursor", "ListHabitsRequest.pagination", false);
      auto sort_by = nullable_string(page, "sort_by", "ListHabitsRequest.pagination", false);
      auto sort_direction = nullable_string(page, "sort_direction", "ListHabitsRequest.pagination", false);
      if (!number.ok()) return fail<picojson::value>(number.error()); if (!size.ok()) return fail<picojson::value>(size.error()); if (!cursor.ok()) return fail<picojson::value>(cursor.error()); if (!sort_by.ok()) return fail<picojson::value>(sort_by.error()); if (!sort_direction.ok()) return fail<picojson::value>(sort_direction.error());
      if ((number.value() && (*number.value() < 1 || *number.value() > domain::kHabitMaxHundredths)) || (size.value() && (*size.value() < 1 || *size.value() > 100)) || (cursor.value() && (cursor.value()->empty() || cursor.value()->size() > 512U)) || sort_by.value() || sort_direction.value())
        return fail<picojson::value>(contract_error("ListHabitsRequest.pagination", "pagination is invalid"));
      if (number.value()) query.page = *number.value(); if (size.value()) query.page_size = *size.value(); query.cursor = cursor.value();
    }
    auto service = current_habit_service(); if (!service) return fail<picojson::value>(storage_not_initialized_error("habit.list"));
    auto result = service->list(query);
    return result.ok() ? common::Result<picojson::value>::success(contract::habit_list_response_json(result.value())) : fail<picojson::value>(result.error());
  });
}

std::string get_habit_detail_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed = parse_habit_object(json); if (!parsed.ok()) return fail<picojson::value>(parsed.error());
    auto known = reject_unknown(parsed.value(), {"id", "timezone", "history_page_size"}, "GetHabitDetailRequest"); if (!known.ok()) return fail<picojson::value>(known.error());
    auto id = required_uuid(parsed.value(), "id", "GetHabitDetailRequest"); auto timezone = require_string(parsed.value(), "timezone", "GetHabitDetailRequest"); auto size = require_int(parsed.value(), "history_page_size", "GetHabitDetailRequest");
    if (!id.ok()) return fail<picojson::value>(id.error()); if (!timezone.ok()) return fail<picojson::value>(timezone.error()); if (!size.ok()) return fail<picojson::value>(size.error()); if (size.value() < 1 || size.value() > 120) return fail<picojson::value>(contract_error("GetHabitDetailRequest.history_page_size", "out of range"));
    auto service = current_habit_service(); if (!service) return fail<picojson::value>(storage_not_initialized_error("habit.detail")); auto result = service->detail(id.value(), timezone.value(), size.value());
    return result.ok() ? common::Result<picojson::value>::success(contract::habit_detail_response_json(result.value())) : fail<picojson::value>(result.error());
  });
}

std::string end_habit_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto command=parse_identity(parsed.value(),"EndHabitRequest"); if(!command.ok())return fail<picojson::value>(command.error()); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.end")); auto result=service->end(command.value()); return result.ok()?common::Result<picojson::value>::success(contract::habit_mutation_commit_response_json(result.value())):fail<picojson::value>(result.error()); });
}

std::string delete_habit_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto command=parse_identity(parsed.value(),"DeleteHabitRequest"); if(!command.ok())return fail<picojson::value>(command.error()); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.delete")); auto result=service->remove(command.value()); return result.ok()?common::Result<picojson::value>::success(contract::habit_delete_commit_response_json(result.value())):fail<picojson::value>(result.error()); });
}

std::string check_in_habit_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> {
    auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); constexpr const char* parent="HabitCheckInCommandRequest";
    auto known=reject_unknown(parsed.value(),{"habit_id","check_date","status","completed_count_hundredths","note","source","occurrence_key","action_id","timezone"},parent); if(!known.ok())return fail<picojson::value>(known.error());
    auto id=required_uuid(parsed.value(),"habit_id",parent); auto date=required_date(parsed.value(),"check_date",parent); auto status=require_string(parsed.value(),"status",parent); auto count=nullable_int64(parsed.value(),"completed_count_hundredths",parent,true); auto note=nullable_string(parsed.value(),"note",parent,true); auto source=require_string(parsed.value(),"source",parent); auto occurrence=nullable_string(parsed.value(),"occurrence_key",parent,true); auto action=nullable_string(parsed.value(),"action_id",parent,true); auto timezone=require_string(parsed.value(),"timezone",parent);
    if(!id.ok())return fail<picojson::value>(id.error()); if(!date.ok())return fail<picojson::value>(date.error()); if(!status.ok())return fail<picojson::value>(status.error()); if(!count.ok())return fail<picojson::value>(count.error()); if(!note.ok())return fail<picojson::value>(note.error()); if(!source.ok())return fail<picojson::value>(source.error()); if(!occurrence.ok())return fail<picojson::value>(occurrence.error()); if(!action.ok())return fail<picojson::value>(action.error()); if(!timezone.ok())return fail<picojson::value>(timezone.error());
    const bool valid_status=status.value()=="done"||status.value()=="partial"||status.value()=="skipped"; const bool valid_count=!count.value()||(*count.value()>=1&&*count.value()<=domain::kHabitMaxHundredths); const bool manual=source.value()=="manual"&&!occurrence.value()&&!action.value(); const bool notification=source.value()=="notification_action"&&status.value()=="done"&&!count.value()&&!note.value()&&occurrence.value()&&action.value()&&common::is_uuid(*occurrence.value())&&common::is_uuid(*action.value());
    if(!valid_status||!valid_count||(status.value()=="partial"&&!count.value())||(status.value()=="skipped"&&count.value())||(!manual&&!notification))return fail<picojson::value>(contract_error(parent,"check-in command combination is invalid"));
    application::HabitCheckInCommand command{id.value(),date.value(),status.value(),count.value(),note.value(),source.value(),occurrence.value(),action.value(),timezone.value()}; auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.check_in")); auto result=service->check_in(command); return result.ok()?common::Result<picojson::value>::success(contract::habit_check_in_commit_response_json(result.value())):fail<picojson::value>(result.error());
  });
}

std::string clear_habit_check_in_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto known=reject_unknown(parsed.value(),{"habit_id","check_date","timezone"},"ClearHabitCheckInRequest"); if(!known.ok())return fail<picojson::value>(known.error()); auto id=required_uuid(parsed.value(),"habit_id","ClearHabitCheckInRequest"); auto date=required_date(parsed.value(),"check_date","ClearHabitCheckInRequest"); auto timezone=require_string(parsed.value(),"timezone","ClearHabitCheckInRequest"); if(!id.ok())return fail<picojson::value>(id.error()); if(!date.ok())return fail<picojson::value>(date.error()); if(!timezone.ok())return fail<picojson::value>(timezone.error()); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.clear_check_in")); auto result=service->clear_check_in({id.value(),date.value(),timezone.value()}); return result.ok()?common::Result<picojson::value>::success(contract::habit_check_in_commit_response_json(result.value())):fail<picojson::value>(result.error()); });
}

std::string list_habit_daily_statuses_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto known=reject_unknown(parsed.value(),{"habit_id","start_date","end_date","timezone"},"ListHabitDailyStatusesRequest"); if(!known.ok())return fail<picojson::value>(known.error()); auto id=required_uuid(parsed.value(),"habit_id","ListHabitDailyStatusesRequest"); auto start=required_date(parsed.value(),"start_date","ListHabitDailyStatusesRequest"); auto end=required_date(parsed.value(),"end_date","ListHabitDailyStatusesRequest"); auto timezone=require_string(parsed.value(),"timezone","ListHabitDailyStatusesRequest"); if(!id.ok())return fail<picojson::value>(id.error()); if(!start.ok())return fail<picojson::value>(start.error()); if(!end.ok())return fail<picojson::value>(end.error()); if(!timezone.ok())return fail<picojson::value>(timezone.error()); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.list_daily_statuses")); auto result=service->list_daily_statuses(id.value(),start.value(),end.value(),timezone.value()); return result.ok()?common::Result<picojson::value>::success(contract::habit_daily_status_list_response_json(result.value())):fail<picojson::value>(result.error()); });
}

std::string set_habit_reminder_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto known=reject_unknown(parsed.value(),{"habit_id","expected_updated_at","reminder","timezone"},"SetHabitReminderRequest"); if(!known.ok())return fail<picojson::value>(known.error()); auto id=required_uuid(parsed.value(),"habit_id","SetHabitReminderRequest"); auto expected=required_utc(parsed.value(),"expected_updated_at","SetHabitReminderRequest"); auto timezone=require_string(parsed.value(),"timezone","SetHabitReminderRequest"); const auto* value=field(parsed.value(),"reminder"); if(!id.ok())return fail<picojson::value>(id.error()); if(!expected.ok())return fail<picojson::value>(expected.error()); if(!timezone.ok())return fail<picojson::value>(timezone.error()); if(!value)return fail<picojson::value>(contract_error("SetHabitReminderRequest.reminder","required field is missing")); auto reminder=parse_reminder(*value,"SetHabitReminderRequest.reminder"); if(!reminder.ok())return fail<picojson::value>(reminder.error()); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.set_reminder")); auto result=service->set_reminder({id.value(),expected.value(),reminder.value(),timezone.value()}); return result.ok()?common::Result<picojson::value>::success(contract::habit_mutation_commit_response_json(result.value())):fail<picojson::value>(result.error()); });
}

std::string reconcile_habit_reminders_v2(std::string_view json) {
  return respond_v2([&]() -> common::Result<picojson::value> { auto parsed=parse_habit_object(json); if(!parsed.ok())return fail<picojson::value>(parsed.error()); auto known=reject_unknown(parsed.value(),{"timezone","trigger_source","cursor","limit"},"ReconcileHabitRemindersRequest"); if(!known.ok())return fail<picojson::value>(known.error()); auto timezone=require_string(parsed.value(),"timezone","ReconcileHabitRemindersRequest"); auto trigger=require_string(parsed.value(),"trigger_source","ReconcileHabitRemindersRequest"); auto cursor=nullable_string(parsed.value(),"cursor","ReconcileHabitRemindersRequest",true); auto limit=require_int(parsed.value(),"limit","ReconcileHabitRemindersRequest"); if(!timezone.ok())return fail<picojson::value>(timezone.error()); if(!trigger.ok())return fail<picojson::value>(trigger.error()); if(!cursor.ok())return fail<picojson::value>(cursor.error()); if(!limit.ok())return fail<picojson::value>(limit.error()); const std::set<std::string> triggers{"app_start","device_boot","app_update","date_changed","time_changed","timezone_changed","permission_restored","manual_retry"}; if(triggers.count(trigger.value())==0U||limit.value()<1||limit.value()>100||(cursor.value()&&(cursor.value()->empty()||cursor.value()->size()>512U)))return fail<picojson::value>(contract_error("ReconcileHabitRemindersRequest","request is invalid")); auto service=current_habit_service(); if(!service)return fail<picojson::value>(storage_not_initialized_error("habit.reconcile_reminders")); auto result=service->reconcile_reminders({timezone.value(),trigger.value(),cursor.value(),limit.value()}); return result.ok()?common::Result<picojson::value>::success(contract::habit_reconcile_response_json(result.value())):fail<picojson::value>(result.error()); });
}

}  // namespace excellent_calendar::boundary::api
