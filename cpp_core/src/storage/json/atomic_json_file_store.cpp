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

constexpr std::string_view kPreparedPreviousPresent =
    "excellent_calendar_atomic_rollback_v1\nstate=P\nprevious=1\n";
constexpr std::string_view kPreparedPreviousAbsent =
    "excellent_calendar_atomic_rollback_v1\nstate=P\nprevious=0\n";
constexpr std::string_view kCommittedPreviousPresent =
    "excellent_calendar_atomic_rollback_v1\nstate=C\nprevious=1\n";
constexpr std::string_view kCommittedPreviousAbsent =
    "excellent_calendar_atomic_rollback_v1\nstate=C\nprevious=0\n";

static_assert(kPreparedPreviousPresent.size() ==
              kCommittedPreviousPresent.size());
static_assert(kPreparedPreviousAbsent.size() ==
              kCommittedPreviousAbsent.size());

struct RecoveryRecord {
  bool committed = false;
  bool previous_existed = false;
};

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

common::Result<RecoveryRecord> parse_recovery_record(
    const std::string& bytes,
    const std::filesystem::path& state_path) {
  if (bytes == kPreparedPreviousPresent) {
    return common::Result<RecoveryRecord>::success({false, true});
  }
  if (bytes == kPreparedPreviousAbsent) {
    return common::Result<RecoveryRecord>::success({false, false});
  }
  if (bytes == kCommittedPreviousPresent) {
    return common::Result<RecoveryRecord>::success({true, true});
  }
  if (bytes == kCommittedPreviousAbsent) {
    return common::Result<RecoveryRecord>::success({true, false});
  }
  return common::Result<RecoveryRecord>::failure(storage_data_corrupted(
      "atomic rollback state is invalid", state_path.filename().string()));
}

common::Result<common::Unit> write_synced_file(
    const std::filesystem::path& path,
    std::string_view bytes,
    std::string operation) {
  {
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
      return common::Result<common::Unit>::failure(storage_io_error(
          std::move(operation), path.filename().string() + " cannot be opened"));
    }
    output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    output.flush();
    if (!output.good()) {
      return common::Result<common::Unit>::failure(storage_io_error(
          std::move(operation), path.filename().string() + " write failed"));
    }
  }
  return sync_file_to_disk(path);
}

common::Result<common::Unit> overwrite_synced_file(
    const std::filesystem::path& path,
    std::string_view bytes,
    std::string operation) {
  {
    std::fstream output(path, std::ios::binary | std::ios::in | std::ios::out);
    if (!output.is_open()) {
      return common::Result<common::Unit>::failure(storage_io_error(
          std::move(operation), path.filename().string() + " cannot be opened"));
    }
    output.seekp(0, std::ios::beg);
    output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    output.flush();
    if (!output.good()) {
      return common::Result<common::Unit>::failure(storage_io_error(
          std::move(operation), path.filename().string() + " write failed"));
    }
  }
  return sync_file_to_disk(path);
}

std::string error_reason(const common::Error& error) {
  const auto reason = error.details.find("reason");
  return reason == error.details.end() ? error.message : reason->second;
}

