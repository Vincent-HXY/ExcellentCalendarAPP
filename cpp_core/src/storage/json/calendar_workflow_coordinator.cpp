#include "excellent_calendar/storage/json/calendar_workflow_coordinator.hpp"

#include <algorithm>
#include <cmath>
#include <optional>
#include <set>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/category_json_codec.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr const char* kJournalFile = "calendar_workflow_transactions.json";
constexpr double kMaximumSafeInteger = 9007199254740991.0;

const std::set<std::string> kOperations = {
    "event_recurrence_and_first_reminder_create_or_update",
    "occurrence_state_and_reminder_transition",
    "delivery_finalize_notification_reminder_and_successor",
    "recovery_batch_reminders_and_summary",
    "series_complete_cancel_delete_or_reopen",
    "anniversary_create_with_reminders",
    "anniversary_update_with_reminders",
    "anniversary_delete_with_reminders",
    "anniversary_toggle_reminders",
    "anniversary_recovery_plan",
    "anniversary_delivery_finalize",
    "anniversary_timezone_recalculate",
};

bool is_integer(double value) {
  return std::isfinite(value) && std::floor(value) == value && value >= 0.0 &&
         value <= kMaximumSafeInteger;
}

std::set<std::string> exact_store_names() {
  std::set<std::string> names;
  for (const auto& store : calendar_core_v3_data_stores()) {
    names.insert(store.logical_name);
  }
  return names;
}

const CalendarCoreV3StoreDefinition* definition(std::string_view logical_name) {
  const auto& stores = calendar_core_v3_data_stores();
  const auto found = std::find_if(stores.begin(), stores.end(), [&](const auto& item) {
    return logical_name == item.logical_name;
  });
  return found == stores.end() ? nullptr : &*found;
}

common::Result<CalendarWorkflowCoordinator::GenerationMap> parse_generations(
    const picojson::value& value,
    const std::set<std::string>& expected) {
  if (!value.is<picojson::object>()) {
    return common::Result<CalendarWorkflowCoordinator::GenerationMap>::failure(
        calendar_workflow_recovery_failed("generation map must be object"));
  }
  const auto& object = value.get<picojson::object>();
  if (object.size() != expected.size()) {
    return common::Result<CalendarWorkflowCoordinator::GenerationMap>::failure(
        calendar_workflow_recovery_failed("generation map store set is invalid"));
  }
  CalendarWorkflowCoordinator::GenerationMap result;
  for (const auto& name : expected) {
    const auto found = object.find(name);
    if (found == object.end() || !found->second.is<double>() ||
        !is_integer(found->second.get<double>())) {
      return common::Result<CalendarWorkflowCoordinator::GenerationMap>::failure(
          calendar_workflow_recovery_failed("generation is missing or invalid"));
    }
    result[name] = static_cast<std::int64_t>(found->second.get<double>());
  }
  return common::Result<CalendarWorkflowCoordinator::GenerationMap>::success(
      std::move(result));
}

picojson::value generations_json(
    const CalendarWorkflowCoordinator::GenerationMap& generations) {
  picojson::object object;
  for (const auto& [name, value] : generations) {
    object[name] = picojson::value(static_cast<double>(value));
  }
  return picojson::value(std::move(object));
}

picojson::value string_array(const picojson::object& stores) {
  picojson::array values;
  for (const auto& [name, _] : stores) values.emplace_back(name);
  return picojson::value(std::move(values));
}

picojson::value journal_json(
    const CalendarWorkflowCoordinator::GenerationMap& generations,
    std::optional<picojson::object> transaction) {
  picojson::array transactions;
  if (transaction.has_value()) transactions.emplace_back(std::move(*transaction));
  picojson::object root;
  root["storage_version"] = picojson::value(3.0);
  root["generations"] = generations_json(generations);
  root["transactions"] = picojson::value(std::move(transactions));
  return picojson::value(std::move(root));
}

