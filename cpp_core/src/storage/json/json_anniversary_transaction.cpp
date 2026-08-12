#include "excellent_calendar/storage/json/json_anniversary_transaction.hpp"

#include <array>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/anniversary_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr const char* kJournalFile = "anniversary_workflow_transactions.json";

struct DataStore {
  const char* logical_name;
  const char* file_name;
};

constexpr std::array<DataStore, 2> kDataStores{{
    {"anniversaries", "anniversaries.json"},
    {"anniversary_recurrences", "anniversary_recurrences.json"},
}};

const std::set<std::string> kOperations = {
    "anniversary_create",
    "anniversary_update",
    "anniversary_delete",
};

common::Error corrupted(std::string reason) {
  return storage_data_corrupted(
      std::move(reason), "anniversary_workflow_transactions.json");
}

common::Error runtime_revoked() {
  return common::make_error(
      "STORAGE_NOT_INITIALIZED", "Native storage has not been initialized",
      {{"operation", "anniversary_transaction"}});
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

common::Result<picojson::object> parse_after_stores(
    const picojson::value& journal,
    std::string& journal_state) {
  if (!journal.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal root must be object"));
  }
  const auto& root = journal.get<picojson::object>();
  if (root.size() != 2U || root.find("storage_version") == root.end() ||
      root.find("transactions") == root.end() ||
      !root.at("storage_version").is<double>() ||
      root.at("storage_version").get<double>() != 2.0 ||
      !root.at("transactions").is<picojson::array>()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal envelope is invalid"));
  }
  const auto& transactions = root.at("transactions").get<picojson::array>();
  if (transactions.empty()) {
    return common::Result<picojson::object>::success(picojson::object{});
  }
  if (transactions.size() != 1U || !transactions.front().is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal must contain at most one transaction"));
  }
  const auto& item = transactions.front().get<picojson::object>();
  const std::set<std::string> keys = {
      "transaction_id", "operation", "intent_version", "intent",
      "affected_stores", "state", "prepared_at", "committed_at"};
  if (item.size() != keys.size()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal transaction fields are invalid"));
  }
  for (const auto& key : keys) {
    if (item.find(key) == item.end()) {
      return common::Result<picojson::object>::failure(
          corrupted("journal transaction field is missing"));
    }
  }
  if (!item.at("transaction_id").is<std::string>() ||
      !common::is_uuid(item.at("transaction_id").get<std::string>()) ||
      !item.at("operation").is<std::string>() ||
      kOperations.count(item.at("operation").get<std::string>()) == 0U ||
      !item.at("intent_version").is<double>() ||
      item.at("intent_version").get<double>() != 1.0 ||
      !item.at("intent").is<picojson::object>() ||
      !item.at("affected_stores").is<picojson::array>() ||
      !item.at("state").is<std::string>() ||
      !item.at("prepared_at").is<std::string>() ||
      !common::is_iso8601_utc_datetime(item.at("prepared_at").get<std::string>())) {
    return common::Result<picojson::object>::failure(
        corrupted("journal transaction values are invalid"));
  }
  journal_state = item.at("state").get<std::string>();
  if (journal_state != "prepared" && journal_state != "committed") {
    return common::Result<picojson::object>::failure(corrupted("journal state is invalid"));
  }
  if ((journal_state == "prepared" && !item.at("committed_at").is<picojson::null>()) ||
      (journal_state == "committed" &&
       (!item.at("committed_at").is<std::string>() ||
        !common::is_iso8601_utc_datetime(
            item.at("committed_at").get<std::string>())))) {
    return common::Result<picojson::object>::failure(
        corrupted("journal commit timestamp is invalid"));
  }
  if (journal_state == "committed") {
    const auto prepared = common::parse_iso8601_utc_epoch_seconds(
        item.at("prepared_at").get<std::string>());
    const auto committed = common::parse_iso8601_utc_epoch_seconds(
        item.at("committed_at").get<std::string>());
    if (!prepared.has_value() || !committed.has_value() || *committed < *prepared) {
      return common::Result<picojson::object>::failure(
          corrupted("journal commit timestamp precedes preparation"));
    }
  }

  std::set<std::string> affected;
  for (const auto& value : item.at("affected_stores").get<picojson::array>()) {
    if (!value.is<std::string>() ||
        !affected.insert(value.get<std::string>()).second) {
      return common::Result<picojson::object>::failure(
          corrupted("journal affected stores are invalid"));
    }
  }
  for (const auto& store : kDataStores) {
    if (affected.erase(store.logical_name) != 1U) {
      return common::Result<picojson::object>::failure(
          corrupted("journal affected stores are incomplete"));
    }
  }
  if (!affected.empty()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal affected stores contain unknown values"));
  }

  const auto& intent = item.at("intent").get<picojson::object>();
  if (intent.size() != 1U || intent.find("after_stores") == intent.end() ||
      !intent.at("after_stores").is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal intent codec is invalid"));
  }
  auto after = intent.at("after_stores").get<picojson::object>();
  if (after.size() != kDataStores.size()) {
    return common::Result<picojson::object>::failure(
        corrupted("journal after-state is incomplete"));
  }
  repository::AnniversaryState validation_state;
  for (const auto& store : kDataStores) {
    const auto found = after.find(store.logical_name);
    if (found == after.end()) {
      return common::Result<picojson::object>::failure(
          corrupted("journal after-state logical store is missing"));
    }
    auto decoded = decode_anniversary_store(store.file_name, found->second, validation_state);
    if (!decoded.ok()) return common::Result<picojson::object>::failure(decoded.error());
  }
  auto valid = validate_anniversary_state(validation_state);
  if (!valid.ok()) return common::Result<picojson::object>::failure(valid.error());
  return common::Result<picojson::object>::success(std::move(after));
}

picojson::value prepared_journal(
    std::string_view operation,
    const std::string& transaction_id,
    const std::string& prepared_at,
    const picojson::object& after_stores) {
  std::vector<std::string> stores;
  for (const auto& store : kDataStores) stores.emplace_back(store.logical_name);
  picojson::object intent;
  intent["after_stores"] = picojson::value(after_stores);
  picojson::object item;
  item["transaction_id"] = picojson::value(transaction_id);
  item["operation"] = picojson::value(std::string(operation));
  item["intent_version"] = picojson::value(1.0);
  item["intent"] = picojson::value(std::move(intent));
  item["affected_stores"] = string_array(stores);
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

picojson::value committed_journal(
    picojson::value journal,
    const std::string& committed_at) {
  auto& item = journal.get<picojson::object>()
                   .at("transactions")
                   .get<picojson::array>()
                   .front()
                   .get<picojson::object>();
  item["state"] = picojson::value("committed");
  item["committed_at"] = picojson::value(committed_at);
  return journal;
}

}  // namespace

JsonAnniversaryTransaction::JsonAnniversaryTransaction(
    std::filesystem::path storage_directory,
    FailureHook failure_hook,
    std::shared_ptr<storage::RuntimeStorageLease> runtime_lease)
    : store_(std::move(storage_directory)),
      failure_hook_(std::move(failure_hook)),
      runtime_lease_(std::move(runtime_lease)) {}

common::Result<common::Unit> JsonAnniversaryTransaction::initialize() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<common::Unit>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) return initialized;
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto ensured = ensure_stores_locked();
  if (!ensured.ok()) return ensured;
  auto loaded = load_locked();
  return loaded.ok() ? validate_anniversary_state(loaded.value())
                     : common::Result<common::Unit>::failure(loaded.error());
}

