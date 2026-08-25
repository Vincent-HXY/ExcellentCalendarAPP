#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"

#include <array>
#include <string>
#include <utility>

#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

struct DataStore {
  const char* logical_name;
  const char* file_name;
};

constexpr std::array<DataStore, 9> kDataStores{{
    {"events", "events.json"},
    {"recurrence_versions", "recurrence_versions.json"},
    {"event_occurrence_states", "event_occurrence_states.json"},
    {"anniversaries", "anniversaries.json"},
    {"anniversary_recurrences", "anniversary_recurrences.json"},
    {"anniversary_reminder_templates",
     "anniversary_reminder_templates.json"},
    {"reminders", "reminders.json"},
    {"notifications", "notifications.json"},
    {"reminder_recovery_batches", "reminder_recovery_batches.json"},
}};

common::Error runtime_revoked() {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
      {{"operation", "v3_transaction"}});
}

common::Error invalid_metadata() {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error",
      {{"reason", "workflow identity is invalid"}});
}

}  // namespace

JsonRecurringEventTransaction::JsonRecurringEventTransaction(
    std::filesystem::path storage_directory,
    FailureHook failure_hook,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : store_(storage_directory),
      coordinator_(std::move(storage_directory), std::move(failure_hook)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonRecurringEventTransaction::initialize() {
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
  return loaded.ok() ? validate_recurring_event_state(loaded.value())
                     : common::Result<common::Unit>::failure(loaded.error());
}

common::Result<repository::RecurringEventState>
JsonRecurringEventTransaction::load() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::RecurringEventState>::failure(
        runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = coordinator_.recover();
  if (!recovered.ok()) {
    return common::Result<repository::RecurringEventState>::failure(
        recovered.error());
  }
  return load_locked();
}

common::Result<repository::RecurringEventState>
JsonRecurringEventTransaction::load_locked() {
  repository::RecurringEventState state;
  for (const auto& data_store : kDataStores) {
    auto root = store_.read_json_file(data_store.file_name);
    if (!root.ok()) {
      return common::Result<repository::RecurringEventState>::failure(
          root.error());
    }
    if (!root.value().has_value()) {
      return common::Result<repository::RecurringEventState>::failure(
          storage_data_corrupted("v3 Store is missing", data_store.file_name));
    }
    auto decoded = decode_recurring_event_store(
        data_store.file_name, *root.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::RecurringEventState>::failure(
          decoded.error());
    }
  }
  auto valid = validate_recurring_event_state(state);
  return valid.ok()
             ? common::Result<repository::RecurringEventState>::success(
                   std::move(state))
             : common::Result<repository::RecurringEventState>::failure(
                   valid.error());
}

common::Result<common::Unit>
JsonRecurringEventTransaction::commit_changed_stores_locked(
    std::string operation,
    std::string transaction_id,
    std::string prepared_at,
    const repository::RecurringEventState& before,
    const repository::RecurringEventState& after) {
  auto generations = coordinator_.load_generations();
  if (!generations.ok()) {
    return common::Result<common::Unit>::failure(generations.error());
  }
  picojson::object after_stores;
  CalendarWorkflowCoordinator::GenerationMap before_generation;
  for (const auto& data_store : kDataStores) {
    auto encoded_before =
        encode_recurring_event_store(data_store.file_name, before);
    if (!encoded_before.ok()) {
      return common::Result<common::Unit>::failure(encoded_before.error());
    }
    auto encoded_after = encode_recurring_event_store(data_store.file_name, after);
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

common::Result<common::Unit>
JsonRecurringEventTransaction::prepare_notification(
    const NotificationPrepareOperation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = coordinator_.recover();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) {
    return common::Result<common::Unit>::failure(loaded.error());
  }
  auto after = loaded.value();
  auto result = action(loaded.value(), after.notifications);
  if (!result.ok()) return result;
  auto valid = validate_recurring_event_state(after);
  if (!valid.ok()) return valid;
  return commit_changed_stores_locked(
      "delivery_finalize_notification_reminder_and_successor",
      common::generate_uuid_v4(), common::utc_now_iso8601(), loaded.value(),
      after);
}

common::Result<common::Unit> JsonRecurringEventTransaction::update_reminders(
    const ReminderUpdateOperation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = coordinator_.recover();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) {
    return common::Result<common::Unit>::failure(loaded.error());
  }
  auto after = loaded.value();
  auto result = action(loaded.value(), after.reminders);
  if (!result.ok()) return result;
  auto valid = validate_recurring_event_state(after);
  if (!valid.ok()) return valid;
  return commit_changed_stores_locked(
      "occurrence_state_and_reminder_transition", common::generate_uuid_v4(),
      common::utc_now_iso8601(), loaded.value(), after);
}

common::Result<common::Unit> JsonRecurringEventTransaction::execute(
    std::string_view operation,
    std::string transaction_id,
    std::string prepared_at,
    const Operation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  if (!common::is_uuid(transaction_id) ||
      !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(invalid_metadata());
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
  auto valid = validate_recurring_event_state(after);
  if (!valid.ok()) return valid;
  return commit_changed_stores_locked(std::string(operation),
                                      std::move(transaction_id),
                                      std::move(prepared_at), loaded.value(),
                                      after);
}

}  // namespace excellent_calendar::storage::json
