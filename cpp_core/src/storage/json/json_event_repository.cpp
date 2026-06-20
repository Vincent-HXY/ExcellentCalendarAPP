#include "excellent_calendar/storage/json/json_event_repository.hpp"

#include <cmath>

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/event_status.hpp"
#include "excellent_calendar/domain/importance.hpp"

namespace excellent_calendar::storage::json {
namespace {

// 本文件匿名 namespace 中的工具函数只服务 JSON 仓库实现，不暴露给其他模块。

/** 存储文件内容格式不符合预期，通常表示 events.json 被破坏或版本不兼容。 */
common::Error storage_corrupted(std::string reason, std::string field = "") {
  return storage_data_corrupted(std::move(reason), std::move(field));
}

/** picojson 的 number 是 double；这里判断 double 是否实际表示整数。 */
bool is_integer_number(double value) {
  return std::floor(value) == value;
}

/** 从 JSON object 中取字段，不存在返回 nullptr，避免直接下标访问产生默认值。 */
const picojson::value* object_field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return nullptr;
  }
  return &found->second;
}

/** 读取必填非空字符串字段。 */
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

/** 读取可选字符串字段；缺失/null 都映射为 std::nullopt。 */
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

/** 读取必填布尔字段。 */
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

/**
 * 把 events.json 中的一条记录解析成 domain::Event。
 *
 * 这里不仅检查 JSON 类型，还会校验时间格式、状态、来源、importance 等值域。
 * 这样损坏数据不会悄悄进入业务层。
 */
common::Result<domain::Event> parse_event_record(const picojson::value& value, std::size_t index) {
  const std::string parent = "events[" + std::to_string(index) + "]";
  if (!value.is<picojson::object>()) {
    return common::Result<domain::Event>::failure(storage_corrupted(parent + " must be object", parent));
  }
  const auto& object = value.get<picojson::object>();

  domain::Event event;

  // required 字段读取失败就立即返回错误；这种早返回写法能保持后续逻辑只处理有效数据。
  auto id = read_required_string(object, "id", parent);
  if (!id.ok()) return common::Result<domain::Event>::failure(id.error());
  auto title = read_required_string(object, "title", parent);
  if (!title.ok()) return common::Result<domain::Event>::failure(title.error());
  auto start_at = read_required_string(object, "start_at", parent);
  if (!start_at.ok()) return common::Result<domain::Event>::failure(start_at.error());
  auto end_at = read_required_string(object, "end_at", parent);
  if (!end_at.ok()) return common::Result<domain::Event>::failure(end_at.error());
  auto status = read_required_string(object, "status", parent);
  if (!status.ok()) return common::Result<domain::Event>::failure(status.error());
  auto source = read_required_string(object, "source", parent);
  if (!source.ok()) return common::Result<domain::Event>::failure(source.error());
  auto created_at = read_required_string(object, "created_at", parent);
  if (!created_at.ok()) return common::Result<domain::Event>::failure(created_at.error());
  auto updated_at = read_required_string(object, "updated_at", parent);
  if (!updated_at.ok()) return common::Result<domain::Event>::failure(updated_at.error());

  event.id = id.value();
  event.title = title.value();
  event.start_at = start_at.value();
  event.end_at = end_at.value();
  event.status = status.value();
  event.source = source.value();
  event.created_at = created_at.value();
  event.updated_at = updated_at.value();

  // optional 字段使用 optional<string>，JSON null 和字段缺失都会变成 std::nullopt。
  auto content = read_optional_string(object, "content", parent);
  if (!content.ok()) return common::Result<domain::Event>::failure(content.error());
  auto completed_at = read_optional_string(object, "completed_at", parent);
  if (!completed_at.ok()) return common::Result<domain::Event>::failure(completed_at.error());
  auto recurrence_id = read_optional_string(object, "recurrence_id", parent);
  if (!recurrence_id.ok()) return common::Result<domain::Event>::failure(recurrence_id.error());
  auto category_id = read_optional_string(object, "category_id", parent);
  if (!category_id.ok()) return common::Result<domain::Event>::failure(category_id.error());
  auto importance = read_optional_string(object, "importance", parent);
  if (!importance.ok()) return common::Result<domain::Event>::failure(importance.error());
  auto location = read_optional_string(object, "location", parent);
  if (!location.ok()) return common::Result<domain::Event>::failure(location.error());
  auto timezone = read_optional_string(object, "timezone", parent);
  if (!timezone.ok()) return common::Result<domain::Event>::failure(timezone.error());
  auto deleted_at = read_optional_string(object, "deleted_at", parent);
  if (!deleted_at.ok()) return common::Result<domain::Event>::failure(deleted_at.error());
  auto is_all_day = read_required_bool(object, "is_all_day", parent);
  if (!is_all_day.ok()) return common::Result<domain::Event>::failure(is_all_day.error());
  auto has_recurrence = read_required_bool(object, "has_recurrence", parent);
  if (!has_recurrence.ok()) return common::Result<domain::Event>::failure(has_recurrence.error());

  event.content = content.value();
  event.completed_at = completed_at.value();
  event.recurrence_id = recurrence_id.value();
  event.category_id = category_id.value();
  event.importance = importance.value();
  event.location = location.value();
  event.timezone = timezone.value();
  event.deleted_at = deleted_at.value();
  event.is_all_day = is_all_day.value();
  event.has_recurrence = has_recurrence.value();

  // 读取完成后做业务值域校验。
  if (!common::is_iso8601_utc_datetime(event.start_at)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored start_at is invalid", parent + ".start_at"));
  }
  if (!common::is_iso8601_utc_datetime(event.end_at)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored end_at is invalid", parent + ".end_at"));
  }
  if (!domain::is_valid_event_status(event.status)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored status is invalid", parent + ".status"));
  }
  if (!domain::is_valid_create_event_source(event.source)) {
    return common::Result<domain::Event>::failure(storage_corrupted("stored source is invalid", parent + ".source"));
  }
  if (event.importance.has_value() && !domain::is_valid_importance(*event.importance)) {
    return common::Result<domain::Event>::failure(
        storage_corrupted("stored importance is invalid", parent + ".importance"));
  }

  return common::Result<domain::Event>::success(std::move(event));
}

