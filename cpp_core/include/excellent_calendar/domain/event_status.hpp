#pragma once

#include <string_view>

namespace excellent_calendar::domain {

/** 事件处于正常可见状态。 */
inline constexpr std::string_view kEventStatusActive = "active";
/** 事件已完成。 */
inline constexpr std::string_view kEventStatusCompleted = "completed";
/** 事件已取消。 */
inline constexpr std::string_view kEventStatusCancelled = "cancelled";
/** 事件已归档。 */
inline constexpr std::string_view kEventStatusArchived = "archived";

/** 校验事件状态字符串是否属于上面的允许值。 */
bool is_valid_event_status(std::string_view value);

}  // namespace excellent_calendar::domain
