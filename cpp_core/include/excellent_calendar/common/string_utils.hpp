#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace excellent_calendar::common {

/** 去掉字符串首尾 ASCII 空白字符。 */
std::string trim_ascii(std::string_view value);

/** 转成小写 ASCII。注意：这里不处理完整 Unicode 大小写规则。 */
std::string lowercase_ascii(std::string_view value);

/** ASCII 范围内的大小写不敏感包含判断，用于当前简单搜索。 */
bool contains_case_insensitive_ascii(std::string_view text, std::string_view keyword);

/** 精确格式化百分位整数；移除无意义的末尾 0，且不经过浮点数。 */
std::string format_hundredths(std::int64_t value);

}  // namespace excellent_calendar::common
