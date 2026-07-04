#include "excellent_calendar/storage/json/json_snapshot_transaction.hpp"

#include <exception>
#include <set>

namespace excellent_calendar::storage::json {
namespace {

common::Error internal_error(std::string reason) {
  return common::make_error(
      "NATIVE_INTERNAL_ERROR", "Native internal error", {{"reason", std::move(reason)}});
}

}  // namespace

JsonSnapshotTransaction::JsonSnapshotTransaction(std::filesystem::path storage_directory,
                                                 std::string journal_file,
                                                 std::vector<std::string> data_files)
    : store_(std::move(storage_directory)),
      journal_file_(std::move(journal_file)),
      data_files_(std::move(data_files)) {}

common::Result<common::Unit> JsonSnapshotTransaction::initialize() {
  auto lock = store_.acquire_directory_lock();
  auto initialized = store_.initialize();
  if (!initialized.ok()) return initialized;
  return recover_locked();
}

common::Result<common::Unit> JsonSnapshotTransaction::execute(const Operation& operation) {
  auto lock = store_.acquire_directory_lock();
  auto recovered = recover_locked();
  if (!recovered.ok()) return recovered;
  auto snapshot = read_snapshot_locked();
  if (!snapshot.ok()) return common::Result<common::Unit>::failure(snapshot.error());
  auto journaled = store_.write_json_file(journal_file_, snapshot_to_json(snapshot.value()));
  if (!journaled.ok()) return journaled;

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
    auto restored = restore_snapshot_locked(snapshot.value());
    if (!restored.ok()) return restored;
    auto removed = store_.remove_file(journal_file_);
    return removed.ok() ? result : removed;
  }

  auto committed = store_.remove_file(journal_file_);
  if (committed.ok()) return result;
  auto restored = restore_snapshot_locked(snapshot.value());
  if (!restored.ok()) return restored;
  auto removed = store_.remove_file(journal_file_);
  return removed.ok() ? committed : removed;
}

common::Result<std::vector<JsonSnapshotTransaction::FileSnapshot>>
JsonSnapshotTransaction::read_snapshot_locked() {
  std::vector<FileSnapshot> snapshot;
  snapshot.reserve(data_files_.size());
  for (const auto& name : data_files_) {
    auto content = store_.read_json_file(name);
    if (!content.ok()) {
      return common::Result<std::vector<FileSnapshot>>::failure(content.error());
    }
    snapshot.push_back(FileSnapshot{name, content.value()});
  }
  return common::Result<std::vector<FileSnapshot>>::success(std::move(snapshot));
}

common::Result<common::Unit> JsonSnapshotTransaction::restore_snapshot_locked(
    const std::vector<FileSnapshot>& snapshot) {
  for (const auto& file : snapshot) {
    auto restored = file.content.has_value()
                        ? store_.write_json_file(file.name, *file.content)
                        : store_.remove_file(file.name);
    if (!restored.ok()) return restored;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

picojson::value JsonSnapshotTransaction::snapshot_to_json(
    const std::vector<FileSnapshot>& snapshot) const {
  picojson::array files;
  for (const auto& file : snapshot) {
    picojson::object item;
    item["name"] = picojson::value(file.name);
    item["exists"] = picojson::value(file.content.has_value());
    item["content"] = file.content.value_or(picojson::value());
    files.push_back(picojson::value(std::move(item)));
  }
  picojson::object root;
  root["storage_version"] = picojson::value(1.0);
  root["files"] = picojson::value(std::move(files));
  return picojson::value(std::move(root));
}

common::Result<std::vector<JsonSnapshotTransaction::FileSnapshot>>
JsonSnapshotTransaction::snapshot_from_json(const picojson::value& value) const {
  if (!value.is<picojson::object>()) {
    return common::Result<std::vector<FileSnapshot>>::failure(
        storage_data_corrupted("transaction journal root must be object"));
  }
  const auto& root = value.get<picojson::object>();
  const auto version = root.find("storage_version");
  const auto files = root.find("files");
  if (version == root.end() || !version->second.is<double>() || version->second.get<double>() != 1.0 ||
      files == root.end() || !files->second.is<picojson::array>()) {
    return common::Result<std::vector<FileSnapshot>>::failure(
        storage_data_corrupted("transaction journal schema is invalid"));
  }

  std::set<std::string> expected(data_files_.begin(), data_files_.end());
  std::vector<FileSnapshot> snapshot;
  for (const auto& value_item : files->second.get<picojson::array>()) {
    if (!value_item.is<picojson::object>()) {
      return common::Result<std::vector<FileSnapshot>>::failure(
          storage_data_corrupted("transaction journal file entry must be object"));
    }
    const auto& item = value_item.get<picojson::object>();
    const auto name = item.find("name");
    const auto exists = item.find("exists");
    const auto content = item.find("content");
    if (name == item.end() || !name->second.is<std::string>() ||
        exists == item.end() || !exists->second.is<bool>() || content == item.end()) {
      return common::Result<std::vector<FileSnapshot>>::failure(
          storage_data_corrupted("transaction journal file entry is invalid"));
    }
    const auto file_name = name->second.get<std::string>();
    if (expected.erase(file_name) != 1) {
      return common::Result<std::vector<FileSnapshot>>::failure(
          storage_data_corrupted("transaction journal contains an unexpected file"));
    }
    std::optional<picojson::value> file_content;
    if (exists->second.get<bool>()) {
      if (content->second.is<picojson::null>()) {
        return common::Result<std::vector<FileSnapshot>>::failure(
            storage_data_corrupted("transaction journal file content is missing"));
      }
      file_content = content->second;
    }
    snapshot.push_back(FileSnapshot{file_name, std::move(file_content)});
  }
  if (!expected.empty()) {
    return common::Result<std::vector<FileSnapshot>>::failure(
        storage_data_corrupted("transaction journal snapshot is incomplete"));
  }
  return common::Result<std::vector<FileSnapshot>>::success(std::move(snapshot));
}

common::Result<common::Unit> JsonSnapshotTransaction::recover_locked() {
  auto journal = store_.read_json_file(journal_file_);
  if (!journal.ok()) return common::Result<common::Unit>::failure(journal.error());
  if (!journal.value().has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  auto snapshot = snapshot_from_json(*journal.value());
  if (!snapshot.ok()) return common::Result<common::Unit>::failure(snapshot.error());
  auto restored = restore_snapshot_locked(snapshot.value());
  if (!restored.ok()) return restored;
  return store_.remove_file(journal_file_);
}

}  // namespace excellent_calendar::storage::json
