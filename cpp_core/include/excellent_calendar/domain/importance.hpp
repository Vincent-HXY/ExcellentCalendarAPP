#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace excellent_calendar::domain {

/** 校验 importance 字符串是否属于四象限重要/紧急值域。 */
bool is_valid_importance(std::string_view value);

/**
 * 将 importance 转成排序权重。
 *
 * 没有 importance 或未知值返回 0；其他值越大，排序时越“重要/紧急”。
 */
int importance_rank(const std::optional<std::string>& value);

}  // namespace excellent_calendar::domain
