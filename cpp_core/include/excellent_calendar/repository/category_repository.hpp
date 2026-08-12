#pragma once

#include <functional>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/category.hpp"

namespace excellent_calendar::repository {

struct CategoryState {
  std::vector<domain::Category> categories;
};

class CategoryRepository {
public:
  using Operation =
      std::function<common::Result<common::Unit>(CategoryState &)>;

  virtual ~CategoryRepository() = default;

  virtual common::Result<common::Unit> initialize() = 0;
  virtual common::Result<CategoryState> load() = 0;
  virtual common::Result<common::Unit> execute(std::string_view operation,
                                               const Operation &action) = 0;
};

} // namespace excellent_calendar::repository
