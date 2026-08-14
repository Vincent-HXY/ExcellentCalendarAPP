#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::storage::json {

/**
 * Small reusable JSON file store for local JSON repositories.
 *
 * It owns only filesystem concerns: directory initialization, UTF-8/binary reads,
 * picojson parsing, and atomic temp-file replacement. Repositories still own their
 * mutexes, schema validation, and domain mapping.
 */
class AtomicJsonFileStore {
 public:
  using DirectoryLock = std::unique_lock<std::recursive_mutex>;
  using FailureHook =
      std::function<common::Result<common::Unit>(std::string_view phase)>;
  enum class DirectorySyncFailurePolicy {
    kLeaveReplacement,
    kRestorePreviousSnapshot,
  };

  explicit AtomicJsonFileStore(std::filesystem::path storage_directory,
                               FailureHook failure_hook = {},
                               DirectorySyncFailurePolicy failure_policy =
                                   DirectorySyncFailurePolicy::kLeaveReplacement);

  common::Result<common::Unit> initialize() const;

  common::Result<std::optional<picojson::value>> read_json_file(const std::string& file_name) const;

  common::Result<common::Unit> write_json_file(const std::string& file_name,
                                               const picojson::value& root) const;

  common::Result<common::Unit> remove_file(const std::string& file_name) const;

  DirectoryLock acquire_directory_lock() const;

  const std::filesystem::path& storage_directory() const { return storage_directory_; }

 private:
  common::Result<common::Unit> call_write_hook(std::string_view phase) const;

  common::Result<common::Unit> recover_pending_write(
      const std::string& file_name) const;

  std::filesystem::path file_path(const std::string& file_name) const;

  std::filesystem::path storage_directory_;
  std::shared_ptr<std::recursive_mutex> directory_mutex_;
  FailureHook failure_hook_;
  DirectorySyncFailurePolicy failure_policy_;
};

common::Error storage_data_corrupted(std::string reason, std::string field = "");

}  // namespace excellent_calendar::storage::json
