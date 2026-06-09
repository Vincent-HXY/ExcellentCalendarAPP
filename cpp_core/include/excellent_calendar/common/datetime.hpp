#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace excellent_calendar::common {

/**
 * 解析 UTC ISO 8601 时间为 Unix epoch 秒。
 *
 * 返回 optional：解析成功时有秒数，格式非法时返回 std::nullopt。
 */
std::optional<std::int64_t> parse_iso8601_utc_epoch_seconds(std::string_view value);

/** 只校验字符串是否是本项目接受的 UTC ISO 8601 时间格式。 */
bool is_iso8601_utc_datetime(std::string_view value);

}  // namespace excellent_calendar::common
