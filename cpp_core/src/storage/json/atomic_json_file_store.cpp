#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

#include <cerrno>
#include <exception>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
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

common::Result<std::string> read_file_bytes(
    const std::filesystem::path& path,
    std::string operation) {
  std::ifstream input(path, std::ios::binary);
  if (!input.is_open()) {
    return common::Result<std::string>::failure(
        storage_io_error(std::move(operation), path.filename().string() +
                                                   " cannot be opened"));
  }
  std::stringstream buffer;
  buffer << input.rdbuf();
  if (input.bad()) {
    return common::Result<std::string>::failure(
        storage_io_error(std::move(operation), path.filename().string() +
                                                   " read failed"));
  }
  return common::Result<std::string>::success(buffer.str());
}

void remove_file_best_effort(const std::filesystem::path& path) {
  std::error_code ignored;
  std::filesystem::remove(path, ignored);
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

AtomicJsonFileStore::AtomicJsonFileStore(std::filesystem::path storage_directory,
                                         FailureHook failure_hook,
                                         DirectorySyncFailurePolicy failure_policy)
    : storage_directory_(std::move(storage_directory)),
      directory_mutex_(mutex_for_directory(storage_directory_)),
      failure_hook_(std::move(failure_hook)),
      failure_policy_(failure_policy) {}

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
  const std::filesystem::path tmp_path = target_path.string() + ".tmp";
  const std::filesystem::path rollback_path =
      target_path.string() + ".rollback";

  auto hook = call_write_hook("write");
  if (!hook.ok()) return hook;
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

  hook = call_write_hook("temp_fsync");
  if (!hook.ok()) {
    remove_file_best_effort(tmp_path);
    return hook;
  }
  auto synced = sync_file_to_disk(tmp_path);
  if (!synced.ok()) {
    remove_file_best_effort(tmp_path);
    return synced;
  }

  bool target_existed = false;
  std::optional<std::string> previous_bytes;
  if (failure_policy_ ==
      DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
    std::error_code exists_error;
    target_existed = std::filesystem::exists(target_path, exists_error);
    if (exists_error) {
      remove_file_best_effort(tmp_path);
      return common::Result<common::Unit>::failure(
          storage_io_error("exists_before_replace", exists_error.message()));
    }
    if (target_existed) {
      auto previous = read_file_bytes(target_path, "read_before_replace");
      if (!previous.ok()) {
        remove_file_best_effort(tmp_path);
        return common::Result<common::Unit>::failure(previous.error());
      }
      previous_bytes = previous.value();

      std::error_code copy_error;
      std::filesystem::copy_file(
          target_path, rollback_path,
          std::filesystem::copy_options::overwrite_existing, copy_error);
      if (copy_error) {
        remove_file_best_effort(tmp_path);
        return common::Result<common::Unit>::failure(
            storage_io_error("prepare_rollback", copy_error.message()));
      }
      auto rollback_synced = sync_file_to_disk(rollback_path);
      if (!rollback_synced.ok()) {
        remove_file_best_effort(tmp_path);
        remove_file_best_effort(rollback_path);
        return rollback_synced;
      }
      rollback_synced = sync_directory_to_disk(storage_directory_);
      if (!rollback_synced.ok()) {
        remove_file_best_effort(tmp_path);
        remove_file_best_effort(rollback_path);
        return rollback_synced;
      }
    } else {
      std::error_code remove_error;
      std::filesystem::remove(rollback_path, remove_error);
      if (remove_error) {
        remove_file_best_effort(tmp_path);
        return common::Result<common::Unit>::failure(storage_io_error(
            "remove_stale_rollback", remove_error.message()));
      }
    }
  }

  hook = call_write_hook("replace");
  if (!hook.ok()) {
    remove_file_best_effort(tmp_path);
    remove_file_best_effort(rollback_path);
    return hook;
  }
  auto replaced = replace_file_atomically(tmp_path, target_path);
  if (!replaced.ok()) {
    remove_file_best_effort(tmp_path);
    remove_file_best_effort(rollback_path);
    return replaced;
  }

  hook = call_write_hook("directory_fsync");
  auto directory_synced = hook.ok() ? sync_directory_to_disk(storage_directory_)
                                    : hook;
  if (!directory_synced.ok()) {
    if (failure_policy_ !=
        DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
      return directory_synced;
    }
    common::Result<common::Unit> restored =
        common::Result<common::Unit>::success(common::Unit{});
    if (target_existed) {
      restored = replace_file_atomically(rollback_path, target_path);
    } else {
      std::error_code remove_error;
      const bool removed = std::filesystem::remove(target_path, remove_error);
      if (remove_error || !removed) {
        restored = common::Result<common::Unit>::failure(storage_io_error(
            "rollback_remove", remove_error ? remove_error.message()
                                             : "replacement file is missing"));
      }
    }
    if (restored.ok()) {
      restored = sync_directory_to_disk(storage_directory_);
    }
    if (restored.ok() && target_existed) {
      auto restored_bytes = read_file_bytes(target_path, "verify_rollback");
      if (!restored_bytes.ok()) {
        restored = common::Result<common::Unit>::failure(
            restored_bytes.error());
      } else if (!previous_bytes.has_value() ||
                 restored_bytes.value() != *previous_bytes) {
        restored = common::Result<common::Unit>::failure(storage_io_error(
            "verify_rollback", "restored bytes differ from previous snapshot"));
      }
    } else if (restored.ok()) {
      std::error_code rollback_exists_error;
      const bool replacement_exists =
          std::filesystem::exists(target_path, rollback_exists_error);
      if (rollback_exists_error || replacement_exists) {
        restored = common::Result<common::Unit>::failure(storage_io_error(
            "verify_rollback",
            rollback_exists_error ? rollback_exists_error.message()
                                  : "replacement file is still visible"));
      }
    }
    remove_file_best_effort(tmp_path);
    if (!restored.ok()) {
      // Keep an unconsumed rollback snapshot available for diagnosis/recovery.
      const auto reason = directory_synced.error().details.find("reason");
      return common::Result<common::Unit>::failure(storage_io_error(
          "rollback_after_directory_fsync",
          "commit failure: " +
              (reason == directory_synced.error().details.end()
                   ? directory_synced.error().message
                   : reason->second) +
              "; rollback failure: " + restored.error().message));
    }
    remove_file_best_effort(rollback_path);
    return directory_synced;
  }

  // The successful directory sync is the commit point. Cleanup is best-effort:
  // a stale rollback copy is never consulted as authoritative state.
  if (failure_policy_ ==
      DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
    remove_file_best_effort(rollback_path);
  }
  return common::Result<common::Unit>::success(common::Unit{});
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

common::Result<common::Unit> AtomicJsonFileStore::call_write_hook(
    std::string_view phase) const {
  if (!failure_hook_) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  try {
    return failure_hook_(phase);
  } catch (const std::exception& error) {
    return common::Result<common::Unit>::failure(
        storage_io_error("failure_hook", error.what()));
  } catch (...) {
    return common::Result<common::Unit>::failure(
        storage_io_error("failure_hook", "unknown failure hook exception"));
  }
}

std::filesystem::path AtomicJsonFileStore::file_path(const std::string& file_name) const {
  return storage_directory_ / file_name;
}

}  // namespace excellent_calendar::storage::json