/** 把 optional<string> 转为 picojson value；无值时生成 JSON null。 */
picojson::value optional_string_to_json(const std::optional<std::string>& value) {
  if (!value.has_value()) {
    return picojson::value();
  }
  return picojson::value(*value);
}

/** 把领域 Event 转为存储文件中的 JSON object。 */
picojson::value event_to_storage_json(const domain::Event& event) {
  picojson::object object;
  object["id"] = picojson::value(event.id);
  object["title"] = picojson::value(event.title);
  object["content"] = optional_string_to_json(event.content);
  object["start_at"] = picojson::value(event.start_at);
  object["end_at"] = picojson::value(event.end_at);
  object["is_all_day"] = picojson::value(event.is_all_day);
  object["has_recurrence"] = picojson::value(event.has_recurrence);
  object["status"] = picojson::value(event.status);
  object["completed_at"] = optional_string_to_json(event.completed_at);
  object["recurrence_id"] = optional_string_to_json(event.recurrence_id);
  object["category_id"] = optional_string_to_json(event.category_id);
  object["importance"] = optional_string_to_json(event.importance);
  object["location"] = optional_string_to_json(event.location);
  object["timezone"] = optional_string_to_json(event.timezone);
  object["source"] = picojson::value(event.source);
  object["created_at"] = picojson::value(event.created_at);
  object["updated_at"] = picojson::value(event.updated_at);
  object["deleted_at"] = optional_string_to_json(event.deleted_at);
  return picojson::value(object);
}

}  // namespace

/** 保存存储目录路径，实际目录创建放在 initialize()。 */
JsonEventRepository::JsonEventRepository(std::filesystem::path storage_directory)
    : store_(std::move(storage_directory)) {}

