#pragma once

#include <filesystem>
#include <optional>
#include <string>

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
  explicit AtomicJsonFileStore(std::filesystem::path storage_directory);

  common::Result<common::Unit> initialize() const;

  common::Result<std::optional<picojson::value>> read_json_file(const std::string& file_name) const;

  common::Result<common::Unit> write_json_file(const std::string& file_name,
                                               const picojson::value& root) const;

  const std::filesystem::path& storage_directory() const { return storage_directory_; }

 private:
  std::filesystem::path file_path(const std::string& file_name) const;

  std::filesystem::path storage_directory_;
};

common::Error storage_data_corrupted(std::string reason, std::string field = "");

}  // namespace excellent_calendar::storage::json