common::Result<repository::AnniversaryState> JsonAnniversaryTransaction::load() {
  auto runtime_access = runtime_lease_ ? runtime_lease_->acquire() : std::nullopt;
  if (runtime_lease_ && !runtime_access.has_value()) {
    return common::Result<repository::AnniversaryState>::failure(runtime_revoked());
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) {
    return common::Result<repository::AnniversaryState>::failure(recovered.error());
  }
  return load_locked();
}

common::Result<repository::AnniversaryState> JsonAnniversaryTransaction::load_locked() {
  repository::AnniversaryState state;
  for (const auto& store : kDataStores) {
    auto root = store_.read_json_file(store.file_name);
    if (!root.ok()) {
      return common::Result<repository::AnniversaryState>::failure(root.error());
    }
    if (!root.value().has_value()) {
      return common::Result<repository::AnniversaryState>::failure(
          corrupted(std::string(store.file_name) + " is missing"));
    }
    auto decoded = decode_anniversary_store(store.file_name, *root.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::AnniversaryState>::failure(decoded.error());
    }
  }
  auto valid = validate_anniversary_state(state);
  return valid.ok()
             ? common::Result<repository::AnniversaryState>::success(std::move(state))
             : common::Result<repository::AnniversaryState>::failure(valid.error());
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
  if (kOperations.count(std::string(operation)) == 0U ||
      !common::is_uuid(transaction_id) ||
      !common::is_iso8601_utc_datetime(prepared_at)) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "Anniversary transaction metadata is invalid"}}));
  }
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto loaded = load_locked();
  if (!loaded.ok()) return common::Result<common::Unit>::failure(loaded.error());
  auto state = std::move(loaded.value());
  auto result = action(state);
  if (!result.ok()) return result;
  auto valid = validate_anniversary_state(state);
  if (!valid.ok()) return valid;

  picojson::object after_stores;
  for (const auto& store : kDataStores) {
    auto encoded = encode_anniversary_store(store.file_name, state);
    if (!encoded.ok()) return common::Result<common::Unit>::failure(encoded.error());
    after_stores[store.logical_name] = std::move(encoded.value());
  }
  auto journal = prepared_journal(operation, transaction_id, prepared_at, after_stores);
  auto journaled = store_.write_json_file(kJournalFile, journal);
  if (!journaled.ok()) return journaled;
  auto hook = call_hook("after_prepare");
  if (!hook.ok()) return hook;
  auto applied = apply_after_stores_locked(after_stores, true);
  if (!applied.ok()) return applied;
  auto committed = store_.write_json_file(
      kJournalFile, committed_journal(journal, prepared_at));
  if (!committed.ok()) return committed;
  hook = call_hook("after_commit");
  if (!hook.ok()) return hook;
  return store_.write_json_file(kJournalFile, empty_journal());
}

