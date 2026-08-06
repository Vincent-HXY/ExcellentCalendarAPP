#include "excellent_calendar/storage/json/json_event_reminder_transaction.hpp"

#include <exception>
#include <optional>
#include <string>

#include <picojson/picojson.h>

namespace excellent_calendar::storage::json {
namespace {

constexpr const char* kJournalFile = "event_reminder_transaction.json";
constexpr const char* kEventsFile = "events.json";
constexpr const char* kRemindersFile = "reminders.json";

struct Snapshot {
  std::optional<picojson::value> events;
  std::optional<picojson::value> reminders;
};

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR",
      "Native internal error",
      {{"reason", std::move(reason)}});
}

common::Result<Snapshot> read_snapshot(AtomicJsonFileStore& store) {
  auto events = store.read_json_file(kEventsFile);
  if (!events.ok()) {
    return common::Result<Snapshot>::failure(events.error());
  }
  auto reminders = store.read_json_file(kRemindersFile);
  if (!reminders.ok()) {
    return common::Result<Snapshot>::failure(reminders.error());
  }
  return common::Result<Snapshot>::success(Snapshot{events.value(), reminders.value()});
}

picojson::value snapshot_to_journal(const Snapshot& snapshot) {
  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["events_exists"] = picojson::value(snapshot.events.has_value());
  root["events"] = snapshot.events.value_or(picojson::value());
  root["reminders_exists"] = picojson::value(snapshot.reminders.has_value());
  root["reminders"] = snapshot.reminders.value_or(picojson::value());
  return picojson::value(std::move(root));
}

common::Result<Snapshot> snapshot_from_journal(const picojson::value& journal) {
  if (!journal.is<picojson::object>()) {
    return common::Result<Snapshot>::failure(storage_data_corrupted("transaction journal root must be object"));
  }
  const auto& root = journal.get<picojson::object>();
  const auto version = root.find("storage_version");
  const auto events_exists = root.find("events_exists");
  const auto events = root.find("events");
  const auto reminders_exists = root.find("reminders_exists");
  const auto reminders = root.find("reminders");
  if (version == root.end() || !version->second.is<double>() || version->second.get<double>() != 1.0 ||
      events_exists == root.end() || !events_exists->second.is<bool>() || events == root.end() ||
      reminders_exists == root.end() || !reminders_exists->second.is<bool>() || reminders == root.end()) {
    return common::Result<Snapshot>::failure(storage_data_corrupted("transaction journal schema is invalid"));
  }

  Snapshot snapshot;
  if (events_exists->second.get<bool>()) {
    if (events->second.is<picojson::null>()) {
      return common::Result<Snapshot>::failure(storage_data_corrupted("transaction events snapshot is missing"));
    }
    snapshot.events = events->second;
  }
  if (reminders_exists->second.get<bool>()) {
    if (reminders->second.is<picojson::null>()) {
      return common::Result<Snapshot>::failure(storage_data_corrupted("transaction reminders snapshot is missing"));
    }
    snapshot.reminders = reminders->second;
  }
  return common::Result<Snapshot>::success(std::move(snapshot));
}

common::Result<common::Unit> restore_snapshot(AtomicJsonFileStore& store, const Snapshot& snapshot) {
  auto events = snapshot.events.has_value()
                    ? store.write_json_file(kEventsFile, *snapshot.events)
                    : store.remove_file(kEventsFile);
  if (!events.ok()) {
    return events;
  }
  auto reminders = snapshot.reminders.has_value()
                       ? store.write_json_file(kRemindersFile, *snapshot.reminders)
                       : store.remove_file(kRemindersFile);
  if (!reminders.ok()) {
    return reminders;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

}  // namespace

JsonEventReminderTransaction::JsonEventReminderTransaction(std::filesystem::path storage_directory)
    : store_(std::move(storage_directory)) {}

common::Result<common::Unit> JsonEventReminderTransaction::initialize() {
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) {
    return initialized;
  }
  return recover_locked();
}

common::Result<common::Unit> JsonEventReminderTransaction::execute(const Operation& operation) {
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) {
    return recovered;
  }

  auto snapshot = read_snapshot(store_);
  if (!snapshot.ok()) {
    return common::Result<common::Unit>::failure(snapshot.error());
  }
  auto journaled = store_.write_json_file(kJournalFile, snapshot_to_journal(snapshot.value()));
  if (!journaled.ok()) {
    return journaled;
  }

  common::Result<common::Unit> result = common::Result<common::Unit>::failure(
      internal_error("transaction operation did not complete"));
  try {
    result = operation();
  } catch (const std::exception& error) {
    result = common::Result<common::Unit>::failure(internal_error(error.what()));
  } catch (...) {
    result = common::Result<common::Unit>::failure(internal_error("unknown transaction exception"));
  }

  if (!result.ok()) {
    auto restored = restore_snapshot(store_, snapshot.value());
    if (!restored.ok()) {
      return restored;
    }
    auto removed = store_.remove_file(kJournalFile);
    if (!removed.ok()) {
      return removed;
    }
    return result;
  }

  auto committed = store_.remove_file(kJournalFile);
  if (committed.ok()) {
    return result;
  }

  auto restored = restore_snapshot(store_, snapshot.value());
  if (!restored.ok()) {
    return restored;
  }
  auto removed = store_.remove_file(kJournalFile);
  if (!removed.ok()) {
    return removed;
  }
  return committed;
}

common::Result<common::Unit> JsonEventReminderTransaction::recover_locked() {
  auto journal = store_.read_json_file(kJournalFile);
  if (!journal.ok()) {
    return common::Result<common::Unit>::failure(journal.error());
  }
  if (!journal.value().has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }

  auto snapshot = snapshot_from_journal(*journal.value());
  if (!snapshot.ok()) {
    return common::Result<common::Unit>::failure(snapshot.error());
  }
  auto restored = restore_snapshot(store_, snapshot.value());
  if (!restored.ok()) {
    return restored;
  }
  return store_.remove_file(kJournalFile);
}

}  // namespace excellent_calendar::storage::json
