#include "excellent_calendar/boundary/api/event_api.hpp"

#include <cmath>
#include <limits>
#include <set>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/application/event_service.hpp"
#include "excellent_calendar/application/create_event_workflow_service.hpp"
#include "excellent_calendar/boundary/api/native_runtime.hpp"
#include "excellent_calendar/boundary/contract/create_event_request.hpp"
#include "excellent_calendar/boundary/contract/event_list_response.hpp"
#include "excellent_calendar/boundary/contract/event_response.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/data_source.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/reminder.hpp"

namespace excellent_calendar::boundary::api {
namespace {

/** 创建合约错误，field 可选。 */
common::Error contract_error(std::string message, std::string field = "") {
  std::map<std::string, std::string> details;
  if (!field.empty()) {
    details["field"] = std::move(field);
  }
  return common::make_error("CONTRACT_VALIDATION_FAILED", std::move(message), std::move(details));
}

/** 当前阶段未实现的能力统一返回 FEATURE_NOT_IMPLEMENTED。 */
common::Error feature_not_implemented(std::string feature) {
  return common::make_error(
      "FEATURE_NOT_IMPLEMENTED",
      "Requested feature is not implemented in this phase",
      {{"feature", std::move(feature)}});
}

/** 最外层异常兜底时使用的内部错误。 */
common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR",
      "Native internal error",
      {{"reason", std::move(reason)}});
}

/** 解析请求 JSON，并要求顶层一定是 object。 */
common::Result<picojson::object> parse_json_object(std::string_view request_json) {
  picojson::value value;
  const std::string error = picojson::parse(value, std::string(request_json));
  if (!error.empty()) {
    return common::Result<picojson::object>::failure(contract_error("Request JSON is malformed.", "json"));
  }
  if (!value.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(contract_error("Request JSON must be an object.", "json"));
  }
  return common::Result<picojson::object>::success(value.get<picojson::object>());
}

/** 安全获取 object 字段；不存在时返回 nullptr。 */
const picojson::value* field(const picojson::object& object, const std::string& key) {
  const auto found = object.find(key);
  if (found == object.end()) {
    return nullptr;
  }
  return &found->second;
}

/** 检查是否包含白名单以外的字段。unknown 返回第一个发现的未知字段名。 */
bool has_unknown_field(const picojson::object& object, const std::set<std::string>& allowed, std::string& unknown) {
  for (const auto& [key, _] : object) {
    if (allowed.find(key) == allowed.end()) {
      unknown = key;
      return true;
    }
  }
  return false;
}

/** 读取必填字符串字段。Result 失败时包含字段路径，便于 Dart 展示/日志定位。 */
common::Result<std::string> require_string(const picojson::object& object,
                                           const std::string& key,
                                           const std::string& parent,
                                           bool non_empty = false) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<std::string>::failure(contract_error(parent + "." + key + " is required.", parent + "." + key));
  }
  if (!value->is<std::string>() || (non_empty && value->get<std::string>().empty())) {
    return common::Result<std::string>::failure(
        contract_error(parent + "." + key + " must be a string.", parent + "." + key));
  }
  return common::Result<std::string>::success(value->get<std::string>());
}

/** 读取可选字符串字段：字段缺失或 JSON null 都映射为 std::nullopt。 */
common::Result<std::optional<std::string>> optional_string(const picojson::object& object,
                                                           const std::string& key,
                                                           const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<std::string>>::success(std::nullopt);
  }
  if (!value->is<std::string>()) {
    return common::Result<std::optional<std::string>>::failure(
        contract_error(parent + "." + key + " must be a string or null.", parent + "." + key));
  }
  return common::Result<std::optional<std::string>>::success(value->get<std::string>());
}

/** 读取必填 bool 字段。 */
common::Result<bool> require_bool(const picojson::object& object,
                                  const std::string& key,
                                  const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<bool>::failure(contract_error(parent + "." + key + " is required.", parent + "." + key));
  }
  if (!value->is<bool>()) {
    return common::Result<bool>::failure(contract_error(parent + "." + key + " must be boolean.", parent + "." + key));
  }
  return common::Result<bool>::success(value->get<bool>());
}

