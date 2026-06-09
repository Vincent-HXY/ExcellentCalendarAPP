#pragma once

#include <optional>
#include <string>

namespace excellent_calendar::boundary::contract {

/**
 * boundary 层看到的创建事件请求。
 *
 * 这个结构体和 application::CreateEventCommand 基本一致，用来表达 JSON 合约字段。
 * 当前解析逻辑直接生成 CreateEventCommand，因此此结构主要作为合约文档/类型占位。
 */
struct CreateEventRequest {
  std::string title;
  std::optional<std::string> content;
  std::string start_at;
  std::string end_at;
  bool is_all_day = false;
  std::optional<std::string> category_id;
  std::optional<std::string> importance;
  std::optional<std::string> location;
  std::optional<std::string> timezone;
  std::string source;
};

}  // namespace excellent_calendar::boundary::contract
