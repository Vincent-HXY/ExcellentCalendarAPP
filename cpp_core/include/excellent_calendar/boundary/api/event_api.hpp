#pragma once

#include <string>
#include <string_view>

namespace excellent_calendar::boundary::api {

/**
 * 初始化 native 存储。
 *
 * JNI/Kotlin 会在第一次业务调用前调用它。返回值永远是 NativeResult JSON 字符串，
 * 即使失败也不会直接把 C++ 异常抛给 Java。
 */
std::string initialize_storage(std::string_view storage_directory);

/** 创建事件 API。request_json 是 CreateEventRequest JSON，返回 NativeResult JSON。 */
std::string create_event(std::string_view request_json);

/** 更新事件 API。当前阶段先保留合约化入口。 */
std::string update_event(std::string_view request_json);

/** 删除事件 API。当前阶段先保留合约化入口。 */
std::string delete_event(std::string_view request_json);

/** 搜索事件 API。request_json 是 SearchEventRequest JSON，返回 NativeResult JSON。 */
std::string search_events(std::string_view request_json);

/** 完成事件 API。当前阶段可能返回 FEATURE_NOT_IMPLEMENTED。 */
std::string complete_event(std::string_view request_json);

/** 重新打开事件 API。当前阶段可能返回 FEATURE_NOT_IMPLEMENTED。 */
std::string reopen_event(std::string_view request_json);

}  // namespace excellent_calendar::boundary::api
