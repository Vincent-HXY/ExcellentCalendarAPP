#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::domain {

/**
 * 事件领域对象。
 *
 * domain 层只描述业务概念，不关心 JSON、JNI、Flutter、文件存储等外部细节。
 * `std::optional<std::string>` 表示该字段可以没有值；序列化到 JSON 时通常对应 null。
 */
struct Event {
  /** 事件唯一 id，当前由 UUID v4 生成。 */
  std::string id;
  /** 事件标题，业务层要求 trim 后不能为空。 */
  std::string title;
  /** 事件详情正文，可选。 */
  std::optional<std::string> content;
  /** UTC ISO 8601 开始时间，例如 2026-06-09T10:00:00Z。 */
  std::string start_at;
  /** UTC ISO 8601 结束时间，必须晚于 start_at。 */
  std::string end_at;
  /** 是否为全天事件。 */
  bool is_all_day = false;
  /** 是否有关联的重复规则；当前阶段创建接口尚未持久化 recurrence。 */
  bool has_recurrence = false;
  /** 事件状态，如 active/completed/cancelled/archived。 */
  std::string status;
  /** 完成时间，可选。 */
  std::optional<std::string> completed_at;
  /** 重复规则 id，可选。 */
  std::optional<std::string> recurrence_id;
  /** 分类 id，可选。 */
  std::optional<std::string> category_id;
  /** 重要程度，可选，取值见 importance.hpp。 */
  std::optional<std::string> importance;
  /** 地点，可选。 */
  std::optional<std::string> location;
  /** 时区标识，可选。 */
  std::optional<std::string> timezone;
  /** 数据来源，如 manual/import/wechat。 */
  std::string source;
  /** 创建时间。 */
  std::string created_at;
  /** 最后更新时间。 */
  std::string updated_at;
  /** 软删除时间；有值表示事件已删除。 */
  std::optional<std::string> deleted_at;
};

}  // namespace excellent_calendar::domain
