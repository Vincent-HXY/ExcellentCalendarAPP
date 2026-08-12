#include "excellent_calendar/application/category_service.hpp"

#include <algorithm>
#include <utility>

namespace excellent_calendar::application {
namespace {

common::Error internal_error(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", std::move(reason)}});
}

common::Error sort_order_contract_error() {
  return common::make_error(
      "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
      {{"field", "CreateCategoryRequest.sort_order"},
       {"reason",
        "sort_order must be from 0 through 9007199254740991"}});
}

common::Error sort_order_exhausted() {
  return common::make_error(
      "CATEGORY_SORT_ORDER_EXHAUSTED",
      "Category sort order has reached the maximum safe integer");
}

} // namespace

CategoryService::CategoryService(
    std::shared_ptr<repository::CategoryRepository> repository, Clock clock,
    IdGenerator id_generator)
    : repository_(std::move(repository)), clock_(std::move(clock)),
      id_generator_(std::move(id_generator)) {}

common::Result<domain::Category>
CategoryService::create(const CreateCategoryCommand &command) {
  if (!repository_ || !clock_ || !id_generator_) {
    return common::Result<domain::Category>::failure(
        internal_error("CategoryService dependencies are unavailable"));
  }
  auto name = domain::normalize_category_name(command.name);
  if (!name.ok())
    return common::Result<domain::Category>::failure(name.error());
  auto description = domain::normalize_category_optional_text(
      command.description, 200U, "CreateCategoryRequest.description");
  if (!description.ok()) {
    return common::Result<domain::Category>::failure(description.error());
  }
  auto icon = domain::normalize_category_optional_text(
      command.icon, 64U, "CreateCategoryRequest.icon");
  if (!icon.ok())
    return common::Result<domain::Category>::failure(icon.error());
  auto color = domain::normalize_category_color(command.color);
  if (!color.ok())
    return common::Result<domain::Category>::failure(color.error());
  if (command.sort_order.has_value() &&
      (*command.sort_order < 0 ||
       *command.sort_order > domain::kMaximumCategorySortOrder)) {
    return common::Result<domain::Category>::failure(
        sort_order_contract_error());
  }

  std::optional<domain::Category> created;
  auto executed = repository_->execute(
      "category_create", [&](repository::CategoryState &state) {
        std::int64_t sort_order = 0;
        if (command.sort_order.has_value()) {
          sort_order = *command.sort_order;
        } else {
          bool found_active = false;
          std::int64_t maximum = 0;
          for (const auto &category : state.categories) {
            if (category.deleted_at.has_value() ||
                !category.sort_order.has_value())
              continue;
            if (!found_active || *category.sort_order > maximum) {
              maximum = *category.sort_order;
              found_active = true;
            }
          }
          if (found_active) {
            if (maximum >= domain::kMaximumCategorySortOrder) {
              return common::Result<common::Unit>::failure(
                  sort_order_exhausted());
            }
            sort_order = maximum + 1;
          }
        }

        const auto id = id_generator_();
        const auto now = clock_();
        if (std::any_of(state.categories.begin(), state.categories.end(),
                        [&](const auto &item) { return item.id == id; })) {
          return common::Result<common::Unit>::failure(
              internal_error("Category ID generator returned a duplicate"));
        }
        domain::Category category{id,
                                  name.value(),
                                  description.value(),
                                  color.value(),
                                  icon.value(),
                                  sort_order,
                                  now,
                                  now,
                                  std::nullopt};
        auto valid = domain::validate_category(category);
        if (!valid.ok())
          return valid;
        state.categories.push_back(category);
        created = std::move(category);
        return common::Result<common::Unit>::success(common::Unit{});
      });
  if (!executed.ok())
    return common::Result<domain::Category>::failure(executed.error());
  if (!created.has_value()) {
    return common::Result<domain::Category>::failure(
        internal_error("Category repository completed without a result"));
  }
  return common::Result<domain::Category>::success(std::move(*created));
}

common::Result<std::vector<domain::Category>>
CategoryService::list(const ListCategoriesQuery &) {
  if (!repository_) {
    return common::Result<std::vector<domain::Category>>::failure(
        internal_error("CategoryRepository is unavailable"));
  }
  auto loaded = repository_->load();
  if (!loaded.ok()) {
    return common::Result<std::vector<domain::Category>>::failure(
        loaded.error());
  }
  std::vector<domain::Category> active;
  active.reserve(loaded.value().categories.size());
  for (const auto &category : loaded.value().categories) {
    if (!category.deleted_at.has_value())
      active.push_back(category);
  }
  std::sort(active.begin(), active.end(),
            [](const auto &left, const auto &right) {
              if (left.sort_order != right.sort_order) {
                if (!left.sort_order.has_value())
                  return false;
                if (!right.sort_order.has_value())
                  return true;
                return *left.sort_order < *right.sort_order;
              }
              if (left.created_at != right.created_at)
                return left.created_at < right.created_at;
              return left.id < right.id;
            });
  return common::Result<std::vector<domain::Category>>::success(
      std::move(active));
}

} // namespace excellent_calendar::application
