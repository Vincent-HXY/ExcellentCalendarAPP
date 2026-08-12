#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <string>

#include "excellent_calendar/repository/anniversary_transaction.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"

namespace excellent_calendar::storage::json {

class JsonAnniversaryTransaction final : public repository::AnniversaryTransaction {
 public:
  using FailureHook = std::function<common::Result<common::Unit>(std::string_view phase)>;

  explicit JsonAnniversaryTransaction(
      std::filesystem::path storage_directory,
      FailureHook failure_hook = {},
      std::shared_ptr<storage::RuntimeStorageLease> runtime_lease = {});

  common::Result<common::Unit> initialize() override;
  common::Result<repository::AnniversaryState> load() override;
  common::Result<common::Unit> execute(
      std::string_view operation,
      std::string transaction_id,
      std::string prepared_at,
      const Operation& action) override;

 private:
  common::Result<repository::AnniversaryState> load_locked();
  common::Result<common::Unit> recover_locked();
  common::Result<common::Unit> ensure_stores_locked();
  common::Result<common::Unit> apply_after_stores_locked(
      const picojson::object& after_stores,
      bool invoke_hooks);
  common::Result<common::Unit> call_hook(std::string_view phase) const;

  AtomicJsonFileStore store_;
  FailureHook failure_hook_;
  std::shared_ptr<storage::RuntimeStorageLease> runtime_lease_;
};

}  // namespace excellent_calendar::storage::json
