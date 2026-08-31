#include "excellent_calendar/common/string_utils.hpp"

#include <algorithm>
#include <cctype>

namespace excellent_calendar::common {

/** 去掉首尾 ASCII 空白。static_cast<unsigned char> 可避免 char 为负时传给 ctype 函数的未定义行为。 */
std::string trim_ascii(std::string_view value) {
  std::size_t begin = 0;
  while (begin < value.size() && std::isspace(static_cast<unsigned char>(value[begin]))) {
    ++begin;
  }
  std::size_t end = value.size();
  while (end > begin && std::isspace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return std::string(value.substr(begin, end - begin));
}

/** 转小写 ASCII，用于简单搜索。 */
std::string lowercase_ascii(std::string_view value) {
  std::string result(value);
  std::transform(result.begin(), result.end(), result.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return result;
}

/** 先统一转小写，再用 string::find 判断包含关系。 */
bool contains_case_insensitive_ascii(std::string_view text, std::string_view keyword) {
  const auto lower_text = lowercase_ascii(text);
  const auto lower_keyword = lowercase_ascii(keyword);
  return lower_text.find(lower_keyword) != std::string::npos;
}

std::string format_hundredths(std::int64_t value) {
  const auto whole = value / 100;
  auto fraction = value % 100;
  if (fraction < 0) fraction = -fraction;
  const auto whole_text = value < 0 && whole == 0
                              ? std::string("-0")
                              : std::to_string(whole);
  if (fraction == 0) return whole_text;
  if (fraction % 10 == 0) {
    return whole_text + "." + std::to_string(fraction / 10);
  }
  return whole_text + "." +
         (fraction < 10 ? "0" : "") + std::to_string(fraction);
}

}  // namespace excellent_calendar::common