common::Result<common::Unit> validate_transaction_shape(
    const picojson::object& item,
    const CalendarWorkflowCoordinator::GenerationMap& generations) {
  const std::set<std::string> fields = {
      "transaction_id", "operation", "intent_version", "affected_stores",
      "before_generation", "after_stores", "state", "prepared_at",
      "committed_at"};
  if (item.size() != fields.size()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("workflow transaction fields are invalid"));
  }
  for (const auto& field : fields) {
    if (item.find(field) == item.end()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("workflow transaction field is missing"));
    }
  }
  if (!item.at("transaction_id").is<std::string>() ||
      !common::is_uuid(item.at("transaction_id").get<std::string>()) ||
      !item.at("operation").is<std::string>() ||
      kOperations.count(item.at("operation").get<std::string>()) == 0U ||
      !item.at("intent_version").is<double>() ||
      item.at("intent_version").get<double>() != 1.0 ||
      !item.at("affected_stores").is<picojson::array>() ||
      !item.at("before_generation").is<picojson::object>() ||
      !item.at("after_stores").is<picojson::object>() ||
      !item.at("state").is<std::string>() ||
      !item.at("prepared_at").is<std::string>() ||
      !common::is_iso8601_utc_datetime(
          item.at("prepared_at").get<std::string>())) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("workflow transaction values are invalid"));
  }
  std::set<std::string> affected;
  for (const auto& value : item.at("affected_stores").get<picojson::array>()) {
    if (!value.is<std::string>() || definition(value.get<std::string>()) == nullptr ||
        !affected.insert(value.get<std::string>()).second) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("affected stores are invalid"));
    }
  }
  const auto& after = item.at("after_stores").get<picojson::object>();
  if (affected.empty() || after.size() != affected.size()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("after-state store set is invalid"));
  }
  for (const auto& name : affected) {
    if (after.find(name) == after.end()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("after-state store is missing"));
    }
  }
  auto before = parse_generations(item.at("before_generation"), affected);
  if (!before.ok()) return common::Result<common::Unit>::failure(before.error());

  const auto state = item.at("state").get<std::string>();
  if (state == "prepared") {
    if (!item.at("committed_at").is<picojson::null>()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("prepared transaction has committed_at"));
    }
    for (const auto& name : affected) {
      if (generations.at(name) != before.value().at(name)) {
        return common::Result<common::Unit>::failure(
            calendar_workflow_recovery_failed(
                "prepared transaction generation is stale"));
      }
    }
  } else if (state == "committed") {
    if (!item.at("committed_at").is<std::string>() ||
        !common::is_iso8601_utc_datetime(
            item.at("committed_at").get<std::string>())) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("committed_at is invalid"));
    }
    for (const auto& name : affected) {
      if (before.value().at(name) >=
              static_cast<std::int64_t>(kMaximumSafeInteger) ||
          generations.at(name) != before.value().at(name) + 1) {
        return common::Result<common::Unit>::failure(
            calendar_workflow_recovery_failed(
                "committed transaction generation is invalid"));
      }
    }
  } else {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("workflow transaction state is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

bool matches_commit_request(
    const picojson::object& item,
    const CalendarWorkflowCoordinator::CommitRequest& request) {
  return item.at("transaction_id").get<std::string>() ==
             request.transaction_id &&
         item.at("operation").get<std::string>() == request.operation &&
         item.at("prepared_at").get<std::string>() == request.prepared_at &&
         item.at("before_generation").serialize() ==
             generations_json(request.before_generation).serialize() &&
         item.at("after_stores").serialize() ==
             picojson::value(request.after_stores).serialize();
}

}  // namespace

const std::vector<CalendarCoreV3StoreDefinition>&
calendar_core_v3_data_stores() {
  static const std::vector<CalendarCoreV3StoreDefinition> stores = {
      {"categories", "categories.json", "categories"},
      {"events", "events.json", "events"},
      {"recurrence_versions", "recurrence_versions.json",
       "recurrence_versions"},
      {"event_occurrence_states", "event_occurrence_states.json",
       "event_occurrence_states"},
      {"anniversaries", "anniversaries.json", "anniversaries"},
      {"anniversary_recurrences", "anniversary_recurrences.json",
       "anniversary_recurrences"},
      {"anniversary_reminder_templates",
       "anniversary_reminder_templates.json",
       "anniversary_reminder_templates"},
      {"reminders", "reminders.json", "reminders"},
      {"notifications", "notifications.json", "notifications"},
      {"reminder_recovery_batches", "reminder_recovery_batches.json",
       "reminder_recovery_batches"},
  };
  return stores;
}

common::Error calendar_workflow_commit_failed(std::string reason) {
  return common::make_error(
      "CALENDAR_WORKFLOW_COMMIT_FAILED",
      "Calendar workflow logical commit failed before becoming authoritative",
      {{"reason", std::move(reason)}}, true);
}

common::Error calendar_workflow_recovery_failed(std::string reason) {
  return common::make_error(
      "CALENDAR_WORKFLOW_RECOVERY_FAILED",
      "Calendar workflow recovery could not prove a complete authoritative state",
      {{"reason", std::move(reason)}});
}

CalendarWorkflowCoordinator::CalendarWorkflowCoordinator(
    std::filesystem::path storage_directory,
    FailureHook failure_hook)
    : store_(std::move(storage_directory)),
      failure_hook_(std::move(failure_hook)) {}

picojson::value CalendarWorkflowCoordinator::empty_journal() {
  GenerationMap generations;
  for (const auto& store : calendar_core_v3_data_stores()) {
    generations[store.logical_name] = 0;
  }
  return journal_json(generations, std::nullopt);
}

common::Result<common::Unit> CalendarWorkflowCoordinator::initialize() {
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) return initialized;
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (!journal.value().has_value()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("unified workflow journal is missing"));
  }
  return recover_locked();
}

