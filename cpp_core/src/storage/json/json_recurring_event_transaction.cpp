#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"

#include <iterator>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr const char* kJournalFile = "workflow_transactions.json";
struct DataStore {
  const char* logical_name;
  const char* file_name;
};

constexpr DataStore kDataStores[] = {
    {"events", "events.json"},
    {"recurrence_versions", "recurrence_versions.json"},
    {"event_occurrence_states", "event_occurrence_states.json"},
    {"reminders", "reminders.json"},
    {"notifications", "notifications.json"},
    {"reminder_recovery_batches", "reminder_recovery_batches.json"},
};

const std::set<std::string> kOperations = {
    "event_recurrence_and_first_reminder_create_or_update",
    "occurrence_state_and_reminder_transition",
    "delivery_finalize_notification_reminder_and_successor",
    "recovery_batch_reminders_and_summary",
    "series_complete_cancel_delete_or_reopen",
};

common::Error corrupted(std::string reason) {
  return storage_data_corrupted(std::move(reason), "workflow_transactions.json");
}

common::Error runtime_revoked() {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
      {{"operation", "v2_transaction"}});
}

picojson::value empty_journal() {
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root["transactions"] = picojson::value(picojson::array{});
  return picojson::value(std::move(root));
}

picojson::value string_array(const std::vector<std::string>& values) {
  picojson::array result;
  for (const auto& value : values) result.emplace_back(value);
  return picojson::value(std::move(result));
}

common::Result<picojson::object> parse_after_stores(const picojson::value& journal,
                                                    std::string& state) {
  if (!journal.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(corrupted("journal root must be object"));
  }
  const auto& root = journal.get<picojson::object>();
  if (root.size() != 2U || root.find("storage_version") == root.end() ||
      root.find("transactions") == root.end() ||
      !root.at("storage_version").is<double>() || root.at("storage_version").get<double>() != 2.0 ||
      !root.at("transactions").is<picojson::array>()) {
    return common::Result<picojson::object>::failure(corrupted("journal envelope is invalid"));
  }
  const auto& transactions = root.at("transactions").get<picojson::array>();
  if (transactions.empty()) {
    return common::Result<picojson::object>::success(picojson::object{});
  }
  if (transactions.size() != 1U || !transactions.front().is<picojson::object>()) {
    return common::Result<picojson::object>::failure(corrupted("journal must contain at most one transaction"));
  }
  const auto& item = transactions.front().get<picojson::object>();
  const std::set<std::string> keys = {"transaction_id", "operation", "intent_version", "intent",
                                      "affected_stores", "state", "prepared_at", "committed_at"};
  if (item.size() != keys.size()) {
    return common::Result<picojson::object>::failure(corrupted("journal transaction fields are invalid"));
  }
  for (const auto& key : keys) {
    if (item.find(key) == item.end()) {
      return common::Result<picojson::object>::failure(corrupted("journal transaction field is missing"));
    }
  }
  if (!item.at("transaction_id").is<std::string>() ||
      !common::is_uuid(item.at("transaction_id").get<std::string>()) ||
      !item.at("operation").is<std::string>() ||
      kOperations.find(item.at("operation").get<std::string>()) == kOperations.end() ||
      !item.at("intent_version").is<double>() || item.at("intent_version").get<double>() != 1.0 ||
      !item.at("affected_stores").is<picojson::array>() || !item.at("state").is<std::string>() ||
      !item.at("prepared_at").is<std::string>() ||
      !common::is_iso8601_utc_datetime(item.at("prepared_at").get<std::string>())) {
    return common::Result<picojson::object>::failure(corrupted("journal transaction values are invalid"));
  }
  state = item.at("state").get<std::string>();
  if (state != "prepared" && state != "committed") {
    return common::Result<picojson::object>::failure(corrupted("journal state is invalid"));
  }
  if ((state == "prepared" && !item.at("committed_at").is<picojson::null>()) ||
      (state == "committed" &&
       (!item.at("committed_at").is<std::string>() ||
        !common::is_iso8601_utc_datetime(item.at("committed_at").get<std::string>())))) {
    return common::Result<picojson::object>::failure(corrupted("journal commit timestamp is invalid"));
  }
  std::set<std::string> affected;
  for (const auto& value : item.at("affected_stores").get<picojson::array>()) {
    if (!value.is<std::string>() || !affected.insert(value.get<std::string>()).second) {
      return common::Result<picojson::object>::failure(corrupted("journal affected stores are invalid"));
    }
  }
  repository::RecurringEventState validation_state;
  for (const auto& store : kDataStores) {
    if (affected.erase(store.logical_name) != 1U) {
      return common::Result<picojson::object>::failure(corrupted("journal affected stores are incomplete"));
    }
  }
  if (!affected.empty() || !item.at("intent").is<picojson::object>()) {
    return common::Result<picojson::object>::failure(corrupted("journal intent is invalid"));
  }
  const auto& intent = item.at("intent").get<picojson::object>();
  if (intent.size() != 1U || intent.find("after_stores") == intent.end() ||
      !intent.at("after_stores").is<picojson::object>()) {
    return common::Result<picojson::object>::failure(corrupted("journal intent codec is invalid"));
  }
  auto after = intent.at("after_stores").get<picojson::object>();
  if (after.size() != std::size(kDataStores)) {
    return common::Result<picojson::object>::failure(corrupted("journal after-state is incomplete"));
  }
  for (const auto& store : kDataStores) {
    if (after.find(store.logical_name) == after.end()) {
      return common::Result<picojson::object>::failure(
          corrupted("journal after-state logical store is missing"));
    }
    auto decoded = decode_recurring_event_store(
        store.file_name, after.at(store.logical_name), validation_state);
    if (!decoded.ok()) return common::Result<picojson::object>::failure(decoded.error());
  }
  auto valid = validate_recurring_event_state(validation_state);
  if (!valid.ok()) return common::Result<picojson::object>::failure(valid.error());
  return common::Result<picojson::object>::success(std::move(after));
}

