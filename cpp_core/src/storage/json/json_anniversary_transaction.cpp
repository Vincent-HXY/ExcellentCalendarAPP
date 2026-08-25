#include "excellent_calendar/storage/json/json_anniversary_transaction.hpp"

#include <array>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/anniversary_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

struct DataStore {
  const char* logical_name;
  const char* file_name;
};

constexpr std::array<DataStore, 4> kDataStores{{
    {"anniversaries", "anniversaries.json"},
    {"anniversary_recurrences", "anniversary_recurrences.json"},
    {"anniversary_reminder_templates",
     "anniversary_reminder_templates.json"},
    {"reminders", "reminders.json"},
}};

common::Error runtime_revoked() {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
      {{"operation", "anniversary_transaction"}});
}

std::string v3_operation(std::string_view operation) {
  if (operation == "anniversary_create") {
    return "anniversary_create_with_reminders";
  }
  if (operation == "anniversary_update") {
    return "anniversary_update_with_reminders";
  }
  if (operation == "anniversary_delete") {
    return "anniversary_delete_with_reminders";
  }
  if (operation == "anniversary_toggle_reminders") {
    return "anniversary_toggle_reminders";
  }
  if (operation == "anniversary_timezone_recalculate") {
    return "anniversary_timezone_recalculate";
  }
  return {};
}

}  // namespace

JsonAnniversaryTransaction::JsonAnniversaryTransaction(
    std::filesystem::path storage_directory,
    FailureHook failure_hook,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : store_(storage_directory),
      coordinator_(std::move(storage_directory), std::move(failure_hook)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonAnniversaryTransaction::initialize() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) return initialized;
  auto recovered = coordinator_.initialize();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  return loaded.ok() ? validate_anniversary_state(loaded.value())
                     : common::Result<common::Unit>::failure(loaded.error());
}

common::Result<repository::AnniversaryState>
JsonAnniversaryTransaction::load() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::AnniversaryState>::failure(
        runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = coordinator_.recover();
  if (!recovered.ok()) {
    return common::Result<repository::AnniversaryState>::failure(
        recovered.error());
  }
  return load_locked();
}

common::Result<repository::AnniversaryOccurrenceSnapshot>
JsonAnniversaryTransaction::load_occurrence_snapshot() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto generations = coordinator_.load_generations();
  if (!generations.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        generations.error());
  }
  auto loaded = load_locked();
  if (!loaded.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        loaded.error());
  }
  const auto& values = generations.value();
  repository::AnniversaryOccurrenceSnapshot snapshot;
  snapshot.state = std::move(loaded.value());
  snapshot.generation =
      std::to_string(values.at("anniversaries")) + "-" +
      std::to_string(values.at("anniversary_recurrences")) + "-" +
      std::to_string(values.at("anniversary_reminder_templates"));
  return common::Result<repository::AnniversaryOccurrenceSnapshot>::success(
      std::move(snapshot));
}

common::Result<repository::AnniversaryState>
JsonAnniversaryTransaction::load_locked() {
  repository::AnniversaryState state;
  for (const auto& data_store : kDataStores) {
    auto root = store_.read_json_file(data_store.file_name);
    if (!root.ok()) {
      return common::Result<repository::AnniversaryState>::failure(root.error());
    }
    if (!root.value().has_value()) {
      return common::Result<repository::AnniversaryState>::failure(
          storage_data_corrupted("v3 Store is missing", data_store.file_name));
    }
    auto decoded = decode_anniversary_store(
        data_store.file_name, *root.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::AnniversaryState>::failure(
          decoded.error());
    }
  }
  auto valid = validate_anniversary_state(state);
  return valid.ok()
             ? common::Result<repository::AnniversaryState>::success(
                   std::move(state))
             : common::Result<repository::AnniversaryState>::failure(
                   valid.error());
}

common::Result<common::Unit>
JsonAnniversaryTransaction::commit_changed_stores_locked(
    std::string operation,
    std::string transaction_id,
    std::string prepared_at,
    const repository::AnniversaryState& before,
    const repository::AnniversaryState& after) {
  auto generations = coordinator_.load_generations();
  if (!generations.ok()) {
    return common::Result<common::Unit>::failure(generations.error());
  }
  picojson::object after_stores;
  CalendarWorkflowCoordinator::GenerationMap before_generation;
  for (const auto& data_store : kDataStores) {
    auto encoded_before = encode_anniversary_store(data_store.file_name, before);
    if (!encoded_before.ok()) {
      return common::Result<common::Unit>::failure(encoded_before.error());
    }
    auto encoded_after = encode_anniversary_store(data_store.file_name, after);
    if (!encoded_after.ok()) {
      return common::Result<common::Unit>::failure(encoded_after.error());
    }
    if (encoded_before.value().serialize() ==
        encoded_after.value().serialize()) {
      continue;
    }
    after_stores[data_store.logical_name] = std::move(encoded_after.value());
    before_generation[data_store.logical_name] =
        generations.value().at(data_store.logical_name);
  }
  if (after_stores.empty()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  CalendarWorkflowCoordinator::CommitRequest request;
  request.operation = std::move(operation);
  request.transaction_id = std::move(transaction_id);
  request.prepared_at = std::move(prepared_at);
  request.before_generation = std::move(before_generation);
  request.after_stores = std::move(after_stores);
  return coordinator_.execute(request);
}

common::Result<common::Unit> JsonAnniversaryTransaction::execute(
    std::string_view operation,
    std::string transaction_id,
    std::string prepared_at,
    const Operation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  const auto mapped_operation = v3_operation(operation);
  if (mapped_operation.empty() || !common::is_uuid(transaction_id) ||
      !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Anniversary transaction metadata is invalid"}}));
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = coordinator_.recover();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) {
    return common::Result<common::Unit>::failure(loaded.error());
  }
  auto after = loaded.value();
  auto result = action(after);
  if (!result.ok()) return result;
  auto valid = validate_anniversary_state(after);
  if (!valid.ok()) return valid;
  return commit_changed_stores_locked(mapped_operation,
                                      std::move(transaction_id),
                                      std::move(prepared_at), loaded.value(),
                                      after);
}

}  // namespace excellent_calendar::storage::json
