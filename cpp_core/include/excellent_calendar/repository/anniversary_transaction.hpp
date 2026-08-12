#pragma once

#include <functional>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/anniversary.hpp"

namespace excellent_calendar::repository {

struct AnniversaryState {
  std::vector<domain::Anniversary> anniversaries;
  std::vector<domain::AnniversaryRecurrence> recurrences;
};

class AnniversaryTransaction {
 public:
  using Operation = std::function<common::Result<common::Unit>(AnniversaryState&)>;

  virtual ~AnniversaryTransaction() = default;

  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<AnniversaryState> load() = 0;
  virtual common::Result<common::Unit> execute(
      std::string_view operation,
      std::string transaction_id,
      std::string prepared_at,
      const Operation& action) = 0;
};

}  // namespace excellent_calendar::repository