common::Result<common::Unit> JsonAnniversaryTransaction::recover_locked() {
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (!journal.value().has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  std::string state;
  auto after_stores = parse_after_stores(*journal.value(), state);
  if (!after_stores.ok()) {
    return common::Result<common::Unit>::failure(after_stores.error());
  }
  if (!after_stores.value().empty()) {
    auto applied = apply_after_stores_locked(after_stores.value(), false);
    if (!applied.ok()) return applied;
  }
  return store_.write_json_file(kJournalFile, empty_journal());
}

common::Result<common::Unit> JsonAnniversaryTransaction::ensure_stores_locked() {
  std::vector<const DataStore*> missing;
  repository::AnniversaryState existing_state;
  for (const auto& store : kDataStores) {
    auto root = store_.read_json_file(store.file_name);
    if (!root.ok()) return common::Result<common::Unit>::failure(root.error());
    if (!root.value().has_value()) {
      missing.push_back(&store);
      continue;
    }
    auto decoded = decode_anniversary_store(store.file_name, *root.value(), existing_state);
    if (!decoded.ok()) return decoded;
  }
  const bool existing_data = !existing_state.anniversaries.empty() ||
                             !existing_state.recurrences.empty();
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (existing_data && (!missing.empty() || !journal.value().has_value())) {
    return common::Result<common::Unit>::failure(
        corrupted("Anniversary store set is incomplete"));
  }
  if (!journal.value().has_value()) {
    auto created = store_.write_json_file(kJournalFile, empty_journal());
    if (!created.ok()) return created;
  } else {
    std::string journal_state;
    auto parsed = parse_after_stores(*journal.value(), journal_state);
    if (!parsed.ok()) return common::Result<common::Unit>::failure(parsed.error());
    if (!parsed.value().empty()) {
      return common::Result<common::Unit>::failure(
          corrupted("Anniversary journal recovery did not complete"));
    }
  }
  for (const auto* store : missing) {
    auto created = store_.write_json_file(
        store->file_name, empty_anniversary_store(store->file_name));
    if (!created.ok()) return created;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> JsonAnniversaryTransaction::apply_after_stores_locked(
    const picojson::object& after_stores,
    bool invoke_hooks) {
  for (const auto& store : kDataStores) {
    const auto found = after_stores.find(store.logical_name);
    if (found == after_stores.end()) {
      return common::Result<common::Unit>::failure(
          corrupted("Anniversary after-state store is missing"));
    }
    auto written = store_.write_json_file(store.file_name, found->second);
    if (!written.ok()) return written;
    if (invoke_hooks) {
      auto hook = call_hook(std::string("after_") + store.logical_name);
      if (!hook.ok()) return hook;
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> JsonAnniversaryTransaction::call_hook(
    std::string_view phase) const {
  return failure_hook_ ? failure_hook_(phase)
                       : common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::storage::json
