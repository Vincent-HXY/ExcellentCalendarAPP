#include "excellent_calendar/storage/json/json_reminder_repository.hpp"

#include <cmath>
#include <limits>
#include <set>

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"

namespace excellent_calendar::storage::json {
namespace {

common::Error storage_corrupted(std::string reason, std::string field = "") {
  return storage_data_corrupted(std::move(reason), std::move(field));
}

common::Error reminder_not_found(std::string id) {
  return common::make_error(
      "REMINDER_NOT_FOUND",
      "Reminder not found",
      {{"id", std::move(id)}});
}

bool is_integer_number(double value) {
  return std::floor(value) == value;
}

const picojson::value* object_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return nullptr;
  }
  return &found->second;
}

common::Result<std::string> read_required_string(const picojson::object& object,
                                                 const std::string& key,
                                                 const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || !value->is<std::string>() || value->get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        storage_corrupted(parent + "." + key + " must be a non-empty string", parent + "." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> read_optional_string(const picojson::object& object,
                                                                const std::string& key,
                                                                const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        storage_corrupted(parent + "." + key + " must be a string or null", parent + "." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<bool> read_required_bool(const picojson::object& object,
                                        const std::string& key,
                                        const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || !value->is<bool>()) {
    return common::Result<bool>::failure(
        storage_corrupted(parent + "." + key + " must be boolean", parent + "." + key));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<std::optional<int>> read_optional_int(const picojson::object& object,
                                                     const std::string& key,
                                                     const std::string& parent) {
  const auto* value = object_field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || !is_integer_number(value->get<double>())) {
    return common::Result<std::optional<int>>::failure(
        storage_corrupted(parent + "." + key + " must be an integer or null", parent + "." + key));
  }
  const auto number = value->get<double>();
  if (number < 0 || number > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        storage_corrupted(parent + "." + key + " is out of range", parent + "." + key));
  }
  return common::Result<std::optional<int>>::success(static_cast<int>(number));
}

common::Result<std::vector<std::string>> read_methods(const picojson::object& object,
                                                      const std::string& parent) {
  const auto* value = object_field(object, "methods");
  if (value == nullptr || !value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        storage_corrupted(parent + ".methods must be an array", parent + ".methods"));
  }
  const auto& array = value->get<picojson::array>();
  if (array.empty()) {
    return common::Result<std::vector<std::string>>::failure(
        storage_corrupted(parent + ".methods must not be empty", parent + ".methods"));
  }

  std::set<std::string> seen;
  std::vector<std::string> methods;
  methods.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    if (!array[index].is<std::string>()) {
      return common::Result<std::vector<std::string>>::failure(
          storage_corrupted(parent + ".methods item must be string", parent + ".methods"));
    }
    const auto method = array[index].get<std::string>();
    if (!domain::is_valid_reminder_method(method)) {
      return common::Result<std::vector<std::string>>::failure(
          storage_corrupted(parent + ".methods item is invalid", parent + ".methods"));
    }
    if (!seen.insert(method).second) {
      return common::Result<std::vector<std::string>>::failure(
          storage_corrupted(parent + ".methods contains duplicate values", parent + ".methods"));
    }
    methods.push_back(method);
  }
  return common::Result<std::vector<std::string>>::success(std::move(methods));
}

bool optional_datetime_valid(const std::optional<std::string>& value) {
  return !value.has_value() || common::is_iso8601_utc_datetime(*value);
}

common::Result<domain::Reminder> parse_reminder_record(const picojson::value& value, std::size_t index) {
  const std::string parent = "reminders[" + std::to_string(index) + "]";
  if (!value.is<picojson::object>()) {
    return common::Result<domain::Reminder>::failure(storage_corrupted(parent + " must be object", parent));
  }
  const auto& object = value.get<picojson::object>();

  domain::Reminder reminder;

  auto id = read_required_string(object, "id", parent);
  if (!id.ok()) return common::Result<domain::Reminder>::failure(id.error());
  auto target_type = read_required_string(object, "target_type", parent);
  if (!target_type.ok()) return common::Result<domain::Reminder>::failure(target_type.error());
  auto target_id = read_required_string(object, "target_id", parent);
  if (!target_id.ok()) return common::Result<domain::Reminder>::failure(target_id.error());
  auto remind_at = read_required_string(object, "remind_at", parent);
  if (!remind_at.ok()) return common::Result<domain::Reminder>::failure(remind_at.error());
  auto methods = read_methods(object, parent);
  if (!methods.ok()) return common::Result<domain::Reminder>::failure(methods.error());
  auto is_enabled = read_required_bool(object, "is_enabled", parent);
  if (!is_enabled.ok()) return common::Result<domain::Reminder>::failure(is_enabled.error());
  auto status = read_required_string(object, "status", parent);
  if (!status.ok()) return common::Result<domain::Reminder>::failure(status.error());
  auto source = read_required_string(object, "source", parent);
  if (!source.ok()) return common::Result<domain::Reminder>::failure(source.error());
  auto created_at = read_required_string(object, "created_at", parent);
  if (!created_at.ok()) return common::Result<domain::Reminder>::failure(created_at.error());
  auto updated_at = read_required_string(object, "updated_at", parent);
  if (!updated_at.ok()) return common::Result<domain::Reminder>::failure(updated_at.error());

  auto advance_minutes = read_optional_int(object, "advance_minutes", parent);
  if (!advance_minutes.ok()) return common::Result<domain::Reminder>::failure(advance_minutes.error());
  auto message = read_optional_string(object, "message", parent);
  if (!message.ok()) return common::Result<domain::Reminder>::failure(message.error());
  auto scheduled_at = read_optional_string(object, "scheduled_at", parent);
  if (!scheduled_at.ok()) return common::Result<domain::Reminder>::failure(scheduled_at.error());
  auto last_triggered_at = read_optional_string(object, "last_triggered_at", parent);
  if (!last_triggered_at.ok()) return common::Result<domain::Reminder>::failure(last_triggered_at.error());
  auto failure_reason = read_optional_string(object, "failure_reason", parent);
  if (!failure_reason.ok()) return common::Result<domain::Reminder>::failure(failure_reason.error());
  auto cancellation_reason = read_optional_string(object, "cancellation_reason", parent);
  if (!cancellation_reason.ok()) return common::Result<domain::Reminder>::failure(cancellation_reason.error());
  auto deleted_at = read_optional_string(object, "deleted_at", parent);
  if (!deleted_at.ok()) return common::Result<domain::Reminder>::failure(deleted_at.error());

  reminder.id = id.value();
  reminder.target_type = target_type.value();
  reminder.target_id = target_id.value();
  reminder.remind_at = remind_at.value();
  reminder.methods = methods.value();
  reminder.advance_minutes = advance_minutes.value();
  reminder.message = message.value();
  reminder.is_enabled = is_enabled.value();
  reminder.status = status.value();
  reminder.scheduled_at = scheduled_at.value();
  reminder.last_triggered_at = last_triggered_at.value();
  reminder.failure_reason = failure_reason.value();
  reminder.cancellation_reason = cancellation_reason.value();
  reminder.source = source.value();
  reminder.created_at = created_at.value();
  reminder.updated_at = updated_at.value();
  reminder.deleted_at = deleted_at.value();

  if (!domain::is_valid_reminder_target_type(reminder.target_type)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored target_type is invalid", parent + ".target_type"));
  }
  if (!common::is_iso8601_utc_datetime(reminder.remind_at)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored remind_at is invalid", parent + ".remind_at"));
  }
  if (!domain::is_valid_reminder_status(reminder.status)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored status is invalid", parent + ".status"));
  }
  if (!domain::is_valid_reminder_source(reminder.source)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored source is invalid", parent + ".source"));
  }
  if (reminder.cancellation_reason.has_value() &&
      !domain::is_valid_reminder_cancellation_reason(*reminder.cancellation_reason)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored cancellation_reason is invalid", parent + ".cancellation_reason"));
  }
  if (!common::is_iso8601_utc_datetime(reminder.created_at)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored created_at is invalid", parent + ".created_at"));
  }
  if (!common::is_iso8601_utc_datetime(reminder.updated_at)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored updated_at is invalid", parent + ".updated_at"));
  }
  if (!optional_datetime_valid(reminder.scheduled_at) ||
      !optional_datetime_valid(reminder.last_triggered_at) ||
      !optional_datetime_valid(reminder.deleted_at)) {
    return common::Result<domain::Reminder>::failure(
        storage_corrupted("stored optional datetime is invalid", parent));
  }

  return common::Result<domain::Reminder>::success(std::move(reminder));
}

picojson::value optional_string_to_json(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(*value);
}

picojson::value optional_int_to_json(const std::optional<int>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(static_cast<double>(*value));
}

picojson::value reminder_to_storage_json(const domain::Reminder& reminder) {
  picojson::array methods;
  methods.reserve(reminder.methods.size());
  for (const auto& method : reminder.methods) {
    methods.push_back(picojson::value(method));
  }

  picojson::object object;
  object["id"] = picojson::value(reminder.id);
  object["target_type"] = picojson::value(reminder.target_type);
  object["target_id"] = picojson::value(reminder.target_id);
  object["remind_at"] = picojson::value(reminder.remind_at);
  object["methods"] = picojson::value(std::move(methods));
  object["advance_minutes"] = optional_int_to_json(reminder.advance_minutes);
  object["message"] = optional_string_to_json(reminder.message);
  object["is_enabled"] = picojson::value(reminder.is_enabled);
  object["status"] = picojson::value(reminder.status);
  object["scheduled_at"] = optional_string_to_json(reminder.scheduled_at);
  object["last_triggered_at"] = optional_string_to_json(reminder.last_triggered_at);
  object["failure_reason"] = optional_string_to_json(reminder.failure_reason);
  object["cancellation_reason"] = optional_string_to_json(reminder.cancellation_reason);
  object["source"] = picojson::value(reminder.source);
  object["created_at"] = picojson::value(reminder.created_at);
  object["updated_at"] = picojson::value(reminder.updated_at);
  object["deleted_at"] = optional_string_to_json(reminder.deleted_at);
  return picojson::value(object);
}

}  // namespace

