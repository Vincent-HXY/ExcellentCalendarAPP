#include "excellent_calendar/boundary/contract/event_list_response.hpp"

#include "excellent_calendar/boundary/contract/event_response.hpp"

namespace excellent_calendar::boundary::contract {

/** 把搜索结果映射为 EventListResponse JSON。 */
picojson::value event_list_response_to_json(const application::EventSearchResult& result) {
  picojson::array items;
  items.reserve(result.items.size());
  // 复用单个事件的转换逻辑，避免列表接口和创建接口字段不一致。
  for (const auto& event : result.items) {
    items.push_back(event_response_to_json(event));
  }

  // picojson 使用 double 表示 JSON number，因此整数写出时需要 static_cast<double>。
  picojson::object pagination;
  pagination["total"] = picojson::value(static_cast<double>(result.pagination.total));
  pagination["page"] = picojson::value(static_cast<double>(result.pagination.page));
  pagination["page_size"] = picojson::value(static_cast<double>(result.pagination.page_size));
  pagination["has_more"] = picojson::value(result.pagination.has_more);
  pagination["next_cursor"] = result.pagination.next_cursor.has_value()
                                   ? picojson::value(*result.pagination.next_cursor)
                                   : picojson::value();

  picojson::object object;
  object["items"] = picojson::value(std::move(items));
  object["pagination"] = picojson::value(std::move(pagination));
  return picojson::value(std::move(object));
}

}  // namespace excellent_calendar::boundary::contract