common::Result<common::Unit> CalendarWorkflowCoordinator::recover() {
  auto lock = store_.acquire_directory_lock();
  return recover_locked();
}

common::Result<CalendarWorkflowCoordinator::GenerationMap>
CalendarWorkflowCoordinator::load_generations() {
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) {
    return common::Result<GenerationMap>::failure(recovered.error());
  }
  auto journal = read_journal_locked();
  return journal.ok()
             ? common::Result<GenerationMap>::success(
                   std::move(journal.value().generations))
             : common::Result<GenerationMap>::failure(journal.error());
}

common::Result<CalendarWorkflowCoordinator::JournalState>
CalendarWorkflowCoordinator::read_journal_locked() const {
  auto root = store_.read_json_file(kJournalFile);
  if (!root.ok()) return common::Result<JournalState>::failure(root.error());
  if (!root.value().has_value() || !root.value()->is<picojson::object>()) {
    return common::Result<JournalState>::failure(
        calendar_workflow_recovery_failed("workflow journal root is missing or invalid"));
  }
  const auto& object = root.value()->get<picojson::object>();
  if (object.size() != 3U || object.find("storage_version") == object.end() ||
      object.find("generations") == object.end() ||
      object.find("transactions") == object.end() ||
      !object.at("storage_version").is<double>() ||
      object.at("storage_version").get<double>() != 3.0 ||
      !object.at("transactions").is<picojson::array>()) {
    return common::Result<JournalState>::failure(
        calendar_workflow_recovery_failed("workflow journal envelope is invalid"));
  }
  auto generations =
      parse_generations(object.at("generations"), exact_store_names());
  if (!generations.ok()) {
    return common::Result<JournalState>::failure(generations.error());
  }
  const auto& transactions = object.at("transactions").get<picojson::array>();
  if (transactions.size() > 1U ||
      (!transactions.empty() && !transactions.front().is<picojson::object>())) {
    return common::Result<JournalState>::failure(
        calendar_workflow_recovery_failed(
            "workflow journal must contain at most one transaction"));
  }
  JournalState result;
  result.generations = std::move(generations.value());
  if (!transactions.empty()) {
    result.transaction = transactions.front().get<picojson::object>();
    auto valid = validate_transaction_shape(*result.transaction,
                                            result.generations);
    if (!valid.ok()) return common::Result<JournalState>::failure(valid.error());
  }
  return common::Result<JournalState>::success(std::move(result));
}

common::Result<common::Unit>
CalendarWorkflowCoordinator::validate_candidate_locked(
    const picojson::object& after_stores) const {
  repository::RecurringEventState state;
  for (const auto& store : calendar_core_v3_data_stores()) {
    const picojson::value* root = nullptr;
    const auto after = after_stores.find(store.logical_name);
    std::optional<picojson::value> current;
    if (after != after_stores.end()) {
      root = &after->second;
    } else {
      auto read = store_.read_json_file(store.file_name);
      if (!read.ok()) return common::Result<common::Unit>::failure(read.error());
      if (!read.value().has_value()) {
        return common::Result<common::Unit>::failure(
            storage_data_corrupted("v3 Store is missing", store.file_name));
      }
      current = std::move(*read.value());
      root = &*current;
    }
    if (std::string_view(store.logical_name) == "categories") {
      auto categories = decode_category_store(*root, 3);
      if (!categories.ok()) {
        return common::Result<common::Unit>::failure(categories.error());
      }
      continue;
    }
    auto decoded = decode_recurring_event_store(store.file_name, *root, state);
    if (!decoded.ok()) return decoded;
  }
  return validate_recurring_event_state(state);
}

