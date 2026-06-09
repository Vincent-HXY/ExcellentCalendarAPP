#include "excellent_calendar/domain/data_source.hpp"

namespace excellent_calendar::domain {

/** 创建事件来源白名单。 */
bool is_valid_create_event_source(std::string_view value) {
  return value == "manual" ||
         value == "ai_extraction" ||
         value == "sync" ||
         value == "import" ||
         value == "wechat";
}

}  // namespace excellent_calendar::domain