common::Result<common::Unit> combined_recovery_error(
    const common::Error& operation_error,
    const common::Error& recovery_error) {
  return common::Result<common::Unit>::failure(storage_io_error(
      "rollback_after_directory_fsync",
      "commit failure: " + error_reason(operation_error) +
          "; rollback failure: " + error_reason(recovery_error)));
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
  if (failure_policy_ ==
      DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
    auto recovered = recover_pending_write(file_name);
    if (!recovered.ok()) {
      return common::Result<std::optional<picojson::value>>::failure(
          recovered.error());
    }
  }
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
  const std::filesystem::path rollback_state_path =
      target_path.string() + ".rollback.state";
  const std::filesystem::path rollback_state_tmp_path =
      rollback_state_path.string() + ".tmp";

  if (failure_policy_ ==
      DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
    auto recovered = recover_pending_write(file_name);
    if (!recovered.ok()) return recovered;
  }

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
      auto copied_bytes = read_file_bytes(rollback_path, "verify_prepared_rollback");
      if (!copied_bytes.ok() || copied_bytes.value() != *previous_bytes) {
        remove_file_best_effort(tmp_path);
        remove_file_best_effort(rollback_path);
        return copied_bytes.ok()
                   ? common::Result<common::Unit>::failure(storage_io_error(
                         "verify_prepared_rollback",
                         "rollback bytes differ from previous snapshot"))
                   : common::Result<common::Unit>::failure(copied_bytes.error());
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

    const auto prepared_state =
        target_existed ? kPreparedPreviousPresent : kPreparedPreviousAbsent;
    auto state_written = write_synced_file(
        rollback_state_tmp_path, prepared_state, "prepare_rollback_state");
    if (!state_written.ok()) {
      remove_file_best_effort(tmp_path);
      remove_file_best_effort(rollback_state_tmp_path);
      remove_file_best_effort(rollback_path);
      return state_written;
    }
    state_written =
        replace_file_atomically(rollback_state_tmp_path, rollback_state_path);
    if (!state_written.ok()) {
      remove_file_best_effort(tmp_path);
      remove_file_best_effort(rollback_state_tmp_path);
      remove_file_best_effort(rollback_path);
      return state_written;
    }
    state_written = sync_directory_to_disk(storage_directory_);
    if (!state_written.ok()) {
      remove_file_best_effort(tmp_path);
      // The prepared state is intentionally retained when cleanup itself is
      // not known durable. A later read will idempotently restore the old
      // snapshot before treating the target as authoritative.
      return state_written;
    }
  }

  hook = call_write_hook("replace");
  if (!hook.ok()) {
    remove_file_best_effort(tmp_path);
    if (failure_policy_ ==
        DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
      auto restored = recover_pending_write(file_name);
      if (!restored.ok()) return combined_recovery_error(hook.error(), restored.error());
    } else {
      remove_file_best_effort(rollback_path);
    }
    return hook;
  }
  auto replaced = replace_file_atomically(tmp_path, target_path);
  if (!replaced.ok()) {
    remove_file_best_effort(tmp_path);
    if (failure_policy_ ==
        DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
      auto restored = recover_pending_write(file_name);
      if (!restored.ok()) {
        return combined_recovery_error(replaced.error(), restored.error());
      }
    } else {
      remove_file_best_effort(rollback_path);
    }
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
    auto restored = recover_pending_write(file_name);
    remove_file_best_effort(tmp_path);
    if (!restored.ok()) {
      return combined_recovery_error(directory_synced.error(), restored.error());
    }
    return directory_synced;
  }

  // The successful target-directory sync is the Contract commit point. Before
  // returning success, durably change the already-persisted fixed-size state
  // record in place. This avoids a second directory-entry rename window: file
  // fsync proves whether recovery must keep the replacement. If cleanup is
  // interrupted, a later reader keeps the replacement and only removes the
  // committed sidecars.
  if (failure_policy_ ==
      DirectorySyncFailurePolicy::kRestorePreviousSnapshot) {
    const auto committed_state =
        target_existed ? kCommittedPreviousPresent : kCommittedPreviousAbsent;
    hook = call_write_hook("commit_state_fsync");
    if (!hook.ok()) {
      auto restored = recover_pending_write(file_name);
      return restored.ok()
                 ? hook
                 : combined_recovery_error(hook.error(), restored.error());
    }
    auto state_written = overwrite_synced_file(
        rollback_state_path, committed_state, "commit_rollback_state");
    if (!state_written.ok()) {
      const auto prepared_state =
          target_existed ? kPreparedPreviousPresent : kPreparedPreviousAbsent;
      auto reset_state = overwrite_synced_file(
          rollback_state_path, prepared_state, "reset_rollback_state");
      if (!reset_state.ok()) {
        return combined_recovery_error(state_written.error(),
                                       reset_state.error());
      }
      auto restored = recover_pending_write(file_name);
      return restored.ok()
                 ? state_written
                 : combined_recovery_error(state_written.error(),
                                           restored.error());
    }
    auto cleanup_hook = call_write_hook("post_commit_cleanup");
    if (cleanup_hook.ok()) {
      remove_file_best_effort(rollback_state_path);
      remove_file_best_effort(rollback_path);
      remove_file_best_effort(rollback_state_tmp_path);
      static_cast<void>(sync_directory_to_disk(storage_directory_));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> AtomicJsonFileStore::recover_pending_write(
    const std::string& file_name) const {
  auto lock = acquire_directory_lock();
  const auto target_path = file_path(file_name);
  const std::filesystem::path rollback_path =
      target_path.string() + ".rollback";
  const std::filesystem::path rollback_state_path =
      target_path.string() + ".rollback.state";
  const std::filesystem::path rollback_state_tmp_path =
      rollback_state_path.string() + ".tmp";
  const std::filesystem::path restore_tmp_path =
      target_path.string() + ".rollback.restore.tmp";

  std::error_code exists_error;
  const bool state_exists =
      std::filesystem::exists(rollback_state_path, exists_error);
  if (exists_error) {
    return common::Result<common::Unit>::failure(
        storage_io_error("inspect_rollback_state", exists_error.message()));
  }
  if (!state_exists) {
    // Unmarked temp/backup files cannot override the target. They can remain
    // after a completed commit or a crash before the prepared state was made
    // durable, so only remove them best-effort.
    remove_file_best_effort(rollback_state_tmp_path);
    remove_file_best_effort(restore_tmp_path);
    return common::Result<common::Unit>::success(common::Unit{});
  }

  auto state_bytes =
      read_file_bytes(rollback_state_path, "read_rollback_state");
  if (!state_bytes.ok()) {
    return common::Result<common::Unit>::failure(state_bytes.error());
  }
  auto parsed = parse_recovery_record(state_bytes.value(), rollback_state_path);
  if (!parsed.ok()) {
    return common::Result<common::Unit>::failure(parsed.error());
  }
  const auto record = parsed.value();
  if (record.committed) {
    std::error_code target_error;
    const bool target_exists = std::filesystem::exists(target_path, target_error);
    if (target_error || !target_exists) {
      return common::Result<common::Unit>::failure(storage_io_error(
          "verify_committed_replacement",
          target_error ? target_error.message()
                       : "committed replacement file is missing"));
    }
    remove_file_best_effort(rollback_state_path);
    remove_file_best_effort(rollback_path);
    remove_file_best_effort(rollback_state_tmp_path);
    remove_file_best_effort(restore_tmp_path);
    static_cast<void>(sync_directory_to_disk(storage_directory_));
    return common::Result<common::Unit>::success(common::Unit{});
  }

  std::optional<std::string> rollback_bytes;
  if (record.previous_existed) {
    auto bytes = read_file_bytes(rollback_path, "read_prepared_rollback");
    if (!bytes.ok()) {
      return common::Result<common::Unit>::failure(bytes.error());
    }
    rollback_bytes = bytes.value();
  } else {
    std::error_code rollback_exists_error;
    const bool rollback_exists =
        std::filesystem::exists(rollback_path, rollback_exists_error);
    if (rollback_exists_error || rollback_exists) {
      return common::Result<common::Unit>::failure(storage_io_error(
          "verify_rollback_state",
          rollback_exists_error
              ? rollback_exists_error.message()
              : "rollback snapshot exists for a previously absent target"));
    }
  }

  auto hook = call_write_hook("rollback_replace");
  if (!hook.ok()) return hook;
  if (record.previous_existed) {
    std::error_code copy_error;
    std::filesystem::copy_file(
        rollback_path, restore_tmp_path,
        std::filesystem::copy_options::overwrite_existing, copy_error);
    if (copy_error) {
      return common::Result<common::Unit>::failure(
          storage_io_error("rollback_copy", copy_error.message()));
    }
    auto restore_synced = sync_file_to_disk(restore_tmp_path);
    if (!restore_synced.ok()) return restore_synced;
    auto restored = replace_file_atomically(restore_tmp_path, target_path);
    if (!restored.ok()) return restored;
  } else {
    std::error_code remove_error;
    std::filesystem::remove(target_path, remove_error);
    if (remove_error) {
      return common::Result<common::Unit>::failure(
          storage_io_error("rollback_remove", remove_error.message()));
    }
  }

  hook = call_write_hook("rollback_directory_fsync");
  if (!hook.ok()) return hook;
  auto directory_synced = sync_directory_to_disk(storage_directory_);
  if (!directory_synced.ok()) return directory_synced;

  hook = call_write_hook("rollback_verify");
  if (!hook.ok()) return hook;
  if (record.previous_existed) {
    auto restored_bytes = read_file_bytes(target_path, "verify_rollback");
    if (!restored_bytes.ok()) {
      return common::Result<common::Unit>::failure(restored_bytes.error());
    }
    if (!rollback_bytes.has_value() ||
        restored_bytes.value() != *rollback_bytes) {
      return common::Result<common::Unit>::failure(storage_io_error(
          "verify_rollback", "restored bytes differ from previous snapshot"));
    }
  } else {
    std::error_code replacement_error;
    const bool replacement_exists =
        std::filesystem::exists(target_path, replacement_error);
    if (replacement_error || replacement_exists) {
      return common::Result<common::Unit>::failure(storage_io_error(
          "verify_rollback",
          replacement_error ? replacement_error.message()
                            : "replacement file is still visible"));
    }
  }

  // The old snapshot is durable and verified. Removing the state first makes
  // any leftover backup non-authoritative; cleanup is idempotent and best-effort.
  remove_file_best_effort(rollback_state_path);
  remove_file_best_effort(rollback_path);
  remove_file_best_effort(rollback_state_tmp_path);
  remove_file_best_effort(restore_tmp_path);
  static_cast<void>(sync_directory_to_disk(storage_directory_));
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
