#include "excellent_calendar/storage/json/calendar_core_v2_storage_bootstrap.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <limits>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {
namespace {

const std::set<std::string> kVersionedV1Files = {
    "events.json",
    "reminders.json",
    "notifications.json",
    "event_reminder_transaction.json",
    "reminder_notification_transaction.json",
};

const std::set<std::string> kVersionedV2Files = {
    "categories.json",
    "anniversaries.json",
    "anniversary_recurrences.json",
    "anniversary_workflow_transactions.json",
    "events.json",
    "recurrence_versions.json",
    "event_occurrence_states.json",
    "reminders.json",
    "notifications.json",
    "reminder_recovery_batches.json",
    "workflow_transactions.json",
};

common::Error path_invalid(std::string reason) {
  return common::make_error(
      "STORAGE_PATH_INVALID", "Storage path is invalid or not writable",
      {{"reason", std::move(reason)}});
}

common::Error io_error(std::string operation, std::string reason) {
  return common::make_error(
      "STORAGE_IO_ERROR", "Storage input/output operation failed",
      {{"operation", std::move(operation)}, {"reason", std::move(reason)}}, true);
}

common::Error corrupted(std::string reason) {
  return storage_data_corrupted(std::move(reason), "storage_directory");
}

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  return found == object.end() ? nullptr : &found->second;
}

bool is_integer_number(double value) {
  return std::isfinite(value) && std::floor(value) == value;
}

common::Result<picojson::value> read_json_document(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input.is_open()) {
    return common::Result<picojson::value>::failure(
        io_error("read", path.filename().generic_string() + " cannot be opened"));
  }
  std::stringstream buffer;
  buffer << input.rdbuf();
  if (input.bad()) {
    return common::Result<picojson::value>::failure(
        io_error("read", path.filename().generic_string() + " read failed"));
  }
  picojson::value root;
  const auto parse_error = picojson::parse(root, buffer.str());
  if (!parse_error.empty() || !root.is<picojson::object>()) {
    return common::Result<picojson::value>::failure(
        corrupted(path.filename().generic_string() + " is not a valid JSON object"));
  }
  return common::Result<picojson::value>::success(std::move(root));
}

common::Result<int> declared_storage_version(const picojson::value& root,
                                             std::string_view context) {
  const auto& object = root.get<picojson::object>();
  const auto version = object.find("storage_version");
  if (version == object.end() || !version->second.is<double>() ||
      !is_integer_number(version->second.get<double>())) {
    return common::Result<int>::failure(
        corrupted(std::string(context) + " has no integer storage_version"));
  }
  const double value = version->second.get<double>();
  if (value != 1.0 && value != 2.0) {
    return common::Result<int>::failure(
        corrupted(std::string(context) + " has an unsupported storage_version"));
  }
  return common::Result<int>::success(static_cast<int>(value));
}

common::Result<std::string> required_string(const picojson::object& object,
                                            const std::string& key,
                                            const std::string& context) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<std::string>() || value->get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        corrupted(context + "." + key + " must be a non-empty string"));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> optional_string(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        corrupted(context + "." + key + " must be a string or null"));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

common::Result<bool> required_bool(const picojson::object& object,
                                   const std::string& key,
                                   const std::string& context) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<bool>()) {
    return common::Result<bool>::failure(
        corrupted(context + "." + key + " must be boolean"));
  }
  return common::Result<bool>::success(value->get<bool>());
}

common::Result<std::optional<int>> optional_non_negative_int(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || !is_integer_number(value->get<double>()) ||
      value->get<double>() < 0.0 ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        corrupted(context + "." + key + " must be a non-negative integer or null"));
  }
  return common::Result<std::optional<int>>::success(
      static_cast<int>(value->get<double>()));
}