JsonReminderRepository::JsonReminderRepository(
    std::filesystem::path storage_directory,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : store_(std::move(storage_directory)), runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonReminderRepository::initialize() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(
        storage::runtime_storage_revoked_error("reminder_repository.initialize"));
  }
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  return store_.initialize();
}

common::Result<domain::Reminder> JsonReminderRepository::create(const domain::Reminder& reminder) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<domain::Reminder>::failure(
        storage::runtime_storage_revoked_error("reminder_repository.create"));
  }
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_reminders_locked();
  if (!loaded.ok()) {
    return common::Result<domain::Reminder>::failure(loaded.error());
  }
  auto reminders = loaded.value();
  for (const auto& existing : reminders) {
    if (existing.id == reminder.id) {
      return common::Result<domain::Reminder>::failure(
          storage_corrupted("duplicate reminder id", "reminders.id"));
    }
  }
  reminders.push_back(reminder);

  auto saved = save_reminders_locked(reminders);
  if (!saved.ok()) {
    return common::Result<domain::Reminder>::failure(saved.error());
  }
  return common::Result<domain::Reminder>::success(reminder);
}

common::Result<std::optional<domain::Reminder>> JsonReminderRepository::find_by_id(std::string_view id) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<std::optional<domain::Reminder>>::failure(
        storage::runtime_storage_revoked_error("reminder_repository.find_by_id"));
  }
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_reminders_locked();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Reminder>>::failure(loaded.error());
  }
  for (const auto& reminder : loaded.value()) {
    if (reminder.id == std::string(id)) {
      return common::Result<std::optional<domain::Reminder>>::success(reminder);
    }
  }
  return common::Result<std::optional<domain::Reminder>>::success(std::nullopt);
}

