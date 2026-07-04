#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {

class JsonSnapshotTransaction {
 public:
  using Operation = std::function<common::Result<common::Unit>()>;

  JsonSnapshotTransaction(std::filesystem::path storage_directory,
                          std::string journal_file,
                          std::vector<std::string> data_files);

  common::Result<common::Unit> initialize();

  common::Result<common::Unit> execute(const Operation& operation);

 private:
  struct FileSnapshot {
    std::string name;
    std::optional<picojson::value> content;
  };

  common::Result<std::vector<FileSnapshot>> read_snapshot_locked();
  common::Result<common::Unit> restore_snapshot_locked(
      const std::vector<FileSnapshot>& snapshot);
  common::Result<common::Unit> recover_locked();
  picojson::value snapshot_to_json(const std::vector<FileSnapshot>& snapshot) const;
  common::Result<std::vector<FileSnapshot>> snapshot_from_json(
      const picojson::value& value) const;

  AtomicJsonFileStore store_;
  std::string journal_file_;
  std::vector<std::string> data_files_;
};

}  // namespace excellent_calendar::storage::json
