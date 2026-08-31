#include "excellent_calendar/storage/json/habit_json_codec.hpp"

#include <cmath>
#include <cstdint>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/storage/json/habit_state_validator.hpp"

namespace excellent_calendar::storage::json {
namespace {

class DecodeFailure final : public std::runtime_error {
 public:
  explicit DecodeFailure(std::string message)
      : std::runtime_error(std::move(message)) {}
};

common::Error corrupted(std::string reason, std::string field = {}) {
  std::map<std::string, std::string> details{{"reason", std::move(reason)}};
  if (!field.empty()) details["field"] = std::move(field);
  return common::make_error("STORAGE_DATA_CORRUPTED",
                            "Stored Habit data is invalid",
                            std::move(details));
}

const picojson::object& object(const picojson::value& value,
                               std::string_view name) {
  if (!value.is<picojson::object>())
    throw DecodeFailure(std::string(name) + " must be object");
  return value.get<picojson::object>();
}

void exact(const picojson::object& value,
           std::initializer_list<const char*> keys,
           std::string_view name) {
  std::set<std::string> expected;
  for (const auto* key : keys) expected.insert(key);
  if (value.size() != expected.size())
    throw DecodeFailure(std::string(name) + " field count is invalid");
  for (const auto& [key, _] : value) {
    if (expected.count(key) == 0U)
      throw DecodeFailure(std::string(name) + "." + key + " is unknown");
  }
}

const picojson::value& required(const picojson::object& value,
                                const char* key,
                                std::string_view name) {
  const auto found = value.find(key);
  if (found == value.end())
    throw DecodeFailure(std::string(name) + "." + key + " is missing");
  return found->second;
}

std::string string(const picojson::object& value, const char* key,
                   std::string_view name) {
  const auto& item = required(value, key, name);
  if (!item.is<std::string>())
    throw DecodeFailure(std::string(name) + "." + key + " must be string");
  return item.get<std::string>();
}

bool boolean(const picojson::object& value, const char* key,
             std::string_view name) {
  const auto& item = required(value, key, name);
  if (!item.is<bool>())
    throw DecodeFailure(std::string(name) + "." + key + " must be boolean");
  return item.get<bool>();
}

std::int64_t integer(const picojson::object& value, const char* key,
                     std::string_view name) {
  const auto& item = required(value, key, name);
  if (!item.is<double>() || std::floor(item.get<double>()) != item.get<double>() ||
      item.get<double>() < -9007199254740991.0 ||
      item.get<double>() > 9007199254740991.0) {
    throw DecodeFailure(std::string(name) + "." + key + " must be safe integer");
  }
  return static_cast<std::int64_t>(item.get<double>());
}

std::optional<std::string> nullable_string(const picojson::object& value,
                                           const char* key,
                                           std::string_view name) {
  const auto& item = required(value, key, name);
  if (item.is<picojson::null>()) return std::nullopt;
  if (!item.is<std::string>())
    throw DecodeFailure(std::string(name) + "." + key + " must be string or null");
  return item.get<std::string>();
}

std::optional<std::int64_t> nullable_integer(const picojson::object& value,
                                             const char* key,
                                             std::string_view name) {
  const auto& item = required(value, key, name);
  if (item.is<picojson::null>()) return std::nullopt;
  return integer(value, key, name);
}

domain::LocalDate date(const picojson::object& value, const char* key,
                       std::string_view name) {
  auto parsed = domain::parse_local_date(string(value, key, name));
  if (!parsed.ok())
    throw DecodeFailure(std::string(name) + "." + key + " is invalid");
  return parsed.value();
}

std::optional<domain::LocalDate> nullable_date(const picojson::object& value,
                                                const char* key,
                                                std::string_view name) {
  auto text = nullable_string(value, key, name);
  if (!text.has_value()) return std::nullopt;
  auto parsed = domain::parse_local_date(*text);
  if (!parsed.ok())
    throw DecodeFailure(std::string(name) + "." + key + " is invalid");
  return parsed.value();
}

picojson::value nullable(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value nullable(const std::optional<std::int64_t>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

picojson::value nullable(const std::optional<domain::LocalDate>& value) {
  return value.has_value()
             ? picojson::value(domain::format_local_date(*value))
             : picojson::value();
}

picojson::value encode(const domain::HabitRecurrence& item) {
  picojson::object value;
  value["id"] = picojson::value(item.id);
  value["frequency"] = picojson::value(item.frequency);
  value["interval"] = picojson::value(static_cast<double>(item.interval));
  value["timezone_mode"] = picojson::value(item.timezone_mode);
  value["created_at"] = picojson::value(item.created_at);
  value["updated_at"] = picojson::value(item.updated_at);
  value["deleted_at"] = nullable(item.deleted_at);
  return picojson::value(std::move(value));
}

picojson::value encode(const domain::Habit& item) {
  picojson::object value;
  value["id"] = picojson::value(item.id);
  value["title"] = picojson::value(item.title);
  value["description"] = nullable(item.description);
  value["category_id"] = nullable(item.category_id);
  value["recurrence_id"] = picojson::value(item.recurrence_id);
  value["target_count_hundredths"] = nullable(item.target_count_hundredths);
  value["unit"] = nullable(item.unit);
  value["start_date"] = picojson::value(domain::format_local_date(item.start_date));
  value["end_date"] = picojson::value(domain::format_local_date(item.end_date));
  value["ended_date"] = nullable(item.ended_date);
  value["is_active"] = picojson::value(item.is_active);
  value["first_check_in_at"] = nullable(item.first_check_in_at);
  value["created_at"] = picojson::value(item.created_at);
  value["updated_at"] = picojson::value(item.updated_at);
  value["deleted_at"] = nullable(item.deleted_at);
  return picojson::value(std::move(value));
}

picojson::value encode(const domain::HabitCheckIn& item) {
  picojson::object value;
  value["id"] = picojson::value(item.id);
  value["habit_id"] = picojson::value(item.habit_id);
  value["check_date"] = picojson::value(domain::format_local_date(item.check_date));
  value["status"] = picojson::value(item.status);
  value["completed_count_hundredths"] = nullable(item.completed_count_hundredths);
  value["target_count_snapshot_hundredths"] =
      nullable(item.target_count_snapshot_hundredths);
  value["unit_snapshot"] = nullable(item.unit_snapshot);
  value["completed_at"] = nullable(item.completed_at);
  value["note"] = nullable(item.note);
  value["source"] = picojson::value(item.source);
  value["created_at"] = picojson::value(item.created_at);
  value["updated_at"] = picojson::value(item.updated_at);
  value["deleted_at"] = nullable(item.deleted_at);
  return picojson::value(std::move(value));
}

picojson::value encode(const domain::HabitReminderTemplate& item) {
  picojson::object value;
  value["template_key"] = picojson::value(item.template_key);
  value["habit_id"] = picojson::value(item.habit_id);
  value["local_time"] = picojson::value(item.local_time);
  value["timezone_mode"] = picojson::value(item.timezone_mode);
  value["method"] = picojson::value(item.method);
  value["is_enabled"] = picojson::value(item.is_enabled);
  value["created_at"] = picojson::value(item.created_at);
  value["updated_at"] = picojson::value(item.updated_at);
  value["deleted_at"] = nullable(item.deleted_at);
  return picojson::value(std::move(value));
}

domain::HabitRecurrence decode_recurrence(const picojson::value& source) {
  const auto& value = object(source, "HabitRecurrence");
  exact(value, {"id", "frequency", "interval", "timezone_mode", "created_at",
                "updated_at", "deleted_at"}, "HabitRecurrence");
  return domain::HabitRecurrence{
      string(value, "id", "HabitRecurrence"),
      string(value, "frequency", "HabitRecurrence"),
      static_cast<int>(integer(value, "interval", "HabitRecurrence")),
      string(value, "timezone_mode", "HabitRecurrence"),
      string(value, "created_at", "HabitRecurrence"),
      string(value, "updated_at", "HabitRecurrence"),
      nullable_string(value, "deleted_at", "HabitRecurrence")};
}

domain::Habit decode_habit(const picojson::value& source) {
  const auto& value = object(source, "Habit");
  exact(value, {"id", "title", "description", "category_id", "recurrence_id",
                "target_count_hundredths", "unit", "start_date", "end_date",
                "ended_date", "is_active", "first_check_in_at", "created_at",
                "updated_at", "deleted_at"}, "Habit");
  domain::Habit item;
  item.id = string(value, "id", "Habit");
  item.title = string(value, "title", "Habit");
  item.description = nullable_string(value, "description", "Habit");
  item.category_id = nullable_string(value, "category_id", "Habit");
  item.recurrence_id = string(value, "recurrence_id", "Habit");
  item.target_count_hundredths = nullable_integer(value, "target_count_hundredths", "Habit");
  item.unit = nullable_string(value, "unit", "Habit");
  item.start_date = date(value, "start_date", "Habit");
  item.end_date = date(value, "end_date", "Habit");
  item.ended_date = nullable_date(value, "ended_date", "Habit");
  item.is_active = boolean(value, "is_active", "Habit");
  item.first_check_in_at = nullable_string(value, "first_check_in_at", "Habit");
  item.created_at = string(value, "created_at", "Habit");
  item.updated_at = string(value, "updated_at", "Habit");
  item.deleted_at = nullable_string(value, "deleted_at", "Habit");
  return item;
}

domain::HabitCheckIn decode_check_in(const picojson::value& source) {
  const auto& value = object(source, "HabitCheckIn");
  exact(value, {"id", "habit_id", "check_date", "status",
                "completed_count_hundredths", "target_count_snapshot_hundredths",
                "unit_snapshot", "completed_at", "note", "source", "created_at",
                "updated_at", "deleted_at"}, "HabitCheckIn");
  domain::HabitCheckIn item;
  item.id = string(value, "id", "HabitCheckIn");
  item.habit_id = string(value, "habit_id", "HabitCheckIn");
  item.check_date = date(value, "check_date", "HabitCheckIn");
  item.status = string(value, "status", "HabitCheckIn");
  item.completed_count_hundredths =
      nullable_integer(value, "completed_count_hundredths", "HabitCheckIn");
  item.target_count_snapshot_hundredths = nullable_integer(
      value, "target_count_snapshot_hundredths", "HabitCheckIn");
  item.unit_snapshot = nullable_string(value, "unit_snapshot", "HabitCheckIn");
  item.completed_at = nullable_string(value, "completed_at", "HabitCheckIn");
  item.note = nullable_string(value, "note", "HabitCheckIn");
  item.source = string(value, "source", "HabitCheckIn");
  item.created_at = string(value, "created_at", "HabitCheckIn");
  item.updated_at = string(value, "updated_at", "HabitCheckIn");
  item.deleted_at = nullable_string(value, "deleted_at", "HabitCheckIn");
  return item;
}

domain::HabitReminderTemplate decode_template(const picojson::value& source) {
  const auto& value = object(source, "HabitReminderTemplate");
  exact(value, {"template_key", "habit_id", "local_time", "timezone_mode",
                "method", "is_enabled", "created_at", "updated_at", "deleted_at"},
        "HabitReminderTemplate");
  return domain::HabitReminderTemplate{
      string(value, "template_key", "HabitReminderTemplate"),
      string(value, "habit_id", "HabitReminderTemplate"),
      string(value, "local_time", "HabitReminderTemplate"),
      string(value, "timezone_mode", "HabitReminderTemplate"),
      string(value, "method", "HabitReminderTemplate"),
      boolean(value, "is_enabled", "HabitReminderTemplate"),
      string(value, "created_at", "HabitReminderTemplate"),
      string(value, "updated_at", "HabitReminderTemplate"),
      nullable_string(value, "deleted_at", "HabitReminderTemplate")};
}

}  // namespace

common::Result<picojson::value> encode_habit_store(
    std::string_view file_name, const repository::HabitState& state) {
  auto valid = validate_habit_state(state);
  if (!valid.ok()) return common::Result<picojson::value>::failure(valid.error());
  picojson::array items;
  std::string collection;
  if (file_name == "habit_recurrences.json") {
    collection = "habit_recurrences";
    for (const auto& item : state.recurrences) items.push_back(encode(item));
  } else if (file_name == "habits.json") {
    collection = "habits";
    for (const auto& item : state.habits) items.push_back(encode(item));
  } else if (file_name == "habit_check_ins.json") {
    collection = "habit_check_ins";
    for (const auto& item : state.check_ins) items.push_back(encode(item));
  } else if (file_name == "habit_reminder_templates.json") {
    collection = "habit_reminder_templates";
    for (const auto& item : state.reminder_templates) items.push_back(encode(item));
  } else {
    return common::Result<picojson::value>::failure(
        corrupted("unknown Habit Store", std::string(file_name)));
  }
  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root[collection] = picojson::value(std::move(items));
  return common::Result<picojson::value>::success(picojson::value(std::move(root)));
}

common::Result<common::Unit> decode_habit_store(
    std::string_view file_name, const picojson::value& root,
    repository::HabitState& state) {
  try {
    const auto& value = object(root, "HabitStore");
    std::string collection;
    if (file_name == "habit_recurrences.json") collection = "habit_recurrences";
    else if (file_name == "habits.json") collection = "habits";
    else if (file_name == "habit_check_ins.json") collection = "habit_check_ins";
    else if (file_name == "habit_reminder_templates.json")
      collection = "habit_reminder_templates";
    else throw DecodeFailure("unknown Habit Store");
    exact(value, {"storage_version", collection.c_str()}, "HabitStore");
    if (integer(value, "storage_version", "HabitStore") != 1)
      throw DecodeFailure("HabitStore.storage_version must be 1");
    const auto& records = required(value, collection.c_str(), "HabitStore");
    if (!records.is<picojson::array>()) throw DecodeFailure("HabitStore collection must be array");
    for (const auto& item : records.get<picojson::array>()) {
      if (collection == "habit_recurrences") state.recurrences.push_back(decode_recurrence(item));
      else if (collection == "habits") state.habits.push_back(decode_habit(item));
      else if (collection == "habit_check_ins") state.check_ins.push_back(decode_check_in(item));
      else state.reminder_templates.push_back(decode_template(item));
    }
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (const DecodeFailure& error) {
    return common::Result<common::Unit>::failure(corrupted(error.what()));
  }
}

}  // namespace excellent_calendar::storage::json