common::Result<common::Unit> require_utc_datetime(std::string_view value,
                                                  const std::string& context) {
  if (!common::is_iso8601_utc_datetime(value)) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " must be an ISO 8601 UTC datetime"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_optional_utc_datetime(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  auto value = optional_string(object, key, context);
  if (!value.ok()) {
    return common::Result<common::Unit>::failure(value.error());
  }
  if (value.value().has_value()) {
    return require_utc_datetime(*value.value(), context + "." + key);
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_event_record(const picojson::value& value,
                                                    const std::string& context) {
  if (!value.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " must be object"));
  }
  const auto& object = value.get<picojson::object>();
  const std::vector<std::string> required_strings = {
      "id", "title", "start_at", "end_at", "status", "source", "created_at", "updated_at"};
  for (const auto& key : required_strings) {
    auto checked = required_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }
  for (const auto& key : {"is_all_day", "has_recurrence"}) {
    auto checked = required_bool(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }
  for (const auto& key : {"content", "completed_at", "recurrence_id", "category_id",
                          "importance", "location", "timezone", "deleted_at"}) {
    auto checked = optional_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }

  for (const auto& key : {"start_at", "end_at", "created_at", "updated_at"}) {
    auto checked = require_utc_datetime(field(object, key)->get<std::string>(),
                                        context + "." + key);
    if (!checked.ok()) return checked;
  }
  for (const auto& key : {"completed_at", "deleted_at"}) {
    auto checked = validate_optional_utc_datetime(object, key, context);
    if (!checked.ok()) return checked;
  }
  if (!domain::is_valid_event_status(field(object, "status")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".status has an unsupported value"));
  }
  if (!domain::is_valid_create_event_source(field(object, "source")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".source has an unsupported value"));
  }
  auto importance = optional_string(object, "importance", context);
  if (importance.value().has_value() && !domain::is_valid_importance(*importance.value())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".importance has an unsupported value"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_reminder_methods(const picojson::object& object,
                                                       const std::string& context) {
  const auto* methods = field(object, "methods");
  if (methods == nullptr || !methods->is<picojson::array>() ||
      methods->get<picojson::array>().empty()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".methods must be a non-empty array"));
  }
  std::set<std::string> unique;
  for (const auto& item : methods->get<picojson::array>()) {
    if (!item.is<std::string>() ||
        !domain::is_valid_reminder_method(item.get<std::string>()) ||
        !unique.insert(item.get<std::string>()).second) {
      return common::Result<common::Unit>::failure(
          corrupted(context + ".methods contains an invalid or duplicate value"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

// These sets describe the discarded v1 wire/storage format. Keep them independent
// from the evolving v2 domain validators so new v2 values cannot make a v1
// directory look valid during the destructive discard gate.
bool is_valid_v1_reminder_status(std::string_view value) {
  return value == "pending" || value == "scheduled" || value == "sent" ||
         value == "failed" || value == "cancelled";
}

bool is_valid_v1_reminder_cancellation_reason(std::string_view value) {
  return value == "user_cancelled" || value == "event_completed";
}

common::Result<common::Unit> validate_reminder_record(const picojson::value& value,
                                                       const std::string& context) {
  if (!value.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " must be object"));
  }
  const auto& object = value.get<picojson::object>();
  const std::vector<std::string> required_strings = {
      "id", "target_type", "target_id", "remind_at", "status", "source", "created_at",
      "updated_at"};
  for (const auto& key : required_strings) {
    auto checked = required_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }
  auto enabled = required_bool(object, "is_enabled", context);
  if (!enabled.ok()) return common::Result<common::Unit>::failure(enabled.error());
  auto methods = validate_reminder_methods(object, context);
  if (!methods.ok()) return methods;
  auto advance = optional_non_negative_int(object, "advance_minutes", context);
  if (!advance.ok()) return common::Result<common::Unit>::failure(advance.error());
  for (const auto& key : {"message", "scheduled_at", "last_triggered_at", "failure_reason",
                          "cancellation_reason", "deleted_at"}) {
    auto checked = optional_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }

  if (!domain::is_valid_reminder_target_type(
          field(object, "target_type")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".target_type has an unsupported value"));
  }
  if (!is_valid_v1_reminder_status(field(object, "status")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".status has an unsupported value"));
  }
  if (!domain::is_valid_reminder_source(field(object, "source")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".source has an unsupported value"));
  }
  auto cancellation_reason = optional_string(object, "cancellation_reason", context);
  if (cancellation_reason.value().has_value() &&
      !is_valid_v1_reminder_cancellation_reason(*cancellation_reason.value())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".cancellation_reason has an unsupported value"));
  }
  for (const auto& key : {"remind_at", "created_at", "updated_at"}) {
    auto checked = require_utc_datetime(field(object, key)->get<std::string>(),
                                        context + "." + key);
    if (!checked.ok()) return checked;
  }
  for (const auto& key : {"scheduled_at", "last_triggered_at", "deleted_at"}) {
    auto checked = validate_optional_utc_datetime(object, key, context);
    if (!checked.ok()) return checked;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_notification_record(const picojson::value& value,
                                                           const std::string& context) {
  if (!value.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " must be object"));
  }
  const auto& object = value.get<picojson::object>();
  const std::vector<std::string> required_strings = {
      "id", "target_type", "target_id", "method", "title", "planned_at", "status",
      "created_at", "updated_at"};
  for (const auto& key : required_strings) {
    auto checked = required_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }
  for (const auto& key : {"reminder_id", "body", "sent_at", "failure_reason"}) {
    auto checked = optional_string(object, key, context);
    if (!checked.ok()) {
      return common::Result<common::Unit>::failure(checked.error());
    }
  }
  const auto reminder_id = optional_string(object, "reminder_id", context).value();
  if (reminder_id.has_value() && reminder_id->empty()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".reminder_id must be non-empty when present"));
  }
  if (!domain::is_valid_notification_target_type(
          field(object, "target_type")->get<std::string>()) ||
      !domain::is_valid_reminder_method(field(object, "method")->get<std::string>()) ||
      !domain::is_valid_notification_status(field(object, "status")->get<std::string>())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " contains an unsupported enum value"));
  }
  for (const auto& key : {"planned_at", "created_at", "updated_at"}) {
    auto checked = require_utc_datetime(field(object, key)->get<std::string>(),
                                        context + "." + key);
    if (!checked.ok()) return checked;
  }
  auto sent_at = validate_optional_utc_datetime(object, "sent_at", context);
  if (!sent_at.ok()) return sent_at;

  const auto status = field(object, "status")->get<std::string>();
  const auto sent = optional_string(object, "sent_at", context).value();
  const auto failure = optional_string(object, "failure_reason", context).value();
  if (status == std::string(domain::kNotificationStatusSent) &&
      (!sent.has_value() || failure.has_value())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " has inconsistent sent fields"));
  }
  if (status == std::string(domain::kNotificationStatusFailed) &&
      (!failure.has_value() || failure->empty())) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " failed status requires failure_reason"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

