#include "excellent_calendar/storage/json/json_category_repository.hpp"

#include <optional>
#include <string>
#include <utility>

#include "excellent_calendar/storage/json/category_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr const char *kCategoryStoreFile = "categories.json";

common::Error runtime_revoked(std::string operation) {
  return storage::runtime_storage_revoked_error(std::move(operation));
}

common::Error internal_error(std::string reason) {
  return common::make_error("NATIVE_INTERNAL_ERROR", "Native internal error",
                            {{"reason", std::move(reason)}});
}

} // namespace

JsonCategoryRepository::JsonCategoryRepository(
    std::filesystem::path storage_directory,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease,
    FailureHook failure_hook)
    : store_(std::move(storage_directory), std::move(failure_hook),
             AtomicJsonFileStore::DirectorySyncFailurePolicy::
                 kRestorePreviousSnapshot),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonCategoryRepository::initialize() {
  auto runtime_access =
      runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(
        runtime_revoked("category.initialize"));
  }
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok())
    return initialized;
  auto root = store_.read_json_file(kCategoryStoreFile);
  if (!root.ok())
    return common::Result<common::Unit>::failure(root.error());
  if (!root.value().has_value()) {
    return store_.write_json_file(kCategoryStoreFile, empty_category_store());
  }
  auto records = decode_category_store(*root.value());
  if (!records.ok())
    return common::Result<common::Unit>::failure(records.error());
  auto state = category_state_from_storage_records(records.value());
  return state.ok() ? common::Result<common::Unit>::success(common::Unit{})
                    : common::Result<common::Unit>::failure(state.error());
}

common::Result<repository::CategoryState> JsonCategoryRepository::load() {
  auto runtime_access =
      runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::CategoryState>::failure(
        runtime_revoked("category.list"));
  }
  auto lock = store_.acquire_directory_lock();
  return load_locked();
}

common::Result<repository::CategoryState>
JsonCategoryRepository::load_locked() {
  auto root = store_.read_json_file(kCategoryStoreFile);
  if (!root.ok())
    return common::Result<repository::CategoryState>::failure(root.error());
  if (!root.value().has_value()) {
    return common::Result<repository::CategoryState>::failure(
        storage_data_corrupted("categories.json is missing",
                               kCategoryStoreFile));
  }
  auto records = decode_category_store(*root.value());
  return records.ok() ? category_state_from_storage_records(records.value())
                      : common::Result<repository::CategoryState>::failure(
                            records.error());
}

common::Result<common::Unit>
JsonCategoryRepository::execute(std::string_view operation,
                                const Operation &action) {
  auto runtime_access =
      runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(
        runtime_revoked(std::string(operation)));
  }
  if (operation != "category_create" || !action) {
    return common::Result<common::Unit>::failure(
        internal_error("Category repository operation is invalid"));
  }
  auto lock = store_.acquire_directory_lock();
  auto loaded = load_locked();
  if (!loaded.ok())
    return common::Result<common::Unit>::failure(loaded.error());
  auto state = std::move(loaded.value());
  auto applied = action(state);
  if (!applied.ok())
    return applied;
  auto records = category_storage_records_from_state(state);
  if (!records.ok())
    return common::Result<common::Unit>::failure(records.error());
  auto encoded = encode_category_store(records.value());
  if (!encoded.ok())
    return common::Result<common::Unit>::failure(encoded.error());
  return store_.write_json_file(kCategoryStoreFile, encoded.value());
}

} // namespace excellent_calendar::storage::json
