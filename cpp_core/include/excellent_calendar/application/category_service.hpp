#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/domain/category.hpp"
#include "excellent_calendar/repository/category_repository.hpp"

namespace excellent_calendar::application {

struct CreateCategoryCommand {
  std::string name;
  std::optional<std::string> description;
  std::string color;
  std::optional<std::string> icon;
  std::optional<std::int64_t> sort_order;
};

struct ListCategoriesQuery {};

class CategoryService {
public:
  using Clock = std::function<std::string()>;
  using IdGenerator = std::function<std::string()>;

  CategoryService(std::shared_ptr<repository::CategoryRepository> repository,
                  Clock clock, IdGenerator id_generator);

  common::Result<domain::Category> create(const CreateCategoryCommand &command);

  common::Result<std::vector<domain::Category>>
  list(const ListCategoriesQuery &query = {});

private:
  std::shared_ptr<repository::CategoryRepository> repository_;
  Clock clock_;
  IdGenerator id_generator_;
};

} // namespace excellent_calendar::application