common::Result<domain::Reminder> JsonReminderRepository::update(const domain::Reminder& reminder) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<domain::Reminder>::failure(
        storage::runtime_storage_revoked_error("reminder_repository.update"));
  }
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_reminders_locked();
  if (!loaded.ok()) {
    return common::Result<domain::Reminder>::failure(loaded.error());
  }
  auto reminders = loaded.value();
  bool replaced = false;
  for (auto& existing : reminders) {
    if (existing.id == reminder.id) {
      existing = reminder;
      replaced = true;
      break;
    }
  }
  if (!replaced) {
    return common::Result<domain::Reminder>::failure(reminder_not_found(reminder.id));
  }

  auto saved = save_reminders_locked(reminders);
  if (!saved.ok()) {
    return common::Result<domain::Reminder>::failure(saved.error());
  }
  return common::Result<domain::Reminder>::success(reminder);
}

common::Result<std::vector<domain::Reminder>> JsonReminderRepository::find_all() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        storage::runtime_storage_revoked_error("reminder_repository.find_all"));
  }
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  return load_reminders_locked();
}

common::Result<std::vector<domain::Reminder>> JsonReminderRepository::load_reminders_locked() {
  auto loaded = store_.read_json_file("reminders.json");
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::Reminder>>::failure(loaded.error());
  }
  if (!loaded.value().has_value()) {
    return common::Result<std::vector<domain::Reminder>>::success({});
  }

  const auto& root = *loaded.value();
  if (!root.is<picojson::object>()) {
    return common::Result<std::vector<domain::Reminder>>::failure(storage_corrupted("root must be object"));
  }
  const auto& object = root.get<picojson::object>();
  const auto* version = object_field(object, "storage_version");
  if (version == nullptr || !version->is<double>() || !is_integer_number(version->get<double>()) ||
      static_cast<int>(version->get<double>()) != 1) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        storage_corrupted("storage_version must be 1", "storage_version"));
  }
  const auto* reminders_value = object_field(object, "reminders");
  if (reminders_value == nullptr || !reminders_value->is<picojson::array>()) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        storage_corrupted("reminders must be array", "reminders"));
  }

  std::vector<domain::Reminder> reminders;
  const auto& array = reminders_value->get<picojson::array>();
  reminders.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    auto parsed = parse_reminder_record(array[index], index);
    if (!parsed.ok()) {
      return common::Result<std::vector<domain::Reminder>>::failure(parsed.error());
    }
    reminders.push_back(std::move(parsed.value()));
  }
  return common::Result<std::vector<domain::Reminder>>::success(std::move(reminders));
}

common::Result<common::Unit> JsonReminderRepository::save_reminders_locked(
    const std::vector<domain::Reminder>& reminders) {
  picojson::array reminder_array;
  reminder_array.reserve(reminders.size());
  for (const auto& reminder : reminders) {
    reminder_array.push_back(reminder_to_storage_json(reminder));
  }

  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["reminders"] = picojson::value(std::move(reminder_array));
  return store_.write_json_file("reminders.json", picojson::value(root));
}

}  // namespace excellent_calendar::storage::json
