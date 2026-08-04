#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

#include <cerrno>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <system_error>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

namespace excellent_calendar::storage::json {
namespace {

std::shared_ptr<std::recursive_mutex> mutex_for_directory(const std::filesystem::path& directory) {
  static std::mutex registry_mutex;
  static std::map<std::string, std::weak_ptr<std::recursive_mutex>> registry;

  std::error_code absolute_error;
  auto normalized = std::filesystem::absolute(directory, absolute_error).lexically_normal();
  const auto key = (absolute_error ? directory.lexically_normal() : normalized).generic_string();

  std::lock_guard<std::mutex> lock(registry_mutex);
  auto& weak = registry[key];
  auto shared = weak.lock();
  if (!shared) {
    shared = std::make_shared<std::recursive_mutex>();
    weak = shared;
  }
  return shared;
}

common::Error storage_path_invalid(std::string reason) {
  return common::make_error(
      "STORAGE_PATH_INVALID",
      "Storage path is invalid or not writable",
      {{"reason", std::move(reason)}});
}

common::Error storage_io_error(std::string operation, std::string reason) {
  return common::make_error(
      "STORAGE_IO_ERROR",
      "Storage input/output operation failed",
      {{"operation", std::move(operation)}, {"reason", std::move(reason)}},
      true);
}

common::Result<common::Unit> replace_file_atomically(const std::filesystem::path& source,
                                                     const std::filesystem::path& target) {
#if defined(_WIN32)
  if (!MoveFileExW(
          source.c_str(),
          target.c_str(),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    return common::Result<common::Unit>::failure(
        storage_io_error("rename", "MoveFileEx failed with code " + std::to_string(GetLastError())));
  }
#else
  std::error_code rename_error;
  std::filesystem::rename(source, target, rename_error);
  if (rename_error) {
    return common::Result<common::Unit>::failure(storage_io_error("rename", rename_error.message()));
  }
#endif
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> sync_file_to_disk(const std::filesystem::path& path) {
#if defined(_WIN32)
  const auto handle = CreateFileW(
      path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return common::Result<common::Unit>::failure(storage_io_error(
        "open_for_sync", "CreateFile failed with code " + std::to_string(GetLastError())));
  }
  const bool flushed = FlushFileBuffers(handle) != 0;
  const auto error = flushed ? ERROR_SUCCESS : GetLastError();
  CloseHandle(handle);
  return flushed ? common::Result<common::Unit>::success(common::Unit{})
                 : common::Result<common::Unit>::failure(storage_io_error(
                       "fsync", "FlushFileBuffers failed with code " + std::to_string(error)));
#else
  const int descriptor = ::open(path.c_str(), O_RDONLY);
  if (descriptor < 0) {
    return common::Result<common::Unit>::failure(
        storage_io_error("open_for_sync", std::system_category().message(errno)));
  }
  const int result = ::fsync(descriptor);
  const int error = errno;
  ::close(descriptor);
  return result == 0 ? common::Result<common::Unit>::success(common::Unit{})
                     : common::Result<common::Unit>::failure(
                           storage_io_error("fsync", std::system_category().message(error)));
#endif
}

common::Result<common::Unit> sync_directory_to_disk(const std::filesystem::path& path) {
#if defined(_WIN32)
  static_cast<void>(path);
  return common::Result<common::Unit>::success(common::Unit{});
#else
  int flags = O_RDONLY;
#if defined(O_DIRECTORY)
  flags |= O_DIRECTORY;
#endif
  const int descriptor = ::open(path.c_str(), flags);
  if (descriptor < 0) {
    return common::Result<common::Unit>::failure(
        storage_io_error("open_directory_for_sync", std::system_category().message(errno)));
  }
  const int result = ::fsync(descriptor);
  const int error = errno;
  ::close(descriptor);
  return result == 0 ? common::Result<common::Unit>::success(common::Unit{})
                     : common::Result<common::Unit>::failure(
                           storage_io_error("fsync_directory", std::system_category().message(error)));
#endif
}

}  // namespace

common::Error storage_data_corrupted(std::string reason, std::string field) {
  std::map<std::string, std::string> details{{"reason", std::move(reason)}};
  if (!field.empty()) {
    details["field"] = std::move(field);
  }
  return common::make_error(
      "STORAGE_DATA_CORRUPTED",
      "Storage data is corrupted",
      std::move(details));
}

AtomicJsonFileStore::AtomicJsonFileStore(std::filesystem::path storage_directory)
    : storage_directory_(std::move(storage_directory)),
      directory_mutex_(mutex_for_directory(storage_directory_)) {}

common::Result<common::Unit> AtomicJsonFileStore::initialize() const {
  auto lock = acquire_directory_lock();
  if (storage_directory_.empty()) {
    return common::Result<common::Unit>::failure(storage_path_invalid("path is empty"));
  }

  std::error_code create_error;
  std::filesystem::create_directories(storage_directory_, create_error);
  if (create_error) {
    return common::Result<common::Unit>::failure(storage_path_invalid(create_error.message()));
  }

  std::error_code status_error;
  if (!std::filesystem::is_directory(storage_directory_, status_error) || status_error) {
    return common::Result<common::Unit>::failure(storage_path_invalid("path is not a directory"));
  }

  const auto probe_path = storage_directory_ / ".write_probe.tmp";
  {
    std::ofstream probe(probe_path, std::ios::binary | std::ios::trunc);
    if (!probe.is_open()) {
      return common::Result<common::Unit>::failure(storage_path_invalid("probe file cannot be opened"));
    }
    probe << "ok";
    probe.flush();
    if (!probe.good()) {
      return common::Result<common::Unit>::failure(storage_path_invalid("probe file cannot be written"));
    }
  }
  std::error_code remove_error;
  std::filesystem::remove(probe_path, remove_error);

  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::optional<picojson::value>> AtomicJsonFileStore::read_json_file(
    const std::string& file_name) const {
  auto lock = acquire_directory_lock();
  const auto path = file_path(file_name);
  std::error_code exists_error;
  if (!std::filesystem::exists(path, exists_error)) {
    return common::Result<std::optional<picojson::value>>::success(std::nullopt);
  }
  if (exists_error) {
    return common::Result<std::optional<picojson::value>>::failure(
        storage_io_error("exists", exists_error.message()));
  }

  std::ifstream input(path, std::ios::binary);
  if (!input.is_open()) {
    return common::Result<std::optional<picojson::value>>::failure(
        storage_io_error("read", file_name + " cannot be opened"));
  }
  std::stringstream buffer;
  buffer << input.rdbuf();
  if (input.bad()) {
    return common::Result<std::optional<picojson::value>>::failure(
        storage_io_error("read", file_name + " read failed"));
  }

  picojson::value root;
  const std::string parse_error = picojson::parse(root, buffer.str());
  if (!parse_error.empty()) {
    return common::Result<std::optional<picojson::value>>::failure(storage_data_corrupted(parse_error));
  }
  return common::Result<std::optional<picojson::value>>::success(std::move(root));
}

common::Result<common::Unit> AtomicJsonFileStore::write_json_file(const std::string& file_name,
                                                                  const picojson::value& root) const {
  auto lock = acquire_directory_lock();
  std::error_code create_error;
  std::filesystem::create_directories(storage_directory_, create_error);
  if (create_error) {
    return common::Result<common::Unit>::failure(storage_io_error("create_directories", create_error.message()));
  }

  const auto target_path = file_path(file_name);
  const auto tmp_path = target_path.string() + ".tmp";
  {
    std::ofstream output(tmp_path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
      return common::Result<common::Unit>::failure(storage_io_error("write_tmp", file_name + ".tmp cannot be opened"));
    }
    output << root.serialize();
    output.flush();
    if (!output.good()) {
      return common::Result<common::Unit>::failure(storage_io_error("write_tmp", file_name + ".tmp write failed"));
    }
  }

  auto synced = sync_file_to_disk(tmp_path);
  if (!synced.ok()) {
    std::error_code remove_error;
    std::filesystem::remove(tmp_path, remove_error);
    return synced;
  }

  auto replaced = replace_file_atomically(tmp_path, target_path);
  if (!replaced.ok()) {
    std::error_code remove_error;
    std::filesystem::remove(tmp_path, remove_error);
    return replaced;
  }
  return sync_directory_to_disk(storage_directory_);
}

common::Result<common::Unit> AtomicJsonFileStore::remove_file(const std::string& file_name) const {
  auto lock = acquire_directory_lock();
  const auto path = file_path(file_name);
  std::error_code exists_error;
  const bool exists = std::filesystem::exists(path, exists_error);
  if (exists_error) {
    return common::Result<common::Unit>::failure(storage_io_error("exists", exists_error.message()));
  }
  if (!exists) {
    return common::Result<common::Unit>::success(common::Unit{});
  }

  std::error_code remove_error;
  std::filesystem::remove(path, remove_error);
  if (remove_error) {
    return common::Result<common::Unit>::failure(storage_io_error("remove", remove_error.message()));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

AtomicJsonFileStore::DirectoryLock AtomicJsonFileStore::acquire_directory_lock() const {
  return DirectoryLock(*directory_mutex_);
}

std::filesystem::path AtomicJsonFileStore::file_path(const std::string& file_name) const {
  return storage_directory_ / file_name;
}

}  // namespace excellent_calendar::storage::json