/** 初始化目录并做一次写入探测，确认路径可用。 */
common::Result<common::Unit> JsonEventRepository::initialize() {
  auto directory_lock = store_.acquire_directory_lock();
  // lock_guard 是 RAII 锁：构造时加锁，离开作用域自动解锁，即使中途 return 也安全。
  std::lock_guard<std::mutex> lock(mutex_);
  return store_.initialize();
}

/** 创建事件：加载全量事件 -> 追加 -> 保存全量事件。 */
common::Result<domain::Event> JsonEventRepository::create(const domain::Event& event) {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_events_locked();
  if (!loaded.ok()) {
    return common::Result<domain::Event>::failure(loaded.error());
  }
  auto events = loaded.value();
  events.push_back(event);

  auto saved = save_events_locked(events);
  if (!saved.ok()) {
    return common::Result<domain::Event>::failure(saved.error());
  }
  return common::Result<domain::Event>::success(event);
}

/** 按 id 查找事件。 */
common::Result<std::optional<domain::Event>> JsonEventRepository::find_by_id(std::string_view id) {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);

  auto loaded = load_events_locked();
  if (!loaded.ok()) {
    return common::Result<std::optional<domain::Event>>::failure(loaded.error());
  }
  for (const auto& event : loaded.value()) {
    if (event.id == std::string(id)) {
      return common::Result<std::optional<domain::Event>>::success(event);
    }
  }
  return common::Result<std::optional<domain::Event>>::success(std::nullopt);
}

/** 读取所有事件。mutex 保证不会和 create/save 同时读写同一个文件。 */
common::Result<std::vector<domain::Event>> JsonEventRepository::find_all() {
  auto directory_lock = store_.acquire_directory_lock();
  std::lock_guard<std::mutex> lock(mutex_);
  return load_events_locked();
}

/** 在已持有 mutex_ 的前提下读取 events.json。 */
common::Result<std::vector<domain::Event>> JsonEventRepository::load_events_locked() {
  auto loaded = store_.read_json_file("events.json");
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::Event>>::failure(loaded.error());
  }
  if (!loaded.value().has_value()) {
    return common::Result<std::vector<domain::Event>>::success({});
  }

  const auto& root = *loaded.value();
  if (!root.is<picojson::object>()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_corrupted("root must be object"));
  }
  const auto& object = root.get<picojson::object>();
  const auto* version = object_field(object, "storage_version");
  // storage_version 用于未来升级文件格式；当前只接受版本 1。
  if (version == nullptr || !version->is<double>() || !is_integer_number(version->get<double>()) ||
      static_cast<int>(version->get<double>()) != 1) {
    return common::Result<std::vector<domain::Event>>::failure(
        storage_corrupted("storage_version must be 1", "storage_version"));
  }
  const auto* events_value = object_field(object, "events");
  if (events_value == nullptr || !events_value->is<picojson::array>()) {
    return common::Result<std::vector<domain::Event>>::failure(storage_corrupted("events must be array", "events"));
  }

  std::vector<domain::Event> events;
  const auto& array = events_value->get<picojson::array>();
  events.reserve(array.size());
  // 逐条解析，任何一条损坏都会让整个读取失败，避免返回半可信数据。
  for (std::size_t index = 0; index < array.size(); ++index) {
    auto parsed = parse_event_record(array[index], index);
    if (!parsed.ok()) {
      return common::Result<std::vector<domain::Event>>::failure(parsed.error());
    }
    events.push_back(std::move(parsed.value()));
  }
  return common::Result<std::vector<domain::Event>>::success(std::move(events));
}

/** 在已持有 mutex_ 的前提下保存 events.json。 */
common::Result<common::Unit> JsonEventRepository::save_events_locked(const std::vector<domain::Event>& events) {
  // 组装根对象：版本号 + 事件数组。
  picojson::array event_array;
  event_array.reserve(events.size());
  for (const auto& event : events) {
    event_array.push_back(event_to_storage_json(event));
  }

  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["events"] = picojson::value(event_array);

  return store_.write_json_file("events.json", picojson::value(root));
}

}  // namespace excellent_calendar::storage::json
