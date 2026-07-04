#include "excellent_calendar/storage/json/json_notification_repository.hpp"

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/notification.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::storage::json {
namespace {

const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  return found == object.end() ? nullptr : &found->second;
}

common::Result<std::string> required_string(const picojson::object& object,
                                            const std::string& key,
                                            const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || !value->is<std::string>() || value->get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        storage_data_corrupted(parent + "." + key + " must be a non-empty string", parent + "." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

common::Result<std::optional<std::string>> optional_string(const picojson::object& object,
                                                           const std::string& key,
                                                           const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        storage_data_corrupted(parent + "." + key + " must be a string or null", parent + "." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

bool optional_datetime_valid(const std::optional<std::string>& value) {
  return !value.has_value() || common::is_iso8601_utc_datetime(*value);
}

common::Result<domain::Notification> parse_notification(const picojson::value& value,
                                                        std::size_t index) {
  const auto parent = "notifications[" + std::to_string(index) + "]";
  if (!value.is<picojson::object>()) {
    return common::Result<domain::Notification>::failure(
        storage_data_corrupted(parent + " must be object", parent));
  }
  const auto& object = value.get<picojson::object>();
  auto id = required_string(object, "id", parent);
  auto reminder_id = optional_string(object, "reminder_id", parent);
  auto target_type = required_string(object, "target_type", parent);
  auto target_id = required_string(object, "target_id", parent);
  auto method = required_string(object, "method", parent);
  auto title = required_string(object, "title", parent);
  auto body = optional_string(object, "body", parent);
  auto planned_at = required_string(object, "planned_at", parent);
  auto sent_at = optional_string(object, "sent_at", parent);
  auto status = required_string(object, "status", parent);
  auto failure_reason = optional_string(object, "failure_reason", parent);
  auto created_at = required_string(object, "created_at", parent);
  auto updated_at = required_string(object, "updated_at", parent);
  if (!id.ok()) return common::Result<domain::Notification>::failure(id.error());
  if (!reminder_id.ok()) return common::Result<domain::Notification>::failure(reminder_id.error());
  if (!target_type.ok()) return common::Result<domain::Notification>::failure(target_type.error());
  if (!target_id.ok()) return common::Result<domain::Notification>::failure(target_id.error());
  if (!method.ok()) return common::Result<domain::Notification>::failure(method.error());
  if (!title.ok()) return common::Result<domain::Notification>::failure(title.error());
  if (!body.ok()) return common::Result<domain::Notification>::failure(body.error());
  if (!planned_at.ok()) return common::Result<domain::Notification>::failure(planned_at.error());
  if (!sent_at.ok()) return common::Result<domain::Notification>::failure(sent_at.error());
  if (!status.ok()) return common::Result<domain::Notification>::failure(status.error());
  if (!failure_reason.ok()) return common::Result<domain::Notification>::failure(failure_reason.error());
  if (!created_at.ok()) return common::Result<domain::Notification>::failure(created_at.error());
  if (!updated_at.ok()) return common::Result<domain::Notification>::failure(updated_at.error());

  domain::Notification notification;
  notification.id = id.value();
  notification.reminder_id = reminder_id.value();
  notification.target_type = target_type.value();
  notification.target_id = target_id.value();
  notification.method = method.value();
  notification.title = title.value();
  notification.body = body.value();
  notification.planned_at = planned_at.value();
  notification.sent_at = sent_at.value();
  notification.status = status.value();
  notification.failure_reason = failure_reason.value();
  notification.created_at = created_at.value();
  notification.updated_at = updated_at.value();

  if ((notification.reminder_id.has_value() && notification.reminder_id->empty()) ||
      !domain::is_valid_notification_target_type(notification.target_type) ||
      !domain::is_valid_reminder_method(notification.method) ||
      !domain::is_valid_notification_status(notification.status) ||
      !common::is_iso8601_utc_datetime(notification.planned_at) ||
      !optional_datetime_valid(notification.sent_at) ||
      !common::is_iso8601_utc_datetime(notification.created_at) ||
      !common::is_iso8601_utc_datetime(notification.updated_at)) {
    return common::Result<domain::Notification>::failure(
        storage_data_corrupted("stored notification contains invalid values", parent));
  }
  if (notification.status == std::string(domain::kNotificationStatusSent) &&
      (!notification.sent_at.has_value() || notification.failure_reason.has_value())) {
    return common::Result<domain::Notification>::failure(
        storage_data_corrupted("stored sent notification fields are inconsistent", parent));
  }
  if (notification.status == std::string(domain::kNotificationStatusFailed) &&
      (!notification.failure_reason.has_value() || notification.failure_reason->empty())) {
    return common::Result<domain::Notification>::failure(
        storage_data_corrupted("stored failed notification requires failure_reason", parent));
  }
  return common::Result<domain::Notification>::success(std::move(notification));
}

picojson::value optional_to_json(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value to_json(const domain::Notification& notification) {
  picojson::object object;
  object["id"] = picojson::value(notification.id);
  object["reminder_id"] = optional_to_json(notification.reminder_id);
  object["target_type"] = picojson::value(notification.target_type);
  object["target_id"] = picojson::value(notification.target_id);
  object["method"] = picojson::value(notification.method);
  object["title"] = picojson::value(notification.title);
  object["body"] = optional_to_json(notification.body);
  object["planned_at"] = picojson::value(notification.planned_at);
  object["sent_at"] = optional_to_json(notification.sent_at);
  object["status"] = picojson::value(notification.status);
  object["failure_reason"] = optional_to_json(notification.failure_reason);
  object["created_at"] = picojson::value(notification.created_at);
  object["updated_at"] = picojson::value(notification.updated_at);
  return picojson::value(std::move(object));
}

}  // namespace

JsonNotificationRepository::JsonNotificationRepository(std::filesystem::path storage_directory)
    : store_(std::move(storage_directory)) {}

common::Result<common::Unit> JsonNotificationRepository::initialize() {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  return store_.initialize();
}

common::Result<domain::Notification> JsonNotificationRepository::create(
    const domain::Notification& notification) {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  auto loaded = load_notifications_locked();
  if (!loaded.ok()) return common::Result<domain::Notification>::failure(loaded.error());
  auto notifications = loaded.value();
  for (const auto& existing : notifications) {
    if (existing.id == notification.id) {
      return common::Result<domain::Notification>::failure(
          storage_data_corrupted("duplicate notification id", "notifications.id"));
    }
  }
  notifications.push_back(notification);
  auto saved = save_notifications_locked(notifications);
  if (!saved.ok()) return common::Result<domain::Notification>::failure(saved.error());
  return common::Result<domain::Notification>::success(notification);
}

common::Result<std::optional<domain::Notification>>
JsonNotificationRepository::find_sent_by_reminder_id(std::string_view reminder_id) {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  auto loaded = load_notifications_locked();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Notification>>::failure(loaded.error());
  }
  for (auto it = loaded.value().rbegin(); it != loaded.value().rend(); ++it) {
    if (it->reminder_id == std::optional<std::string>(std::string(reminder_id)) &&
        it->status == std::string(domain::kNotificationStatusSent)) {
      return common::Result<std::optional<domain::Notification>>::success(*it);
    }
  }
  return common::Result<std::optional<domain::Notification>>::success(std::nullopt);
}

common::Result<std::vector<domain::Notification>> JsonNotificationRepository::find_all() {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  return load_notifications_locked();
}

common::Result<std::vector<domain::Notification>>
JsonNotificationRepository::load_notifications_locked() {
  auto loaded = store_.read_json_file("notifications.json");
  if (!loaded.ok()) return common::Result<std::vector<domain::Notification>>::failure(loaded.error());
  if (!loaded.value().has_value()) {
    return common::Result<std::vector<domain::Notification>>::success({});
  }
  if (!loaded.value()->is<picojson::object>()) {
    return common::Result<std::vector<domain::Notification>>::failure(
        storage_data_corrupted("root must be object"));
  }
  const auto& root = loaded.value()->get<picojson::object>();
  const auto* version = field(root, "storage_version");
  const auto* values = field(root, "notifications");
  if (version == nullptr || !version->is<double>() || version->get<double>() != 1.0 ||
      values == nullptr || !values->is<picojson::array>()) {
    return common::Result<std::vector<domain::Notification>>::failure(
        storage_data_corrupted("notification storage schema is invalid"));
  }
  std::vector<domain::Notification> notifications;
  const auto& array = values->get<picojson::array>();
  notifications.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    auto parsed = parse_notification(array[index], index);
    if (!parsed.ok()) {
      return common::Result<std::vector<domain::Notification>>::failure(parsed.error());
    }
    notifications.push_back(std::move(parsed.value()));
  }
  return common::Result<std::vector<domain::Notification>>::success(std::move(notifications));
}

common::Result<common::Unit> JsonNotificationRepository::save_notifications_locked(
    const std::vector<domain::Notification>& notifications) {
  picojson::array array;
  array.reserve(notifications.size());
  for (const auto& notification : notifications) array.push_back(to_json(notification));
  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["notifications"] = picojson::value(std::move(array));
  return store_.write_json_file("notifications.json", picojson::value(std::move(root)));
}

}  // namespace excellent_calendar::storage::json