/** 读取可选 bool 字段。 */
common::Result<std::optional<bool>> optional_bool(const picojson::object& object,
                                                  const std::string& key,
                                                  const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<bool>>::success(std::nullopt);
  }
  if (!value->is<bool>()) {
    return common::Result<std::optional<bool>>::failure(
        contract_error(parent + "." + key + " must be boolean or null.", parent + "." + key));
  }
  return common::Result<std::optional<bool>>::success(value->get<bool>());
}

/** picojson 把 JSON number 表示为 double，所以需要额外判断它是不是整数。 */
bool is_integer(double value) {
  return std::floor(value) == value;
}

/** 读取可选整数。JSON 中是 double，校验为整数后再转 int。 */
common::Result<std::optional<int>> optional_int(const picojson::object& object,
                                                const std::string& key,
                                                const std::string& parent) {
  const auto* value = field(object, key);
  if (value == nullptr || value->is<picojson::null>()) {
    return common::Result<std::optional<int>>::success(std::nullopt);
  }
  if (!value->is<double>() || !is_integer(value->get<double>()) ||
      value->get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value->get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    return common::Result<std::optional<int>>::failure(
        contract_error(parent + "." + key + " must be integer or null.", parent + "." + key));
  }
  return common::Result<std::optional<int>>::success(static_cast<int>(value->get<double>()));
}

/** 读取可选字符串数组，可选地校验每一项是否在 allowed 集合中。 */
common::Result<std::vector<std::string>> optional_string_array(const picojson::object& object,
                                                               const std::string& key,
                                                               const std::string& parent,
                                                               const std::set<std::string>* allowed = nullptr) {
  const auto* value = field(object, key);
  if (value == nullptr) {
    return common::Result<std::vector<std::string>>::success({});
  }
  if (!value->is<picojson::array>()) {
    return common::Result<std::vector<std::string>>::failure(
        contract_error(parent + "." + key + " must be an array.", parent + "." + key));
  }
  std::vector<std::string> result;
  const auto& array = value->get<picojson::array>();
  result.reserve(array.size());
  for (std::size_t index = 0; index < array.size(); ++index) {
    if (!array[index].is<std::string>()) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + "." + key + " item must be string.", parent + "." + key));
    }
    const auto item = array[index].get<std::string>();
    if (allowed != nullptr && allowed->find(item) == allowed->end()) {
      return common::Result<std::vector<std::string>>::failure(
          contract_error(parent + "." + key + " item has an unsupported value.", parent + "." + key));
    }
    result.push_back(item);
  }
  return common::Result<std::vector<std::string>>::success(std::move(result));
}

