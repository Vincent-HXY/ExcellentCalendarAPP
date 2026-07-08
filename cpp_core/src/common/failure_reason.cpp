#include "excellent_calendar/common/failure_reason.hpp"

#include <cctype>
#include <sstream>

#include "excellent_calendar/common/string_utils.hpp"

namespace excellent_calendar::common {

std::string sanitize_failure_reason(std::string_view reason,
                                    std::string_view fallback) {
  std::string first_line;
  first_line.reserve(reason.size());
  for (const char ch : reason) {
    if (ch == '\r' || ch == '\n') break;
    first_line.push_back(std::iscntrl(static_cast<unsigned char>(ch)) ? ' ' : ch);
  }

  std::istringstream input(first_line);
  std::ostringstream output;
  bool first = true;
  std::string token;
  while (input >> token) {
    if (token.find('/') != std::string::npos || token.find('\\') != std::string::npos) {
      token = "[path]";
    }
    if (!first) output << ' ';
    output << token;
    first = false;
  }

  auto cleaned = trim_ascii(output.str());
  if (cleaned.empty()) cleaned = std::string(fallback);
  static constexpr std::size_t kMaxReasonLength = 200;
  if (cleaned.size() > kMaxReasonLength) cleaned.resize(kMaxReasonLength);
  return cleaned;
}

}  // namespace excellent_calendar::common
