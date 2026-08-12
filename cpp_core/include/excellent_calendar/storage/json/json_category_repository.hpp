#pragma once

#include <filesystem>
#include <memory>
#include <string_view>

#include "excellent_calendar/repository/category_repository.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage::json {

class JsonCategoryRepository final : public repository::CategoryRepository {
public:
  using FailureHook = AtomicJsonFileStore::FailureHook;

  explicit JsonCategoryRepository(
      std::filesystem::path storage_directory,
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {},
      FailureHook failure_hook = {});

  common::Result<common::Unit> initialize() override;
  common::Result<repository::CategoryState> load() override;
  common::Result<common::Unit> execute(std::string_view operation,
                                       const Operation &action) override;

private:
  common::Result<repository::CategoryState> load_locked();

  AtomicJsonFileStore store_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

} // namespace excellent_calendar::storage::json