/** 把 CreateEventRequest JSON 解析成 application 层命令对象。 */
common::Result<contract::ReminderDraftRequest> parse_reminder_draft(
    const picojson::value& value,
    std::size_t index) {
  const auto parent = "CreateEventRequest.reminders[" + std::to_string(index) + "]";
  if (!value.is<picojson::object>()) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + " must be an object.", parent));
  }
  const auto& object = value.get<picojson::object>();
  static const std::set<std::string> allowed{
      "target_type", "target_id", "remind_at", "advance_minutes",
      "methods", "message", "is_enabled", "source",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + " contains an unknown field.", parent + "." + unknown));
  }

  auto target_type = require_string(object, "target_type", parent, true);
  if (!target_type.ok()) return common::Result<contract::ReminderDraftRequest>::failure(target_type.error());
  if (target_type.value() != "event" && target_type.value() != "anniversary") {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + ".target_type has an unsupported enum value.", parent + ".target_type"));
  }
  auto target_id = optional_string(object, "target_id", parent);
  if (!target_id.ok()) return common::Result<contract::ReminderDraftRequest>::failure(target_id.error());
  auto remind_at = optional_string(object, "remind_at", parent);
  if (!remind_at.ok()) return common::Result<contract::ReminderDraftRequest>::failure(remind_at.error());
  if (remind_at.value().has_value() && !common::is_iso8601_utc_datetime(*remind_at.value())) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + ".remind_at must be ISO 8601 UTC date-time.", parent + ".remind_at"));
  }
  auto advance_minutes = optional_int(object, "advance_minutes", parent);
  if (!advance_minutes.ok()) {
    return common::Result<contract::ReminderDraftRequest>::failure(advance_minutes.error());
  }
  if (advance_minutes.value().has_value() && *advance_minutes.value() < 0) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + ".advance_minutes must be non-negative.", parent + ".advance_minutes"));
  }
  if (!remind_at.value().has_value() && !advance_minutes.value().has_value()) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + " requires remind_at or advance_minutes.", parent));
  }

  const auto* methods_value = field(object, "methods");
  if (methods_value == nullptr || !methods_value->is<picojson::array>() ||
      methods_value->get<picojson::array>().empty()) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + ".methods must be a non-empty array.", parent + ".methods"));
  }
  std::vector<std::string> methods;
  std::set<std::string> seen_methods;
  for (const auto& item : methods_value->get<picojson::array>()) {
    if (!item.is<std::string>()) {
      return common::Result<contract::ReminderDraftRequest>::failure(
          contract_error(parent + ".methods items must be strings.", parent + ".methods"));
    }
    const auto& method = item.get<std::string>();
    if (!domain::is_valid_reminder_method(method) || !seen_methods.insert(method).second) {
      return common::Result<contract::ReminderDraftRequest>::failure(
          contract_error(parent + ".methods contains an invalid or duplicate value.", parent + ".methods"));
    }
    methods.push_back(method);
  }

  auto message = optional_string(object, "message", parent);
  if (!message.ok()) return common::Result<contract::ReminderDraftRequest>::failure(message.error());
  auto is_enabled = require_bool(object, "is_enabled", parent);
  if (!is_enabled.ok()) return common::Result<contract::ReminderDraftRequest>::failure(is_enabled.error());
  auto source = require_string(object, "source", parent, true);
  if (!source.ok()) return common::Result<contract::ReminderDraftRequest>::failure(source.error());
  if (!domain::is_valid_reminder_source(source.value())) {
    return common::Result<contract::ReminderDraftRequest>::failure(
        contract_error(parent + ".source has an unsupported enum value.", parent + ".source"));
  }

  contract::ReminderDraftRequest draft;
  draft.target_type = target_type.value();
  draft.target_id = target_id.value();
  draft.remind_at = remind_at.value();
  draft.advance_minutes = advance_minutes.value();
  draft.methods = std::move(methods);
  draft.message = message.value();
  draft.is_enabled = is_enabled.value();
  draft.source = source.value();
  return common::Result<contract::ReminderDraftRequest>::success(std::move(draft));
}