common::Result<common::Unit>
CalendarWorkflowCoordinator::apply_after_stores_locked(
    const picojson::object& after_stores,
    bool invoke_hooks) const {
  for (const auto& store : calendar_core_v3_data_stores()) {
    const auto found = after_stores.find(store.logical_name);
    if (found == after_stores.end()) continue;
    auto written = store_.write_json_file(store.file_name, found->second);
    if (!written.ok()) return written;
    if (invoke_hooks) {
      auto hook = call_hook(std::string("after_store:") + store.file_name);
      if (!hook.ok()) return hook;
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> CalendarWorkflowCoordinator::recover_locked() {
  auto journal = read_journal_locked();
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (!journal.value().transaction.has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  auto item = *journal.value().transaction;
  const auto state = item.at("state").get<std::string>();
  if (state == "prepared") {
    const auto& after = item.at("after_stores").get<picojson::object>();
    auto valid = validate_candidate_locked(after);
    if (!valid.ok()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed(valid.error().message));
    }
    auto applied = apply_after_stores_locked(after, false);
    if (!applied.ok()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed(applied.error().message));
    }
    const auto& before = item.at("before_generation").get<picojson::object>();
    for (const auto& [name, value] : before) {
      journal.value().generations[name] =
          static_cast<std::int64_t>(value.get<double>()) + 1;
    }
    item["state"] = picojson::value("committed");
    item["committed_at"] = item.at("prepared_at");
    auto committed = store_.write_json_file(
        kJournalFile,
        journal_json(journal.value().generations, item));
    if (!committed.ok()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed(committed.error().message));
    }
  }
  auto compacted = store_.write_json_file(
      kJournalFile, journal_json(journal.value().generations, std::nullopt));
  // A committed marker already proves the Stores and generations are
  // authoritative. Compaction is retryable cleanup and cannot turn that
  // logical commit back into a recovery failure.
  static_cast<void>(compacted);
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> CalendarWorkflowCoordinator::execute(
    const CommitRequest& request) {
  if (kOperations.count(request.operation) == 0U ||
      !common::is_uuid(request.transaction_id) ||
      !common::is_iso8601_utc_datetime(request.prepared_at) ||
      request.after_stores.empty()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed("workflow commit metadata is invalid"));
  }
  auto lock = store_.acquire_directory_lock();
  auto existing = read_journal_locked();
  if (!existing.ok()) {
    return common::Result<common::Unit>::failure(existing.error());
  }
  if (existing.value().transaction.has_value() &&
      existing.value()
              .transaction->at("transaction_id")
              .get<std::string>() == request.transaction_id) {
    if (!matches_commit_request(*existing.value().transaction, request)) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_commit_failed(
              "transaction_id was reused with different commit content"));
    }
    auto replayed = recover_locked();
    return replayed.ok()
               ? common::Result<common::Unit>::success(common::Unit{})
               : common::Result<common::Unit>::failure(replayed.error());
  }
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto journal = read_journal_locked();
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());

  std::set<std::string> affected;
  for (const auto& [name, _] : request.after_stores) {
    if (definition(name) == nullptr || !affected.insert(name).second) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_commit_failed("affected Store is invalid"));
    }
  }
  if (request.before_generation.size() != affected.size()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed("before_generation is incomplete"));
  }
  for (const auto& name : affected) {
    const auto expected = request.before_generation.find(name);
    if (expected == request.before_generation.end() || expected->second < 0 ||
        expected->second >= static_cast<std::int64_t>(kMaximumSafeInteger) ||
        journal.value().generations.at(name) != expected->second) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_commit_failed(
              "Store generation changed before commit"));
    }
  }
  auto valid = validate_candidate_locked(request.after_stores);
  if (!valid.ok()) return valid;

  picojson::object item;
  item["transaction_id"] = picojson::value(request.transaction_id);
  item["operation"] = picojson::value(request.operation);
  item["intent_version"] = picojson::value(1.0);
  item["affected_stores"] = string_array(request.after_stores);
  item["before_generation"] = generations_json(request.before_generation);
  item["after_stores"] = picojson::value(request.after_stores);
  item["state"] = picojson::value("prepared");
  item["prepared_at"] = picojson::value(request.prepared_at);
  item["committed_at"] = picojson::value();
  auto prepared = store_.write_json_file(
      kJournalFile, journal_json(journal.value().generations, item));
  if (!prepared.ok()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed(prepared.error().message));
  }
  auto hook = call_hook("after_prepare");
  if (!hook.ok()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed(hook.error().message));
  }
  auto applied = apply_after_stores_locked(request.after_stores, true);
  if (!applied.ok()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed(applied.error().message));
  }
  for (const auto& name : affected) ++journal.value().generations[name];
  item["state"] = picojson::value("committed");
  item["committed_at"] = picojson::value(request.prepared_at);
  auto committed = store_.write_json_file(
      kJournalFile, journal_json(journal.value().generations, item));
  if (!committed.ok()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_commit_failed(committed.error().message));
  }
  hook = call_hook("after_commit");
  if (!hook.ok()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  hook = call_hook("before_compact");
  if (!hook.ok()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  auto compacted = store_.write_json_file(
      kJournalFile, journal_json(journal.value().generations, std::nullopt));
  // Once the committed journal is durable, compaction is cleanup only. Keep
  // the journal for the next recovery attempt if this write fails, while the
  // caller receives the authoritative committed result.
  static_cast<void>(compacted);
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> CalendarWorkflowCoordinator::call_hook(
    std::string_view phase) const {
  return failure_hook_ ? failure_hook_(phase)
                       : common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace excellent_calendar::storage::json