picojson::value prepared_journal(std::string_view operation,
                                 const std::string& transaction_id,
                                 const std::string& prepared_at,
                                 const picojson::object& after_stores) {
  std::vector<std::string> files;
  for (const auto& store : kDataStores) files.emplace_back(store.logical_name);
  picojson::object intent;
  intent["after_stores"] = picojson::value(after_stores);
  picojson::object item;
  item["transaction_id"] = picojson::value(transaction_id);
  item["operation"] = picojson::value(std::string(operation));
  item["intent_version"] = picojson::value(1.0);
  item["intent"] = picojson::value(std::move(intent));
  item["affected_stores"] = string_array(files);
  item["state"] = picojson::value("prepared");
  item["prepared_at"] = picojson::value(prepared_at);
  item["committed_at"] = picojson::value();
  picojson::array transactions;
  transactions.emplace_back(std::move(item));
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root["transactions"] = picojson::value(std::move(transactions));
  return picojson::value(std::move(root));
}

picojson::value committed_journal(picojson::value journal, const std::string& committed_at) {
  auto& transaction = journal.get<picojson::object>()
                          .at("transactions")
                          .get<picojson::array>()
                          .front()
                          .get<picojson::object>();
  transaction["state"] = picojson::value("committed");
  transaction["committed_at"] = picojson::value(committed_at);
  return journal;
}

}  // namespace

JsonRecurringEventTransaction::JsonRecurringEventTransaction(
    std::filesystem::path storage_directory,
    FailureHook failure_hook,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : store_(std::move(storage_directory)),
      failure_hook_(std::move(failure_hook)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonRecurringEventTransaction::initialize() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) return initialized;
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto ensured = ensure_empty_stores_locked();
  if (!ensured.ok()) return ensured;
  auto loaded = load_locked();
  if (!loaded.ok()) return common::Result<common::Unit>::failure(loaded.error());
  return validate_recurring_event_state(loaded.value());
}

common::Result<repository::RecurringEventState> JsonRecurringEventTransaction::load() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::RecurringEventState>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) {
    return common::Result<repository::RecurringEventState>::failure(recovered.error());
  }
  return load_locked();
}

common::Result<repository::RecurringEventState> JsonRecurringEventTransaction::load_locked() {
  repository::RecurringEventState state;
  for (const auto& store : kDataStores) {
    auto value = store_.read_json_file(store.file_name);
    if (!value.ok()) return common::Result<repository::RecurringEventState>::failure(value.error());
    if (!value.value().has_value()) {
      return common::Result<repository::RecurringEventState>::failure(
          corrupted(std::string(store.file_name) + " is missing"));
    }
    auto decoded = decode_recurring_event_store(store.file_name, *value.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::RecurringEventState>::failure(decoded.error());
    }
  }
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return common::Result<repository::RecurringEventState>::failure(valid.error());
  return common::Result<repository::RecurringEventState>::success(std::move(state));
}

common::Result<common::Unit> JsonRecurringEventTransaction::prepare_notification(
    const NotificationPrepareOperation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) return common::Result<common::Unit>::failure(loaded.error());

  auto notifications = loaded.value().notifications;
  auto result = action(loaded.value(), notifications);
  if (!result.ok()) return result;
  auto state = loaded.value();
  state.notifications = std::move(notifications);
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return valid;
  auto encoded = encode_recurring_event_store("notifications.json", state);
  if (!encoded.ok()) return common::Result<common::Unit>::failure(encoded.error());
  return store_.write_json_file("notifications.json", encoded.value());
}