common::Result<application::CreateEventWorkflowCommand> parse_create_event_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "title",      "content",     "start_at", "end_at",   "is_all_day", "category_id",
      "importance", "location",    "timezone", "source",   "recurrence", "reminders",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(
        contract_error("CreateEventRequest contains an unknown field.", "CreateEventRequest." + unknown));
  }

  // 先读取必填字段，任何一步失败都立即返回对应错误。
  auto title = require_string(object, "title", "CreateEventRequest", false);
  if (!title.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(title.error());
  auto start_at = require_string(object, "start_at", "CreateEventRequest", true);
  if (!start_at.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(start_at.error());
  auto end_at = require_string(object, "end_at", "CreateEventRequest", true);
  if (!end_at.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(end_at.error());
  auto is_all_day = require_bool(object, "is_all_day", "CreateEventRequest");
  if (!is_all_day.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(is_all_day.error());
  auto source = require_string(object, "source", "CreateEventRequest", true);
  if (!source.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(source.error());

  if (!common::is_iso8601_utc_datetime(start_at.value())) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(
        contract_error("CreateEventRequest.start_at must be ISO 8601 UTC date-time.", "CreateEventRequest.start_at"));
  }
  if (!common::is_iso8601_utc_datetime(end_at.value())) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(
        contract_error("CreateEventRequest.end_at must be ISO 8601 UTC date-time.", "CreateEventRequest.end_at"));
  }
  if (!domain::is_valid_create_event_source(source.value())) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(
        contract_error("CreateEventRequest.source has an unsupported enum value.", "CreateEventRequest.source"));
  }

  // 再读取可选字段。optional<T> 让“未传/null”和“传了字符串”都能明确表达。
  auto content = optional_string(object, "content", "CreateEventRequest");
  if (!content.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(content.error());
  auto category_id = optional_string(object, "category_id", "CreateEventRequest");
  if (!category_id.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(category_id.error());
  auto importance = optional_string(object, "importance", "CreateEventRequest");
  if (!importance.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(importance.error());
  if (importance.value().has_value() && !domain::is_valid_importance(*importance.value())) {
    return common::Result<application::CreateEventWorkflowCommand>::failure(
        contract_error("CreateEventRequest.importance has an unsupported enum value.", "CreateEventRequest.importance"));
  }
  auto location = optional_string(object, "location", "CreateEventRequest");
  if (!location.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(location.error());
  auto timezone = optional_string(object, "timezone", "CreateEventRequest");
  if (!timezone.ok()) return common::Result<application::CreateEventWorkflowCommand>::failure(timezone.error());

  const auto* recurrence = field(object, "recurrence");
  if (recurrence != nullptr && !recurrence->is<picojson::null>()) {
    // TODO(recurrence): persist Recurrence as an independent entity.
    return common::Result<application::CreateEventWorkflowCommand>::failure(feature_not_implemented("recurrence"));
  }
  std::vector<contract::ReminderDraftRequest> reminder_drafts;
  const auto* reminders = field(object, "reminders");
  if (reminders != nullptr) {
    if (!reminders->is<picojson::array>()) {
      return common::Result<application::CreateEventWorkflowCommand>::failure(
          contract_error("CreateEventRequest.reminders must be an array.", "CreateEventRequest.reminders"));
    }
    const auto& array = reminders->get<picojson::array>();
    reminder_drafts.reserve(array.size());
    for (std::size_t index = 0; index < array.size(); ++index) {
      auto draft = parse_reminder_draft(array[index], index);
      if (!draft.ok()) {
        return common::Result<application::CreateEventWorkflowCommand>::failure(draft.error());
      }
      reminder_drafts.push_back(std::move(draft.value()));
    }
  }

  // 最后组装 application 层命令。std::move 避免复制整个 command。
  application::CreateEventWorkflowCommand command;
  command.event.title = title.value();
  command.event.content = content.value();
  command.event.start_at = start_at.value();
  command.event.end_at = end_at.value();
  command.event.is_all_day = is_all_day.value();
  command.event.category_id = category_id.value();
  command.event.importance = importance.value();
  command.event.location = location.value();
  command.event.timezone = timezone.value();
  command.event.source = source.value();
  command.reminders.reserve(reminder_drafts.size());
  for (const auto& request_draft : reminder_drafts) {
    application::ReminderDraftCommand draft;
    draft.target_type = request_draft.target_type;
    draft.target_id = request_draft.target_id;
    draft.remind_at = request_draft.remind_at;
    draft.advance_minutes = request_draft.advance_minutes;
    draft.methods = request_draft.methods;
    draft.message = request_draft.message;
    draft.is_enabled = request_draft.is_enabled;
    draft.source = request_draft.source;
    command.reminders.push_back(std::move(draft));
  }
  return common::Result<application::CreateEventWorkflowCommand>::success(std::move(command));
}

/** 把 SearchEventRequest JSON 解析成 application 层查询对象。 */
common::Result<application::EventQuery> parse_search_event_request(std::string_view request_json) {
  auto parsed = parse_json_object(request_json);
  if (!parsed.ok()) {
    return common::Result<application::EventQuery>::failure(parsed.error());
  }
  const auto& object = parsed.value();
  static const std::set<std::string> allowed{
      "keyword",      "start_at_from", "start_at_to", "category_ids", "importance", "location",
      "has_recurrence", "source",      "include_deleted", "pagination", "sort_by", "sort_direction",
  };
  std::string unknown;
  if (has_unknown_field(object, allowed, unknown)) {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest contains an unknown field.", "SearchEventRequest." + unknown));
  }

  application::EventQuery query;
  // 顶层过滤字段大多是可选项，未传时保持 EventQuery 的默认值。
  auto keyword = optional_string(object, "keyword", "SearchEventRequest");
  if (!keyword.ok()) return common::Result<application::EventQuery>::failure(keyword.error());
  auto start_at_from = optional_string(object, "start_at_from", "SearchEventRequest");
  if (!start_at_from.ok()) return common::Result<application::EventQuery>::failure(start_at_from.error());
  auto start_at_to = optional_string(object, "start_at_to", "SearchEventRequest");
  if (!start_at_to.ok()) return common::Result<application::EventQuery>::failure(start_at_to.error());
  auto location = optional_string(object, "location", "SearchEventRequest");
  if (!location.ok()) return common::Result<application::EventQuery>::failure(location.error());
  auto has_recurrence = optional_bool(object, "has_recurrence", "SearchEventRequest");
  if (!has_recurrence.ok()) return common::Result<application::EventQuery>::failure(has_recurrence.error());
  auto include_deleted = optional_bool(object, "include_deleted", "SearchEventRequest");
  if (!include_deleted.ok()) return common::Result<application::EventQuery>::failure(include_deleted.error());

  static const std::set<std::string> importance_values{
      "unimportant_noturgent", "important_noturgent", "unimportant_urgent", "important_urgent",
  };
  // 数组字段用 vector<string> 表示；空 vector 意味着不按该字段过滤。
  static const std::set<std::string> source_values{"manual", "ai_extraction", "sync", "import", "wechat"};
  auto category_ids = optional_string_array(object, "category_ids", "SearchEventRequest");
  if (!category_ids.ok()) return common::Result<application::EventQuery>::failure(category_ids.error());
  auto importance = optional_string_array(object, "importance", "SearchEventRequest", &importance_values);
  if (!importance.ok()) return common::Result<application::EventQuery>::failure(importance.error());
  auto source = optional_string_array(object, "source", "SearchEventRequest", &source_values);
  if (!source.ok()) return common::Result<application::EventQuery>::failure(source.error());

  query.keyword = keyword.value();
  query.start_at_from = start_at_from.value();
  query.start_at_to = start_at_to.value();
  query.location = location.value();
  query.has_recurrence = has_recurrence.value();
  query.include_deleted = include_deleted.value().value_or(false);
  query.category_ids = category_ids.value();
  query.importance = importance.value();
  query.source = source.value();

  // 顶层 sort_by/sort_direction 优先级高于 pagination 内部同名字段。
  auto sort_by = optional_string(object, "sort_by", "SearchEventRequest");
  if (!sort_by.ok()) return common::Result<application::EventQuery>::failure(sort_by.error());
  auto sort_direction = optional_string(object, "sort_direction", "SearchEventRequest");
  if (!sort_direction.ok()) return common::Result<application::EventQuery>::failure(sort_direction.error());
  if (sort_by.value().has_value()) {
    query.sort_by = *sort_by.value();
  }
  if (sort_direction.value().has_value()) {
    query.sort_direction = *sort_direction.value();
  }

  if (query.sort_by != "start_at" && query.sort_by != "created_at" &&
      query.sort_by != "updated_at" && query.sort_by != "importance" && query.sort_by != "title") {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest.sort_by has an unsupported enum value.", "SearchEventRequest.sort_by"));
  }
  if (query.sort_direction != "asc" && query.sort_direction != "desc") {
    return common::Result<application::EventQuery>::failure(
        contract_error("SearchEventRequest.sort_direction has an unsupported enum value.", "SearchEventRequest.sort_direction"));
  }

  const auto* pagination_value = field(object, "pagination");
  if (pagination_value != nullptr && !pagination_value->is<picojson::null>()) {
    if (!pagination_value->is<picojson::object>()) {
      return common::Result<application::EventQuery>::failure(
          contract_error("SearchEventRequest.pagination must be an object.", "SearchEventRequest.pagination"));
    }
    const auto& pagination = pagination_value->get<picojson::object>();
    static const std::set<std::string> pagination_allowed{"page", "page_size", "cursor", "sort_by", "sort_direction"};
    if (has_unknown_field(pagination, pagination_allowed, unknown)) {
      return common::Result<application::EventQuery>::failure(
          contract_error("SearchEventRequest.pagination contains an unknown field.",
                         "SearchEventRequest.pagination." + unknown));
    }
    auto page = optional_int(pagination, "page", "SearchEventRequest.pagination");
    if (!page.ok()) return common::Result<application::EventQuery>::failure(page.error());
    auto page_size = optional_int(pagination, "page_size", "SearchEventRequest.pagination");
    if (!page_size.ok()) return common::Result<application::EventQuery>::failure(page_size.error());
    auto cursor = optional_string(pagination, "cursor", "SearchEventRequest.pagination");
    if (!cursor.ok()) return common::Result<application::EventQuery>::failure(cursor.error());
    if (cursor.value().has_value()) {
      // 当前阶段只支持 page/page_size，cursor 字段保留给未来扩展。
      return common::Result<application::EventQuery>::failure(
          common::make_error("SEARCH_QUERY_INVALID", "Cursor pagination is not implemented in this phase",
                             {{"field", "pagination.cursor"}}));
    }
    auto pagination_sort_by = optional_string(pagination, "sort_by", "SearchEventRequest.pagination");
    if (!pagination_sort_by.ok()) return common::Result<application::EventQuery>::failure(pagination_sort_by.error());
    auto pagination_sort_direction =
        optional_string(pagination, "sort_direction", "SearchEventRequest.pagination");
    if (!pagination_sort_direction.ok()) {
      return common::Result<application::EventQuery>::failure(pagination_sort_direction.error());
    }
    if (page.value().has_value()) {
      query.pagination.page = *page.value();
    }
    if (page_size.value().has_value()) {
      query.pagination.page_size = *page_size.value();
    }
    if (!sort_by.value().has_value() && pagination_sort_by.value().has_value()) {
      query.sort_by = *pagination_sort_by.value();
    }
    if (!sort_direction.value().has_value() && pagination_sort_direction.value().has_value()) {
      query.sort_direction = *pagination_sort_direction.value();
    }
  }

  return common::Result<application::EventQuery>::success(std::move(query));
}

/** 把 common::Error 包成 NativeResult JSON。 */
std::string failure_response(const common::Error& error, const std::string& request_id) {
  return contract::native_failure_json(error, request_id);
}

}  // namespace

/** 初始化 JSON 仓库和 EventService，并保存到全局运行状态。 */
std::string initialize_storage(std::string_view storage_directory) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto initialized = initialize_runtime(storage_directory);
    if (!initialized.ok()) {
      return failure_response(initialized.error(), request_id);
    }

    picojson::object data;
    data["storage_directory"] = picojson::value(std::string(storage_directory));
    data["storage_version"] = picojson::value(1.0);
    return contract::native_success_json(picojson::value(std::move(data)), request_id);
  } catch (const std::exception& error) {
    // API 边界兜底捕获异常，保证 JNI/Kotlin 收到的是 JSON，而不是 C++ 异常穿透。
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

/** native 创建事件入口。 */
std::string create_event(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_create_event_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }

    const auto service = current_create_event_workflow_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("event"), request_id);
    }

    auto created = service->create_event(parsed.value());
    if (!created.ok()) {
      return failure_response(created.error(), request_id);
    }
    return contract::native_success_json(contract::event_response_to_json(created.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

/** native 搜索事件入口。 */
std::string search_events(std::string_view request_json) {
  const auto request_id = common::generate_uuid_v4();
  try {
    auto parsed = parse_search_event_request(request_json);
    if (!parsed.ok()) {
      return failure_response(parsed.error(), request_id);
    }

    const auto service = current_event_service();
    if (!service) {
      return failure_response(storage_not_initialized_error("event"), request_id);
    }

    auto result = service->search_events(parsed.value());
    if (!result.ok()) {
      return failure_response(result.error(), request_id);
    }
    return contract::native_success_json(contract::event_list_response_to_json(result.value()), request_id);
  } catch (const std::exception& error) {
    return failure_response(internal_error(error.what()), request_id);
  } catch (...) {
    return failure_response(internal_error("unknown exception"), request_id);
  }
}

/** 当前阶段未实现，保留 API 形状以便 Dart/Kotlin 先接通完整链路。 */
std::string complete_event(std::string_view /*request_json*/) {
  const auto request_id = common::generate_uuid_v4();
  return failure_response(feature_not_implemented("event.complete"), request_id);
}

/** 当前阶段未实现，保留 API 形状以便 Dart/Kotlin 先接通完整链路。 */
std::string reopen_event(std::string_view /*request_json*/) {
  const auto request_id = common::generate_uuid_v4();
  return failure_response(feature_not_implemented("event.reopen"), request_id);
}

}  // namespace excellent_calendar::boundary::api