enum class V1DataKind { kEvents, kReminders, kNotifications };

std::string_view collection_name(V1DataKind kind) {
  switch (kind) {
    case V1DataKind::kEvents:
      return "events";
    case V1DataKind::kReminders:
      return "reminders";
    case V1DataKind::kNotifications:
      return "notifications";
  }
  return "";
}

common::Result<common::Unit> validate_v1_data_root(const picojson::value& root,
                                                   V1DataKind kind,
                                                   const std::string& context) {
  if (!root.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " root must be object"));
  }
  auto version = declared_storage_version(root, context);
  if (!version.ok()) return common::Result<common::Unit>::failure(version.error());
  if (version.value() != 1) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " snapshot must declare storage_version 1"));
  }
  const auto& object = root.get<picojson::object>();
  const std::string collection(collection_name(kind));
  const auto* records = field(object, collection);
  if (records == nullptr || !records->is<picojson::array>()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + "." + collection + " must be array"));
  }
  const auto& array = records->get<picojson::array>();
  for (std::size_t index = 0; index < array.size(); ++index) {
    const auto record_context = context + "." + collection + "[" + std::to_string(index) + "]";
    common::Result<common::Unit> validated =
        common::Result<common::Unit>::failure(corrupted(record_context + " was not validated"));
    switch (kind) {
      case V1DataKind::kEvents:
        validated = validate_event_record(array[index], record_context);
        break;
      case V1DataKind::kReminders:
        validated = validate_reminder_record(array[index], record_context);
        break;
      case V1DataKind::kNotifications:
        validated = validate_notification_record(array[index], record_context);
        break;
    }
    if (!validated.ok()) return validated;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_snapshot_member(const picojson::object& journal,
                                                      const std::string& prefix,
                                                      V1DataKind kind,
                                                      const std::string& context) {
  const auto* exists = field(journal, prefix + "_exists");
  const auto* content = field(journal, prefix);
  if (exists == nullptr || !exists->is<bool>() || content == nullptr) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " has an invalid " + prefix + " snapshot entry"));
  }
  if (!exists->get<bool>()) {
    if (!content->is<picojson::null>()) {
      return common::Result<common::Unit>::failure(
          corrupted(context + "." + prefix + " must be null when it did not exist"));
    }
    return common::Result<common::Unit>::success(common::Unit{});
  }
  if (content->is<picojson::null>()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + "." + prefix + " snapshot content is missing"));
  }
  return validate_v1_data_root(*content, kind, context + "." + prefix);
}