common::Result<common::Unit> JsonRecurringEventTransaction::update_reminders(
    const ReminderUpdateOperation& action) {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) return common::Result<common::Unit>::failure(loaded.error());

  auto reminders = loaded.value().reminders;
  auto result = action(loaded.value(), reminders);
  if (!result.ok()) return result;
  auto state = loaded.value();
  state.reminders = std::move(reminders);
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return valid;
  auto encoded = encode_recurring_event_store("reminders.json", state);
  if (!encoded.ok()) return common::Result<common::Unit>::failure(encoded.error());
  return store_.write_json_file("reminders.json", encoded.value());
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
  if (kOperations.find(std::string(operation)) == kOperations.end() ||
      !common::is_uuid(transaction_id) || !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", "workflow identity is invalid"}}));
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) return common::Result<common::Unit>::failure(loaded.error());
  auto state = loaded.value();
  auto result = action(state);
  if (!result.ok()) return result;
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return valid;

  picojson::object after_stores;
  for (const auto& store : kDataStores) {
    auto encoded = encode_recurring_event_store(store.file_name, state);
    if (!encoded.ok()) return common::Result<common::Unit>::failure(encoded.error());
    after_stores[store.logical_name] = encoded.value();
  }
  auto journal = prepared_journal(operation, transaction_id, prepared_at, after_stores);
  auto journaled = store_.write_json_file(kJournalFile, journal);
  if (!journaled.ok()) return journaled;
  auto hook = call_hook("after_prepare");
  if (!hook.ok()) return hook;

  auto applied = apply_after_stores_locked(after_stores);
  if (!applied.ok()) return applied;
  auto committed = store_.write_json_file(kJournalFile, committed_journal(journal, prepared_at));
  if (!committed.ok()) return committed;
  hook = call_hook("after_commit");
  if (!hook.ok()) return hook;
  return store_.write_json_file(kJournalFile, empty_journal());
}

common::Result<common::Unit> JsonRecurringEventTransaction::recover_locked() {
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (!journal.value().has_value()) return common::Result<common::Unit>::success(common::Unit{});
  std::string state;
  auto after_stores = parse_after_stores(*journal.value(), state);
  if (!after_stores.ok()) return common::Result<common::Unit>::failure(after_stores.error());
  if (!after_stores.value().empty()) {
    auto applied = apply_after_stores_locked(after_stores.value());
    if (!applied.ok()) return applied;
  }
  return store_.write_json_file(kJournalFile, empty_journal());
}

common::Result<common::Unit> JsonRecurringEventTransaction::ensure_empty_stores_locked() {
  repository::RecurringEventState existing_state;
  std::vector<std::string> missing_files;
  for (const auto& store : kDataStores) {
    auto existing = store_.read_json_file(store.file_name);
    if (!existing.ok()) return common::Result<common::Unit>::failure(existing.error());
    if (!existing.value().has_value()) {
      missing_files.emplace_back(store.file_name);
      continue;
    }
    auto decoded = decode_recurring_event_store(
        store.file_name, *existing.value(), existing_state);
    if (!decoded.ok()) return decoded;
  }
  const bool existing_data = !existing_state.events.empty() ||
                             !existing_state.recurrences.empty() ||
                             !existing_state.occurrence_states.empty() ||
                             !existing_state.reminders.empty() ||
                             !existing_state.notifications.empty() ||
                             !existing_state.recovery_batches.empty();
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (existing_data && (!missing_files.empty() || !journal.value().has_value())) {
    return common::Result<common::Unit>::failure(
        corrupted("non-empty v2 storage is incomplete"));
  }
  if (journal.value().has_value()) {
    std::string journal_state;
    auto parsed = parse_after_stores(*journal.value(), journal_state);
    if (!parsed.ok()) return common::Result<common::Unit>::failure(parsed.error());
    if (!parsed.value().empty()) {
      return common::Result<common::Unit>::failure(
          corrupted("initialization found an unapplied workflow transaction"));
    }
  }

  repository::RecurringEventState empty;
  for (const auto& file : missing_files) {
    auto encoded = encode_recurring_event_store(file, empty);
    if (!encoded.ok()) return common::Result<common::Unit>::failure(encoded.error());
    auto written = store_.write_json_file(file, encoded.value());
    if (!written.ok()) return written;
  }
  return journal.value().has_value() ? common::Result<common::Unit>::success(common::Unit{})
                                     : store_.write_json_file(kJournalFile, empty_journal());
}

common::Result<common::Unit> JsonRecurringEventTransaction::apply_after_stores_locked(
    const picojson::object& after_stores) {
  for (const auto& store : kDataStores) {
    const auto found = after_stores.find(store.logical_name);
    if (found == after_stores.end()) {
      return common::Result<common::Unit>::failure(corrupted("after-state file is missing"));
    }
    auto written = store_.write_json_file(store.file_name, found->second);
    if (!written.ok()) return written;
    auto hook = call_hook(std::string("after_store:") + store.file_name);
    if (!hook.ok()) return hook;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> JsonRecurringEventTransaction::call_hook(
    std::string_view phase) const {
  return failure_hook_ ? failure_hook_(phase)
                       : common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::storage::json