common::Result<common::Unit> validate_event_reminder_journal(const picojson::value& root,
                                                             const std::string& context) {
  if (!root.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " root must be object"));
  }
  auto version = declared_storage_version(root, context);
  if (!version.ok()) return common::Result<common::Unit>::failure(version.error());
  if (version.value() != 1) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " must declare storage_version 1"));
  }
  const auto& object = root.get<picojson::object>();
  auto events = validate_snapshot_member(object, "events", V1DataKind::kEvents, context);
  if (!events.ok()) return events;
  return validate_snapshot_member(object, "reminders", V1DataKind::kReminders, context);
}

common::Result<common::Unit> validate_reminder_notification_journal(
    const picojson::value& root,
    const std::string& context) {
  if (!root.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(corrupted(context + " root must be object"));
  }
  auto version = declared_storage_version(root, context);
  if (!version.ok()) return common::Result<common::Unit>::failure(version.error());
  if (version.value() != 1) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " must declare storage_version 1"));
  }
  const auto& object = root.get<picojson::object>();
  const auto* files = field(object, "files");
  if (files == nullptr || !files->is<picojson::array>()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + ".files must be array"));
  }

  std::set<std::string> expected = {"reminders.json", "notifications.json"};
  for (std::size_t index = 0; index < files->get<picojson::array>().size(); ++index) {
    const auto& value = files->get<picojson::array>()[index];
    const auto item_context = context + ".files[" + std::to_string(index) + "]";
    if (!value.is<picojson::object>()) {
      return common::Result<common::Unit>::failure(corrupted(item_context + " must be object"));
    }
    const auto& item = value.get<picojson::object>();
    const auto* name = field(item, "name");
    const auto* exists = field(item, "exists");
    const auto* content = field(item, "content");
    if (name == nullptr || !name->is<std::string>() || exists == nullptr ||
        !exists->is<bool>() || content == nullptr) {
      return common::Result<common::Unit>::failure(
          corrupted(item_context + " has an invalid file snapshot entry"));
    }
    const auto file_name = name->get<std::string>();
    if (expected.erase(file_name) != 1U) {
      return common::Result<common::Unit>::failure(
          corrupted(item_context + " contains an unexpected or duplicate file name"));
    }
    if (!exists->get<bool>()) {
      if (!content->is<picojson::null>()) {
        return common::Result<common::Unit>::failure(
            corrupted(item_context + ".content must be null when the file did not exist"));
      }
      continue;
    }
    if (content->is<picojson::null>()) {
      return common::Result<common::Unit>::failure(
          corrupted(item_context + ".content is missing"));
    }
    const auto kind = file_name == "reminders.json" ? V1DataKind::kReminders
                                                     : V1DataKind::kNotifications;
    auto validated = validate_v1_data_root(*content, kind, item_context + ".content");
    if (!validated.ok()) return validated;
  }
  if (!expected.empty()) {
    return common::Result<common::Unit>::failure(
        corrupted(context + " transaction snapshot is incomplete"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> validate_v1_file(const std::string& name,
                                              const picojson::value& root) {
  if (name == "events.json") {
    return validate_v1_data_root(root, V1DataKind::kEvents, name);
  }
  if (name == "reminders.json") {
    return validate_v1_data_root(root, V1DataKind::kReminders, name);
  }
  if (name == "notifications.json") {
    return validate_v1_data_root(root, V1DataKind::kNotifications, name);
  }
  if (name == "event_reminder_transaction.json") {
    return validate_event_reminder_journal(root, name);
  }
  if (name == "reminder_notification_transaction.json") {
    return validate_reminder_notification_journal(root, name);
  }
  return common::Result<common::Unit>::failure(
      corrupted(name + " is not a recognized v1 Calendar Core file"));
}

}  // namespace

common::Result<CalendarCoreV2StoragePreparation> prepare_calendar_core_v2_storage(
    const std::filesystem::path& active_directory) {
  if (active_directory.empty()) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        path_invalid("path is empty"));
  }

  // Coordinate with every JSON repository using this directory so the source
  // cannot change between the read-only validation and the directory removal.
  AtomicJsonFileStore lock_owner(active_directory);
  auto directory_lock = lock_owner.acquire_directory_lock();

  std::error_code exists_error;
  const bool exists = std::filesystem::exists(active_directory, exists_error);
  if (exists_error) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        io_error("exists", exists_error.message()));
  }
  if (!exists) {
    return common::Result<CalendarCoreV2StoragePreparation>::success({});
  }

  std::error_code type_error;
  if (!std::filesystem::is_directory(active_directory, type_error) || type_error) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        path_invalid(type_error ? type_error.message() : "path is not a directory"));
  }

  bool has_entry = false;
  bool has_v1 = false;
  bool has_v2 = false;
  std::error_code iterate_error;
  for (std::filesystem::directory_iterator iterator(active_directory, iterate_error), end;
       iterator != end && !iterate_error;
       iterator.increment(iterate_error)) {
    has_entry = true;
    std::error_code regular_error;
    if (!iterator->is_regular_file(regular_error)) {
      if (regular_error) {
        return common::Result<CalendarCoreV2StoragePreparation>::failure(
            io_error("inspect", regular_error.message()));
      }
      continue;
    }
    const auto name = iterator->path().filename().generic_string();
    if (kVersionedV1Files.count(name) == 0U && kVersionedV2Files.count(name) == 0U) {
      continue;
    }
    auto document = read_json_document(iterator->path());
    if (!document.ok()) {
      return common::Result<CalendarCoreV2StoragePreparation>::failure(document.error());
    }
    auto version = declared_storage_version(document.value(), name);
    if (!version.ok()) {
      return common::Result<CalendarCoreV2StoragePreparation>::failure(version.error());
    }
    has_v1 = has_v1 || version.value() == 1;
    has_v2 = has_v2 || version.value() == 2;
    if ((version.value() == 1 && kVersionedV1Files.count(name) == 0U) ||
        (version.value() == 2 && kVersionedV2Files.count(name) == 0U)) {
      return common::Result<CalendarCoreV2StoragePreparation>::failure(
          corrupted("storage file set does not match its declared version"));
    }
    if (version.value() == 1) {
      auto validated = validate_v1_file(name, document.value());
      if (!validated.ok()) {
        return common::Result<CalendarCoreV2StoragePreparation>::failure(validated.error());
      }
    }
  }
  if (iterate_error) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        io_error("enumerate", iterate_error.message()));
  }
  if (!has_entry) {
    return common::Result<CalendarCoreV2StoragePreparation>::success({});
  }
  if (has_v1 && has_v2) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        corrupted("mixed v1 and v2 Calendar Core storage is forbidden"));
  }
  if (has_v2) {
    return common::Result<CalendarCoreV2StoragePreparation>::success({});
  }
  if (!has_v1) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        corrupted("non-empty directory is not a confirmed Calendar Core store"));
  }

  std::error_code remove_error;
  std::filesystem::remove_all(active_directory, remove_error);
  if (remove_error) {
    return common::Result<CalendarCoreV2StoragePreparation>::failure(
        io_error("discard", remove_error.message()));
  }
  CalendarCoreV2StoragePreparation result;
  result.discarded_v1 = true;
  return common::Result<CalendarCoreV2StoragePreparation>::success(std::move(result));
}

}  // namespace excellent_calendar::storage::json
